import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/utils/logger.dart';
import 'data/datasources/local/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize media_kit for video playback
  MediaKit.ensureInitialized();

  // Initialize logger
  AppLogger.init();
  AppLogger.info('FlowTV starting...');

  // Initialize database
  await DatabaseService.initialize();
  AppLogger.info('Database initialized');

  runApp(
    const ProviderScope(
      child: FlowTVApp(),
    ),
  );
}
