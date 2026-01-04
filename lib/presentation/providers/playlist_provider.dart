import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_service.dart';
import '../../data/datasources/local/drift/app_database.dart';
import '../../data/datasources/remote/m3u_parser.dart';
import '../../core/utils/logger.dart';
import 'epg_provider.dart' show ProgressState;

/// Progress callback for tracking import progress
/// [current] is the number of items processed so far
/// [total] is the total number of items to process
/// [phase] describes what phase we're in
typedef PlaylistProgressCallback = void Function(int current, int total, String phase);

/// Playlist progress state notifier
class PlaylistProgressNotifier extends Notifier<ProgressState> {
  @override
  ProgressState build() => const ProgressState();

  void startLoading(String phase) {
    state = ProgressState(phase: phase, isLoading: true);
  }

  void updateProgress(int current, int total, String phase) {
    state = ProgressState(
      current: current,
      total: total,
      phase: phase,
      isLoading: true,
    );
  }

  void stopLoading() {
    state = const ProgressState();
  }
}

/// Playlist progress state provider
final playlistProgressProvider = NotifierProvider<PlaylistProgressNotifier, ProgressState>(
  PlaylistProgressNotifier.new,
);

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
  return PlaylistManager(ref);
});

class PlaylistManager {
  final Ref _ref;
  final M3uParser _parser = M3uParser();

  PlaylistManager(this._ref);

  AppDatabase get _db => DatabaseService.instance;

  void _updateProgress(int current, int total, String phase) {
    _ref.read(playlistProgressProvider.notifier).updateProgress(current, total, phase);
  }

  /// Add a new M3U playlist with optional progress callback
  Future<Playlist> addM3uPlaylist({
    required String name,
    required String url,
    String? epgUrl,
    PlaylistProgressCallback? onProgress,
  }) async {
    _ref.read(playlistProgressProvider.notifier).startLoading('Downloading playlist...');

    // Parse the playlist
    onProgress?.call(0, 100, 'Downloading playlist...');
    _updateProgress(0, 100, 'Downloading playlist...');
    AppLogger.info('Parsing playlist: $name');
    final result = await _parser.parseFromUrl(url);

    final channels = result.channels;
    final total = channels.length;

    onProgress?.call(0, total, 'Preparing database...');
    _updateProgress(0, total, 'Preparing database...');

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
        channelCount: Value(channels.length),
        lastRefresh: Value(DateTime.now()),
      ),
    );

    // Batch insert channels in chunks
    const batchSize = 500;
    int processed = 0;

    for (int i = 0; i < channels.length; i += batchSize) {
      final end = (i + batchSize > channels.length) ? channels.length : i + batchSize;
      final chunk = channels.sublist(i, end);

      await _db.batch((batch) {
        for (final c in chunk) {
          batch.insert(
            _db.channels,
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
      });

      processed = end;
      onProgress?.call(processed, total, 'Adding channels...');
      _updateProgress(processed, total, 'Adding channels...');
    }

    final playlist = await (_db.select(_db.playlists)..where((t) => t.id.equals(playlistId))).getSingle();
    AppLogger.info('Added playlist with $total channels using batch inserts');
    _ref.read(playlistProgressProvider.notifier).stopLoading();
    return playlist;
  }

  /// Update playlist metadata
  Future<void> updatePlaylist({
    required int playlistId,
    String? name,
    String? url,
    String? epgUrl,
  }) async {
    final updates = PlaylistsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      url: url != null ? Value(url) : const Value.absent(),
      epgUrl: epgUrl != null ? Value(epgUrl) : const Value.absent(),
    );

    await (_db.update(_db.playlists)..where((t) => t.id.equals(playlistId)))
        .write(updates);

    AppLogger.info('Updated playlist: $playlistId');
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

  /// Refresh playlist from source with optional progress callback
  Future<void> refreshPlaylist(
    int playlistId, {
    PlaylistProgressCallback? onProgress,
  }) async {
    final playlist = await (_db.select(_db.playlists)..where((t) => t.id.equals(playlistId))).getSingleOrNull();
    if (playlist == null) return;

    _ref.read(playlistProgressProvider.notifier).startLoading('Downloading playlist...');

    // Re-parse the playlist
    onProgress?.call(0, 100, 'Downloading playlist...');
    _updateProgress(0, 100, 'Downloading playlist...');
    final result = await _parser.parseFromUrl(playlist.url);

    final channels = result.channels;
    final total = channels.length;

    onProgress?.call(0, total, 'Clearing old channels...');
    _updateProgress(0, total, 'Clearing old channels...');

    // Delete old channels
    await (_db.delete(_db.channels)..where((t) => t.playlistId.equals(playlistId))).go();

    // Batch insert new channels
    const batchSize = 500;
    int processed = 0;

    for (int i = 0; i < channels.length; i += batchSize) {
      final end = (i + batchSize > channels.length) ? channels.length : i + batchSize;
      final chunk = channels.sublist(i, end);

      await _db.batch((batch) {
        for (final c in chunk) {
          batch.insert(
            _db.channels,
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
      });

      processed = end;
      onProgress?.call(processed, total, 'Adding channels...');
      _updateProgress(processed, total, 'Adding channels...');
    }

    // Update playlist
    await (_db.update(_db.playlists)..where((t) => t.id.equals(playlistId)))
        .write(PlaylistsCompanion(
      channelCount: Value(total),
      lastRefresh: Value(DateTime.now()),
      epgUrl: result.epgUrl != null && playlist.epgUrl == null ? Value(result.epgUrl) : const Value.absent(),
    ));

    AppLogger.info('Refreshed playlist with $total channels using batch inserts');
    _ref.read(playlistProgressProvider.notifier).stopLoading();
  }
}
