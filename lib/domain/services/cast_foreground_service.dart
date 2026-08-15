import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Controls the Android foreground service that keeps the CPU, Wi-Fi, and the
/// on-device HLS proxy alive while a Chromecast session is active and the
/// screen is off.
///
/// No-op on every platform except Android (iOS casting doesn't run a local
/// proxy pipeline that needs protecting, and desktop has no cast support).
class CastForegroundService {
  CastForegroundService._();

  static const _channel = MethodChannel('flowtv/cast_foreground');

  /// Start (or update) the foreground service. Safe to call repeatedly —
  /// re-invoking updates the notification with the new device/title.
  static Future<void> start({required String deviceName, String? title}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('start', {
        'deviceName': deviceName,
        'title': title,
      });
      AppLogger.info('CastForegroundService: started (device=$deviceName)');
    } on PlatformException catch (e) {
      // Non-fatal: casting still works with the screen on. Most likely cause
      // is a foreground-service-start restriction while backgrounded (API 31+).
      AppLogger.warning('CastForegroundService: start failed — ${e.message}');
    }
  }

  /// Stop the foreground service and release its wakelock/Wi-Fi lock.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stop');
      AppLogger.info('CastForegroundService: stopped');
    } on PlatformException catch (e) {
      AppLogger.warning('CastForegroundService: stop failed — ${e.message}');
    }
  }
}
