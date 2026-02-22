import 'package:dio/dio.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/retry.dart';

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
  final bool _ownsDio;

  // Cache compiled RegExp per attribute name to avoid recompilation on every line
  static final _attrPatternCache = <String, List<RegExp>>{};

  M3uParser({Dio? dio})
      : _dio = dio ?? Dio(),
        _ownsDio = dio == null;

  /// Close the internal Dio client if it was created by this parser.
  void close() {
    if (_ownsDio) _dio.close();
  }

  /// Parse M3U from URL with automatic retry on transient failures
  Future<M3uParseResult> parseFromUrl(String url) async {
    return withRetry(
      () => _fetchAndParse(url),
      label: 'M3U fetch',
    );
  }

  Future<M3uParseResult> _fetchAndParse(String url) async {
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
    String? currentType;

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
        currentType = parsed['type'] as String?;
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
          isVod: _isVodContent(line, currentType, currentGroup),
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
        currentType = null;
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
    result['type'] = _extractAttribute(line, 'tvg-type');

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
    // Use cached RegExp patterns — avoids recompilation per line per attribute
    final patterns = _attrPatternCache.putIfAbsent(attribute, () => [
      RegExp('$attribute="([^"]*)"'),
      RegExp("$attribute='([^']*)'"),
    ]);

    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null && match.group(1)?.isNotEmpty == true) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Determine if content is VOD using metadata, group, and URL heuristics.
  ///
  /// Checks in priority order:
  /// 1. Explicit `tvg-type` attribute from the EXTINF line (most reliable)
  /// 2. Group name containing VOD/movie/series keywords
  /// 3. URL path patterns (Xtream-style /movie/ or /series/)
  /// 4. File extension heuristics (.mp4, .mkv, etc.)
  bool _isVodContent(String url, String? tvgType, String? group) {
    // 1. Explicit type attribute is most reliable
    if (tvgType != null) {
      final lower = tvgType.toLowerCase();
      return lower == 'movie' || lower == 'vod' || lower == 'series';
    }

    // 2. Group name hints
    if (group != null) {
      final lowerGroup = group.toLowerCase();
      if (lowerGroup.contains('vod') ||
          lowerGroup.contains('movie') ||
          lowerGroup.contains('film') ||
          lowerGroup.contains('series')) {
        return true;
      }
    }

    // 3. URL path and extension heuristics
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('/movie/') || lowerUrl.contains('/series/')) {
      return true;
    }

    const vodExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv'];
    return vodExtensions.any((ext) => lowerUrl.endsWith(ext));
  }
}
