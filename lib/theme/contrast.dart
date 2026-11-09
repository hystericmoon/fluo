import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.x relative luminance of an sRGB colour (alpha ignored).
double luminance(Color c) {
  double chan(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

/// WCAG contrast ratio between two colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Text under 18pt (or 14pt bold) needs 4.5:1 (WCAG 1.4.3 AA).
const double minTextContrast = 4.5;

/// Borders, icons and controls need 3:1 against their surroundings (1.4.11).
const double minUiContrast = 3.0;
