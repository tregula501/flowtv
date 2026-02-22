import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../providers/playlist_provider.dart';
import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/cast_provider.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../settings/settings_screen.dart';
import '../epg_guide/epg_guide_screen.dart';

/// Mobile-optimized home screen for Android/iOS
class MobileHomeScreen extends ConsumerStatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  ConsumerState<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends ConsumerState<MobileHomeScreen> {
  int _currentIndex = 0;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final currentChannel = ref.watch(currentChannelProvider);
    final playerState = ref.watch(playerControllerProvider);

    // Show fullscreen player when a channel is playing
    if (currentChannel != null && playerState.isPlaying) {
      return _MobilePlayerScreen(
        channel: currentChannel,
        onBack: () {
          ref.read(playerControllerProvider.notifier).stop();
          ref.read(currentChannelProvider.notifier).select(null);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowTV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
        ],
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (playlists) => _buildBody(playlists.isEmpty),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.live_tv),
            label: 'Channels',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star),
            label: 'Favorites',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Guide',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool noPlaylists) {
    switch (_currentIndex) {
      case 0:
        return noPlaylists
            ? _buildEmptyState(context)
            : const _MobileChannelList(showFavoritesOnly: false);
      case 1:
        return noPlaylists
            ? _buildNoPlaylistTab(
                context,
                icon: Icons.star_border,
                message: 'Add a playlist to see favorites',
              )
            : const _MobileChannelList(showFavoritesOnly: true);
      case 2:
        return noPlaylists
            ? _buildNoPlaylistTab(
                context,
                icon: Icons.schedule,
                message: 'Add a playlist to view the TV guide',
              )
            : const EpgGuideScreen();
      case 3:
        return const SettingsScreen();
      default:
        return noPlaylists
            ? _buildEmptyState(context)
            : const _MobileChannelList(showFavoritesOnly: false);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to FlowTV',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a playlist to get started',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddPlaylistDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Playlist'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPlaylistTab(
    BuildContext context, {
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _showAddPlaylistDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Playlist'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPlaylistDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddPlaylistDialog(),
    );
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SearchDialog(
        controller: _searchController,
        onSearch: (query) {
          ref.read(channelSearchQueryProvider.notifier).setQuery(query);
          Navigator.pop(context);
          setState(() => _currentIndex = 0); // Switch to channels tab
        },
      ),
    );
  }
}

/// Mobile channel list with categories
class _MobileChannelList extends ConsumerWidget {
  final bool showFavoritesOnly;

  const _MobileChannelList({required this.showFavoritesOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = showFavoritesOnly
        ? ref.watch(favoriteChannelsProvider)
        : ref.watch(searchedChannelsProvider);
    final groups = ref.watch(channelGroupsProvider);
    final selectedGroup = ref.watch(selectedGroupProvider);

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showFavoritesOnly ? Icons.star_border : Icons.live_tv,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              showFavoritesOnly ? 'No favorites yet' : 'No channels found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (showFavoritesOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tap the star on a channel to add it',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Category filter chips (only for channels tab)
        if (!showFavoritesOnly && groups.isNotEmpty)
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: selectedGroup == null,
                    onSelected: (_) {
                      ref.read(selectedGroupProvider.notifier).select(null);
                    },
                  ),
                ),
                ...groups.map((group) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FilterChip(
                    label: Text(group),
                    selected: selectedGroup == group,
                    onSelected: (_) {
                      ref.read(selectedGroupProvider.notifier).select(group);
                    },
                  ),
                ),),
              ],
            ),
          ),

        // Channel list
        Expanded(
          child: ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _MobileChannelTile(
                channel: channel,
                onTap: () => _playChannel(context, ref, channel),
                onFavoriteToggle: () {
                  ref.read(channelManagerProvider).toggleFavorite(channel.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _playChannel(BuildContext context, WidgetRef ref, Channel channel) {
    ref.read(currentChannelProvider.notifier).select(channel);
    ref.read(playerControllerProvider.notifier).playChannel(channel);
    ref.read(channelManagerProvider).markAsWatched(channel.id);
  }
}

/// Mobile channel tile
class _MobileChannelTile extends StatelessWidget {
  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _MobileChannelTile({
    required this.channel,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildLogo(),
      title: Text(
        channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: channel.group != null
          ? Text(
              channel.group!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: IconButton(
        icon: Icon(
          channel.isFavorite ? Icons.star : Icons.star_border,
          color: channel.isFavorite ? Colors.amber : null,
        ),
        onPressed: onFavoriteToggle,
      ),
      onTap: onTap,
    );
  }

  Widget _buildLogo() {
    if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          channel.logoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.tv, color: Colors.grey),
    );
  }
}

/// Mobile fullscreen player
class _MobilePlayerScreen extends ConsumerWidget {
  final Channel channel;
  final VoidCallback onBack;

  const _MobilePlayerScreen({
    required this.channel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerControllerProvider);
    final playerNotifier = ref.read(playerControllerProvider.notifier);
    final castState = ref.watch(castControllerProvider);
    final castNotifier = ref.read(castControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video player
            Positioned.fill(
              child: GestureDetector(
                onTap: () => playerNotifier.playPause(),
                child: Video(
                  controller: playerNotifier.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),

            // Loading indicator
            if (playerState.isBuffering || playerState.isPrebuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Error message
            if (playerState.error != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Playback Error',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playerState.error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => playerNotifier.playChannel(channel),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),

            // Top bar with back button, channel name, and cast button
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: onBack,
                    ),
                    Expanded(
                      child: Text(
                        channel.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Chromecast button
                    if (castState.isSupported)
                      IconButton(
                        icon: Icon(
                          castState.isConnected
                              ? Icons.cast_connected
                              : Icons.cast,
                          color: castState.isConnected
                              ? Colors.blue
                              : Colors.white,
                        ),
                        onPressed: () => _showCastDialog(
                          context,
                          ref,
                          castState,
                          castNotifier,
                          channel,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Play/Pause
                    IconButton(
                      icon: Icon(
                        playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => playerNotifier.playPause(),
                    ),
                    const SizedBox(width: 24),
                    // Volume
                    IconButton(
                      icon: Icon(
                        playerState.isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                      onPressed: () => playerNotifier.toggleMute(),
                    ),
                    const SizedBox(width: 24),
                    // Refresh
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () => playerNotifier.refreshChannel(channel),
                    ),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  void _showCastDialog(
    BuildContext context,
    WidgetRef ref,
    CastState castState,
    CastControllerNotifier castNotifier,
    Channel channel,
  ) {
    // Start discovery when dialog opens
    castNotifier.startDiscovery();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _CastDeviceSheet(
        channel: channel,
        onClose: () {
          castNotifier.stopDiscovery();
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// Chromecast device selection sheet
class _CastDeviceSheet extends ConsumerWidget {
  final Channel channel;
  final VoidCallback onClose;

  const _CastDeviceSheet({
    required this.channel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castControllerProvider);
    final castNotifier = ref.read(castControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.cast, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cast to',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (castState.isDiscovering)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Connected device info
          if (castState.isConnected && castState.connectedDevice != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cast_connected, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected to ${castState.connectedDevice!.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Tap to cast "${channel.name}"',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cast current channel button
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final success = await castNotifier.castMedia(
                          url: channel.streamUrl,
                          title: channel.name,
                          subtitle: channel.group,
                          imageUrl: channel.logoUrl,
                          contentType: 'video/mp4',
                        );
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Casting "${channel.name}"'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          onClose();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Cast failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Cast'),
                  ),
                  const SizedBox(width: 8),
                  // Disconnect button
                  TextButton(
                    onPressed: () async {
                      await castNotifier.disconnect();
                    },
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),

          // Device list
          if (castState.devices.isEmpty && !castState.isDiscovering)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No Cast devices found.\n\n'
                  'Make sure your device is on the same network.\n\n'
                  'Note: Audio-only devices (Google Home, Nest Mini)\n'
                  'are hidden as they cannot display video.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: castState.devices.length,
                itemBuilder: (context, index) {
                  final device = castState.devices[index];
                  final isConnected = castState.connectedDevice?.id == device.id;

                  return ListTile(
                    leading: Icon(
                      isConnected ? Icons.cast_connected : Icons.cast,
                      color: isConnected ? Colors.blue : Colors.white,
                    ),
                    title: Text(
                      device.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            isConnected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: device.modelName != null
                        ? Text(
                            device.modelName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    trailing: isConnected
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () async {
                      if (!isConnected) {
                        try {
                          // Show connecting feedback
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Connecting to ${device.name}...'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }

                          final success = await castNotifier.connect(device);
                          if (success && context.mounted) {
                            // Stop local playback to avoid duplicate audio
                            ref
                                .read(playerControllerProvider.notifier)
                                .pause();

                            // After connecting, cast the current channel
                            final castSuccess = await castNotifier.castMedia(
                              url: channel.streamUrl,
                              title: channel.name,
                              subtitle: channel.group,
                              imageUrl: channel.logoUrl,
                              contentType: 'video/mp4',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    castSuccess
                                        ? 'Casting "${channel.name}" to ${device.name}'
                                        : 'Connected but failed to start playback',
                                  ),
                                  backgroundColor:
                                      castSuccess ? Colors.green : Colors.orange,
                                ),
                              );
                              onClose();
                            }
                          } else if (context.mounted) {
                            // Connection failed
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Failed to connect to ${device.name}',),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cast error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Search dialog
class _SearchDialog extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearch;

  const _SearchDialog({
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Channels'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Enter channel name...',
          prefixIcon: Icon(Icons.search),
        ),
        autofocus: true,
        onSubmitted: onSearch,
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.clear();
            onSearch('');
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => onSearch(controller.text),
          child: const Text('Search'),
        ),
      ],
    );
  }
}
