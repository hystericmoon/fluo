import 'package:flutter/painting.dart';

/// Design tokens, taken from refs/mocks. Keep in sync with the mocks.
abstract final class FluoColors {
  static const lime = Color(0xFFC8FF3D);
  static const limeSoft = Color(0xFFD8FF85);
  static const limeTint = Color(0xFF1B2508); // active session card fill
  static const onLime = Color(0xFF0B0B0F);

  static const bg = Color(0xFF09090B);
  static const surface = Color(0xFF18181B);
  static const surfaceHi = Color(0xFF27272A);
  static const border = Color(0xFF2E2E33);
  static const borderStrong = Color(0xFF6B6B76); // 3:1 on bg, for controls
  static const fg = Color(0xFFFAFAFA);
  static const fgMuted = Color(0xFFA1A1AA);

  // Pin severities (shape and letter carry meaning too, never colour alone).
  static const bug = Color(0xFFF87171);
  static const ux = Color(0xFFFBBF24);
  static const a11y = Color(0xFF38BDF8);
}

abstract final class FluoFonts {
  static const display = 'Lexend';
  static const body = 'Inter';

  static TextStyle lexend(double size, {double weight = 600, double? tracking}) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontVariations: [FontVariation('wght', weight)],
        letterSpacing: tracking == null ? null : size * tracking,
      );
}
