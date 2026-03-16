import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/datasources/remote/xmltv_parser.dart';
import 'package:flowtv/core/errors/exceptions.dart';

void main() {
  group('XmltvParser', () {
    late XmltvParser parser;

    setUp(() {
      parser = XmltvParser();
    });

    tearDown(() {
      parser.close();
    });

    group('parseContent', () {
      test('should parse valid XMLTV content with multiple programmes',
          () async {
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
        expect(result.programs[0].title, 'Program 1');
        expect(result.programs[1].title, 'Program 2');
        expect(result.programs[2].title, 'Program 3');
      });

      test('should throw EpgParseException for missing <tv> root element',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<notTv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test</title>
  </programme>
</notTv>''';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<EpgParseException>().having(
            (e) => e.message,
            'message',
            contains('missing <tv> root element'),
          )),
        );
      });

      test(
          'should skip programmes with missing channel attribute',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000">
    <title>Missing channel</title>
  </programme>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Complete Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].title, 'Complete Program');
      });

      test('should skip programmes with missing start attribute', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme stop="20240115130000 +0000" channel="channel.1">
    <title>Missing start</title>
  </programme>
  <programme start="20240115130000 +0000" stop="20240115140000 +0000" channel="channel.1">
    <title>Valid Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].title, 'Valid Program');
      });

      test('should skip programmes with missing stop attribute', () async {
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

      test('should skip programmes with malformed start date strings',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="not-a-date" stop="20240115130000 +0000" channel="channel.1">
    <title>Bad start date</title>
  </programme>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Good Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].title, 'Good Program');
      });

      test('should skip programmes with malformed stop date strings',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="xyz" channel="channel.1">
    <title>Bad stop date</title>
  </programme>
  <programme start="20240115130000 +0000" stop="20240115140000 +0000" channel="channel.1">
    <title>Good Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].title, 'Good Program');
      });

      test('should handle positive timezone offsets correctly', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0500" stop="20240115130000 +0500" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // 12:00 +0500 = 12:00 UTC - 5h = 07:00 UTC
        expect(result.programs[0].startTime.hour, 7);
        expect(result.programs[0].startTime.isUtc, isTrue);
      });

      test('should handle negative timezone offsets correctly', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 -0500" stop="20240115130000 -0500" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // 12:00 -0500 = 12:00 UTC + 5h = 17:00 UTC
        expect(result.programs[0].startTime.hour, 17);
        expect(result.programs[0].startTime.isUtc, isTrue);
      });

      test('should handle timezone offset with minutes', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0530" stop="20240115130000 +0530" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // 12:00 +0530 = 12:00 UTC - 5h30m = 06:30 UTC
        expect(result.programs[0].startTime.hour, 6);
        expect(result.programs[0].startTime.minute, 30);
      });

      test('should handle dates without timezone (local time)', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000" stop="20240115130000" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].startTime.hour, 12);
      });

      test('should handle dates without seconds', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="202401151200 +0000" stop="202401151300 +0000" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        // Should parse with second=0
        expect(result.programs[0].startTime.hour, 12);
        expect(result.programs[0].startTime.minute, 0);
      });

      test('should throw EpgParseException for empty content', () async {
        const content = '';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<EpgParseException>()),
        );
      });

      test('should handle programme with all optional fields', () async {
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

      test('should handle programme with no optional fields', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Minimal Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);
        final program = result.programs[0];

        expect(program.title, 'Minimal Program');
        expect(program.description, isNull);
        expect(program.category, isNull);
        expect(program.episode, isNull);
        expect(program.iconUrl, isNull);
      });

      test('should use "Unknown" title when title element is missing',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].title, 'Unknown');
      });

      test('should handle large number of programmes efficiently', () async {
        // Generate 500 programmes across 50 channels
        final buffer = StringBuffer(
            '<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n');
        for (int i = 0; i < 500; i++) {
          final channelNum = i % 50;
          final hour = 10 + (i ~/ 50);
          final startHour = hour.toString().padLeft(2, '0');
          final endHour = (hour + 1).toString().padLeft(2, '0');
          buffer.writeln(
            '  <programme start="20240115${startHour}0000 +0000" '
            'stop="20240115${endHour}0000 +0000" '
            'channel="channel.$channelNum">'
            '<title>Program $i</title>'
            '</programme>',
          );
        }
        buffer.writeln('</tv>');

        final stopwatch = Stopwatch()..start();
        final result = await parser.parseContent(buffer.toString());
        stopwatch.stop();

        expect(result.programs.length, 500);
        expect(result.programCount, 500);
        expect(result.channelCount, 50);
        // Parsing 500 programmes should be well under 5 seconds even on CI
        expect(stopwatch.elapsedMilliseconds, lessThan(5000));
      });

      test('should count unique channel IDs correctly', () async {
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
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.3">
    <title>Program 5</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programCount, 5);
        // 3 unique channels: channel.1, channel.2, channel.3
        expect(result.channelCount, 3);
      });

      test('should parse single programme with correct start/end times',
          () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>Test Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs.length, 1);
        expect(result.programs[0].startTime,
            DateTime.utc(2024, 1, 15, 12, 0, 0));
        expect(result.programs[0].endTime,
            DateTime.utc(2024, 1, 15, 13, 0, 0));
      });

      test('should parse description element', () async {
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

      test('should parse category element', () async {
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

      test('should parse episode-num element', () async {
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

      test('should parse icon element with src attribute', () async {
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

      test('should handle TV root with no programmes', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs, isEmpty);
        expect(result.programCount, 0);
        expect(result.channelCount, 0);
      });

      test('should throw EpgParseException for completely invalid XML',
          () async {
        const content = 'This is not valid XML at all';

        await expectLater(
          parser.parseContent(content),
          throwsA(isA<EpgParseException>()),
        );
      });

      test('should handle +0000 timezone as UTC', () async {
        const content = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20240115120000 +0000" stop="20240115130000 +0000" channel="channel.1">
    <title>UTC Program</title>
  </programme>
</tv>''';

        final result = await parser.parseContent(content);

        expect(result.programs[0].startTime,
            DateTime.utc(2024, 1, 15, 12, 0, 0));
      });
    });
  });

  group('XmltvProgram', () {
    test('should store all required fields', () {
      final program = XmltvProgram(
        channelId: 'ch1',
        title: 'Test',
        startTime: DateTime(2024, 1, 15, 12),
        endTime: DateTime(2024, 1, 15, 13),
      );

      expect(program.channelId, 'ch1');
      expect(program.title, 'Test');
      expect(program.startTime, DateTime(2024, 1, 15, 12));
      expect(program.endTime, DateTime(2024, 1, 15, 13));
      expect(program.description, isNull);
      expect(program.category, isNull);
      expect(program.episode, isNull);
      expect(program.iconUrl, isNull);
    });

    test('should store all optional fields', () {
      final program = XmltvProgram(
        channelId: 'ch1',
        title: 'Test',
        startTime: DateTime(2024, 1, 15, 12),
        endTime: DateTime(2024, 1, 15, 13),
        description: 'A description',
        category: 'News',
        episode: 'S01E01',
        iconUrl: 'http://example.com/icon.png',
      );

      expect(program.description, 'A description');
      expect(program.category, 'News');
      expect(program.episode, 'S01E01');
      expect(program.iconUrl, 'http://example.com/icon.png');
    });
  });

  group('XmltvParseResult', () {
    test('should store programs, channelCount, and programCount', () {
      final result = XmltvParseResult(
        programs: [
          XmltvProgram(
            channelId: 'ch1',
            title: 'Test',
            startTime: DateTime(2024, 1, 15, 12),
            endTime: DateTime(2024, 1, 15, 13),
          ),
        ],
        channelCount: 1,
        programCount: 1,
      );

      expect(result.programs.length, 1);
      expect(result.channelCount, 1);
      expect(result.programCount, 1);
    });
  });
}
