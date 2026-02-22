import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playlist_provider.dart';
import '../../core/extensions/string_extensions.dart';
import '../../l10n/app_localizations.dart';

class AddPlaylistDialog extends ConsumerStatefulWidget {
  const AddPlaylistDialog({super.key});

  @override
  ConsumerState<AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends ConsumerState<AddPlaylistDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // M3U form
  final _m3uNameController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  final _epgUrlController = TextEditingController();

  // Xtream form
  final _xtreamNameController = TextEditingController();
  final _xtreamServerController = TextEditingController();
  final _xtreamUsernameController = TextEditingController();
  final _xtreamPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _m3uNameController.dispose();
    _m3uUrlController.dispose();
    _epgUrlController.dispose();
    _xtreamNameController.dispose();
    _xtreamServerController.dispose();
    _xtreamUsernameController.dispose();
    _xtreamPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
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
                  const Icon(Icons.playlist_add),
                  const SizedBox(width: 12),
                  Text(
                    l10n.addPlaylist,
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

            // Tabs
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.m3uUrl),
                Tab(text: l10n.xtreamCodes),
              ],
            ),

            // Tab content
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildM3uForm(),
                  _buildXtreamForm(),
                ],
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
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.addPlaylist),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildM3uForm() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _m3uNameController,
            decoration: InputDecoration(
              labelText: l10n.playlistName,
              hintText: l10n.playlistNameHint,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _m3uUrlController,
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
            l10n.epgAutoDetectHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildXtreamForm() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _xtreamNameController,
            decoration: InputDecoration(
              labelText: l10n.playlistName,
              hintText: l10n.playlistNameHint,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _xtreamServerController,
            decoration: InputDecoration(
              labelText: l10n.serverUrl,
              hintText: l10n.serverUrlHint,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _xtreamUsernameController,
            decoration: InputDecoration(
              labelText: l10n.username,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _xtreamPasswordController,
            decoration: InputDecoration(
              labelText: l10n.password,
            ),
            obscureText: true,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      if (_tabController.index == 0) {
        // M3U
        final name = _m3uNameController.text.trim();
        final url = _m3uUrlController.text.trim();
        final epgUrl = _epgUrlController.text.trim();

        if (name.isEmpty) {
          throw Exception(l10n.validationPlaylistName);
        }
        if (url.isEmpty || !url.isValidUrl) {
          throw Exception(l10n.validationM3uUrl);
        }

        await ref.read(playlistManagerProvider).addM3uPlaylist(
              name: name,
              url: url,
              epgUrl: epgUrl.isNotEmpty ? epgUrl : null,
            );
      } else {
        // Xtream Codes
        final name = _xtreamNameController.text.trim();
        final serverUrl = _xtreamServerController.text.trim();
        final username = _xtreamUsernameController.text.trim();
        final password = _xtreamPasswordController.text.trim();

        if (name.isEmpty) {
          throw Exception(l10n.validationPlaylistName);
        }
        if (serverUrl.isEmpty) {
          throw Exception(l10n.validationServerUrl);
        }
        if (username.isEmpty) {
          throw Exception(l10n.validationUsername);
        }
        if (password.isEmpty) {
          throw Exception(l10n.validationPassword);
        }

        await ref.read(playlistManagerProvider).addXtreamPlaylist(
              name: name,
              serverUrl: serverUrl,
              username: username,
              password: password,
            );
      }

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
          _isLoading = false;
        });
      }
    }
  }
}
