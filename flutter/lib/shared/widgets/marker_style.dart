import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Building blocks of the "Marker" look shared by the diary screens: serif
/// prose, a mood-colored highlighter stroke behind titles, and the paper-leaf
/// date marker.

const kMarkerSerif = 'Newsreader';
const kMarkerLeafWidth = 52.0;

/// Newsreader ships as a variable font, so weight and optical size are set
/// through the axes as well as through fontWeight.
TextStyle markerSerif({
  required double size,
  required Color color,
  int weight = 400,
  double? height,
  bool italic = false,
}) =>
    TextStyle(
      fontFamily: kMarkerSerif,
      fontSize: size,
      height: height,
      color: color,
      letterSpacing: 0,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: FontWeight.values[weight ~/ 100 - 1],
      fontVariations: [
        FontVariation('wght', weight.toDouble()),
        FontVariation('opsz', size.clamp(6, 72).toDouble()),
      ],
      fontFeatures: const [FontFeature.liningFigures()],
    );

/// Accent color for a mood value (`Mood.name`).
Color moodColor(String mood) => switch (mood) {
      'happy' => const Color(0xFFF9A825),
      'calm' => const Color(0xFF43A047),
      'tense' => const Color(0xFFEF6C00),
      'sad' => const Color(0xFF1565C0),
      'mixed' => const Color(0xFF6A1B9A),
      _ => const Color(0xFF5C6BC0),
    };

/// Mood colors are tuned as accents; as text they need more contrast against
/// the surface.
Color moodInk(Color c, Brightness brightness) {
  final hsl = HSLColor.fromColor(c);
  return (brightness == Brightness.dark
          ? hsl.withLightness(max(hsl.lightness, 0.70))
          : hsl.withLightness(min(hsl.lightness, 0.34)))
      .toColor();
}

/// The translucent stroke color a mood leaves behind a title.
Color moodHighlight(Color c, Brightness brightness) =>
    c.withValues(alpha: brightness == Brightness.dark ? 0.45 : 0.32);

/// A title with a highlighter stroke along the lower half of each line.
class MarkerHighlightedTitle extends StatelessWidget {
  const MarkerHighlightedTitle({
    super.key,
    required this.text,
    required this.style,
    required this.color,
  });

  final String text;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Full width, so the painter lays the text out against the same
    // constraint as the Text widget and breaks lines identically.
    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        painter: _HighlightPainter(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
          color: color,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.text,
    required this.style,
    required this.color,
    required this.textScaler,
    required this.textDirection,
  });

  final String text;
  final TextStyle style;
  final Color color;
  final TextScaler textScaler;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    final paint = Paint()..color = color;
    // The stroke covers the lower half of each line, like a marker pen
    // dragged along the baseline.
    for (final line in tp.computeLineMetrics()) {
      canvas.drawRect(
        Rect.fromLTRB(
          line.left - 3,
          line.baseline - line.ascent * 0.40,
          line.left + line.width + 3,
          line.baseline + line.descent * 0.5,
        ),
        paint,
      );
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.text != text ||
      old.style != style ||
      old.color != color ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection;
}

/// The date leaf: a small slip of paper. The weekday is the dark, bold part;
/// the day number is deliberately paler. Both turn primary on today.
class MarkerDateLeaf extends StatelessWidget {
  const MarkerDateLeaf({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;
    final now = DateTime.now();
    final today =
        date.year == now.year && date.month == now.month && date.day == now.day;

    return Container(
      width: kMarkerLeafWidth,
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 3),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerLowest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              DateFormat.E(locale)
                  .format(date)
                  .replaceAll('.', '')
                  .toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                color: today ? cs.primary : cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              date.day.toString().padLeft(2, '0'),
              style: markerSerif(
                size: 30,
                height: 1.15,
                color: today ? cs.primary : cs.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
