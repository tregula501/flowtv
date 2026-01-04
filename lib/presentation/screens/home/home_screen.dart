import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/playlist_provider.dart';
import '../../providers/channel_provider.dart';
import '../../widgets/category_sidebar.dart';
import '../../widgets/channel_grid.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../player/player_screen.dart';
import '../epg_guide/epg_guide_screen.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+F for search
      if (HardwareKeyboard.instance.isControlPressed &&
          event.logicalKey == LogicalKeyboardKey.keyF) {
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final currentChannel = ref.watch(currentChannelProvider);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
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
                  const VerticalDivider(width: 1),
                  const SizedBox(
                    width: 480,
                    child: PlayerScreen(),
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

          // Search bar
          SizedBox(
            width: 300,
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
                          ref.read(channelSearchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                ref.read(channelSearchQueryProvider.notifier).state = value;
              },
            ),
          ),

          const SizedBox(width: 8),

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
