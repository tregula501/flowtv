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
      test('should parse basic M3U with single channel', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels.length, 1);
        expect(result.channels[0].name, 'Test Channel');
        expect(result.channels[0].streamUrl, 'http://example.com/stream.m3u8');
        expect(result.channels[0].group, 'Uncategorized');
      });

      test('should parse M3U with multiple channels', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Channel 1
http://example.com/stream1.m3u8
#EXTINF:-1,Channel 2
http://example.com/stream2.m3u8
#EXTINF:-1,Channel 3
http://example.com/stream3.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels.length, 3);
        expect(result.channels[0].name, 'Channel 1');
        expect(result.channels[1].name, 'Channel 2');
        expect(result.channels[2].name, 'Channel 3');
      });

      test('should parse tvg-logo attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-logo="http://example.com/logo.png",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].logoUrl, 'http://example.com/logo.png');
      });

      test('should parse tvg-id attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-id="channel.id",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].epgId, 'channel.id');
      });

      test('should parse group-title attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 group-title="Sports",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].group, 'Sports');
        expect(result.groupCounts['Sports'], 1);
      });

      test('should parse tvg-chno (channel number) attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-chno="42",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].channelNumber, 42);
      });

      test('should parse tvg-language attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-language="English",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].language, 'English');
      });

      test('should parse tvg-country attribute', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-country="US",Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].country, 'US');
      });

      test('should parse multiple attributes on same line', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://logo.png" group-title="News" tvg-chno="100",CNN
http://example.com/cnn.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].name, 'CNN');
        expect(result.channels[0].epgId, 'cnn.us');
        expect(result.channels[0].logoUrl, 'http://logo.png');
        expect(result.channels[0].group, 'News');
        expect(result.channels[0].channelNumber, 100);
      });

      test('should extract EPG URL from x-tvg-url in header', () async {
        const content = '''#EXTM3U x-tvg-url="http://example.com/epg.xml"
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.epgUrl, 'http://example.com/epg.xml');
      });

      test('should extract EPG URL from url-tvg in header', () async {
        const content = '''#EXTM3U url-tvg="http://example.com/epg.xml"
#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.epgUrl, 'http://example.com/epg.xml');
      });

      test('should count channels per group correctly', () async {
        const content = '''#EXTM3U
#EXTINF:-1 group-title="Sports",ESPN
http://example.com/espn.m3u8
#EXTINF:-1 group-title="Sports",Fox Sports
http://example.com/fox.m3u8
#EXTINF:-1 group-title="News",CNN
http://example.com/cnn.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.groupCounts['Sports'], 2);
        expect(result.groupCounts['News'], 1);
      });

      test('should handle single quotes in attributes', () async {
        const content = '''#EXTM3U
#EXTINF:-1 tvg-logo='http://example.com/logo.png',Test Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].logoUrl, 'http://example.com/logo.png');
      });

      test('should detect VOD items by URL pattern /movie/', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Test Movie
http://example.com/movie/123.mp4''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect VOD items by URL pattern /series/', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Test Series Episode
http://example.com/series/123.mp4''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect VOD items by .mp4 extension', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Test Video
http://example.com/video.mp4''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].isVod, true);
      });

      test('should detect live streams (not VOD)', () async {
        const content = '''#EXTM3U
#EXTINF:-1,Live Channel
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].isVod, false);
      });

      test('should throw PlaylistParseException for missing header', () async {
        const content = '''#EXTINF:-1,Test Channel
http://example.com/stream.m3u8''';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<PlaylistParseException>()),
        );
      });

      test('should throw PlaylistParseException for empty content', () async {
        const content = '';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<PlaylistParseException>()),
        );
      });

      test('should handle empty lines between entries', () async {
        const content = '''#EXTM3U

#EXTINF:-1,Channel 1
http://example.com/stream1.m3u8

#EXTINF:-1,Channel 2
http://example.com/stream2.m3u8
''';

        final result = await parser.parseContent(content);

        expect(result.channels.length, 2);
      });

      test('should skip comment lines', () async {
        const content = '''#EXTM3U
# This is a comment
#EXTINF:-1,Test Channel
# Another comment
http://example.com/stream.m3u8''';

        final result = await parser.parseContent(content);

        expect(result.channels.length, 1);
      });

      test('should trim whitespace from lines', () async {
        const content = '''#EXTM3U
  #EXTINF:-1,Test Channel
  http://example.com/stream.m3u8  ''';

        final result = await parser.parseContent(content);

        expect(result.channels[0].name, 'Test Channel');
        expect(result.channels[0].streamUrl, 'http://example.com/stream.m3u8');
      });
    });

    group('M3uChannel', () {
      test('should store all properties correctly', () {
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

        expect(m3uChannel.name, 'Test Channel');
        expect(m3uChannel.streamUrl, 'http://example.com/stream.m3u8');
        expect(m3uChannel.logoUrl, 'http://example.com/logo.png');
        expect(m3uChannel.epgId, 'test.channel');
        expect(m3uChannel.group, 'Sports');
        expect(m3uChannel.channelNumber, 42);
        expect(m3uChannel.language, 'English');
        expect(m3uChannel.country, 'US');
        expect(m3uChannel.isVod, false);
      });
    });
  });
}
