import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/themes/motion.dart';

/// A reusable, actionable error state to replace dead-end single-line error
/// text. Shows an icon, the message, and an optional Retry button, with a gentle
/// fade + shake entrance (suppressed under reduced-motion).
///
/// Presentation-only: [onRetry] is supplied by the caller (typically
/// `ref.invalidate(someProvider)`) and fires immediately when pressed.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.error_outline,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  /// When true, lays out horizontally for inline/banner contexts.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;

    final Widget content = compact
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(message, style: theme.textTheme.bodyMedium),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onRetry, child: Text(retryLabel)),
              ],
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 56),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(retryLabel),
                ),
              ],
            ],
          );

    final padded = Padding(
      padding: const EdgeInsets.all(24),
      child: compact ? content : Center(child: content),
    );

    if (context.reduceMotion) return padded;
    return padded
        .animate()
        .fadeIn(duration: MotionTokens.base, curve: MotionTokens.exit)
        .shake(
          hz: 3,
          offset: const Offset(2, 0),
          rotation: 0,
          duration: MotionTokens.base,
        );
  }
}
