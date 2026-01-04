import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_service.dart';
import '../../data/datasources/local/drift/app_database.dart';
import '../../data/datasources/remote/m3u_parser.dart';
import '../../core/utils/logger.dart';

/// All playlists provider
final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  final db = DatabaseService.instance;
  return db.select(db.playlists).watch();
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

  AppDatabase get _db => DatabaseService.instance;

  /// Add a new M3U playlist
  Future<Playlist> addM3uPlaylist({
    required String name,
    required String url,
    String? epgUrl,
  }) async {
    // Parse the playlist
    AppLogger.info('Parsing playlist: $name');
    final result = await _parser.parseFromUrl(url);

    // Check if this is the first playlist
    final existingCount = await _db.playlists.count().getSingle();
    final isActive = existingCount == 0;

    // Save playlist
    final playlistId = await _db.into(_db.playlists).insert(
      PlaylistsCompanion.insert(
        name: name,
        url: url,
        type: PlaylistType.m3u,
        createdAt: DateTime.now(),
        epgUrl: Value(epgUrl ?? result.epgUrl),
        isActive: Value(isActive),
        channelCount: Value(result.channels.length),
        lastRefresh: Value(DateTime.now()),
      ),
    );

    // Save channels
    for (final c in result.channels) {
      await _db.into(_db.channels).insert(
        ChannelsCompanion.insert(
          playlistId: playlistId,
          name: c.name,
          streamUrl: c.streamUrl,
          logoUrl: Value(c.logoUrl),
          epgId: Value(c.epgId),
          group: Value(c.group),
          channelNumber: Value(c.channelNumber),
        ),
      );
    }

    final playlist = await (_db.select(_db.playlists)..where((t) => t.id.equals(playlistId))).getSingle();
    AppLogger.info('Added playlist with ${result.channels.length} channels');
    return playlist;
  }

  /// Set active playlist
  Future<void> setActivePlaylist(int playlistId) async {
    // Deactivate all playlists
    await _db.update(_db.playlists).write(const PlaylistsCompanion(isActive: Value(false)));

    // Activate selected playlist
    await (_db.update(_db.playlists)..where((t) => t.id.equals(playlistId)))
        .write(const PlaylistsCompanion(isActive: Value(true)));
  }

  /// Delete a playlist and its channels
  Future<void> deletePlaylist(int playlistId) async {
    // Delete channels
    await (_db.delete(_db.channels)..where((t) => t.playlistId.equals(playlistId))).go();

    // Delete playlist
    await (_db.delete(_db.playlists)..where((t) => t.id.equals(playlistId))).go();

    AppLogger.info('Deleted playlist: $playlistId');
  }

  /// Refresh playlist from source
  Future<void> refreshPlaylist(int playlistId) async {
    final playlist = await (_db.select(_db.playlists)..where((t) => t.id.equals(playlistId))).getSingleOrNull();
    if (playlist == null) return;

    // Re-parse the playlist
    final result = await _parser.parseFromUrl(playlist.url);

    // Delete old channels
    await (_db.delete(_db.channels)..where((t) => t.playlistId.equals(playlistId))).go();

    // Save new channels
    for (final c in result.channels) {
      await _db.into(_db.channels).insert(
        ChannelsCompanion.insert(
          playlistId: playlistId,
          name: c.name,
          streamUrl: c.streamUrl,
          logoUrl: Value(c.logoUrl),
          epgId: Value(c.epgId),
          group: Value(c.group),
          channelNumber: Value(c.channelNumber),
        ),
      );
    }

    // Update playlist
    await (_db.update(_db.playlists)..where((t) => t.id.equals(playlistId)))
        .write(PlaylistsCompanion(
      channelCount: Value(result.channels.length),
      lastRefresh: Value(DateTime.now()),
      epgUrl: result.epgUrl != null && playlist.epgUrl == null ? Value(result.epgUrl) : const Value.absent(),
    ));

    AppLogger.info('Refreshed playlist with ${result.channels.length} channels');
  }
}
