import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../data/datasources/local/drift/app_database.dart' show Channel;
import '../providers/channel_provider.dart';
import '../providers/player_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../core/themes/motion.dart';
import 'channel_letter_avatar.dart';
import 'common/entrance.dart';
import 'common/skeleton.dart';

class ChannelGrid extends ConsumerWidget {
  const ChannelGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 1.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
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
        ).animatedEntrance(context, index: index);
      },
    );
  }
}

class ChannelTile extends StatefulWidget {
  final Channel channel;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.isPlaying,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Combined press + hover scale: press wins (0.97), then hover lift (1.03).
    final double scale = _isPressed ? 0.97 : (_isHovered ? 1.03 : 1.0);
    // Hover and keyboard/D-pad focus share the same highlighted border.
    final bool highlighted = _isHovered || _isFocused;

    return Semantics(
      label: '${widget.channel.name}${widget.channel.isFavorite ? ', favorite' : ''}${widget.isPlaying ? ', now playing' : ''}',
      button: true,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (mounted) setState(() => _isFocused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: MotionTokens.instant,
          child: AnimatedContainer(
          duration: MotionTokens.fast,
          decoration: BoxDecoration(
            color: widget.isPlaying
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isPlaying
                  ? theme.colorScheme.primary
                  : highlighted
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.dividerColor,
              width: widget.isPlaying ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Channel logo
                    Expanded(
                      child: _buildLogo(theme),
                    ),

                    const SizedBox(height: 8),

                    // Channel name
                    Text(
                      widget.channel.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: widget.isPlaying ? FontWeight.w600 : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Channel number
                    if (widget.channel.channelNumber != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '#${widget.channel.channelNumber}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),

              // Favorite button (always visible for touch devices)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: Icon(
                    widget.channel.isFavorite ? Icons.star : Icons.star_border,
                    color: widget.channel.isFavorite
                        ? Colors.amber
                        : Colors.white70,
                    size: 20,
                  ),
                  onPressed: widget.onFavoriteToggle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),

              // Playing indicator
              if (widget.isPlaying)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ).livePulse(context),
                ),

              // Locked indicator
              if (widget.channel.isLocked)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Icon(
                    Icons.lock,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        ),
        ),
      ),
      ),
    );
  }

  Widget _buildLogo(ThemeData theme) {
    if (widget.channel.logoUrl != null && widget.channel.logoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.channel.logoUrl!,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 350),
        placeholder: (context, url) =>
            const ShimmerLogoPlaceholder(borderRadius: 8),
        errorWidget: (context, url, error) => _buildPlaceholder(theme),
      );
    }
    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return ChannelLetterAvatar(
      name: widget.channel.name,
      borderRadius: BorderRadius.circular(8),
      fontSize: 20,
    );
  }
}
