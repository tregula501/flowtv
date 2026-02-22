import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/drift/app_database.dart' show Channel;
import '../../l10n/app_localizations.dart';
import '../providers/cast_provider.dart';
import '../providers/player_provider.dart';

/// Shared Chromecast device selection bottom-sheet.
///
/// Used by both the mobile player and the desktop player so that casting
/// works regardless of which layout is active (phone vs tablet/foldable).
class CastDeviceSheet extends ConsumerWidget {
  final Channel channel;
  final VoidCallback onClose;

  const CastDeviceSheet({
    super.key,
    required this.channel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final castState = ref.watch(castControllerProvider);
    final castNotifier = ref.read(castControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.cast, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.castTo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (castState.isDiscovering)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Connected device info
          if (castState.isConnected && castState.connectedDevice != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cast_connected, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected to ${castState.connectedDevice!.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Tap to cast "${channel.name}"',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cast current channel button
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final success = await castNotifier.castMedia(
                          url: channel.streamUrl,
                          title: channel.name,
                          subtitle: channel.group,
                          imageUrl: channel.logoUrl,
                          contentType: 'video/mp4',
                        );
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.castingTo(
                                  channel.name,
                                  castState.connectedDevice!.name)),
                              backgroundColor: Colors.green,
                            ),
                          );
                          onClose();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.castFailed(e.toString())),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: Text(l10n.cast),
                  ),
                  const SizedBox(width: 8),
                  // Disconnect button
                  TextButton(
                    onPressed: () async {
                      await castNotifier.disconnect();
                    },
                    child: Text(l10n.disconnect),
                  ),
                ],
              ),
            ),

          // Device list
          if (castState.devices.isEmpty && !castState.isDiscovering)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  l10n.noCastDevices,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: castState.devices.length,
                itemBuilder: (context, index) {
                  final device = castState.devices[index];
                  final isConnected =
                      castState.connectedDevice?.id == device.id;

                  return ListTile(
                    leading: Icon(
                      isConnected ? Icons.cast_connected : Icons.cast,
                      color: isConnected ? Colors.blue : Colors.white,
                    ),
                    title: Text(
                      device.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            isConnected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: device.modelName != null
                        ? Text(
                            device.modelName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    trailing: isConnected
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () async {
                      if (!isConnected) {
                        try {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.connectingTo(device.name)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }

                          final success = await castNotifier.connect(device);
                          if (success && context.mounted) {
                            ref
                                .read(playerControllerProvider.notifier)
                                .pause();

                            final castSuccess = await castNotifier.castMedia(
                              url: channel.streamUrl,
                              title: channel.name,
                              subtitle: channel.group,
                              imageUrl: channel.logoUrl,
                              contentType: 'video/mp4',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    castSuccess
                                        ? l10n.castingTo(
                                            channel.name, device.name)
                                        : l10n.connectedButPlaybackFailed,
                                  ),
                                  backgroundColor:
                                      castSuccess ? Colors.green : Colors.orange,
                                ),
                              );
                              onClose();
                            }
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    l10n.failedToConnect(device.name)),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.castError(e.toString())),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Helper to show the cast device sheet from anywhere.
void showCastSheet(BuildContext context, WidgetRef ref, Channel channel) {
  ref.read(castControllerProvider.notifier).startDiscovery();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey.shade900,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => CastDeviceSheet(
      channel: channel,
      onClose: () {
        ref.read(castControllerProvider.notifier).stopDiscovery();
        Navigator.pop(context);
      },
    ),
  );
}
