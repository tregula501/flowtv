import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../providers/playlist_provider.dart';
import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/cast_provider.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../../widgets/cast_device_sheet.dart';
import '../settings/settings_screen.dart';
import '../epg_guide/epg_guide_screen.dart';
import '../../../l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final playlistsAsync = ref.watch(playlistsProvider);
    final currentChannel = ref.watch(currentChannelProvider);
    // Only watch isPlaying to avoid rebuilds on every player tick
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.isPlaying));

    // Show fullscreen player when a channel is playing
    if (currentChannel != null && isPlaying) {
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
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(context),
          ),
        ],
      ),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(l10n.failedToLoadPlaylists),
        ),
        data: (playlists) => _buildBody(playlists.isEmpty),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.live_tv),
            label: l10n.channels,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.star),
            label: l10n.favorites,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.schedule),
            label: l10n.guide,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool noPlaylists) {
    final l10n = AppLocalizations.of(context)!;
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
                message: l10n.addPlaylistForFavorites,
              )
            : const _MobileChannelList(showFavoritesOnly: true);
      case 2:
        return noPlaylists
            ? _buildNoPlaylistTab(
                context,
                icon: Icons.schedule,
                message: l10n.addPlaylistForGuide,
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
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: SingleChildScrollView(
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
              l10n.welcomeTitle,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.welcomeSubtitle,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddPlaylistDialog(context),
              icon: const Icon(Icons.add),
              label: Text(l10n.addPlaylist),
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
    final l10n = AppLocalizations.of(context)!;
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
              label: Text(l10n.addPlaylist),
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
    final l10n = AppLocalizations.of(context)!;
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
              showFavoritesOnly ? l10n.noFavorites : l10n.noChannels,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (showFavoritesOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.tapStarToFavorite,
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
                    label: Text(l10n.all),
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
    final l10n = AppLocalizations.of(context)!;
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
                        l10n.playbackError,
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
                        child: Text(l10n.retry),
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
    showCastSheet(context, ref, channel);
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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.searchChannelsDialog),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: l10n.enterChannelName,
          prefixIcon: const Icon(Icons.search),
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
          child: Text(l10n.clear),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => onSearch(controller.text),
          child: Text(l10n.search),
        ),
      ],
    );
  }
}
