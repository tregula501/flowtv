import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/epg_provider.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../../widgets/edit_playlist_dialog.dart';
import '../../../core/extensions/datetime_extensions.dart';
import '../../../core/constants/app_constants.dart';

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

  Widget _buildProgressSubtitle(ProgressState progress) {
    return Text(
      progress.phase,
      style: const TextStyle(fontStyle: FontStyle.italic),
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

    final icon = switch (themeMode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

    final label = switch (themeMode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

    return ListTile(
      leading: Icon(icon),
      title: const Text('Theme'),
      subtitle: Text(label),
      trailing: DropdownButton<ThemeMode>(
        value: themeMode,
        underline: const SizedBox(),
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
        ],
        onChanged: (value) {
          if (value != null) {
            ref.read(themeModeProvider.notifier).setThemeMode(value);
          }
        },
      ),
    );
  }

  Widget _buildPlaylistsTile(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final progressState = ref.watch(playlistProgressProvider);

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
          // Show progress bar when loading
          if (progressState.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          progressState.phase,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                  if (progressState.total > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progressState.progress,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${progressState.current} / ${progressState.total}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
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
                      value: 'edit',
                      child: Text('Edit'),
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
                      case 'edit':
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => EditPlaylistDialog(playlist: playlist),
                          );
                        }
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
    final progressState = ref.watch(epgProgressProvider);
    final lastUpdate = ref.watch(epgLastUpdateProvider);
    final refreshInterval = ref.watch(epgRefreshIntervalProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('TV Guide (EPG)'),
          subtitle: progressState.isLoading
              ? _buildProgressSubtitle(progressState)
              : Text(
                  lastUpdate != null
                      ? 'Last updated: ${lastUpdate.relativeTime}'
                      : 'Not loaded',
                ),
          trailing: progressState.isLoading
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
        if (progressState.isLoading && progressState.total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progressState.progress,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 4),
                Text(
                  '${progressState.current} / ${progressState.total}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
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
                ref.read(epgRefreshIntervalProvider.notifier).setInterval(value);
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
      title: const Text(AppConstants.appName),
      subtitle: const Text('Version ${AppConstants.appVersion}'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: AppConstants.appName,
          applicationVersion: AppConstants.appVersion,
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
