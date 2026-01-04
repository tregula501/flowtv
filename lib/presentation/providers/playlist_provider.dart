import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../data/models/playlist.dart';
import '../../data/models/channel.dart';
import '../../data/datasources/local/database_service.dart';
import '../../data/datasources/remote/m3u_parser.dart';
import '../../core/utils/logger.dart';

/// All playlists provider
final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  final isar = DatabaseService.instance;
  return isar.playlists.where().watch(fireImmediately: true);
});

/// Active playlist provider
final activePlaylistProvider = Provider<Playlist?>((ref) {
  final playlists = ref.watch(playlistsProvider);
  return playlists.whenOrNull(
    data: (list) => list.where((p) => p.isActive).firstOrNull,
  );
});

/// Playlist management provider
final playlistManagerProvider = Provider<PlaylistManager>((ref) {
  return PlaylistManager();
});

class PlaylistManager {
  final M3uParser _parser = M3uParser();

  /// Add a new M3U playlist
  Future<Playlist> addM3uPlaylist({
    required String name,
    required String url,
    String? epgUrl,
  }) async {
    final isar = DatabaseService.instance;

    // Parse the playlist
    AppLogger.info('Parsing playlist: $name');
    final result = await _parser.parseFromUrl(url);

    // Create playlist record
    final playlist = Playlist.create(
      name: name,
      url: url,
      type: PlaylistType.m3u,
      epgUrl: epgUrl ?? result.epgUrl,
    );

    // Check if this is the first playlist
    final existingCount = await isar.playlists.count();
    if (existingCount == 0) {
      playlist.isActive = true;
    }

    await isar.writeTxn(() async {
      // Save playlist
      await isar.playlists.put(playlist);

      // Save channels
      final channels = result.channels
          .map((c) => c.toChannel(playlist.id))
          .toList();

      await isar.channels.putAll(channels);

      // Update channel count
      playlist.channelCount = channels.length;
      playlist.lastRefresh = DateTime.now();
      await isar.playlists.put(playlist);
    });

    AppLogger.info('Added playlist with ${result.channels.length} channels');
    return playlist;
  }

  /// Set active playlist
  Future<void> setActivePlaylist(int playlistId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      // Deactivate all playlists
      final allPlaylists = await isar.playlists.where().findAll();
      for (final p in allPlaylists) {
        p.isActive = p.id == playlistId;
        await isar.playlists.put(p);
      }
    });
  }

  /// Delete a playlist and its channels
  Future<void> deletePlaylist(int playlistId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      // Delete channels
      await isar.channels
          .filter()
          .playlistIdEqualTo(playlistId)
          .deleteAll();

      // Delete playlist
      await isar.playlists.delete(playlistId);
    });

    AppLogger.info('Deleted playlist: $playlistId');
  }

  /// Refresh playlist from source
  Future<void> refreshPlaylist(int playlistId) async {
    final isar = DatabaseService.instance;

    final playlist = await isar.playlists.get(playlistId);
    if (playlist == null) return;

    // Re-parse the playlist
    final result = await _parser.parseFromUrl(playlist.url);

    await isar.writeTxn(() async {
      // Delete old channels
      await isar.channels
          .filter()
          .playlistIdEqualTo(playlistId)
          .deleteAll();

      // Save new channels (preserve favorites)
      final channels = result.channels
          .map((c) => c.toChannel(playlistId))
          .toList();

      await isar.channels.putAll(channels);

      // Update playlist
      playlist.channelCount = channels.length;
      playlist.lastRefresh = DateTime.now();
      if (result.epgUrl != null && playlist.epgUrl == null) {
        playlist.epgUrl = result.epgUrl;
      }
      await isar.playlists.put(playlist);
    });

    AppLogger.info('Refreshed playlist with ${result.channels.length} channels');
  }
}
