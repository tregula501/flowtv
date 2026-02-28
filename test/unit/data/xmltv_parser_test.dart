import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/datasources/remote/xmltv_parser.dart';
import 'package:flowtv/core/errors/exceptions.dart';

void main() {
  group('XmltvParser', () {
    late XmltvParser parser;

    setUp(() {
      parser = XmltvParser();
    });

    group('parseContent', () {
      test('should parse basic XMLTV with single program', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programCount, 1);
        expect(result.channelCount, 1);
        expect(result.programs[0].title, 'Test Program');
        expect(result.programs[0].channelId, 'channel.1');
      });

      test('should parse multiple programs', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Program 1</title>
  </programme>
  <programme start="20240115130000 +0000" stop="20240115140000 +0000" channel="channel.1">
    <title>Program 2</title>
  </programme>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.2">
    <title>Program 3</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 3);
        expect(result.programCount, 3);
        expect(result.channelCount, 2);
      });

      test('should parse program description', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
    <desc>This is a test description</desc>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].description, 'This is a test description');
      });

      test('should parse program category', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
    <category>Sports</category>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].category, 'Sports');
      });

      test('should parse episode number', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
    <episode-num>S01E05</episode-num>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].episode, 'S01E05');
      });

      test('should parse icon URL', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
    <icon src="http://example.com/poster.jpg"/>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].iconUrl, 'http://example.com/poster.jpg');
      });

      test('should parse date with timezone offset', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0500" stop="20240115130000 +0500" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // 12:00 +0500 should convert to 07:00 UTC
        expect(result.programs[0].startTime.hour, 7);
      });

      test('should parse date without timezone', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000" stop="20240115130000" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].startTime.hour, 12);
      });

      test('should skip programs without required attributes', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" channel="channel.1">
    <title>Missing stop</title>
  </programme>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Complete Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].title, 'Complete Program');
      });

      test('should use "Unknown" for missing title', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].title, 'Unknown');
      });

      test('should handle negative timezone offset', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 -0500" stop="20240115130000 -0500" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // 12:00 -0500 should convert to 17:00 UTC
        expect(result.programs[0].startTime.hour, 17);
      });

      test('should throw EpgParseException for invalid XML', () async {
        const content = '''This is not valid XML''';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<EpgParseException>()),
        );
      });

      test('should throw EpgParseException for missing tv element', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<notTv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test</title>
  </programme>
</notTv>''';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<EpgParseException>()),
        );
      });

      test('should count unique channels correctly', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Program 1</title>
  </programme>
  <programme start="20240115130000 +0000" stop="20240115140000 +0000" channel="channel.1">
    <title>Program 2</title>
  </programme>
  <programme start="20240115140000 +0000" stop="20240115150000 +0000" channel="channel.1">
    <title>Program 3</title>
  </programme>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.2">
    <title>Program 4</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programCount, 4);
        expect(result.channelCount, 2);
      });

      test('should handle all optional fields being null', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Minimal Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].description, null);
        expect(result.programs[0].category, null);
        expect(result.programs[0].episode, null);
        expect(result.programs[0].iconUrl, null);
      });

      test('should parse complete program with all fields', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Full Program</title>
    <desc>A complete description of the program</desc>
    <category>Drama</category>
    <episode-num>S02E10</episode-num>
    <icon src="http://example.com/image.jpg"/>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);
        final program = result.programs[0];

        expect(program.title, 'Full Program');
        expect(program.description, 'A complete description of the program');
        expect(program.category, 'Drama');
        expect(program.episode, 'S02E10');
        expect(program.iconUrl, 'http://example.com/image.jpg');
        expect(program.channelId, 'channel.1');
      });
    });
  });
}
