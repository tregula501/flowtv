import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../providers/epg_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/add_playlist_dialog.dart';
import '../../widgets/edit_playlist_dialog.dart';
import '../../../core/extensions/datetime_extensions.dart';
import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            l10n.appearance,
            [
              _buildThemeTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            l10n.playlists,
            [
              _buildRefreshOnLaunchTile(context, ref),
              _buildPlaylistsTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            l10n.tvGuideEpg,
            [
              _buildEpgTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            'Playback',
            [
              _buildBufferSizeTile(context, ref),
            ],
          ),
          _buildSection(
            context,
            l10n.about,
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
    final l10n = AppLocalizations.of(context)!;
    final themeMode = ref.watch(themeModeProvider);

    final icon = switch (themeMode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

    final label = switch (themeMode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };

    return ListTile(
      leading: Icon(icon),
      title: Text(l10n.theme),
      subtitle: Text(label),
      trailing: DropdownButton<ThemeMode>(
        value: themeMode,
        underline: const SizedBox(),
        items: [
          DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeSystem)),
          DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeLight)),
          DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeDark)),
        ],
        onChanged: (value) {
          if (value != null) {
            ref.read(themeModeProvider.notifier).setThemeMode(value);
          }
        },
      ),
    );
  }

  Widget _buildRefreshOnLaunchTile(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = ref.watch(refreshPlaylistsOnLaunchProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.refresh),
      title: Text(l10n.refreshPlaylistsOnLaunch),
      subtitle: Text(l10n.refreshPlaylistsOnLaunchSubtitle),
      value: enabled,
      onChanged: (value) {
        ref
            .read(refreshPlaylistsOnLaunchProvider.notifier)
            .setEnabled(value);
      },
    );
  }

  Widget _buildPlaylistsTile(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final playlistsAsync = ref.watch(playlistsProvider);
    final progressState = ref.watch(playlistProgressProvider);

    return playlistsAsync.when(
      loading: () => ListTile(
        leading: const Icon(Icons.playlist_play),
        title: Text(l10n.playlists),
        subtitle: Text(l10n.loading),
      ),
      error: (_, _) => ListTile(
        leading: const Icon(Icons.playlist_play),
        title: Text(l10n.playlists),
        subtitle: Text(l10n.failedToLoadPlaylistsShort),
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
                  itemBuilder: (context) {
                    final l10n = AppLocalizations.of(context)!;
                    return [
                      PopupMenuItem(
                        value: 'activate',
                        child: Text(l10n.setActive),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l10n.edit),
                      ),
                      PopupMenuItem(
                        value: 'refresh',
                        child: Text(l10n.refresh),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.delete),
                      ),
                    ];
                  },
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
            title: Text(l10n.addPlaylist),
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
    final l10n = AppLocalizations.of(context)!;
    final progressState = ref.watch(epgProgressProvider);
    final lastUpdate = ref.watch(epgLastUpdateProvider);
    final refreshInterval = ref.watch(epgRefreshIntervalProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(l10n.tvGuideEpg),
          subtitle: progressState.isLoading
              ? _buildProgressSubtitle(progressState)
              : Text(
                  lastUpdate != null
                      ? 'Last updated: ${lastUpdate.relativeTime}'
                      : l10n.notLoaded,
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
          title: Text(l10n.epgAutoRefreshInterval),
          subtitle: Text(
            refreshInterval == 0
                ? l10n.epgDisabled
                : l10n.epgEveryHour(refreshInterval),
          ),
          trailing: DropdownButton<int>(
            value: refreshInterval,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: 0, child: Text(l10n.epgRefreshOff)),
              DropdownMenuItem(value: 1, child: Text(l10n.epgRefresh1Hour)),
              DropdownMenuItem(value: 3, child: Text(l10n.epgRefresh3Hours)),
              DropdownMenuItem(value: 6, child: Text(l10n.epgRefresh6Hours)),
              DropdownMenuItem(value: 12, child: Text(l10n.epgRefresh12Hours)),
              DropdownMenuItem(value: 24, child: Text(l10n.epgRefresh24Hours)),
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

  Widget _buildBufferSizeTile(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerControllerProvider);
    final currentSize = playerState.bufferSize;

    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    // extraLarge (240MB) causes OOM on most mobile devices
    final availableSizes = isMobile
        ? BufferSize.values.where((s) => s != BufferSize.extraLarge).toList()
        : BufferSize.values;

    return ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('Buffer Size'),
      subtitle: Text(currentSize.displayName),
      trailing: DropdownButton<BufferSize>(
        value: availableSizes.contains(currentSize) ? currentSize : BufferSize.large,
        underline: const SizedBox(),
        items: availableSizes
            .map((size) => DropdownMenuItem(
                  value: size,
                  child: Text(size.displayName),
                ))
            .toList(),
        onChanged: (value) {
          if (value != null) {
            ref.read(playerControllerProvider.notifier).setBufferSize(value);
          }
        },
      ),
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text(AppConstants.appName),
      subtitle: const Text('Version ${AppConstants.appVersion}'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: AppConstants.appName,
          applicationVersion: AppConstants.appVersion,
          applicationLegalese: l10n.gplLicense,
          children: [
            const SizedBox(height: 16),
            Text(
              l10n.aboutDescription,
            ),
          ],
        );
      },
    );
  }
}
