import 'package:flutter_test/flutter_test.dart';
import 'package:flowtv/data/datasources/local/drift/app_database.dart';

void main() {
  group('Channel', () {
    test('should create channel with constructor', () {
      const channel = Channel(
        id: 1,
        playlistId: 1,
        name: 'Test Channel',
        streamUrl: 'http://example.com/stream.m3u8',
        logoUrl: 'http://example.com/logo.png',
        epgId: 'test.channel',
        group: 'Sports',
        channelNumber: 42,
        isFavorite: false,
        isLocked: false,
        sortOrder: 0,
        isVod: false,
      );

      expect(channel.id, 1);
      expect(channel.playlistId, 1);
      expect(channel.name, 'Test Channel');
      expect(channel.streamUrl, 'http://example.com/stream.m3u8');
      expect(channel.logoUrl, 'http://example.com/logo.png');
      expect(channel.epgId, 'test.channel');
      expect(channel.group, 'Sports');
      expect(channel.channelNumber, 42);
    });

    test('should have correct default values', () {
      const channel = Channel(
        id: 1,
        playlistId: 1,
        name: 'Test',
        streamUrl: 'http://example.com/stream.m3u8',
        isFavorite: false,
        isLocked: false,
        sortOrder: 0,
        isVod: false,
      );

      expect(channel.isFavorite, false);
      expect(channel.isLocked, false);
      expect(channel.lastWatched, null);
      expect(channel.sortOrder, 0);
      expect(channel.isVod, false);
    });

    test('should support optional properties', () {
      const channel = Channel(
        id: 1,
        playlistId: 1,
        name: 'Test',
        streamUrl: 'http://example.com/stream.m3u8',
        isFavorite: true,
        isLocked: true,
        sortOrder: 5,
        isVod: true,
        language: 'English',
        country: 'US',
      );

      expect(channel.language, 'English');
      expect(channel.country, 'US');
      expect(channel.isVod, true);
      expect(channel.isFavorite, true);
    });
  });

  group('Playlist', () {
    test('should create M3U playlist', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 1,
        name: 'My Playlist',
        url: 'http://example.com/playlist.m3u',
        type: PlaylistType.m3u,
        channelCount: 0,
        isActive: false,
        createdAt: now,
        sortOrder: 0,
      );

      expect(playlist.name, 'My Playlist');
      expect(playlist.url, 'http://example.com/playlist.m3u');
      expect(playlist.type, PlaylistType.m3u);
      expect(playlist.createdAt, now);
    });

    test('should create Xtream playlist with credentials', () {
      final playlist = Playlist(
        id: 1,
        name: 'Xtream Playlist',
        url: 'http://xtream.server.com',
        type: PlaylistType.xtream,
        username: 'user123',
        password: 'pass456',
        channelCount: 0,
        isActive: false,
        createdAt: DateTime.now(),
        sortOrder: 0,
      );

      expect(playlist.type, PlaylistType.xtream);
      expect(playlist.username, 'user123');
      expect(playlist.password, 'pass456');
    });

    test('should create playlist with EPG URL', () {
      final playlist = Playlist(
        id: 1,
        name: 'Test',
        url: 'http://example.com/playlist.m3u',
        type: PlaylistType.m3u,
        epgUrl: 'http://example.com/epg.xml',
        channelCount: 0,
        isActive: false,
        createdAt: DateTime.now(),
        sortOrder: 0,
      );

      expect(playlist.epgUrl, 'http://example.com/epg.xml');
    });

    test('PlaylistType should have all expected values', () {
      expect(PlaylistType.values.length, 3);
      expect(PlaylistType.values.contains(PlaylistType.m3u), true);
      expect(PlaylistType.values.contains(PlaylistType.xtream), true);
      expect(PlaylistType.values.contains(PlaylistType.file), true);
    });
  });

  group('Recording', () {
    test('should create recording', () {
      final now = DateTime.now();
      final endTime = now.add(const Duration(hours: 1));

      final recording = Recording(
        id: 1,
        channelId: 1,
        title: 'Football Match',
        filePath: '/recordings/match.mp4',
        scheduledStart: now,
        scheduledEnd: endTime,
        status: RecordingStatus.scheduled,
        fileSize: 0,
        durationSeconds: 0,
        createdAt: now,
      );

      expect(recording.channelId, 1);
      expect(recording.title, 'Football Match');
      expect(recording.filePath, '/recordings/match.mp4');
      expect(recording.scheduledStart, now);
      expect(recording.scheduledEnd, endTime);
      expect(recording.status, RecordingStatus.scheduled);
    });

    test('should create recording with EPG program ID', () {
      final now = DateTime.now();
      final recording = Recording(
        id: 1,
        channelId: 1,
        title: 'Show',
        filePath: '/path.mp4',
        scheduledStart: now,
        scheduledEnd: now.add(const Duration(hours: 1)),
        status: RecordingStatus.scheduled,
        fileSize: 0,
        durationSeconds: 0,
        epgProgramId: 12345,
        createdAt: now,
      );

      expect(recording.epgProgramId, 12345);
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
    test('should create EPG program', () {
      final startTime = DateTime(2024, 1, 15, 20, 0);
      final endTime = DateTime(2024, 1, 15, 21, 0);

      final program = EpgProgram(
        id: 1,
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
      final program = EpgProgram(
        id: 1,
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
  });
}
