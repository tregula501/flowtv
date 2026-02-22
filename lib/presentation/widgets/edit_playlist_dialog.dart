import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playlist_provider.dart';
import '../../data/datasources/local/drift/app_database.dart' show Playlist;
import '../../core/extensions/string_extensions.dart';
import '../../l10n/app_localizations.dart';

class EditPlaylistDialog extends ConsumerStatefulWidget {
  final Playlist playlist;

  const EditPlaylistDialog({super.key, required this.playlist});

  @override
  ConsumerState<EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends ConsumerState<EditPlaylistDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _epgUrlController;

  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
    _urlController = TextEditingController(text: widget.playlist.url);
    _epgUrlController = TextEditingController(text: widget.playlist.epgUrl ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _epgUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit),
                  const SizedBox(width: 12),
                  Text(
                    l10n.editPlaylist,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: l10n.playlistName,
                        hintText: l10n.playlistNameHint,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: l10n.m3uUrl,
                        hintText: l10n.m3uUrlHint,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _epgUrlController,
                      decoration: InputDecoration(
                        labelText: l10n.epgUrlOptional,
                        hintText: l10n.epgUrlHint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.editPlaylistUrlNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final url = _urlController.text.trim();
      final epgUrl = _epgUrlController.text.trim();

      if (name.isEmpty) {
        throw Exception(l10n.validationPlaylistName);
      }
      if (url.isEmpty || !url.isValidUrl) {
        throw Exception(l10n.validationM3uUrl);
      }

      await ref.read(playlistManagerProvider).updatePlaylist(
            playlistId: widget.playlist.id,
            name: name,
            url: url,
            epgUrl: epgUrl.isNotEmpty ? epgUrl : null,
          );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
