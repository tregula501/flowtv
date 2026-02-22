import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/channel_provider.dart';
import '../providers/playlist_provider.dart';
import 'add_playlist_dialog.dart';

class CategorySidebar extends ConsumerWidget {
  const CategorySidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(channelGroupsProvider);
    final selectedGroup = ref.watch(selectedGroupProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final favoriteChannels = ref.watch(favoriteChannelsProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.live_tv,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    activePlaylist?.name ?? l10n.appTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Categories list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // All channels
                _CategoryTile(
                  icon: Icons.grid_view,
                  label: l10n.allChannels,
                  isSelected: selectedGroup == null,
                  onTap: () {
                    ref.read(selectedGroupProvider.notifier).select(null);
                  },
                ),

                // Favorites
                if (favoriteChannels.isNotEmpty)
                  _CategoryTile(
                    icon: Icons.star,
                    label: l10n.favorites,
                    count: favoriteChannels.length,
                    isSelected: selectedGroup == favoritesFilterKey,
                    iconColor: Colors.amber,
                    onTap: () {
                      ref.read(selectedGroupProvider.notifier).select(
                          favoritesFilterKey,);
                    },
                  ),

                const Divider(height: 16),

                // Group categories
                ...groups.map((group) {
                  return _CategoryTile(
                    icon: _getGroupIcon(group),
                    label: group,
                    isSelected: selectedGroup == group,
                    onTap: () {
                      ref.read(selectedGroupProvider.notifier).select(group);
                    },
                  );
                }),
              ],
            ),
          ),

          // Add playlist button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const AddPlaylistDialog(),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.addPlaylist),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getGroupIcon(String group) {
    final lowerGroup = group.toLowerCase();

    if (lowerGroup.contains('sport')) return Icons.sports_soccer;
    if (lowerGroup.contains('news')) return Icons.newspaper;
    if (lowerGroup.contains('movie') || lowerGroup.contains('film')) {
      return Icons.movie;
    }
    if (lowerGroup.contains('kid') || lowerGroup.contains('cartoon')) {
      return Icons.child_care;
    }
    if (lowerGroup.contains('music')) return Icons.music_note;
    if (lowerGroup.contains('document')) return Icons.article;
    if (lowerGroup.contains('entertainment')) return Icons.theater_comedy;
    if (lowerGroup.contains('religious') || lowerGroup.contains('faith')) {
      return Icons.church;
    }

    return Icons.tv;
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool isSelected;
  final Color? iconColor;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.icon,
    required this.label,
    this.count,
    required this.isSelected,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? selectedColor : iconColor ?? theme.iconTheme.color,
        size: 24,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? selectedColor : null,
          fontWeight: isSelected ? FontWeight.w700 : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: count != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: theme.textTheme.bodySmall,
              ),
            )
          : null,
      selected: isSelected,
      selectedTileColor: selectedColor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: onTap,
    );
  }
}
