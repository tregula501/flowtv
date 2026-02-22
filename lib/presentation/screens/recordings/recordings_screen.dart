import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/local/drift/app_database.dart' show Recording, RecordingStatus;
import '../../providers/recording_provider.dart';
import '../../../core/extensions/datetime_extensions.dart';

class RecordingsScreen extends ConsumerWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingsAsync = ref.watch(recordingsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recordings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Recording'),
              Tab(text: 'Scheduled'),
            ],
          ),
        ),
        body: recordingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Failed to load recordings.')),
          data: (recordings) {
            final active = recordings
                .where((r) => r.status == RecordingStatus.recording)
                .toList();
            final scheduled = recordings
                .where((r) => r.status == RecordingStatus.scheduled)
                .toList();

            return TabBarView(
              children: [
                // All recordings
                _RecordingsList(
                  recordings: recordings,
                  emptyMessage: 'No recordings yet',
                ),
                // Active recordings
                _RecordingsList(
                  recordings: active,
                  emptyMessage: 'No active recordings',
                ),
                // Scheduled recordings
                _RecordingsList(
                  recordings: scheduled,
                  emptyMessage: 'No scheduled recordings',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecordingsList extends ConsumerWidget {
  final List<Recording> recordings;
  final String emptyMessage;

  const _RecordingsList({
    required this.recordings,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: recordings.length,
      itemBuilder: (context, index) {
        final recording = recordings[index];
        return _RecordingTile(recording: recording);
      },
    );
  }
}

class _RecordingTile extends ConsumerWidget {
  final Recording recording;

  const _RecordingTile({required this.recording});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: null, // Playback not yet implemented

        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getStatusColor(recording.status).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getStatusIcon(recording.status),
                  color: _getStatusColor(recording.status),
                ),
              ),

              const SizedBox(width: 16),

              // Recording info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getDateTimeText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(status: recording.status),
                        const SizedBox(width: 8),
                        if (recording.fileSize > 0)
                          Text(
                            _formatFileSize(recording.fileSize),
                            style: theme.textTheme.bodySmall,
                          ),
                        if (recording.durationSeconds > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(recording.durationSeconds),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  if (recording.status == RecordingStatus.completed)
                    PopupMenuItem(
                      enabled: false,
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text('Play (coming soon)', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  if (recording.status == RecordingStatus.recording)
                    const PopupMenuItem(
                      value: 'stop',
                      child: Row(
                        children: [
                          Icon(Icons.stop),
                          SizedBox(width: 8),
                          Text('Stop'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) => _handleAction(context, ref, value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDateTimeText() {
    if (recording.status == RecordingStatus.recording) {
      return 'Started: ${recording.actualStart?.timeString ?? recording.scheduledStart.timeString}';
    }
    if (recording.status == RecordingStatus.scheduled) {
      return 'Scheduled: ${recording.scheduledStart.dateTimeString}';
    }
    return recording.actualStart?.dateTimeString ??
        recording.scheduledStart.dateTimeString;
  }

  IconData _getStatusIcon(RecordingStatus status) {
    switch (status) {
      case RecordingStatus.scheduled:
        return Icons.schedule;
      case RecordingStatus.recording:
        return Icons.fiber_manual_record;
      case RecordingStatus.completed:
        return Icons.check_circle;
      case RecordingStatus.failed:
        return Icons.error;
      case RecordingStatus.cancelled:
        return Icons.cancel;
    }
  }

  Color _getStatusColor(RecordingStatus status) {
    switch (status) {
      case RecordingStatus.scheduled:
        return Colors.blue;
      case RecordingStatus.recording:
        return Colors.red;
      case RecordingStatus.completed:
        return Colors.green;
      case RecordingStatus.failed:
        return Colors.orange;
      case RecordingStatus.cancelled:
        return Colors.grey;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m ${secs}s';
  }

  void _playRecording(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recording playback is not yet implemented')),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'play':
        _playRecording(context, ref);
        break;
      case 'stop':
        _confirmStop(context, ref);
        break;
      case 'delete':
        _confirmDelete(context, ref);
        break;
    }
  }

  void _confirmStop(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recording'),
        content: Text('Are you sure you want to stop recording "${recording.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(recordingManagerProvider).stopRecording(recording.channelId);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recording'),
        content: Text('Are you sure you want to delete "${recording.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(recordingManagerProvider).deleteRecording(recording.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final RecordingStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getText(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getText() {
    switch (status) {
      case RecordingStatus.scheduled:
        return 'Scheduled';
      case RecordingStatus.recording:
        return 'Recording';
      case RecordingStatus.completed:
        return 'Completed';
      case RecordingStatus.failed:
        return 'Failed';
      case RecordingStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _getColor() {
    switch (status) {
      case RecordingStatus.scheduled:
        return Colors.blue;
      case RecordingStatus.recording:
        return Colors.red;
      case RecordingStatus.completed:
        return Colors.green;
      case RecordingStatus.failed:
        return Colors.orange;
      case RecordingStatus.cancelled:
        return Colors.grey;
    }
  }
}
