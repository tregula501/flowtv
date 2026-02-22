import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';

/// Whether the device has network connectivity
final connectivityProvider = StreamNotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

class ConnectivityNotifier extends StreamNotifier<bool> {
  @override
  Stream<bool> build() {
    // Check initial state
    Connectivity().checkConnectivity().then((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      AppLogger.info('Initial connectivity: ${connected ? "online" : "offline"}');
    });

    return Connectivity().onConnectivityChanged.map((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      AppLogger.info('Connectivity changed: ${connected ? "online" : "offline"}');
      return connected;
    });
  }
}
