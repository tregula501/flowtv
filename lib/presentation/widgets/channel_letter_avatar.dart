import 'package:flutter/material.dart';

/// Colored initials tile shown when a channel has no logo (or the logo URL
/// fails to load). Far less "broken-looking" than a generic TV icon.
///
/// The color is derived deterministically from the channel name, so a channel
/// keeps the same color across screens and sessions.
class ChannelLetterAvatar extends StatelessWidget {
  final String name;

  /// Fixed square size. Null = fill the parent's constraints.
  final double? size;

  /// Corner radius. Null = circle (for chip avatars).
  final BorderRadius? borderRadius;

  final double fontSize;

  const ChannelLetterAvatar({
    super.key,
    required this.name,
    this.size,
    this.borderRadius,
    this.fontSize = 16,
  });

  // Muted, dark-leaning tones so the white initials stay readable in both
  // themes and the tiles don't shout louder than real logos next to them.
  static const List<Color> _palette = [
    Color(0xFF3949AB), // indigo
    Color(0xFF00695C), // teal
    Color(0xFF6A1B9A), // purple
    Color(0xFFAD1457), // pink
    Color(0xFF283593), // deep indigo
    Color(0xFF00838F), // cyan
    Color(0xFF4527A0), // deep purple
    Color(0xFF2E7D32), // green
    Color(0xFFB71C1C), // red
    Color(0xFFE65100), // orange
  ];

  /// Deterministic across sessions/platforms (String.hashCode is not).
  static int _stableHash(String s) {
    var hash = 0;
    for (final unit in s.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  /// "US: ESPN" -> "ES", "NBA 01:" -> "N0", "YES Network" -> "YN".
  @visibleForTesting
  static String initialsFor(String name) {
    // Strip country-style prefixes ("US:", "UK :") so they don't dominate.
    var cleaned =
        name.replaceFirst(RegExp(r'^[A-Za-z]{2,3}\s*:\s*'), '').trim();
    if (cleaned.isEmpty) cleaned = name.trim();
    if (cleaned.isEmpty) return '?';

    final words =
        cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    final word = words.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[_stableHash(name) % _palette.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: Center(
        child: Text(
          initialsFor(name),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
