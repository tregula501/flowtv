import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/local/drift/app_database.dart' show Recording, RecordingStatus;
import '../../../l10n/app_localizations.dart';
import '../../providers/recording_provider.dart';
import '../../../core/extensions/datetime_extensions.dart';

class RecordingsScreen extends ConsumerWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final recordingsAsync = ref.watch(recordingsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.recordings),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.all),
              Tab(text: l10n.recording),
              Tab(text: l10n.scheduled),
            ],
          ),
        ),
        body: recordingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.failedToLoadRecordings)),
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
                  emptyMessage: l10n.noRecordingsYet,
                ),
                // Active recordings
                _RecordingsList(
                  recordings: active,
                  emptyMessage: l10n.noActiveRecordings,
                ),
                // Scheduled recordings
                _RecordingsList(
                  recordings: scheduled,
                  emptyMessage: l10n.noScheduledRecordings,
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
    final l10n = AppLocalizations.of(context)!;

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
                      _getDateTimeText(l10n),
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
                          Text(l10n.playComingSoon, style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  if (recording.status == RecordingStatus.recording)
                    PopupMenuItem(
                      value: 'stop',
                      child: Row(
                        children: [
                          const Icon(Icons.stop),
                          const SizedBox(width: 8),
                          Text(l10n.stop),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(l10n.delete, style: const TextStyle(color: Colors.red)),
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

  String _getDateTimeText(AppLocalizations l10n) {
    if (recording.status == RecordingStatus.recording) {
      return '${l10n.started}${recording.actualStart?.timeString ?? recording.scheduledStart.timeString}';
    }
    if (recording.status == RecordingStatus.scheduled) {
      return '${l10n.scheduledAt}${recording.scheduledStart.dateTimeString}';
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
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.recordingPlaybackNotImplemented)),
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
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.stopRecording),
        content: Text(l10n.stopRecordingConfirm(recording.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(recordingManagerProvider).stopRecording(recording.channelId);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.stop),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteRecording),
        content: Text(l10n.deleteRecordingConfirm(recording.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(recordingManagerProvider).deleteRecording(recording.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
    final color = _getColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getText(l10n),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getText(AppLocalizations l10n) {
    switch (status) {
      case RecordingStatus.scheduled:
        return l10n.statusScheduled;
      case RecordingStatus.recording:
        return l10n.statusRecording;
      case RecordingStatus.completed:
        return l10n.statusCompleted;
      case RecordingStatus.failed:
        return l10n.statusFailed;
      case RecordingStatus.cancelled:
        return l10n.statusCancelled;
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
