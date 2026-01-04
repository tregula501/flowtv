import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../data/models/channel.dart';
import '../../data/datasources/local/database_service.dart';
import 'playlist_provider.dart';

/// Channels for active playlist
final channelsProvider = StreamProvider<List<Channel>>((ref) {
  final activePlaylist = ref.watch(activePlaylistProvider);

  if (activePlaylist == null) {
    return Stream.value([]);
  }

  final isar = DatabaseService.instance;
  return isar.channels
      .filter()
      .playlistIdEqualTo(activePlaylist.id)
      .watch(fireImmediately: true);
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

/// Currently selected group (null = all, favoritesFilterKey = favorites only)
final selectedGroupProvider = StateProvider<String?>((ref) => null);

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
          return channels.where((c) => c.group == selectedGroup).toList();
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

/// Currently playing channel
final currentChannelProvider = StateProvider<Channel?>((ref) => null);

/// Search query
final channelSearchQueryProvider = StateProvider<String>((ref) => '');

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
  /// Toggle favorite status
  Future<void> toggleFavorite(int channelId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      final channel = await isar.channels.get(channelId);
      if (channel != null) {
        channel.isFavorite = !channel.isFavorite;
        await isar.channels.put(channel);
      }
    });
  }

  /// Update last watched
  Future<void> markAsWatched(int channelId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      final channel = await isar.channels.get(channelId);
      if (channel != null) {
        channel.lastWatched = DateTime.now();
        await isar.channels.put(channel);
      }
    });
  }

  /// Toggle channel lock
  Future<void> toggleLock(int channelId) async {
    final isar = DatabaseService.instance;

    await isar.writeTxn(() async {
      final channel = await isar.channels.get(channelId);
      if (channel != null) {
        channel.isLocked = !channel.isLocked;
        await isar.channels.put(channel);
      }
    });
  }
}
