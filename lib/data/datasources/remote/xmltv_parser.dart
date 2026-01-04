import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../models/epg_program.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/utils/logger.dart';

/// Parsed EPG data from XMLTV
class XmltvParseResult {
  final List<EpgProgram> programs;
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

  XmltvParser({Dio? dio}) : _dio = dio ?? Dio();

  /// Parse XMLTV from URL
  Future<XmltvParseResult> parseFromUrl(String url) async {
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

      return parseContent(response.data!);
    } on DioException catch (e) {
      AppLogger.error('Failed to fetch EPG', e);
      throw NetworkException(
        'Failed to download EPG: ${e.message}',
        originalError: e,
      );
    }
  }

  /// Parse XMLTV content string
  XmltvParseResult parseContent(String content) {
    try {
      final document = XmlDocument.parse(content);
      final tv = document.findElements('tv').first;

      final programs = <EpgProgram>[];
      final channelIds = <String>{};

      // Parse programmes
      for (final programme in tv.findElements('programme')) {
        final channelId = programme.getAttribute('channel');
        final start = programme.getAttribute('start');
        final stop = programme.getAttribute('stop');

        if (channelId == null || start == null || stop == null) continue;

        channelIds.add(channelId);

        final titleElement = programme.findElements('title').firstOrNull;
        final descElement = programme.findElements('desc').firstOrNull;
        final categoryElement = programme.findElements('category').firstOrNull;
        final iconElement = programme.findElements('icon').firstOrNull;
        final episodeElement = programme.findElements('episode-num').firstOrNull;

        final program = EpgProgram.create(
          channelId: channelId,
          title: titleElement?.innerText ?? 'Unknown',
          startTime: _parseXmltvDate(start),
          endTime: _parseXmltvDate(stop),
          description: descElement?.innerText,
          category: categoryElement?.innerText,
          episode: episodeElement?.innerText,
          iconUrl: iconElement?.getAttribute('src'),
        );

        programs.add(program);
      }

      AppLogger.info(
        'Parsed ${programs.length} programs for ${channelIds.length} channels',
      );

      return XmltvParseResult(
        programs: programs,
        channelCount: channelIds.length,
        programCount: programs.length,
      );
    } catch (e, stack) {
      AppLogger.error('Failed to parse XMLTV', e, stack);
      throw EpgParseException('Failed to parse EPG: $e', originalError: e);
    }
  }

  /// Parse XMLTV date format (YYYYMMDDHHmmss +ZZZZ)
  DateTime _parseXmltvDate(String dateStr) {
    try {
      // Format: 20240101120000 +0000
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
        final tzOffset = tzStr.replaceAll(RegExp(r'[+-]'), '');
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
    } catch (e) {
      AppLogger.warning('Failed to parse date: $dateStr');
      return DateTime.now();
    }
  }
}
