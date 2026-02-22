import 'package:dio/dio.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/retry.dart';

/// Xtream Codes API response models
class XtreamUserInfo {
  final String username;
  final String password;
  final String status;
  final String expDate;
  final bool isTrial;
  final int activeCons;
  final int maxConnections;
  final List<String> allowedFormats;

  XtreamUserInfo({
    required this.username,
    required this.password,
    required this.status,
    required this.expDate,
    required this.isTrial,
    required this.activeCons,
    required this.maxConnections,
    required this.allowedFormats,
  });

  factory XtreamUserInfo.fromJson(Map<String, dynamic> json) {
    return XtreamUserInfo(
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      status: json['status'] ?? '',
      expDate: json['exp_date'] ?? '',
      isTrial: json['is_trial'] == '1',
      activeCons: int.tryParse(json['active_cons']?.toString() ?? '0') ?? 0,
      maxConnections: int.tryParse(json['max_connections']?.toString() ?? '1') ?? 1,
      allowedFormats: (json['allowed_output_formats'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class XtreamCategory {
  final String id;
  final String name;
  final int? parentId;

  XtreamCategory({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory XtreamCategory.fromJson(Map<String, dynamic> json) {
    return XtreamCategory(
      id: json['category_id']?.toString() ?? '',
      name: json['category_name'] ?? '',
      parentId: int.tryParse(json['parent_id']?.toString() ?? ''),
    );
  }
}

class XtreamChannel {
  final int id;
  final String name;
  final String streamIcon;
  final String epgChannelId;
  final String categoryId;
  final int? channelNumber;

  XtreamChannel({
    required this.id,
    required this.name,
    required this.streamIcon,
    required this.epgChannelId,
    required this.categoryId,
    this.channelNumber,
  });

  factory XtreamChannel.fromJson(Map<String, dynamic> json) {
    return XtreamChannel(
      id: int.tryParse(json['stream_id']?.toString() ?? '0') ?? 0,
      name: json['name'] ?? '',
      streamIcon: json['stream_icon'] ?? '',
      epgChannelId: json['epg_channel_id'] ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      channelNumber: int.tryParse(json['num']?.toString() ?? ''),
    );
  }
}

class XtreamVodItem {
  final int id;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final double? rating;

  XtreamVodItem({
    required this.id,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
  });

  factory XtreamVodItem.fromJson(Map<String, dynamic> json) {
    return XtreamVodItem(
      id: int.tryParse(json['stream_id']?.toString() ?? '0') ?? 0,
      name: json['name'] ?? '',
      streamIcon: json['stream_icon'] ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      plot: json['plot'],
      cast: json['cast'],
      director: json['director'],
      genre: json['genre'],
      releaseDate: json['releaseDate'],
      rating: double.tryParse(json['rating']?.toString() ?? ''),
    );
  }
}

class XtreamSeries {
  final int id;
  final String name;
  final String cover;
  final String categoryId;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final double? rating;

  XtreamSeries({
    required this.id,
    required this.name,
    required this.cover,
    required this.categoryId,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.rating,
  });

  factory XtreamSeries.fromJson(Map<String, dynamic> json) {
    return XtreamSeries(
      id: int.tryParse(json['series_id']?.toString() ?? '0') ?? 0,
      name: json['name'] ?? '',
      cover: json['cover'] ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      plot: json['plot'],
      cast: json['cast'],
      director: json['director'],
      genre: json['genre'],
      rating: double.tryParse(json['rating']?.toString() ?? ''),
    );
  }
}

/// Xtream Codes API client
class XtreamApiClient {
  final Dio _dio;
  final bool _ownsDio;
  final String serverUrl;
  final String username;
  final String password;

  XtreamApiClient({
    required this.serverUrl,
    required this.username,
    required this.password,
    Dio? dio,
  })  : _dio = dio ?? Dio(),
        _ownsDio = dio == null;

  /// Close the internal Dio client if it was created by this client.
  void close() {
    if (_ownsDio) _dio.close();
  }

  String get _baseUrl {
    var url = serverUrl;
    if (!url.endsWith('/')) url += '/';
    return '${url}player_api.php';
  }

  Map<String, String> get _authParams => {
        'username': username,
        'password': password,
      };

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, String>? extraParams,
  ]) async {
    return withRetry(
      () => _doRequest(action, extraParams),
      label: 'Xtream $action',
    );
  }

  Future<Map<String, dynamic>> _doRequest(
    String action, [
    Map<String, String>? extraParams,
  ]) async {
    try {
      final params = {
        ..._authParams,
        'action': action,
        ...?extraParams,
      };

      final response = await _dio.get<Map<String, dynamic>>(
        _baseUrl,
        queryParameters: params,
      );

      if (response.data == null) {
        throw const ApiException('Empty response from server');
      }

      return response.data!;
    } on DioException catch (e) {
      AppLogger.error('Xtream API error', e);
      throw ApiException(
        'API request failed: ${e.message}',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  /// Authenticate and get user info
  Future<XtreamUserInfo> authenticate() async {
    final response = await _request('get_user_info');

    if (response['user_info'] == null) {
      throw const ApiException('Authentication failed');
    }

    return XtreamUserInfo.fromJson(response['user_info']);
  }

  /// Get live TV categories
  Future<List<XtreamCategory>> getLiveCategories() async {
    final response = await _request('get_live_categories');

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_live_categories returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamCategory.fromJson(e))
        .toList();
  }

  /// Get live TV channels
  Future<List<XtreamChannel>> getLiveStreams([String? categoryId]) async {
    final params = categoryId != null ? {'category_id': categoryId} : null;
    final response = await _request('get_live_streams', params);

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_live_streams returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamChannel.fromJson(e))
        .toList();
  }

  /// Get VOD categories
  Future<List<XtreamCategory>> getVodCategories() async {
    final response = await _request('get_vod_categories');

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_vod_categories returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamCategory.fromJson(e))
        .toList();
  }

  /// Get VOD streams
  Future<List<XtreamVodItem>> getVodStreams([String? categoryId]) async {
    final params = categoryId != null ? {'category_id': categoryId} : null;
    final response = await _request('get_vod_streams', params);

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_vod_streams returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamVodItem.fromJson(e))
        .toList();
  }

  /// Get series categories
  Future<List<XtreamCategory>> getSeriesCategories() async {
    final response = await _request('get_series_categories');

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_series_categories returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamCategory.fromJson(e))
        .toList();
  }

  /// Get series list
  Future<List<XtreamSeries>> getSeries([String? categoryId]) async {
    final params = categoryId != null ? {'category_id': categoryId} : null;
    final response = await _request('get_series', params);

    if (response is! List) {
      AppLogger.warning(
        'Xtream: get_series returned ${response.runtimeType} instead of List',
      );
      return [];
    }

    return (response as List)
        .map((e) => XtreamSeries.fromJson(e))
        .toList();
  }

  /// Build stream URL for live TV
  String getLiveStreamUrl(int streamId, {String format = 'm3u8'}) {
    var url = serverUrl;
    if (!url.endsWith('/')) url += '/';
    return '$url$username/$password/$streamId.$format';
  }

  /// Build stream URL for VOD
  String getVodStreamUrl(int streamId, {String format = 'm3u8'}) {
    var url = serverUrl;
    if (!url.endsWith('/')) url += '/';
    return '${url}movie/$username/$password/$streamId.$format';
  }

  /// Build stream URL for series episode
  String getSeriesStreamUrl(int streamId, {String format = 'm3u8'}) {
    var url = serverUrl;
    if (!url.endsWith('/')) url += '/';
    return '${url}series/$username/$password/$streamId.$format';
  }
}
