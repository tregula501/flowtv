import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/core/models/buffer_size.dart';

void main() {
  group('BufferSize enum', () {
    test('has exactly 5 values', () {
      expect(BufferSize.values.length, 5);
    });

    test('all expected enum values exist', () {
      expect(BufferSize.values, contains(BufferSize.small));
      expect(BufferSize.values, contains(BufferSize.medium));
      expect(BufferSize.values, contains(BufferSize.large));
      expect(BufferSize.values, contains(BufferSize.veryLarge));
      expect(BufferSize.values, contains(BufferSize.extraLarge));
    });
  });

  group('BufferSize.durationSeconds', () {
    test('small returns 1', () {
      expect(BufferSize.small.durationSeconds, 1);
    });

    test('medium returns 5', () {
      expect(BufferSize.medium.durationSeconds, 5);
    });

    test('large returns 15', () {
      expect(BufferSize.large.durationSeconds, 15);
    });

    test('veryLarge returns 30', () {
      expect(BufferSize.veryLarge.durationSeconds, 30);
    });

    test('extraLarge returns 60', () {
      expect(BufferSize.extraLarge.durationSeconds, 60);
    });
  });

  group('BufferSize.displayName', () {
    for (final size in BufferSize.values) {
      test('${size.name} returns a non-empty displayName', () {
        expect(size.displayName, isNotEmpty);
      });
    }

    test('displayNames contain the duration hint', () {
      expect(BufferSize.small.displayName, contains('1s'));
      expect(BufferSize.medium.displayName, contains('5s'));
      expect(BufferSize.large.displayName, contains('15s'));
      expect(BufferSize.veryLarge.displayName, contains('30s'));
      expect(BufferSize.extraLarge.displayName, contains('60s'));
    });
  });

  group('BufferSize.description', () {
    for (final size in BufferSize.values) {
      test('${size.name} returns a non-empty description', () {
        expect(size.description, isNotEmpty);
      });
    }

    test('descriptions are distinct from each other', () {
      final descriptions = BufferSize.values.map((s) => s.description).toSet();
      expect(descriptions.length, BufferSize.values.length,
          reason: 'Each BufferSize should have a unique description');
    });
  });

  group('BufferSize.minBufferBeforeResume', () {
    test('small returns 1', () {
      expect(BufferSize.small.minBufferBeforeResume, 1);
    });

    test('medium returns 2', () {
      expect(BufferSize.medium.minBufferBeforeResume, 2);
    });

    test('large returns 5', () {
      expect(BufferSize.large.minBufferBeforeResume, 5);
    });

    test('veryLarge returns 10', () {
      expect(BufferSize.veryLarge.minBufferBeforeResume, 10);
    });

    test('extraLarge returns 15', () {
      expect(BufferSize.extraLarge.minBufferBeforeResume, 15);
    });

    test('minBufferBeforeResume is always <= durationSeconds', () {
      for (final size in BufferSize.values) {
        expect(
          size.minBufferBeforeResume,
          lessThanOrEqualTo(size.durationSeconds),
          reason:
              '${size.name}.minBufferBeforeResume (${size.minBufferBeforeResume}) '
              'should be <= durationSeconds (${size.durationSeconds})',
        );
      }
    });
  });

  group('BufferSize ordering', () {
    test('durationSeconds are strictly increasing from small to extraLarge',
        () {
      final sizes = BufferSize.values;
      for (int i = 0; i < sizes.length - 1; i++) {
        expect(
          sizes[i].durationSeconds,
          lessThan(sizes[i + 1].durationSeconds),
          reason:
              '${sizes[i].name}.durationSeconds (${sizes[i].durationSeconds}) '
              'should be less than '
              '${sizes[i + 1].name}.durationSeconds (${sizes[i + 1].durationSeconds})',
        );
      }
    });

    test('minBufferBeforeResume values are non-decreasing', () {
      final sizes = BufferSize.values;
      for (int i = 0; i < sizes.length - 1; i++) {
        expect(
          sizes[i].minBufferBeforeResume,
          lessThanOrEqualTo(sizes[i + 1].minBufferBeforeResume),
          reason:
              '${sizes[i].name}.minBufferBeforeResume (${sizes[i].minBufferBeforeResume}) '
              'should be <= '
              '${sizes[i + 1].name}.minBufferBeforeResume (${sizes[i + 1].minBufferBeforeResume})',
        );
      }
    });
  });
}
