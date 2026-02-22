import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/themes/app_theme.dart';
import 'core/utils/logger.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/epg_provider.dart';
import 'presentation/providers/player_provider.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/home/mobile_home_screen.dart';

class FlowTVApp extends ConsumerStatefulWidget {
  const FlowTVApp({super.key});

  @override
  ConsumerState<FlowTVApp> createState() => _FlowTVAppState();
}

class _FlowTVAppState extends ConsumerState<FlowTVApp>
    with WidgetsBindingObserver {
  bool _wasPlayingBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start EPG auto-refresh after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(epgManagerProvider).startAutoRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop EPG auto-refresh when app closes
    ref.read(epgManagerProvider).stopAutoRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only manage lifecycle on mobile — desktop users expect playback to continue
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final player = ref.read(playerControllerProvider.notifier);
    final playerState = ref.read(playerControllerProvider);

    if (state == AppLifecycleState.paused) {
      _wasPlayingBeforePause = playerState.isPlaying;
      if (_wasPlayingBeforePause) {
        player.pause();
        AppLogger.debug('App backgrounded — paused playback');
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasPlayingBeforePause) {
        player.play();
        AppLogger.debug('App resumed — resumed playback');
        _wasPlayingBeforePause = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'FlowTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _buildHomeScreen(),
    );
  }

  Widget _buildHomeScreen() {
    // Use mobile UI for Android and iOS
    if (Platform.isAndroid || Platform.isIOS) {
      return const MobileHomeScreen();
    }
    // Use desktop UI for Windows, macOS, Linux
    return const HomeScreen();
  }
}
