import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:xml/xml_events.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/retry.dart';

/// Temporary program data from XMLTV parsing
class XmltvProgram {
  final String channelId;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final String? category;
  final String? episode;
  final String? iconUrl;

  XmltvProgram({
    required this.channelId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.category,
    this.episode,
    this.iconUrl,
  });
}

/// Parsed EPG data from XMLTV
class XmltvParseResult {
  final List<XmltvProgram> programs;
  final int channelCount;
  final int programCount;

  XmltvParseResult({
    required this.programs,
    required this.channelCount,
    required this.programCount,
  });
}

/// XMLTV EPG parser
class XmltvParser {
  final Dio _dio;
  final bool _ownsDio;

  static final _tzSignRegex = RegExp(r'[+-]');

  XmltvParser({Dio? dio})
      : _dio = dio ?? Dio(),
        _ownsDio = dio == null;

  /// Close the internal Dio client if it was created by this parser.
  void close() {
    if (_ownsDio) _dio.close();
  }

  /// Parse XMLTV from URL with automatic retry on transient failures
  Future<XmltvParseResult> parseFromUrl(String url) async {
    return withRetry(
      () => _fetchAndParse(url),
      label: 'XMLTV fetch',
    );
  }

  Future<XmltvParseResult> _fetchAndParse(String url) async {
    try {
      AppLogger.info('Fetching EPG from: $url');

      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      if (response.data == null || response.data!.isEmpty) {
        throw const EpgParseException('Empty EPG data received');
      }

      return await parseContent(response.data!);
    } on DioException catch (e) {
      AppLogger.error('Failed to fetch EPG', e);
      throw NetworkException(
        'Failed to download EPG: ${e.message}',
        originalError: e,
      );
    }
  }

  /// Parse XMLTV content string (runs in isolate for large EPG files)
  Future<XmltvParseResult> parseContent(String content) async {
    return Isolate.run(() => _parseContentSync(content));
  }

  /// Synchronous parsing logic (runs in isolate).
  ///
  /// Uses event-based (pull) parsing via [parseEvents] to avoid building a
  /// full DOM tree in memory.  For a 50 MB EPG file this keeps memory usage
  /// proportional to the number of *retained* [XmltvProgram] objects instead
  /// of 3-5x the file size for the DOM.
  static XmltvParseResult _parseContentSync(String content) {
    try {
      final programs = <XmltvProgram>[];
      final channelIds = <String>{};

      // Whether we have seen the root <tv> element.
      bool foundTvRoot = false;

      // State while inside a <programme> element.
      bool inProgramme = false;
      String? channelId;
      String? start;
      String? stop;
      String? title;
      String? description;
      String? category;
      String? episode;
      String? iconSrc;

      // The name of the direct child element we are currently reading text
      // from (e.g. "title", "desc", …).  Null when we are not inside a
      // relevant child element.
      String? currentChild;

      // Nesting depth within a <programme>.  We need this to correctly
      // ignore nested elements inside children (e.g. <desc><b>bold</b></desc>)
      // and to know when the <programme> truly ends.
      int programmeDepth = 0;

      for (final event in parseEvents(content)) {
        if (event is XmlStartElementEvent) {
          if (event.name == 'tv') {
            foundTvRoot = true;
          } else if (event.name == 'programme' && !inProgramme) {
            inProgramme = true;
            programmeDepth = 1;

            // Extract attributes from the <programme> tag.
            channelId = null;
            start = null;
            stop = null;
            title = null;
            description = null;
            category = null;
            episode = null;
            iconSrc = null;
            currentChild = null;

            for (final attr in event.attributes) {
              switch (attr.name) {
                case 'channel':
                  channelId = attr.value;
                case 'start':
                  start = attr.value;
                case 'stop':
                  stop = attr.value;
              }
            }

            // Self-closing <programme /> is technically valid XML but
            // useless – skip it.
            if (event.isSelfClosing) {
              inProgramme = false;
              programmeDepth = 0;
            }
          } else if (inProgramme) {
            programmeDepth++;

            // Only treat direct children (depth == 2) as data sources.
            if (programmeDepth == 2) {
              switch (event.name) {
                case 'title':
                case 'desc':
                case 'category':
                case 'episode-num':
                  currentChild = event.name;
                case 'icon':
                  // <icon> carries its data in the src attribute.
                  for (final attr in event.attributes) {
                    if (attr.name == 'src') {
                      iconSrc = attr.value;
                      break;
                    }
                  }
                  currentChild = null;
                default:
                  currentChild = null;
              }
            }

            // Handle self-closing child tags (e.g. <icon src="…" />).
            if (event.isSelfClosing) {
              programmeDepth--;
              if (programmeDepth == 1) {
                currentChild = null;
              }
            }
          }
        } else if (event is XmlTextEvent) {
          if (inProgramme && currentChild != null) {
            final text = event.value;
            switch (currentChild) {
              case 'title':
                title = (title ?? '') + text;
              case 'desc':
                description = (description ?? '') + text;
              case 'category':
                category = (category ?? '') + text;
              case 'episode-num':
                episode = (episode ?? '') + text;
            }
          }
        } else if (event is XmlEndElementEvent) {
          if (inProgramme) {
            programmeDepth--;

            if (event.name == 'programme' && programmeDepth == 0) {
              // Finished a <programme> – build the result object.
              inProgramme = false;
              currentChild = null;

              if (channelId == null || start == null || stop == null) continue;

              final startTime = _parseXmltvDate(start);
              final endTime = _parseXmltvDate(stop);
              if (startTime == null || endTime == null) continue;

              channelIds.add(channelId);

              programs.add(XmltvProgram(
                channelId: channelId,
                title: title ?? 'Unknown',
                startTime: startTime,
                endTime: endTime,
                description: description,
                category: category,
                episode: episode,
                iconUrl: iconSrc,
              ));
            } else if (programmeDepth == 1) {
              // Exiting a direct child element – stop accumulating text.
              currentChild = null;
            }
          }
        }
      }

      if (!foundTvRoot) {
        throw const EpgParseException(
            'Invalid EPG: missing <tv> root element');
      }

      return XmltvParseResult(
        programs: programs,
        channelCount: channelIds.length,
        programCount: programs.length,
      );
    } on EpgParseException {
      rethrow;
    } catch (e) {
      throw EpgParseException('Failed to parse EPG: $e', originalError: e);
    }
  }

  /// Parse XMLTV date format (YYYYMMDDHHmmss +ZZZZ).
  /// Returns null if the date string is malformed so the caller can skip
  /// the program instead of inserting it with a wrong time.
  static DateTime? _parseXmltvDate(String dateStr) {
    try {
      final cleanDate = dateStr.replaceAll(' ', '');

      final year = int.parse(cleanDate.substring(0, 4));
      final month = int.parse(cleanDate.substring(4, 6));
      final day = int.parse(cleanDate.substring(6, 8));
      final hour = int.parse(cleanDate.substring(8, 10));
      final minute = int.parse(cleanDate.substring(10, 12));
      final second = cleanDate.length >= 14
          ? int.parse(cleanDate.substring(12, 14))
          : 0;

      // Handle timezone offset if present
      if (cleanDate.length > 14) {
        final tzStr = cleanDate.substring(14);
        final tzSign = tzStr.startsWith('-') ? -1 : 1;
        final tzOffset = tzStr.replaceAll(_tzSignRegex, '');
        final tzHours = int.parse(tzOffset.substring(0, 2));
        final tzMinutes = tzOffset.length >= 4
            ? int.parse(tzOffset.substring(2, 4))
            : 0;

        final utcTime = DateTime.utc(year, month, day, hour, minute, second);
        return utcTime.subtract(
          Duration(hours: tzSign * tzHours, minutes: tzSign * tzMinutes),
        );
      }

      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
