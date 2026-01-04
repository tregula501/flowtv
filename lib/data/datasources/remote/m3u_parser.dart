import 'package:dio/dio.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/utils/logger.dart';

/// Parsed M3U data
class M3uParseResult {
  final List<M3uChannel> channels;
  final String? epgUrl;
  final Map<String, int> groupCounts;

  M3uParseResult({
    required this.channels,
    this.epgUrl,
    required this.groupCounts,
  });
}

/// Temporary channel data from M3U parsing
class M3uChannel {
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? epgId;
  final String? group;
  final int? channelNumber;
  final String? language;
  final String? country;
  final bool isVod;

  M3uChannel({
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.epgId,
    this.group,
    this.channelNumber,
    this.language,
    this.country,
    this.isVod = false,
  });
}

/// M3U/M3U8 playlist parser
class M3uParser {
  final Dio _dio;

  M3uParser({Dio? dio}) : _dio = dio ?? Dio();

  /// Parse M3U from URL
  Future<M3uParseResult> parseFromUrl(String url) async {
    try {
      AppLogger.info('Fetching M3U from: $url');

      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.data == null || response.data!.isEmpty) {
        throw const PlaylistParseException('Empty playlist received');
      }

      return parseContent(response.data!);
    } on DioException catch (e) {
      AppLogger.error('Failed to fetch M3U', e);
      throw NetworkException(
        'Failed to download playlist: ${e.message}',
        originalError: e,
      );
    }
  }

  /// Parse M3U content string
  M3uParseResult parseContent(String content) {
    final lines = content.split('\n').map((l) => l.trim()).toList();

    if (lines.isEmpty || !lines[0].startsWith('#EXTM3U')) {
      throw const PlaylistParseException('Invalid M3U file: Missing #EXTM3U header');
    }

    final channels = <M3uChannel>[];
    final groupCounts = <String, int>{};
    String? epgUrl;

    // Check for EPG URL in header
    final headerLine = lines[0];
    epgUrl = _extractAttribute(headerLine, 'x-tvg-url') ??
        _extractAttribute(headerLine, 'url-tvg');

    String? currentName;
    String? currentLogo;
    String? currentEpgId;
    String? currentGroup;
    int? currentNumber;
    String? currentLanguage;
    String? currentCountry;

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];

      if (line.isEmpty || line.startsWith('#EXTM3U')) continue;

      if (line.startsWith('#EXTINF:')) {
        // Parse channel info line
        final parsed = _parseExtInf(line);
        currentName = parsed['name'];
        currentLogo = parsed['logo'];
        currentEpgId = parsed['tvg-id'];
        currentGroup = parsed['group'];
        currentNumber = parsed['number'];
        currentLanguage = parsed['language'];
        currentCountry = parsed['country'];
      } else if (line.startsWith('#')) {
        // Skip other directives
        continue;
      } else if (line.isNotEmpty && currentName != null) {
        // This is a stream URL
        final channel = M3uChannel(
          name: currentName,
          streamUrl: line,
          logoUrl: currentLogo,
          epgId: currentEpgId,
          group: currentGroup ?? 'Uncategorized',
          channelNumber: currentNumber,
          language: currentLanguage,
          country: currentCountry,
          isVod: _isVodUrl(line),
        );

        channels.add(channel);

        // Count groups
        final group = currentGroup ?? 'Uncategorized';
        groupCounts[group] = (groupCounts[group] ?? 0) + 1;

        // Reset for next channel
        currentName = null;
        currentLogo = null;
        currentEpgId = null;
        currentGroup = null;
        currentNumber = null;
        currentLanguage = null;
        currentCountry = null;
      }
    }

    AppLogger.info('Parsed ${channels.length} channels in ${groupCounts.length} groups');

    return M3uParseResult(
      channels: channels,
      epgUrl: epgUrl,
      groupCounts: groupCounts,
    );
  }

  /// Parse #EXTINF line
  Map<String, dynamic> _parseExtInf(String line) {
    final result = <String, dynamic>{};

    // Extract name (after last comma)
    final commaIndex = line.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < line.length - 1) {
      result['name'] = line.substring(commaIndex + 1).trim();
    }

    // Extract attributes
    result['logo'] = _extractAttribute(line, 'tvg-logo');
    result['tvg-id'] = _extractAttribute(line, 'tvg-id');
    result['group'] = _extractAttribute(line, 'group-title');
    result['language'] = _extractAttribute(line, 'tvg-language');
    result['country'] = _extractAttribute(line, 'tvg-country');

    // Extract channel number
    final numberStr = _extractAttribute(line, 'tvg-chno') ??
        _extractAttribute(line, 'channel-number');
    if (numberStr != null) {
      result['number'] = int.tryParse(numberStr);
    }

    return result;
  }

  /// Extract attribute value from M3U line
  String? _extractAttribute(String line, String attribute) {
    // Match both: attribute="value" and attribute='value'
    final patterns = [
      RegExp('$attribute="([^"]*)"'),
      RegExp("$attribute='([^']*)'"),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null && match.group(1)?.isNotEmpty == true) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Check if URL is likely a VOD item
  bool _isVodUrl(String url) {
    final vodExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv'];
    final lowerUrl = url.toLowerCase();
    return vodExtensions.any((ext) => lowerUrl.endsWith(ext)) ||
        lowerUrl.contains('/movie/') ||
        lowerUrl.contains('/series/');
  }
}
