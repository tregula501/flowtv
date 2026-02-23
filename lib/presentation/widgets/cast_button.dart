import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final isSupported = ref.watch(castControllerProvider.select((s) => s.isSupported));
    final isConnected = ref.watch(castControllerProvider.select((s) => s.isConnected));
    final connectedDeviceName = ref.watch(castControllerProvider.select((s) => s.connectedDevice?.name));

    // Don't show on unsupported platforms
    if (!isSupported) {
      return const SizedBox.shrink();
    }

    final connectedLabel = isConnected
        ? l10n.castConnectedTo(connectedDeviceName ?? '')
        : l10n.castToDevice;

    return Semantics(
      label: connectedLabel,
      button: true,
      child: IconButton(
        icon: Icon(
          isConnected ? Icons.cast_connected : Icons.cast,
          color: iconColor ?? (isConnected ? Colors.blue : null),
          size: iconSize,
        ),
        tooltip: connectedLabel,
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
