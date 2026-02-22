import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_service.dart';
import '../../data/datasources/local/drift/app_database.dart';
import 'playlist_provider.dart';

/// Channels for active playlist
final channelsProvider = StreamProvider<List<Channel>>((ref) {
  final activePlaylist = ref.watch(activePlaylistProvider);

  if (activePlaylist == null) {
    return Stream.value([]);
  }

  final db = DatabaseService.instance;
  return (db.select(db.channels)..where((t) => t.playlistId.equals(activePlaylist.id))).watch();
});

/// Groups/categories for active playlist
final channelGroupsProvider = Provider<List<String>>((ref) {
  final channelsAsync = ref.watch(channelsProvider);

  return channelsAsync.whenOrNull(
        data: (channels) {
          final groups = channels
              .map((c) => c.group ?? 'Uncategorized')
              .toSet()
              .toList();
          groups.sort();
          return groups;
        },
      ) ??
      [];
});

/// Special constant for favorites filter
const String favoritesFilterKey = '__FAVORITES__';

/// Selected group notifier - migrated to Riverpod 3.x
class SelectedGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? group) {
    state = group;
  }
}

/// Currently selected group (null = all, favoritesFilterKey = favorites only)
final selectedGroupProvider = NotifierProvider<SelectedGroupNotifier, String?>(
  SelectedGroupNotifier.new,
);

/// Filtered channels by selected group
final filteredChannelsProvider = Provider<List<Channel>>((ref) {
  final channelsAsync = ref.watch(channelsProvider);
  final selectedGroup = ref.watch(selectedGroupProvider);

  return channelsAsync.whenOrNull(
        data: (channels) {
          if (selectedGroup == null) return channels;
          if (selectedGroup == favoritesFilterKey) {
            return channels.where((c) => c.isFavorite).toList();
          }
          return channels.where((c) => (c.group ?? 'Uncategorized') == selectedGroup).toList();
        },
      ) ??
      [];
});

/// Favorite channels
final favoriteChannelsProvider = Provider<List<Channel>>((ref) {
  final channelsAsync = ref.watch(channelsProvider);

  return channelsAsync.whenOrNull(
        data: (channels) => channels.where((c) => c.isFavorite).toList(),
      ) ??
      [];
});

/// Current channel notifier - migrated to Riverpod 3.x
class CurrentChannelNotifier extends Notifier<Channel?> {
  @override
  Channel? build() => null;

  void select(Channel? channel) {
    state = channel;
  }
}

/// Currently playing channel
final currentChannelProvider = NotifierProvider<CurrentChannelNotifier, Channel?>(
  CurrentChannelNotifier.new,
);

/// Recently watched channels (last 10, most recent first)
final recentlyWatchedChannelsProvider = Provider<List<Channel>>((ref) {
  final channelsAsync = ref.watch(channelsProvider);

  return channelsAsync.whenOrNull(
        data: (channels) {
          final watched = channels
              .where((c) => c.lastWatched != null)
              .toList()
            ..sort((a, b) => b.lastWatched!.compareTo(a.lastWatched!));
          return watched.take(10).toList();
        },
      ) ??
      [];
});

/// Search query notifier with 300ms debounce
class ChannelSearchQueryNotifier extends Notifier<String> {
  Timer? _debounce;

  @override
  String build() {
    _debounce?.cancel();
    ref.onDispose(() => _debounce?.cancel());
    return '';
  }

  void setQuery(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      // Clear immediately for responsiveness
      state = '';
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      state = query;
    });
  }

  void clear() {
    _debounce?.cancel();
    state = '';
  }
}

/// Search query
final channelSearchQueryProvider = NotifierProvider<ChannelSearchQueryNotifier, String>(
  ChannelSearchQueryNotifier.new,
);

/// Searched channels
final searchedChannelsProvider = Provider<List<Channel>>((ref) {
  final query = ref.watch(channelSearchQueryProvider).toLowerCase();
  final channels = ref.watch(filteredChannelsProvider);

  if (query.isEmpty) return channels;

  return channels.where((c) => c.name.toLowerCase().contains(query)).toList();
});

/// Channel operations
final channelManagerProvider = Provider<ChannelManager>((ref) {
  return ChannelManager();
});

class ChannelManager {
  AppDatabase get _db => DatabaseService.instance;

  /// Toggle favorite status
  Future<void> toggleFavorite(int channelId) async {
    final channel = await (_db.select(_db.channels)..where((t) => t.id.equals(channelId))).getSingleOrNull();
    if (channel != null) {
      await (_db.update(_db.channels)..where((t) => t.id.equals(channelId)))
          .write(ChannelsCompanion(isFavorite: Value(!channel.isFavorite)));
    }
  }

  /// Update last watched
  Future<void> markAsWatched(int channelId) async {
    await (_db.update(_db.channels)..where((t) => t.id.equals(channelId)))
        .write(ChannelsCompanion(lastWatched: Value(DateTime.now())));
  }

  /// Toggle channel lock
  Future<void> toggleLock(int channelId) async {
    final channel = await (_db.select(_db.channels)..where((t) => t.id.equals(channelId))).getSingleOrNull();
    if (channel != null) {
      await (_db.update(_db.channels)..where((t) => t.id.equals(channelId)))
          .write(ChannelsCompanion(isLocked: Value(!channel.isLocked)));
    }
  }
}
