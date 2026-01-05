import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/themes/app_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/epg_provider.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/home/mobile_home_screen.dart';

class FlowTVApp extends ConsumerStatefulWidget {
  const FlowTVApp({super.key});

  @override
  ConsumerState<FlowTVApp> createState() => _FlowTVAppState();
}

class _FlowTVAppState extends ConsumerState<FlowTVApp> {
  @override
  void initState() {
    super.initState();
    // Start EPG auto-refresh after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(epgManagerProvider).startAutoRefresh();
    });
  }

  @override
  void dispose() {
    // Stop EPG auto-refresh when app closes
    ref.read(epgManagerProvider).stopAutoRefresh();
    super.dispose();
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
      ],
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
