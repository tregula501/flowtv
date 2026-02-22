import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cast_provider.dart';
import '../providers/channel_provider.dart';
import 'cast_device_sheet.dart';

/// Cast button widget that shows on supported platforms.
/// Opens the shared cast device sheet which handles both
/// connecting and sending media to the Chromecast.
class CastButton extends ConsumerWidget {
  final Color? iconColor;
  final double iconSize;

  const CastButton({
    super.key,
    this.iconColor,
    this.iconSize = 24.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castControllerProvider);

    // Don't show on unsupported platforms
    if (!castState.isSupported) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: castState.isConnected
          ? 'Cast connected to ${castState.connectedDevice?.name}'
          : 'Cast to device',
      button: true,
      child: IconButton(
        icon: Icon(
          castState.isConnected ? Icons.cast_connected : Icons.cast,
          color: iconColor ?? (castState.isConnected ? Colors.blue : null),
          size: iconSize,
        ),
        tooltip: castState.isConnected
            ? 'Connected to ${castState.connectedDevice?.name}'
            : 'Cast to device',
        onPressed: () {
          final channel = ref.read(currentChannelProvider);
          if (channel != null) {
            showCastSheet(context, ref, channel);
          }
        },
      ),
    );
  }
}
