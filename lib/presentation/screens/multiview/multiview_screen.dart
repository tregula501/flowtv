import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/channel.dart';
import '../../providers/multiview_provider.dart';
import '../../providers/channel_provider.dart';

class MultiViewScreen extends ConsumerStatefulWidget {
  const MultiViewScreen({super.key});

  @override
  ConsumerState<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends ConsumerState<MultiViewScreen> {
  int? _selectedSlotForChannel;

  @override
  void initState() {
    super.initState();
    // Enable multi-view when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(multiViewControllerProvider.notifier).enableMultiView();
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // ESC to exit
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.pop(context);
      }
      // Number keys 1-4 to switch audio
      if (event.logicalKey == LogicalKeyboardKey.digit1) {
        ref.read(multiViewControllerProvider.notifier).setActiveAudioSlot(0);
      }
      if (event.logicalKey == LogicalKeyboardKey.digit2) {
        ref.read(multiViewControllerProvider.notifier).setActiveAudioSlot(1);
      }
      if (event.logicalKey == LogicalKeyboardKey.digit3) {
        ref.read(multiViewControllerProvider.notifier).setActiveAudioSlot(2);
      }
      if (event.logicalKey == LogicalKeyboardKey.digit4) {
        ref.read(multiViewControllerProvider.notifier).setActiveAudioSlot(3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiViewState = ref.watch(multiViewControllerProvider);

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          title: const Text('Multi-View'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await ref
                  .read(multiViewControllerProvider.notifier)
                  .disableMultiView();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            // Audio source indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.volume_up, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'Audio: ${multiViewState.activeAudioSlot + 1}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            // Help button
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Keyboard shortcuts',
              onPressed: () => _showHelpDialog(),
            ),
          ],
        ),
        body: Stack(
          children: [
            // 2x2 Grid of video players
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 16 / 9,
              ),
              itemCount: maxMultiViewChannels,
              itemBuilder: (context, index) {
                final slot = multiViewState.slots[index];
                return _MultiViewTile(
                  slot: slot,
                  onAddChannel: () {
                    setState(() {
                      _selectedSlotForChannel = index;
                    });
                    _showChannelPicker(index);
                  },
                  onRemoveChannel: () {
                    ref
                        .read(multiViewControllerProvider.notifier)
                        .clearSlot(index);
                  },
                  onSetAudioActive: () {
                    ref
                        .read(multiViewControllerProvider.notifier)
                        .setActiveAudioSlot(index);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showChannelPicker(int slotIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _ChannelPickerSheet(
          scrollController: scrollController,
          onChannelSelected: (channel) {
            ref
                .read(multiViewControllerProvider.notifier)
                .setChannelInSlot(slotIndex, channel);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Multi-View Controls'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keyboard Shortcuts:'),
            SizedBox(height: 8),
            Text('• 1-4: Switch audio to slot 1-4'),
            Text('• ESC: Exit multi-view'),
            SizedBox(height: 16),
            Text('Mouse Controls:'),
            SizedBox(height: 8),
            Text('• Click + to add a channel'),
            Text('• Click speaker icon to set audio'),
            Text('• Click X to remove a channel'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _MultiViewTile extends StatefulWidget {
  final MultiViewSlot slot;
  final VoidCallback onAddChannel;
  final VoidCallback onRemoveChannel;
  final VoidCallback onSetAudioActive;

  const _MultiViewTile({
    required this.slot,
    required this.onAddChannel,
    required this.onRemoveChannel,
    required this.onSetAudioActive,
  });

  @override
  State<_MultiViewTile> createState() => _MultiViewTileState();
}

class _MultiViewTileState extends State<_MultiViewTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: widget.slot.isAudioActive
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade800,
            width: widget.slot.isAudioActive ? 3 : 1,
          ),
        ),
        child: Stack(
          children: [
            // Video or empty state
            if (widget.slot.channel != null)
              Video(
                controller: widget.slot.videoController,
                controls: NoVideoControls,
              )
            else
              _buildEmptySlot(),

            // Buffering indicator
            if (widget.slot.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Error overlay
            if (widget.slot.error != null) _buildErrorOverlay(),

            // Controls overlay (on hover)
            if (_isHovered || widget.slot.channel == null)
              _buildControlsOverlay(),

            // Slot number badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.slot.isAudioActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.slot.index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.slot.isAudioActive) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.volume_up, color: Colors.white, size: 16),
                    ],
                  ],
                ),
              ),
            ),

            // Channel name
            if (widget.slot.channel != null)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.slot.channel!.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySlot() {
    return Container(
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tv_off,
              size: 48,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 8),
            Text(
              'Slot ${widget.slot.index + 1}',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              'Playback Error',
              style: TextStyle(color: Colors.red.shade300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black38,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.slot.channel == null)
              // Add channel button
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 48),
                color: Colors.white,
                onPressed: widget.onAddChannel,
                tooltip: 'Add Channel',
              )
            else ...[
              // Set audio active button
              IconButton(
                icon: Icon(
                  widget.slot.isAudioActive ? Icons.volume_up : Icons.volume_off,
                  size: 32,
                ),
                color: widget.slot.isAudioActive ? Colors.amber : Colors.white,
                onPressed: widget.onSetAudioActive,
                tooltip: 'Set Audio Active',
              ),
              const SizedBox(width: 16),
              // Change channel button
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 32),
                color: Colors.white,
                onPressed: widget.onAddChannel,
                tooltip: 'Change Channel',
              ),
              const SizedBox(width: 16),
              // Remove channel button
              IconButton(
                icon: const Icon(Icons.close, size: 32),
                color: Colors.red.shade300,
                onPressed: widget.onRemoveChannel,
                tooltip: 'Remove Channel',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelPickerSheet extends ConsumerWidget {
  final ScrollController scrollController;
  final Function(Channel) onChannelSelected;

  const _ChannelPickerSheet({
    required this.scrollController,
    required this.onChannelSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsProvider);

    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Title
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Select Channel',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),

        // Channel list
        Expanded(
          child: channelsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (channels) => ListView.builder(
              controller: scrollController,
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                return ListTile(
                  leading: channel.logoUrl != null
                      ? Image.network(
                          channel.logoUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.tv, size: 40),
                        )
                      : const Icon(Icons.tv, size: 40),
                  title: Text(channel.name),
                  subtitle: channel.group != null ? Text(channel.group!) : null,
                  trailing: channel.isFavorite
                      ? const Icon(Icons.star, color: Colors.amber, size: 20)
                      : null,
                  onTap: () => onChannelSelected(channel),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
