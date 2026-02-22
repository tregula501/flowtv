import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';

/// Whether the device has network connectivity
final connectivityProvider = StreamNotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);

class ConnectivityNotifier extends StreamNotifier<bool> {
  @override
  Stream<bool> build() async* {
    // Emit initial connectivity state so the provider isn't stuck in loading
    final initial = await Connectivity().checkConnectivity();
    final initiallyConnected = initial.any((r) => r != ConnectivityResult.none);
    AppLogger.info('Initial connectivity: ${initiallyConnected ? "online" : "offline"}');
    yield initiallyConnected;

    // Then stream ongoing changes
    await for (final results in Connectivity().onConnectivityChanged) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      AppLogger.info('Connectivity changed: ${connected ? "online" : "offline"}');
      yield connected;
    }
  }
}
