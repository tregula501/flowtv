import 'package:flutter/material.dart';

/// Centralized motion design tokens — the single source of truth for animation
/// durations and curves across FlowTV.
///
/// Before this existed, durations (150/200/300/400ms) and curves were hardcoded
/// inline at every call site, so the player/overlay surfaces each felt slightly
/// different. Reference these tokens instead of literals so motion stays
/// consistent app-wide.
///
/// IMPORTANT: motion is presentation-only. None of these tokens may be used to
/// gate, delay, or await a playback action (playChannel/playPause/etc.) — taps
/// must always fire their callbacks immediately.
class MotionTokens {
  MotionTokens._();

  /// 100ms — tap/press micro-feedback.
  static const Duration instant = Duration(milliseconds: 100);

  /// 150ms — hover, reversible state toggles, AnimatedSwitcher cross-fades.
  static const Duration fast = Duration(milliseconds: 150);

  /// 200ms — the default: control overlays, dialog/error reveals, route
  /// transitions. Material's standard duration.
  static const Duration base = Duration(milliseconds: 200);

  /// 300ms — content/list/grid entrances, image fade-in, scroll-to-now.
  static const Duration emphasized = Duration(milliseconds: 300);

  /// 400ms — one-shot welcome/empty-state flourishes, channel-switch overlay.
  static const Duration slow = Duration(milliseconds: 400);

  /// Entrances and appearances.
  static const Curve standard = Curves.easeInOutCubicEmphasized;

  /// Dismissals and scroll mirroring.
  static const Curve exit = Curves.easeOut;

  /// Reversible state (hover, selection, opacity).
  static const Curve toggle = Curves.easeInOut;

  /// Per-index stagger delay for list/grid entrances, capped so only the first
  /// viewport staggers and long lists never accumulate visible lag.
  static Duration stagger(int index, {int stepMs = 25, int capMs = 300}) =>
      Duration(milliseconds: (index * stepMs).clamp(0, capMs));

  /// Incoming curve for [fadeThrough] switchers: content appears during the
  /// last two thirds of the transition.
  static const Curve fadeThroughIn =
      Interval(0.35, 1.0, curve: Curves.easeOutCubic);

  /// Outgoing curve for [fadeThrough] switchers: old content clears during the
  /// first third, before the new content lands.
  static const Curve fadeThroughOut =
      Interval(0.65, 1.0, curve: Curves.easeInCubic);

  /// Material fade-through transition for AnimatedSwitcher: fade paired with a
  /// gentle scale-up so surfaces feel like they arrive rather than cross-blend.
  /// Pair with [fadeThroughIn]/[fadeThroughOut] as switchIn/switchOutCurve.
  static Widget fadeThrough(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
        child: child,
      ),
    );
  }
}

/// Reduced-motion helper. Respects the platform accessibility setting
/// (MediaQuery.disableAnimations) so users who opt out of motion get an instant,
/// flourish-free experience. Every additive animation in the app should branch
/// on this before applying entrance/pulse/transition effects.
extension ReducedMotion on BuildContext {
  bool get reduceMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;
}
