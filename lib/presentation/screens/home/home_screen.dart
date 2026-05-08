import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../providers/playlist_provider.dart';
import '../../providers/channel_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/category_sidebar.dart';
import '../../widgets/channel_grid.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../player/player_screen.dart';
import '../player/fullscreen_player_screen.dart';
import '../epg_guide/epg_guide_screen.dart';
import '../multiview/multiview_screen.dart';
import '../settings/settings_screen.dart';
import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  // Resizable player panel width
  double _playerPanelWidth = AppConstants.defaultPlayerPanelWidth;
  static const double _minPlayerWidth = AppConstants.minPlayerWidth;
  static const double _maxPlayerWidth = AppConstants.maxPlayerWidth;
  bool _hasInitializedPlayerWidth = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedPlayerWidth) {
      _hasInitializedPlayerWidth = true;
      final screenWidth = MediaQuery.of(context).size.width;
      _playerPanelWidth = (screenWidth * 0.35).clamp(_minPlayerWidth, _maxPlayerWidth);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    // Ctrl+F: focus search bar (always active)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      _focusNode.requestFocus();
      return;
    }

    // ESC: exit fullscreen (always active)
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final isFullscreen = ref.read(playerControllerProvider).isFullscreen;
      if (isFullscreen) {
        ref.read(playerControllerProvider.notifier).setFullscreen(false);
      }
      return;
    }

    // Skip single-key shortcuts when search is focused or Ctrl is held
    if (_focusNode.hasFocus || isCtrl) return;

    final currentChannel = ref.read(currentChannelProvider);
    if (currentChannel == null) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyF:
        ref.read(playerControllerProvider.notifier).toggleFullscreen();
      case LogicalKeyboardKey.space:
        ref.read(playerControllerProvider.notifier).playPause();
      case LogicalKeyboardKey.keyA:
        ref.read(playerControllerProvider.notifier).cycleAspectRatio();
      case LogicalKeyboardKey.keyM:
        ref.read(playerControllerProvider.notifier).toggleMute();
      case LogicalKeyboardKey.keyP:
        ref.read(playerControllerProvider.notifier).togglePiPMode();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playlistsAsync = ref.watch(playlistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final currentChannel = ref.watch(currentChannelProvider);
    // Only watch the display-mode fields to avoid rebuilds on every player tick
    final isFullscreen = ref.watch(playerControllerProvider.select((s) => s.isFullscreen));
    final isPiPMode = ref.watch(playerControllerProvider.select((s) => s.isPiPMode));

    // Show fullscreen player if in OS fullscreen mode
    if (isFullscreen && currentChannel != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: const FullscreenPlayerScreen(),
      );
    }

    // Show minimal PiP player if in PiP mode
    if (isPiPMode && currentChannel != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: const _PiPPlayerView(),
      );
    }

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        body: SafeArea(
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Text(l10n.failedToLoadPlaylists),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return _buildEmptyState(context);
              }

              return Row(
                children: [
                  // Category sidebar (responsive width)
                  SizedBox(
                    width: _sidebarWidth(context),
                    child: const CategorySidebar(),
                  ),

                  // Vertical divider
                  const VerticalDivider(width: 1),

                  // Main content area
                  Expanded(
                    child: Column(
                      children: [
                        // App bar
                        _buildAppBar(context, activePlaylist?.name ?? l10n.appTitle),

                        // Recently watched + channel grid
                        const Expanded(
                          child: _ChannelContent(),
                        ),
                      ],
                    ),
                  ),

                  // Video player panel (if channel selected)
                  if (currentChannel != null) ...[
                    // Resizable divider
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _playerPanelWidth -= details.delta.dx;
                            _playerPanelWidth = _playerPanelWidth.clamp(
                              _minPlayerWidth,
                              _maxPlayerWidth,
                            );
                          });
                        },
                        child: Container(
                          width: 8,
                          color: Colors.transparent,
                          child: Center(
                            child: Container(
                              width: 4,
                              margin: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).dividerColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _playerPanelWidth,
                      child: const PlayerScreen(),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _sidebarWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth >= 1200) return 280;
    if (screenWidth >= 800) return 240;
    return 220;
  }

  Widget _buildAppBar(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),

          const Spacer(),

          // Search bar - flexible width
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: l10n.searchChannelsCtrlF,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(channelSearchQueryProvider.notifier).clear();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                ref.read(channelSearchQueryProvider.notifier).setQuery(value);
              },
            ),
            ),
          ),

          const SizedBox(width: 8),

          // Multi-view button
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: l10n.multiViewChannels,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MultiViewScreen()),
              );
            },
          ),

          // EPG Guide button
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: l10n.tvGuide,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EpgGuideScreen()),
              );
            },
          ),

          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settings,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
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
          ),
          const SizedBox(height: 8),
          Text(
            l10n.welcomeSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showAddPlaylistDialog(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.addPlaylist),
          ),
        ],
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

/// PiP player view - minimal UI for small window
class _PiPPlayerView extends ConsumerWidget {
  const _PiPPlayerView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currentChannel = ref.watch(currentChannelProvider);
    final playerNotifier = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTap: () => playerNotifier.setPiPMode(false),
        child: Stack(
          children: [
            // Video player fills entire window
            Positioned.fill(
              child: Video(
                controller: playerNotifier.videoController,
                controls: NoVideoControls,
              ),
            ),

            // Minimal overlay with exit button
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Exit PiP button
                  _PiPIconButton(
                    icon: Icons.close_fullscreen,
                    tooltip: l10n.exitPipDoubleClick,
                    onTap: () => playerNotifier.setPiPMode(false),
                  ),
                ],
              ),
            ),

            // Channel name at bottom
            if (currentChannel != null)
              Positioned(
                left: 4,
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    currentChannel.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop channel content with recently watched row + grid
class _ChannelContent extends ConsumerWidget {
  const _ChannelContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final recentlyWatched = ref.watch(recentlyWatchedChannelsProvider);
    final channels = ref.watch(searchedChannelsProvider);
    final currentChannel = ref.watch(currentChannelProvider);

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noChannels,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Recently watched horizontal row
        if (recentlyWatched.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.recentlyWatched,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: recentlyWatched.length,
                itemBuilder: (context, index) {
                  final channel = recentlyWatched[index];
                  final isPlaying = currentChannel?.id == channel.id;
                  return _RecentChannelChip(
                    channel: channel,
                    isPlaying: isPlaying,
                    onTap: () {
                      ref.read(currentChannelProvider.notifier).select(channel);
                      ref.read(playerControllerProvider.notifier).playChannel(channel);
                      ref.read(channelManagerProvider).markAsWatched(channel.id);
                    },
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
        ],

        // Channel grid
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 1.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final channel = channels[index];
                final isPlaying = currentChannel?.id == channel.id;
                return ChannelTile(
                  channel: channel,
                  isPlaying: isPlaying,
                  onTap: () {
                    ref.read(currentChannelProvider.notifier).select(channel);
                    ref.read(playerControllerProvider.notifier).playChannel(channel);
                    ref.read(channelManagerProvider).markAsWatched(channel.id);
                  },
                  onFavoriteToggle: () {
                    ref.read(channelManagerProvider).toggleFavorite(channel.id);
                  },
                );
              },
              childCount: channels.length,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact chip for recently watched channel
class _RecentChannelChip extends StatelessWidget {
  final Channel channel;
  final bool isPlaying;
  final VoidCallback onTap;

  const _RecentChannelChip({
    required this.channel,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Material(
        color: isPlaying
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isPlaying
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.logoUrl!,
                            fit: BoxFit.contain,
                            errorWidget: (_, _, _) => Icon(
                              Icons.tv,
                              size: 24,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                          )
                        : Icon(
                            Icons.tv,
                            size: 24,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isPlaying ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small icon button for PiP mode
class _PiPIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PiPIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

