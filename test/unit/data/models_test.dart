import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/models/channel.dart';
import 'package:flowtv/data/models/playlist.dart';
import 'package:flowtv/data/models/recording.dart';
import 'package:flowtv/data/models/epg_program.dart';

void main() {
  group('Channel', () {
    test('should create channel with factory constructor', () {
      final channel = Channel.create(
        playlistId: 1,
        name: 'Test Channel',
        streamUrl: 'http://example.com/stream.m3u8',
        logoUrl: 'http://example.com/logo.png',
        epgId: 'test.channel',
        group: 'Sports',
        channelNumber: 42,
      );

      expect(channel.playlistId, 1);
      expect(channel.name, 'Test Channel');
      expect(channel.streamUrl, 'http://example.com/stream.m3u8');
      expect(channel.logoUrl, 'http://example.com/logo.png');
      expect(channel.epgId, 'test.channel');
      expect(channel.group, 'Sports');
      expect(channel.channelNumber, 42);
    });

    test('should have default values', () {
      final channel = Channel.create(
        playlistId: 1,
        name: 'Test',
        streamUrl: 'http://example.com/stream.m3u8',
      );

      expect(channel.isFavorite, false);
      expect(channel.isLocked, false);
      expect(channel.lastWatched, null);
      expect(channel.sortOrder, 0);
      expect(channel.isVod, false);
    });

    test('should allow setting optional properties', () {
      final channel = Channel.create(
        playlistId: 1,
        name: 'Test',
        streamUrl: 'http://example.com/stream.m3u8',
      );

      channel.language = 'English';
      channel.country = 'US';
      channel.isVod = true;
      channel.isFavorite = true;

      expect(channel.language, 'English');
      expect(channel.country, 'US');
      expect(channel.isVod, true);
      expect(channel.isFavorite, true);
    });
  });

  group('Playlist', () {
    group('factory constructor', () {
      test('should create M3U playlist', () {
        final playlist = Playlist.create(
          name: 'My Playlist',
          url: 'http://example.com/playlist.m3u',
          type: PlaylistType.m3u,
        );

        expect(playlist.name, 'My Playlist');
        expect(playlist.url, 'http://example.com/playlist.m3u');
        expect(playlist.type, PlaylistType.m3u);
        expect(playlist.createdAt, isA<DateTime>());
      });

      test('should create Xtream playlist with credentials', () {
        final playlist = Playlist.create(
          name: 'Xtream Playlist',
          url: 'http://xtream.server.com',
          type: PlaylistType.xtream,
          username: 'user123',
          password: 'pass456',
        );

        expect(playlist.type, PlaylistType.xtream);
        expect(playlist.username, 'user123');
        expect(playlist.password, 'pass456');
      });

      test('should create playlist with EPG URL', () {
        final playlist = Playlist.create(
          name: 'Test',
          url: 'http://example.com/playlist.m3u',
          type: PlaylistType.m3u,
          epgUrl: 'http://example.com/epg.xml',
        );

        expect(playlist.epgUrl, 'http://example.com/epg.xml');
      });
    });

    test('should have default values', () {
      final playlist = Playlist.create(
        name: 'Test',
        url: 'http://example.com',
        type: PlaylistType.m3u,
      );

      expect(playlist.lastRefresh, null);
      expect(playlist.channelCount, 0);
      expect(playlist.isActive, false);
      expect(playlist.sortOrder, 0);
    });

    test('PlaylistType should have all expected values', () {
      expect(PlaylistType.values.length, 3);
      expect(PlaylistType.values.contains(PlaylistType.m3u), true);
      expect(PlaylistType.values.contains(PlaylistType.xtream), true);
      expect(PlaylistType.values.contains(PlaylistType.file), true);
    });
  });

  group('Recording', () {
    test('should create recording with factory constructor', () {
      final now = DateTime.now();
      final endTime = now.add(const Duration(hours: 1));

      final recording = Recording.create(
        channelId: 1,
        title: 'Football Match',
        filePath: '/recordings/match.mp4',
        scheduledStart: now,
        scheduledEnd: endTime,
      );

      expect(recording.channelId, 1);
      expect(recording.title, 'Football Match');
      expect(recording.filePath, '/recordings/match.mp4');
      expect(recording.scheduledStart, now);
      expect(recording.scheduledEnd, endTime);
      expect(recording.status, RecordingStatus.scheduled);
      expect(recording.createdAt, isA<DateTime>());
    });

    test('should create recording with EPG program ID', () {
      final recording = Recording.create(
        channelId: 1,
        title: 'Show',
        filePath: '/path.mp4',
        scheduledStart: DateTime.now(),
        scheduledEnd: DateTime.now().add(const Duration(hours: 1)),
        epgProgramId: 12345,
      );

      expect(recording.epgProgramId, 12345);
    });

    test('should have default values', () {
      final recording = Recording.create(
        channelId: 1,
        title: 'Test',
        filePath: '/test.mp4',
        scheduledStart: DateTime.now(),
        scheduledEnd: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(recording.actualStart, null);
      expect(recording.actualEnd, null);
      expect(recording.fileSize, 0);
      expect(recording.durationSeconds, 0);
      expect(recording.errorMessage, null);
    });

    test('RecordingStatus should have all expected values', () {
      expect(RecordingStatus.values.length, 5);
      expect(RecordingStatus.values.contains(RecordingStatus.scheduled), true);
      expect(RecordingStatus.values.contains(RecordingStatus.recording), true);
      expect(RecordingStatus.values.contains(RecordingStatus.completed), true);
      expect(RecordingStatus.values.contains(RecordingStatus.failed), true);
      expect(RecordingStatus.values.contains(RecordingStatus.cancelled), true);
    });
  });

  group('EpgProgram', () {
    test('should create EPG program with factory constructor', () {
      final startTime = DateTime(2024, 1, 15, 20, 0);
      final endTime = DateTime(2024, 1, 15, 21, 0);

      final program = EpgProgram.create(
        channelId: 'channel.1',
        title: 'Evening News',
        startTime: startTime,
        endTime: endTime,
      );

      expect(program.channelId, 'channel.1');
      expect(program.title, 'Evening News');
      expect(program.startTime, startTime);
      expect(program.endTime, endTime);
    });

    test('should create program with all optional fields', () {
      final program = EpgProgram.create(
        channelId: 'channel.1',
        title: 'Drama Series',
        startTime: DateTime(2024, 1, 15, 20, 0),
        endTime: DateTime(2024, 1, 15, 21, 0),
        description: 'An exciting episode',
        category: 'Drama',
        episode: 'S05E10',
        iconUrl: 'http://example.com/poster.jpg',
      );

      expect(program.description, 'An exciting episode');
      expect(program.category, 'Drama');
      expect(program.episode, 'S05E10');
      expect(program.iconUrl, 'http://example.com/poster.jpg');
    });

    group('durationMinutes', () {
      test('should calculate duration correctly', () {
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: DateTime(2024, 1, 15, 20, 0),
          endTime: DateTime(2024, 1, 15, 21, 30),
        );

        expect(program.durationMinutes, 90);
      });

      test('should handle short programs', () {
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: DateTime(2024, 1, 15, 20, 0),
          endTime: DateTime(2024, 1, 15, 20, 15),
        );

        expect(program.durationMinutes, 15);
      });
    });

    group('isLive', () {
      test('should return true for currently airing program', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.subtract(const Duration(minutes: 30)),
          endTime: now.add(const Duration(minutes: 30)),
        );

        expect(program.isLive, true);
      });

      test('should return false for past program', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.subtract(const Duration(hours: 2)),
          endTime: now.subtract(const Duration(hours: 1)),
        );

        expect(program.isLive, false);
      });

      test('should return false for future program', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.add(const Duration(hours: 1)),
          endTime: now.add(const Duration(hours: 2)),
        );

        expect(program.isLive, false);
      });
    });

    group('progress', () {
      test('should return 0 for non-live program', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.add(const Duration(hours: 1)),
          endTime: now.add(const Duration(hours: 2)),
        );

        expect(program.progress, 0.0);
      });

      test('should return progress for live program', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.subtract(const Duration(minutes: 30)),
          endTime: now.add(const Duration(minutes: 30)),
        );

        // Should be around 0.5 (halfway through)
        expect(program.progress, closeTo(0.5, 0.1));
      });

      test('should clamp progress between 0 and 1', () {
        final now = DateTime.now();
        final program = EpgProgram.create(
          channelId: 'channel.1',
          title: 'Test',
          startTime: now.subtract(const Duration(minutes: 10)),
          endTime: now.add(const Duration(minutes: 50)),
        );

        expect(program.progress, greaterThanOrEqualTo(0.0));
        expect(program.progress, lessThanOrEqualTo(1.0));
      });
    });
  });
}
