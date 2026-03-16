import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../../../core/utils/logger.dart';

/// Handles fullscreen and Picture-in-Picture window management on desktop.
class DisplayModeController {
  /// Saved window geometry for restoring after PiP
  Size? _savedWindowSize;
  Offset? _savedWindowPosition;
  bool _savedAlwaysOnTop = false;

  /// Toggle fullscreen on/off.
  ///
  /// [currentFullscreen] is the current fullscreen state.
  /// [onChanged] is called with the new fullscreen value so the caller can
  /// update player state.
  Future<void> toggleFullscreen(
    bool currentFullscreen, {
    required void Function(bool fullscreen) onChanged,
  }) async {
    await setFullscreen(!currentFullscreen, onChanged: onChanged);
  }

  /// Set fullscreen to [fullscreen].
  Future<void> setFullscreen(
    bool fullscreen, {
    required void Function(bool fullscreen) onChanged,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.ensureInitialized();
        await windowManager.setFullScreen(fullscreen);
        onChanged(fullscreen);
        AppLogger.info('Fullscreen: $fullscreen');
      } catch (e) {
        AppLogger.error('Failed to toggle fullscreen: $e');
      }
    } else {
      // For mobile / other platforms, just update state (UI will handle it)
      onChanged(fullscreen);
    }
  }

  /// Toggle PiP mode on/off.
  Future<void> togglePiPMode({
    required bool currentPiP,
    required bool currentFullscreen,
    required void Function({required bool isPiP, bool? isFullscreen}) onChanged,
  }) async {
    await setPiPMode(
      !currentPiP,
      currentFullscreen: currentFullscreen,
      onChanged: onChanged,
    );
  }

  /// Enter or leave Picture-in-Picture mode.
  Future<void> setPiPMode(
    bool pip, {
    required bool currentFullscreen,
    required void Function({required bool isPiP, bool? isFullscreen}) onChanged,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      AppLogger.warning('PiP mode only supported on desktop');
      return;
    }

    try {
      await windowManager.ensureInitialized();

      if (pip) {
        // Save current window state before entering PiP
        _savedWindowSize = await windowManager.getSize();
        _savedWindowPosition = await windowManager.getPosition();
        _savedAlwaysOnTop = await windowManager.isAlwaysOnTop();

        // Exit fullscreen if active
        if (currentFullscreen) {
          await windowManager.setFullScreen(false);
        }

        // Configure PiP window: small, always on top, positioned in corner
        await windowManager.setAlwaysOnTop(true);
        const pipSize = Size(400, 250);
        await windowManager.setSize(pipSize);

        // Position in bottom-right area relative to the previous window bounds
        const padding = 20.0;
        final savedPos = _savedWindowPosition ?? Offset.zero;
        final savedSize = _savedWindowSize ?? const Size(1280, 720);
        final right = savedPos.dx + savedSize.width;
        final bottom = savedPos.dy + savedSize.height;
        await windowManager.setPosition(Offset(
          right - pipSize.width - padding,
          bottom - pipSize.height - padding,
        ));

        onChanged(isPiP: true, isFullscreen: false);
        AppLogger.info('Entered PiP mode');
      } else {
        // Restore previous window state
        await windowManager.setAlwaysOnTop(_savedAlwaysOnTop);

        if (_savedWindowSize != null) {
          await windowManager.setSize(_savedWindowSize!);
        }
        if (_savedWindowPosition != null) {
          await windowManager.setPosition(_savedWindowPosition!);
        }

        onChanged(isPiP: false);
        AppLogger.info('Exited PiP mode');
      }
    } catch (e) {
      AppLogger.error('Failed to toggle PiP mode: $e');
    }
  }
}
