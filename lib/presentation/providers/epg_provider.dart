import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/drift/app_database.dart' show EpgProgram;
import '../../data/repositories/epg_repository.dart';
import '../../core/utils/logger.dart';
import 'playlist_provider.dart';

/// EPG repository provider
final epgRepositoryProvider = Provider<EpgRepository>((ref) {
  return EpgRepository();
});

/// Progress state for tracking long-running operations
class ProgressState {
  final int current;
  final int total;
  final String phase;
  final bool isLoading;

  const ProgressState({
    this.current = 0,
    this.total = 0,
    this.phase = '',
    this.isLoading = false,
  });

  double get progress => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

  ProgressState copyWith({
    int? current,
    int? total,
    String? phase,
    bool? isLoading,
  }) {
    return ProgressState(
      current: current ?? this.current,
      total: total ?? this.total,
      phase: phase ?? this.phase,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// EPG progress state notifier
class EpgProgressNotifier extends Notifier<ProgressState> {
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

/// EPG progress state provider
final epgProgressProvider = NotifierProvider<EpgProgressNotifier, ProgressState>(
  EpgProgressNotifier.new,
);

/// EPG loading state notifier - migrated to Riverpod 3.x
class EpgLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool loading) {
    state = loading;
  }
}

/// EPG loading state
final epgLoadingProvider = NotifierProvider<EpgLoadingNotifier, bool>(
  EpgLoadingNotifier.new,
);

/// EPG last update notifier - migrated to Riverpod 3.x
class EpgLastUpdateNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void setLastUpdate(DateTime? time) {
    state = time;
  }
}

/// EPG last update time
final epgLastUpdateProvider = NotifierProvider<EpgLastUpdateNotifier, DateTime?>(
  EpgLastUpdateNotifier.new,
);

/// EPG refresh interval notifier - migrated to Riverpod 3.x
class EpgRefreshIntervalNotifier extends Notifier<int> {
  @override
  int build() => 6; // default 6 hours

  void setInterval(int hours) {
    state = hours;
  }
}

/// EPG auto-refresh interval in hours (default 6)
final epgRefreshIntervalProvider = NotifierProvider<EpgRefreshIntervalNotifier, int>(
  EpgRefreshIntervalNotifier.new,
);

/// Current program for a channel
final currentProgramProvider = FutureProvider.family<EpgProgram?, String>(
  (ref, channelId) async {
    final repo = ref.watch(epgRepositoryProvider);
    return repo.getCurrentProgram(channelId);
  },
);

/// Programs for a channel (next 24 hours)
final channelProgramsProvider = FutureProvider.family<List<EpgProgram>, String>(
  (ref, channelId) async {
    final repo = ref.watch(epgRepositoryProvider);
    return repo.getProgramsForChannel(channelId);
  },
);

/// EPG manager for fetching and refreshing
final epgManagerProvider = Provider<EpgManager>((ref) {
  return EpgManager(ref);
});

class EpgManager {
  final Ref _ref;
  Timer? _autoRefreshTimer;

  EpgManager(this._ref);

  /// Fetch EPG for active playlist
  Future<void> fetchEpg() async {
    final activePlaylist = _ref.read(activePlaylistProvider);
    if (activePlaylist?.epgUrl == null) {
      AppLogger.warning('No EPG URL configured');
      return;
    }

    _ref.read(epgLoadingProvider.notifier).setLoading(true);
    _ref.read(epgProgressProvider.notifier).startLoading('Downloading EPG...');

    try {
      final repo = _ref.read(epgRepositoryProvider);
      final count = await repo.fetchAndStoreEpg(
        activePlaylist!.epgUrl!,
        onProgress: (current, total, phase) {
          _ref.read(epgProgressProvider.notifier).updateProgress(current, total, phase);
        },
      );

      _ref.read(epgLastUpdateProvider.notifier).setLastUpdate(DateTime.now());
      AppLogger.info('EPG updated: $count programs');
    } catch (e) {
      AppLogger.error('Failed to fetch EPG: $e');
      rethrow;
    } finally {
      _ref.read(epgLoadingProvider.notifier).setLoading(false);
      _ref.read(epgProgressProvider.notifier).stopLoading();
    }
  }

  /// Fetch EPG from specific URL
  Future<int> fetchEpgFromUrl(String url) async {
    _ref.read(epgLoadingProvider.notifier).setLoading(true);
    _ref.read(epgProgressProvider.notifier).startLoading('Downloading EPG...');

    try {
      final repo = _ref.read(epgRepositoryProvider);
      final count = await repo.fetchAndStoreEpg(
        url,
        onProgress: (current, total, phase) {
          _ref.read(epgProgressProvider.notifier).updateProgress(current, total, phase);
        },
      );

      _ref.read(epgLastUpdateProvider.notifier).setLastUpdate(DateTime.now());
      return count;
    } finally {
      _ref.read(epgLoadingProvider.notifier).setLoading(false);
      _ref.read(epgProgressProvider.notifier).stopLoading();
    }
  }

  /// Start auto-refresh timer
  void startAutoRefresh() {
    stopAutoRefresh(); // Cancel any existing timer

    final intervalHours = _ref.read(epgRefreshIntervalProvider);
    if (intervalHours <= 0) {
      AppLogger.info('EPG auto-refresh disabled');
      return;
    }

    AppLogger.info('EPG auto-refresh started: every $intervalHours hours');

    // Schedule periodic refresh
    _autoRefreshTimer = Timer.periodic(
      Duration(hours: intervalHours),
      (_) => _autoRefreshIfNeeded(),
    );

    // Also check immediately on startup if refresh is needed
    _autoRefreshIfNeeded();
  }

  /// Stop auto-refresh timer
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// Check if EPG needs refresh and do it
  Future<void> _autoRefreshIfNeeded() async {
    final lastUpdate = _ref.read(epgLastUpdateProvider);
    final intervalHours = _ref.read(epgRefreshIntervalProvider);

    if (lastUpdate == null) {
      // Never refreshed, do it now
      AppLogger.info('EPG auto-refresh: first fetch');
      try {
        await fetchEpg();
      } catch (e) {
        AppLogger.error('EPG auto-refresh failed: $e');
      }
      return;
    }

    final hoursSinceUpdate = DateTime.now().difference(lastUpdate).inHours;
    if (hoursSinceUpdate >= intervalHours) {
      AppLogger.info('EPG auto-refresh: $hoursSinceUpdate hours since last update');
      try {
        await fetchEpg();
      } catch (e) {
        AppLogger.error('EPG auto-refresh failed: $e');
      }
    } else {
      AppLogger.info('EPG auto-refresh: skipped, only $hoursSinceUpdate hours since last update');
    }
  }

  /// Check if EPG is stale (needs refresh)
  bool isEpgStale() {
    final lastUpdate = _ref.read(epgLastUpdateProvider);
    if (lastUpdate == null) return true;

    final intervalHours = _ref.read(epgRefreshIntervalProvider);
    final hoursSinceUpdate = DateTime.now().difference(lastUpdate).inHours;
    return hoursSinceUpdate >= intervalHours;
  }
}

/// EPG programs for time range (for EPG grid view)
final epgGridDataProvider = FutureProvider.family<
    Map<String, List<EpgProgram>>, ({DateTime from, DateTime to})>(
  (ref, range) async {
    final repo = ref.watch(epgRepositoryProvider);
    return repo.getProgramsForTimeRange(range.from, range.to);
  },
);
