import 'package:flutter/material.dart';

import '../themes/motion.dart';

/// Shared "fade-through" route transition for top-level screen pushes
/// (Settings / EPG / MultiView). A [MotionTokens.base] fade combined with a
/// subtle scale (0.98 -> 1.0) so navigation feels cohesive with the rest of the
/// app's motion system.
///
/// Presentation-only: this never touches playback. Do NOT use it for any
/// in-place fullscreen / PiP swap that mounts-unmounts a media_kit Video — it is
/// only for pushing a brand-new screen onto the navigator.
Route<T> fadeThroughRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionTokens.base,
    reverseTransitionDuration: MotionTokens.base,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Respect reduced-motion: no fade/scale flourish, just show the page.
      if (context.reduceMotion) return child;

      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionTokens.standard,
        reverseCurve: MotionTokens.exit,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
