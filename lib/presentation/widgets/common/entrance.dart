import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/themes/motion.dart';

/// Shared entrance-animation helpers built on flutter_animate, all wired through
/// [MotionTokens] and respecting reduced-motion.
///
/// These are PURE presentation wrappers — they animate a widget's appearance and
/// never touch its callbacks, controllers, or the playback pipeline. When the
/// user has reduced motion enabled the child is returned unchanged.
extension EntranceAnimations on Widget {
  /// Staggered fade + subtle upward slide, intended for grid/list items.
  ///
  /// [index] drives a capped per-item delay so only the first viewport staggers.
  /// Pass [context] so reduced-motion is respected.
  Widget animatedEntrance(
    BuildContext context, {
    int index = 0,
    double slideBegin = 0.06,
  }) {
    if (context.reduceMotion) return this;
    return animate(delay: MotionTokens.stagger(index))
        .fadeIn(duration: MotionTokens.emphasized, curve: MotionTokens.exit)
        .slideY(
          begin: slideBegin,
          end: 0,
          duration: MotionTokens.emphasized,
          curve: MotionTokens.standard,
        );
  }

  /// One-shot fade + gentle scale-up, intended for empty/welcome state icons and
  /// hero text. Not staggered.
  Widget animatedReveal(
    BuildContext context, {
    Duration delay = Duration.zero,
    double scaleBegin = 0.92,
  }) {
    if (context.reduceMotion) return this;
    return animate(delay: delay)
        .fadeIn(duration: MotionTokens.slow, curve: MotionTokens.exit)
        .scale(
          begin: Offset(scaleBegin, scaleBegin),
          end: const Offset(1, 1),
          duration: MotionTokens.slow,
          curve: MotionTokens.standard,
        );
  }

  /// Slow breathing pulse (scale + opacity) for live indicators — now-playing
  /// dot, active-recording light, the EPG "now" line. Reads no state; it simply
  /// loops while mounted. Disabled under reduced-motion (returns a still child).
  Widget livePulse(BuildContext context) {
    if (context.reduceMotion) return this;
    return animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: Duration.zero)
        .scaleXY(
          begin: 0.85,
          end: 1.1,
          duration: const Duration(milliseconds: 800),
          curve: MotionTokens.toggle,
        );
  }
}
