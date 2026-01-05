import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/utils/logger.dart';
import 'data/datasources/local/database_service.dart';
import 'presentation/screens/player/popup_player_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback
  MediaKit.ensureInitialized();

  // Check if this is a sub-window (popup player)
  if (args.firstOrNull == 'multi_window') {
    // This is a sub-window - show the popup player
    final windowId = args[1];
    final argument = args.length > 2 ? args[2] : '{}';

    // Parse the channel data passed from main window
    Map<String, dynamic> channelData = {};
    try {
      channelData = jsonDecode(argument) as Map<String, dynamic>;
    } catch (_) {}

    // Initialize window manager for this sub-window
    await windowManager.ensureInitialized();
    await windowManager.setTitle('FlowTV - ${channelData['name'] ?? 'Player'}');
    await windowManager.setMinimumSize(const Size(400, 300));

    runApp(
      ProviderScope(
        child: PopupPlayerWindow(
          windowId: windowId,
          channelName: channelData['name'] as String? ?? 'Unknown Channel',
          streamUrl: channelData['streamUrl'] as String? ?? '',
          logoUrl: channelData['logoUrl'] as String?,
        ),
      ),
    );
    return;
  }

  // Initialize window manager for desktop (main window only)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.black,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'FlowTV',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize logger
  AppLogger.init();
  AppLogger.info('FlowTV starting...');

  // Initialize database
  try {
    await DatabaseService.initialize();
    AppLogger.info('Database initialized');
  } catch (e) {
    AppLogger.error('Database init failed: $e');
  }

  runApp(
    const ProviderScope(
      child: FlowTVApp(),
    ),
  );
}
