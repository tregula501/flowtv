import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/epg_provider.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../../../core/extensions/datetime_extensions.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            'Appearance',
            [
              _buildThemeTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            'Playlists',
            [
              _buildPlaylistsTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            'EPG',
            [
              _buildEpgTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            'About',
            [
              _buildAboutTile(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _buildThemeTile(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return ListTile(
      leading: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      title: const Text('Theme'),
      subtitle: Text(isDark ? 'Dark' : 'Light'),
      trailing: Switch(
        value: isDark,
        onChanged: (value) {
          ref.read(themeModeProvider.notifier).setThemeMode(
                value ? ThemeMode.dark : ThemeMode.light,
              );
        },
      ),
    );
  }

  Widget _buildPlaylistsTile(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return playlistsAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.playlist_play),
        title: Text('Playlists'),
        subtitle: Text('Loading...'),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.playlist_play),
        title: const Text('Playlists'),
        subtitle: Text('Error: $e'),
      ),
      data: (playlists) => Column(
        children: [
          ...playlists.map((playlist) => ListTile(
                leading: Icon(
                  playlist.isActive ? Icons.check_circle : Icons.circle_outlined,
                  color: playlist.isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  '${playlist.channelCount} channels${playlist.lastRefresh != null ? ' - Updated ${playlist.lastRefresh!.relativeTime}' : ''}',
                ),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'activate',
                      child: Text('Set Active'),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                  onSelected: (value) async {
                    final manager = ref.read(playlistManagerProvider);
                    switch (value) {
                      case 'activate':
                        await manager.setActivePlaylist(playlist.id);
                        break;
                      case 'refresh':
                        await manager.refreshPlaylist(playlist.id);
                        break;
                      case 'delete':
                        await manager.deletePlaylist(playlist.id);
                        break;
                    }
                  },
                ),
              ),),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add Playlist'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const AddPlaylistDialog(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEpgTile(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(epgLoadingProvider);
    final lastUpdate = ref.watch(epgLastUpdateProvider);
    final refreshInterval = ref.watch(epgRefreshIntervalProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('TV Guide (EPG)'),
          subtitle: Text(
            lastUpdate != null
                ? 'Last updated: ${lastUpdate.relativeTime}'
                : 'Not loaded',
          ),
          trailing: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.read(epgManagerProvider).fetchEpg(),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('Auto-refresh interval'),
          subtitle: Text(
            refreshInterval == 0
                ? 'Disabled'
                : 'Every $refreshInterval ${refreshInterval == 1 ? "hour" : "hours"}',
          ),
          trailing: DropdownButton<int>(
            value: refreshInterval,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Off')),
              DropdownMenuItem(value: 1, child: Text('1 hour')),
              DropdownMenuItem(value: 3, child: Text('3 hours')),
              DropdownMenuItem(value: 6, child: Text('6 hours')),
              DropdownMenuItem(value: 12, child: Text('12 hours')),
              DropdownMenuItem(value: 24, child: Text('24 hours')),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(epgRefreshIntervalProvider.notifier).state = value;
                // Restart auto-refresh with new interval
                ref.read(epgManagerProvider).startAutoRefresh();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('FlowTV'),
      subtitle: const Text('Version 0.1.0'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: 'FlowTV',
          applicationVersion: '0.1.0',
          applicationLegalese: 'GPL v3 License',
          children: [
            const SizedBox(height: 16),
            const Text(
              'A cross-platform IPTV streaming application with EPG, DVR, and multi-view support.',
            ),
          ],
        );
      },
    );
  }
}
