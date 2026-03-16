import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/utils/logger.dart';
import 'data/datasources/local/database_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap in-memory decoded image cache to prevent memory bloat
  // when scrolling through large channel lists with logos
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB

  // Initialize media_kit for video playback
  MediaKit.ensureInitialized();

  // NOTE: Multi-window support (popup player windows) is planned but not yet implemented.
  // The desktop_multi_window package requires native code integration that needs further work.
  // For now, users should use the "Open in External Player" option for separate window playback.

  // Initialize window manager for desktop
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
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Database Error',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Failed to initialize database:\n$e\n\nPlease restart the app.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    return;
  }

  runApp(
    const ProviderScope(
      child: FlowTVApp(),
    ),
  );
}
