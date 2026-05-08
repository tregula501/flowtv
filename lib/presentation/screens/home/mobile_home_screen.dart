import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
  bool _isSearching = false;

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

    // Show fullscreen player when a channel is selected (not just playing —
    // isPlaying is false during buffering, which would flicker the screen)
    if (currentChannel != null) {
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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchChannels,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(channelSearchQueryProvider.notifier).clear();
                      setState(() => _isSearching = false);
                    },
                  ),
                ),
                onChanged: (value) {
                  ref.read(channelSearchQueryProvider.notifier).setQuery(value);
                },
              )
            : Text(l10n.appTitle),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
        ],
      ),
      body: SafeArea(
        // Bottom is handled by Scaffold via the BottomNavigationBar; the body
        // only needs protection from top status bar / cutouts and from
        // horizontal cutouts on foldables (e.g. ZFold6 inner display).
        bottom: false,
        child: playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(l10n.failedToLoadPlaylists),
          ),
          data: (playlists) => _buildBody(playlists.isEmpty),
        ),
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
              l10n.welcomeSubtitleDetailed,
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

        // Channel list with optional recently watched header
        Expanded(
          child: _buildChannelListView(context, ref, channels),
        ),
      ],
    );
  }

  Widget _buildChannelListView(BuildContext context, WidgetRef ref, List<Channel> channels) {
    final l10n = AppLocalizations.of(context)!;
    final recentlyWatched = ref.watch(recentlyWatchedChannelsProvider);
    final showRecent = !showFavoritesOnly && recentlyWatched.isNotEmpty;

    return ListView.builder(
      itemCount: channels.length + (showRecent ? 1 : 0),
      itemBuilder: (context, index) {
        // Recently watched horizontal row as first item
        if (showRecent && index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.recentlyWatched,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: recentlyWatched.length,
                  itemBuilder: (context, i) {
                    final channel = recentlyWatched[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        avatar: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                            ? CircleAvatar(
                                backgroundImage: CachedNetworkImageProvider(channel.logoUrl!),
                                backgroundColor: Colors.grey.shade800,
                              )
                            : const CircleAvatar(child: Icon(Icons.tv, size: 16)),
                        label: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _playChannel(context, ref, channel),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
            ],
          );
        }

        final channelIndex = showRecent ? index - 1 : index;
        final channel = channels[channelIndex];
        return _MobileChannelTile(
          channel: channel,
          onTap: () => _playChannel(context, ref, channel),
          onFavoriteToggle: () {
            ref.read(channelManagerProvider).toggleFavorite(channel.id);
          },
        );
      },
    );
  }

  void _playChannel(BuildContext context, WidgetRef ref, Channel channel) {
    ref.read(currentChannelProvider.notifier).select(channel);
    ref.read(playerControllerProvider.notifier).playChannel(channel);
    ref.read(channelManagerProvider).markAsWatched(channel.id);
  }
}

/// Mobile channel tile with long-press context menu
class _MobileChannelTile extends ConsumerWidget {
  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _MobileChannelTile({
    required this.channel,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      onLongPress: () => _showContextMenu(context, ref),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final castState = ref.read(castControllerProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Channel header
            ListTile(
              leading: _buildLogo(),
              title: Text(channel.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: channel.group != null ? Text(channel.group!) : null,
            ),
            const Divider(height: 1),
            // Favorite toggle
            ListTile(
              leading: Icon(
                channel.isFavorite ? Icons.star : Icons.star_border,
                color: channel.isFavorite ? Colors.amber : null,
              ),
              title: Text(channel.isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites),
              onTap: () {
                Navigator.pop(context);
                ref.read(channelManagerProvider).toggleFavorite(channel.id);
              },
            ),
            // Cast to device
            if (castState.isSupported)
              ListTile(
                leading: const Icon(Icons.cast),
                title: Text(l10n.castToDeviceAction),
                onTap: () {
                  Navigator.pop(context);
                  // Start playing the channel first, then show cast sheet
                  ref.read(currentChannelProvider.notifier).select(channel);
                  ref.read(playerControllerProvider.notifier).playChannel(channel);
                  ref.read(channelManagerProvider).markAsWatched(channel.id);
                  showCastSheet(context, ref, channel);
                },
              ),
            // Channel info
            if (channel.group != null || channel.channelNumber != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.channelInfo),
                subtitle: Text([
                  if (channel.group != null) l10n.channelGroup(channel.group!),
                  if (channel.channelNumber != null) '#${channel.channelNumber}',
                ].join(' • ')),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedNetworkImage(
          imageUrl: channel.logoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          placeholder: (_, _) => _buildPlaceholder(),
          errorWidget: (_, _, _) => _buildPlaceholder(),
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

/// Mobile fullscreen player with swipe-to-switch-channel support
class _MobilePlayerScreen extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onBack;

  const _MobilePlayerScreen({
    required this.channel,
    required this.onBack,
  });

  @override
  ConsumerState<_MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends ConsumerState<_MobilePlayerScreen> {
  /// Channel name to show in the switch overlay (null = hidden)
  String? _switchOverlayText;

  /// Controls the fade-in / fade-out of the channel switch overlay
  double _switchOverlayOpacity = 0.0;

  /// Timer that auto-dismisses the overlay after 2 seconds
  Timer? _switchOverlayTimer;

  @override
  void dispose() {
    _switchOverlayTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Channel switching
  // ------------------------------------------------------------------

  /// Switch to the next (+1) or previous (-1) channel in the list.
  void _switchChannel(int direction) {
    final currentChannel = ref.read(currentChannelProvider);
    if (currentChannel == null) return;

    // Use the same list the channel-list tab shows (respects search/filter)
    final channels = ref.read(searchedChannelsProvider);
    if (channels.isEmpty) return;

    final currentIndex = channels.indexWhere((c) => c.id == currentChannel.id);
    if (currentIndex == -1) return;

    // Wrap around at boundaries
    final nextIndex = (currentIndex + direction) % channels.length;
    final nextChannel = channels[nextIndex];

    // Play the new channel
    ref.read(currentChannelProvider.notifier).select(nextChannel);
    ref.read(playerControllerProvider.notifier).playChannel(nextChannel);
    ref.read(channelManagerProvider).markAsWatched(nextChannel.id);

    // Show the overlay
    _showSwitchOverlay(nextChannel);
  }

  /// Display a brief overlay with the new channel's name, auto-hiding after
  /// 2 seconds with a fade-out animation.
  void _showSwitchOverlay(Channel channel) {
    _switchOverlayTimer?.cancel();

    setState(() {
      _switchOverlayText = channel.channelNumber != null
          ? '${channel.channelNumber}  ${channel.name}'
          : channel.name;
      _switchOverlayOpacity = 1.0;
    });

    _switchOverlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _switchOverlayOpacity = 0.0);
      }
    });
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final channel = widget.channel;
    final playerNotifier = ref.read(playerControllerProvider.notifier);
    // Keep the video edge-to-edge (immersive) but offset the control overlays
    // so they clear system status bar / nav bar / cutouts on devices that
    // render edge-to-edge (Android 15+, foldables like ZFold6).
    final mediaPadding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
            // Video player — swipe up/down to switch channels,
            // tap to toggle play/pause (unchanged behaviour).
            Positioned.fill(
              child: GestureDetector(
                onTap: () => playerNotifier.playPause(),
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! < -300) {
                    // Swipe up -> next channel
                    _switchChannel(1);
                  } else if (details.primaryVelocity! > 300) {
                    // Swipe down -> previous channel
                    _switchChannel(-1);
                  }
                },
                child: Video(
                  controller: playerNotifier.videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),

            // Status overlays (use Consumer + .select to avoid full-state rebuilds)
            Consumer(
              builder: (context, ref, _) {
                final isBuffering = ref.watch(playerControllerProvider.select((s) => s.isBuffering));
                final isPrebuffering = ref.watch(playerControllerProvider.select((s) => s.isPrebuffering));
                final isReconnecting = ref.watch(playerControllerProvider.select((s) => s.isReconnecting));
                final error = ref.watch(playerControllerProvider.select((s) => s.error));
                final retryAttempt = ref.watch(playerControllerProvider.select((s) => s.retryAttempt));
                final maxRetries = ref.watch(playerControllerProvider.select((s) => s.maxRetries));

                return Stack(
                  children: [
                    // Prebuffering / reconnecting / buffering indicator
                    if (isPrebuffering || isReconnecting || isBuffering)
                      Center(
                        child: CircularProgressIndicator(
                          color: isReconnecting ? Colors.orange : Colors.white,
                        ),
                      ),
                    if (isReconnecting)
                      Positioned(
                        bottom: 80,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            l10n.retryAttempt(retryAttempt, maxRetries),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ),

                    // Error message (hidden during auto-reconnect)
                    if (error != null && !isReconnecting)
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
                              const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                l10n.playbackError,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error,
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => ref.read(playerControllerProvider.notifier).playChannel(channel),
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            // Channel switch overlay — semi-transparent bar at the top
            if (_switchOverlayText != null)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _switchOverlayOpacity,
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _switchOverlayText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),

            // Top bar with back button, channel name, and cast button.
            // Offset by the system top inset (status bar / cutout) so the
            // overlay sits flush below it on edge-to-edge devices.
            Positioned(
              top: mediaPadding.top,
              left: mediaPadding.left,
              right: mediaPadding.right,
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
                      onPressed: widget.onBack,
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
                    Consumer(
                      builder: (context, ref, _) {
                        final isSupported = ref.watch(castControllerProvider.select((s) => s.isSupported));
                        final isConnected = ref.watch(castControllerProvider.select((s) => s.isConnected));
                        if (!isSupported) return const SizedBox.shrink();
                        return IconButton(
                          icon: Icon(
                            isConnected ? Icons.cast_connected : Icons.cast,
                            color: isConnected ? Colors.blue : Colors.white,
                          ),
                          onPressed: () => showCastSheet(context, ref, channel),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Bottom controls. Lift by the system bottom inset (nav bar /
            // gesture area) so play/pause/volume/refresh remain visible on
            // edge-to-edge devices (Android 15+, foldables like ZFold6).
            Positioned(
              bottom: mediaPadding.bottom,
              left: mediaPadding.left,
              right: mediaPadding.right,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.isPlaying));
                    final isMuted = ref.watch(playerControllerProvider.select((s) => s.isMuted));
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Play/Pause
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () => ref.read(playerControllerProvider.notifier).playPause(),
                        ),
                        const SizedBox(width: 24),
                        // Volume
                        IconButton(
                          icon: Icon(
                            isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          onPressed: () => ref.read(playerControllerProvider.notifier).toggleMute(),
                        ),
                        const SizedBox(width: 24),
                        // Refresh
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: () => ref.read(playerControllerProvider.notifier).refreshChannel(channel),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

        ],
      ),
    );
  }
}
