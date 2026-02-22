import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
import '../recordings/recordings_screen.dart';
import '../settings/settings_screen.dart';
import '../../../core/constants/app_constants.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+F for search
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyF) {
        _focusNode.requestFocus();
      }
      // ESC to exit fullscreen
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        final isFullscreen = ref.read(playerControllerProvider).isFullscreen;
        if (isFullscreen) {
          ref.read(playerControllerProvider.notifier).setFullscreen(false);
        }
      }
      // F to toggle fullscreen when playing
      if (event.logicalKey == LogicalKeyboardKey.keyF &&
          !HardwareKeyboard.instance.isControlPressed) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).toggleFullscreen();
        }
      }
      // Space to play/pause
      if (event.logicalKey == LogicalKeyboardKey.space) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).playPause();
        }
      }
      // A to cycle aspect ratio
      if (event.logicalKey == LogicalKeyboardKey.keyA) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).cycleAspectRatio();
        }
      }
      // M to toggle mute
      if (event.logicalKey == LogicalKeyboardKey.keyM) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).toggleMute();
        }
      }
      // E to toggle expanded mode
      if (event.logicalKey == LogicalKeyboardKey.keyE) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).toggleExpanded();
        }
      }
      // P to toggle PiP mode
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        final currentChannel = ref.read(currentChannelProvider);
        if (currentChannel != null) {
          ref.read(playerControllerProvider.notifier).togglePiPMode();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final currentChannel = ref.watch(currentChannelProvider);
    final playerState = ref.watch(playerControllerProvider);

    // Show fullscreen player if in OS fullscreen mode
    if (playerState.isFullscreen && currentChannel != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: const FullscreenPlayerScreen(),
      );
    }

    // Show minimal PiP player if in PiP mode
    if (playerState.isPiPMode && currentChannel != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: const _PiPPlayerView(),
      );
    }

    // Show expanded player (fills app window but not OS fullscreen)
    if (playerState.isExpanded && currentChannel != null) {
      return KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        autofocus: true,
        child: const _ExpandedPlayerView(),
      );
    }

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        body: playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(
            child: Text('Failed to load playlists. Please restart the app.'),
          ),
          data: (playlists) {
            if (playlists.isEmpty) {
              return _buildEmptyState(context);
            }

            return Row(
              children: [
                // Category sidebar
                const SizedBox(
                  width: AppConstants.sidebarWidth,
                  child: CategorySidebar(),
                ),

                // Vertical divider
                const VerticalDivider(width: 1),

                // Main content area
                Expanded(
                  child: Column(
                    children: [
                      // App bar
                      _buildAppBar(context, activePlaylist?.name ?? 'FlowTV'),

                      // Channel grid
                      const Expanded(
                        child: ChannelGrid(),
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
    );
  }

  Widget _buildAppBar(BuildContext context, String title) {
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
                hintText: 'Search channels... (Ctrl+F)',
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
            tooltip: 'Multi-View (4 channels)',
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
            tooltip: 'TV Guide',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EpgGuideScreen()),
              );
            },
          ),

          // Recordings button
          IconButton(
            icon: const Icon(Icons.video_library),
            tooltip: 'Recordings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecordingsScreen()),
              );
            },
          ),

          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
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
            'Welcome to FlowTV',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add a playlist to get started',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showAddPlaylistDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Playlist'),
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

/// Expanded player view - fills the app window
class _ExpandedPlayerView extends ConsumerWidget {
  const _ExpandedPlayerView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Simply show the PlayerScreen - it already has all the controls
    // including the collapse button when in expanded mode
    return const Scaffold(
      backgroundColor: Colors.black,
      body: PlayerScreen(),
    );
  }
}

/// PiP player view - minimal UI for small window
class _PiPPlayerView extends ConsumerWidget {
  const _PiPPlayerView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    tooltip: 'Exit PiP (double-click)',
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

