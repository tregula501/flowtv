import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/cast_service.dart';
import '../providers/cast_provider.dart';

/// Cast button widget that shows on supported platforms
/// Displays cast icon and opens device picker dialog
class CastButton extends ConsumerWidget {
  final Color? iconColor;
  final double iconSize;
  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  const CastButton({
    super.key,
    this.iconColor,
    this.iconSize = 24.0,
    this.onCastStarted,
    this.onCastStopped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castControllerProvider);

    // Don't show on unsupported platforms
    if (!castState.isSupported) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        castState.isConnected ? Icons.cast_connected : Icons.cast,
        color: iconColor ?? (castState.isConnected ? Colors.blue : null),
        size: iconSize,
      ),
      tooltip: castState.isConnected
          ? 'Connected to ${castState.connectedDevice?.name}'
          : 'Cast to device',
      onPressed: () => _showCastDialog(context, ref, castState),
    );
  }

  void _showCastDialog(
      BuildContext context, WidgetRef ref, CastState castState,) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _CastDeviceSheet(
        onCastStarted: onCastStarted,
        onCastStopped: onCastStopped,
      ),
    );
  }
}

/// Bottom sheet for Cast device selection
class _CastDeviceSheet extends ConsumerStatefulWidget {
  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  const _CastDeviceSheet({
    this.onCastStarted,
    this.onCastStopped,
  });

  @override
  ConsumerState<_CastDeviceSheet> createState() => _CastDeviceSheetState();
}

class _CastDeviceSheetState extends ConsumerState<_CastDeviceSheet> {
  @override
  void initState() {
    super.initState();
    // Start discovery when sheet opens
    Future.microtask(() {
      ref.read(castControllerProvider.notifier).startDiscovery();
    });
  }

  @override
  void dispose() {
    // Stop discovery when sheet closes
    ref.read(castControllerProvider.notifier).stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final castState = ref.watch(castControllerProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                castState.isConnected ? Icons.cast_connected : Icons.cast,
                color: castState.isConnected ? Colors.blue : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  castState.isConnected
                      ? 'Connected to ${castState.connectedDevice?.name}'
                      : 'Select a device',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (castState.isConnected)
                TextButton(
                  onPressed: () async {
                    await ref.read(castControllerProvider.notifier).disconnect();
                    widget.onCastStopped?.call();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Disconnect'),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Device list or loading
          if (castState.isDiscovering && castState.devices.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Searching for devices...'),
                  ],
                ),
              ),
            )
          else if (castState.devices.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.cast,
                      size: 48,
                      color: theme.colorScheme.onSurface.withAlpha(102),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No devices found',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Make sure your Chromecast is on the same network',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.read(castControllerProvider.notifier).startDiscovery();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Search again'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: castState.devices.length,
              itemBuilder: (context, index) {
                final device = castState.devices[index];
                final isConnected =
                    castState.connectedDevice?.id == device.id;

                return ListTile(
                  leading: Icon(
                    Icons.tv,
                    color: isConnected ? Colors.blue : null,
                  ),
                  title: Text(device.name),
                  subtitle: isConnected ? const Text('Connected') : null,
                  trailing: isConnected
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: isConnected
                      ? null
                      : () async {
                          final success = await ref
                              .read(castControllerProvider.notifier)
                              .connect(device);
                          if (success) {
                            widget.onCastStarted?.call();
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                );
              },
            ),

          // Discovering indicator
          if (castState.isDiscovering && castState.devices.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Searching for more devices...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Mini controller widget for active Cast session
/// Shows playback controls when casting
class CastMiniController extends ConsumerWidget {
  const CastMiniController({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castControllerProvider);

    // Don't show if not connected or not playing
    if (!castState.isConnected ||
        castState.playbackState == CastPlaybackState.idle) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final session = castState.sessionState;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cast icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cast_connected, color: Colors.blue),
          ),
          const SizedBox(width: 12),

          // Device name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  castState.connectedDevice?.name ?? 'Casting',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _getStatusText(session.playbackState),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Playback controls
          if (session.playbackState == CastPlaybackState.playing)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () =>
                  ref.read(castControllerProvider.notifier).pause(),
            )
          else if (session.playbackState == CastPlaybackState.paused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () =>
                  ref.read(castControllerProvider.notifier).play(),
            )
          else if (session.playbackState == CastPlaybackState.buffering ||
              session.playbackState == CastPlaybackState.loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          // Stop button
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: () => ref.read(castControllerProvider.notifier).stop(),
          ),
        ],
      ),
    );
  }

  String _getStatusText(CastPlaybackState state) {
    switch (state) {
      case CastPlaybackState.loading:
        return 'Loading...';
      case CastPlaybackState.buffering:
        return 'Buffering...';
      case CastPlaybackState.playing:
        return 'Playing';
      case CastPlaybackState.paused:
        return 'Paused';
      case CastPlaybackState.stopped:
        return 'Stopped';
      case CastPlaybackState.idle:
        return 'Ready';
    }
  }
}
