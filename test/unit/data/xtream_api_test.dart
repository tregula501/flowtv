import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/datasources/remote/xtream_api_client.dart';

void main() {
  group('XtreamUserInfo', () {
    test('should parse from JSON with all fields', () {
      final json = {
        'username': 'testuser',
        'password': 'testpass',
        'status': 'Active',
        'exp_date': '1735689600',
        'is_trial': '0',
        'active_cons': '1',
        'max_connections': '2',
        'allowed_output_formats': ['m3u8', 'ts'],
      };

      final userInfo = XtreamUserInfo.fromJson(json);

      expect(userInfo.username, 'testuser');
      expect(userInfo.password, 'testpass');
      expect(userInfo.status, 'Active');
      expect(userInfo.expDate, '1735689600');
      expect(userInfo.isTrial, false);
      expect(userInfo.activeCons, 1);
      expect(userInfo.maxConnections, 2);
      expect(userInfo.allowedFormats, ['m3u8', 'ts']);
    });

    test('should parse trial account correctly', () {
      final json = {
        'username': 'trial',
        'password': 'pass',
        'status': 'Active',
        'exp_date': '',
        'is_trial': '1',
        'active_cons': '0',
        'max_connections': '1',
        'allowed_output_formats': [],
      };

      final userInfo = XtreamUserInfo.fromJson(json);

      expect(userInfo.isTrial, true);
    });

    test('should handle missing fields with defaults', () {
      final json = <String, dynamic>{};

      final userInfo = XtreamUserInfo.fromJson(json);

      expect(userInfo.username, '');
      expect(userInfo.password, '');
      expect(userInfo.status, '');
      expect(userInfo.expDate, '');
      expect(userInfo.isTrial, false);
      expect(userInfo.activeCons, 0);
      expect(userInfo.maxConnections, 1);
      expect(userInfo.allowedFormats, isEmpty);
    });

    test('should handle null allowed_output_formats', () {
      final json = {
        'username': 'user',
        'password': 'pass',
        'status': 'Active',
        'exp_date': '',
        'is_trial': '0',
        'active_cons': '0',
        'max_connections': '1',
        'allowed_output_formats': null,
      };

      final userInfo = XtreamUserInfo.fromJson(json);

      expect(userInfo.allowedFormats, isEmpty);
    });
  });

  group('XtreamCategory', () {
    test('should parse from JSON', () {
      final json = {
        'category_id': '123',
        'category_name': 'Sports',
        'parent_id': '0',
      };

      final category = XtreamCategory.fromJson(json);

      expect(category.id, '123');
      expect(category.name, 'Sports');
      expect(category.parentId, 0);
    });

    test('should handle integer category_id', () {
      final json = {
        'category_id': 456,
        'category_name': 'Movies',
      };

      final category = XtreamCategory.fromJson(json);

      expect(category.id, '456');
      expect(category.name, 'Movies');
      expect(category.parentId, null);
    });

    test('should handle missing fields', () {
      final json = <String, dynamic>{};

      final category = XtreamCategory.fromJson(json);

      expect(category.id, '');
      expect(category.name, '');
      expect(category.parentId, null);
    });
  });

  group('XtreamChannel', () {
    test('should parse from JSON with all fields', () {
      final json = {
        'stream_id': '12345',
        'name': 'ESPN HD',
        'stream_icon': 'http://example.com/espn.png',
        'epg_channel_id': 'espn.us',
        'category_id': '1',
        'num': '101',
      };

      final channel = XtreamChannel.fromJson(json);

      expect(channel.id, 12345);
      expect(channel.name, 'ESPN HD');
      expect(channel.streamIcon, 'http://example.com/espn.png');
      expect(channel.epgChannelId, 'espn.us');
      expect(channel.categoryId, '1');
      expect(channel.channelNumber, 101);
    });

    test('should handle integer stream_id', () {
      final json = {
        'stream_id': 789,
        'name': 'CNN',
        'stream_icon': '',
        'epg_channel_id': '',
        'category_id': 2,
      };

      final channel = XtreamChannel.fromJson(json);

      expect(channel.id, 789);
      expect(channel.categoryId, '2');
      expect(channel.channelNumber, null);
    });

    test('should handle missing fields', () {
      final json = <String, dynamic>{};

      final channel = XtreamChannel.fromJson(json);

      expect(channel.id, 0);
      expect(channel.name, '');
      expect(channel.streamIcon, '');
      expect(channel.epgChannelId, '');
      expect(channel.categoryId, '');
      expect(channel.channelNumber, null);
    });
  });

  group('XtreamVodItem', () {
    test('should parse from JSON with all fields', () {
      final json = {
        'stream_id': '5678',
        'name': 'The Matrix',
        'stream_icon': 'http://example.com/matrix.jpg',
        'category_id': '10',
        'plot': 'A computer hacker learns about the true nature of reality.',
        'cast': 'Keanu Reeves, Laurence Fishburne',
        'director': 'The Wachowskis',
        'genre': 'Sci-Fi, Action',
        'releaseDate': '1999-03-31',
        'rating': '8.7',
      };

      final vod = XtreamVodItem.fromJson(json);

      expect(vod.id, 5678);
      expect(vod.name, 'The Matrix');
      expect(vod.streamIcon, 'http://example.com/matrix.jpg');
      expect(vod.categoryId, '10');
      expect(vod.plot, 'A computer hacker learns about the true nature of reality.');
      expect(vod.cast, 'Keanu Reeves, Laurence Fishburne');
      expect(vod.director, 'The Wachowskis');
      expect(vod.genre, 'Sci-Fi, Action');
      expect(vod.releaseDate, '1999-03-31');
      expect(vod.rating, closeTo(8.7, 0.01));
    });

    test('should handle missing optional fields', () {
      final json = {
        'stream_id': '1000',
        'name': 'Unknown Movie',
        'stream_icon': '',
        'category_id': '1',
      };

      final vod = XtreamVodItem.fromJson(json);

      expect(vod.id, 1000);
      expect(vod.name, 'Unknown Movie');
      expect(vod.plot, null);
      expect(vod.cast, null);
      expect(vod.director, null);
      expect(vod.genre, null);
      expect(vod.releaseDate, null);
      expect(vod.rating, null);
    });

    test('should handle integer rating', () {
      final json = {
        'stream_id': '100',
        'name': 'Movie',
        'stream_icon': '',
        'category_id': '1',
        'rating': 7,
      };

      final vod = XtreamVodItem.fromJson(json);

      expect(vod.rating, 7.0);
    });
  });

  group('XtreamSeries', () {
    test('should parse from JSON with all fields', () {
      final json = {
        'series_id': '999',
        'name': 'Breaking Bad',
        'cover': 'http://example.com/bb.jpg',
        'category_id': '5',
        'plot': 'A high school chemistry teacher turned meth producer.',
        'cast': 'Bryan Cranston, Aaron Paul',
        'director': 'Vince Gilligan',
        'genre': 'Drama, Crime',
        'rating': '9.5',
      };

      final series = XtreamSeries.fromJson(json);

      expect(series.id, 999);
      expect(series.name, 'Breaking Bad');
      expect(series.cover, 'http://example.com/bb.jpg');
      expect(series.categoryId, '5');
      expect(series.plot, 'A high school chemistry teacher turned meth producer.');
      expect(series.cast, 'Bryan Cranston, Aaron Paul');
      expect(series.director, 'Vince Gilligan');
      expect(series.genre, 'Drama, Crime');
      expect(series.rating, closeTo(9.5, 0.01));
    });

    test('should handle integer series_id', () {
      final json = {
        'series_id': 123,
        'name': 'Show',
        'cover': '',
        'category_id': 1,
      };

      final series = XtreamSeries.fromJson(json);

      expect(series.id, 123);
      expect(series.categoryId, '1');
    });

    test('should handle missing optional fields', () {
      final json = {
        'series_id': '50',
        'name': 'Unknown Series',
        'cover': '',
        'category_id': '1',
      };

      final series = XtreamSeries.fromJson(json);

      expect(series.id, 50);
      expect(series.plot, null);
      expect(series.cast, null);
      expect(series.director, null);
      expect(series.genre, null);
      expect(series.rating, null);
    });
  });

  group('XtreamApiClient URL builders', () {
    late XtreamApiClient client;

    setUp(() {
      client = XtreamApiClient(
        serverUrl: 'http://example.com',
        username: 'user',
        password: 'pass',
      );
    });

    test('getLiveStreamUrl should build correct URL', () {
      final url = client.getLiveStreamUrl(12345);
      expect(url, 'http://example.com/user/pass/12345.m3u8');
    });

    test('getLiveStreamUrl should support custom format', () {
      final url = client.getLiveStreamUrl(12345, format: 'ts');
      expect(url, 'http://example.com/user/pass/12345.ts');
    });

    test('getVodStreamUrl should build correct URL', () {
      final url = client.getVodStreamUrl(5678);
      expect(url, 'http://example.com/movie/user/pass/5678.m3u8');
    });

    test('getVodStreamUrl should support custom format', () {
      final url = client.getVodStreamUrl(5678, format: 'mp4');
      expect(url, 'http://example.com/movie/user/pass/5678.mp4');
    });

    test('getSeriesStreamUrl should build correct URL', () {
      final url = client.getSeriesStreamUrl(999);
      expect(url, 'http://example.com/series/user/pass/999.m3u8');
    });

    test('getSeriesStreamUrl should support custom format', () {
      final url = client.getSeriesStreamUrl(999, format: 'ts');
      expect(url, 'http://example.com/series/user/pass/999.ts');
    });

    test('should handle serverUrl with trailing slash', () {
      final clientWithSlash = XtreamApiClient(
        serverUrl: 'http://example.com/',
        username: 'user',
        password: 'pass',
      );

      expect(clientWithSlash.getLiveStreamUrl(100), 'http://example.com/user/pass/100.m3u8');
      expect(clientWithSlash.getVodStreamUrl(200), 'http://example.com/movie/user/pass/200.m3u8');
      expect(clientWithSlash.getSeriesStreamUrl(300), 'http://example.com/series/user/pass/300.m3u8');
    });

    test('should handle serverUrl with port', () {
      final clientWithPort = XtreamApiClient(
        serverUrl: 'http://example.com:8080',
        username: 'user',
        password: 'pass',
      );

      expect(clientWithPort.getLiveStreamUrl(100), 'http://example.com:8080/user/pass/100.m3u8');
    });
  });
}
