import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/datasources/remote/m3u_parser.dart';
import 'package:flowtv/core/errors/exceptions.dart';

void main() {
  group('M3uParser', () {
    late M3uParser parser;

    setUp(() {
      parser = M3uParser();
    });

    group('parseContent', () {
      test('should parse basic M3U with single channel', () {
        const content = '''#EXTM3U
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels.length, 1);
        expect(result.channels[0].name, 'Test Channel');
        expect(result.channels[0].streamUrl, 'http://example.com/stream.m3u8');
        expect(result.channels[0].group, 'Uncategorized');
      });

      test('should parse M3U with multiple channels', () {
        const content = '''#EXTM3U
#EXTINF:-1,Channel 1
http://example.com/stream1.m3u8
#EXTINF:-1,Channel 2
http://example.com/stream2.m3u8
#EXTINF:-1,Channel 3
http://example.com/stream3.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels.length, 3);
        expect(result.channels[0].name, 'Channel 1');
        expect(result.channels[1].name, 'Channel 2');
        expect(result.channels[2].name, 'Channel 3');
      });

      test('should parse tvg-logo attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-logo="http://example.com/logo.png",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].logoUrl, 'http://example.com/logo.png');
      });

      test('should parse tvg-id attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-id="channel.id",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].epgId, 'channel.id');
      });

      test('should parse group-title attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 group-title="Sports",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].group, 'Sports');
        expect(result.groupCounts['Sports'], 1);
      });

      test('should parse tvg-chno (channel number) attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-chno="42",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].channelNumber, 42);
      });

      test('should parse tvg-language attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-language="English",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].language, 'English');
      });

      test('should parse tvg-country attribute', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-country="US",Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].country, 'US');
      });

      test('should parse multiple attributes on same line', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://logo.png" group-title="News" tvg-chno="100",CNN
http://example.com/cnn.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].name, 'CNN');
        expect(result.channels[0].epgId, 'cnn.us');
        expect(result.channels[0].logoUrl, 'http://logo.png');
        expect(result.channels[0].group, 'News');
        expect(result.channels[0].channelNumber, 100);
      });

      test('should extract EPG URL from x-tvg-url in header', () {
        const content = '''#EXTM3U x-tvg-url="http://example.com/epg.xml"
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.epgUrl, 'http://example.com/epg.xml');
      });

      test('should extract EPG URL from url-tvg in header', () {
        const content = '''#EXTM3U url-tvg="http://example.com/epg.xml"
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.epgUrl, 'http://example.com/epg.xml');
      });

      test('should count channels per group correctly', () {
        const content = '''#EXTM3U
#EXTINF:-1 group-title="Sports",ESPN
http://example.com/espn.m3u8
#EXTINF:-1 group-title="Sports",Fox Sports
http://example.com/fox.m3u8
#EXTINF:-1 group-title="News",CNN
http://example.com/cnn.m3u8''';

        final result = parser.parseContent(content);

        expect(result.groupCounts['Sports'], 2);
        expect(result.groupCounts['News'], 1);
      });

      test('should handle single quotes in attributes', () {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-logo='http://example.com/logo.png',Test Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].logoUrl, 'http://example.com/logo.png');
      });

      test('should detect VOD items by URL pattern /movie/', () {
        const content = '''#EXTM3U
#EXTINF:-1,Test Movie
http://example.com/movie/123.mp4''';

        final result = parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect VOD items by URL pattern /series/', () {
        const content = '''#EXTM3U
#EXTINF:-1,Test Series Episode
http://example.com/series/123.mp4''';

        final result = parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect VOD items by .mp4 extension', () {
        const content = '''#EXTM3U
#EXTINF:-1,Test Video
http://example.com/video.mp4''';

        final result = parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect live streams (not VOD)', () {
        const content = '''#EXTM3U
#EXTINF:-1,Live Channel
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels[0].isVod, false);
      });

      test('should throw PlaylistParseException for missing header', () {
        const content = '''#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        expect(
          () => parser.parseContent(content),
          throwsA(isA<PlaylistParseException>()),
        );
      });

      test('should throw PlaylistParseException for empty content', () {
        const content = '';

        expect(
          () => parser.parseContent(content),
          throwsA(isA<PlaylistParseException>()),
        );
      });

      test('should handle empty lines between entries', () {
        const content = '''#EXTM3U

#EXTINF:-1,Channel 1
http://example.com/stream1.m3u8

#EXTINF:-1,Channel 2
http://example.com/stream2.m3u8
''';

        final result = parser.parseContent(content);

        expect(result.channels.length, 2);
      });

      test('should skip comment lines', () {
        const content = '''#EXTM3U
# This is a comment
#EXTINF:-1,Test Channel
# Another comment
http://example.com/stream.m3u8''';

        final result = parser.parseContent(content);

        expect(result.channels.length, 1);
      });

      test('should trim whitespace from lines', () {
        const content = '''#EXTM3U
  #EXTINF:-1,Test Channel
  http://example.com/stream.m3u8  ''';

        final result = parser.parseContent(content);

        expect(result.channels[0].name, 'Test Channel');
        expect(result.channels[0].streamUrl, 'http://example.com/stream.m3u8');
      });
    });

    group('M3uChannel', () {
      test('toChannel should create Channel with correct properties', () {
        final m3uChannel = M3uChannel(
          name: 'Test Channel',
          streamUrl: 'http://example.com/stream.m3u8',
          logoUrl: 'http://example.com/logo.png',
          epgId: 'test.channel',
          group: 'Sports',
          channelNumber: 42,
          language: 'English',
          country: 'US',
          isVod: false,
        );

        final channel = m3uChannel.toChannel(1);

        expect(channel.playlistId, 1);
        expect(channel.name, 'Test Channel');
        expect(channel.streamUrl, 'http://example.com/stream.m3u8');
        expect(channel.logoUrl, 'http://example.com/logo.png');
        expect(channel.epgId, 'test.channel');
        expect(channel.group, 'Sports');
        expect(channel.channelNumber, 42);
        expect(channel.language, 'English');
        expect(channel.country, 'US');
        expect(channel.isVod, false);
      });
    });
  });
}
