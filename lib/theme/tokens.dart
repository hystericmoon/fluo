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

/// Soft fills and extra tints used by the mocks.
abstract final class FluoTints {
  static const bugSoft = Color(0xFF2A1416);
  static const bugInk = Color(0xFFFCA5A5);
  static const warnSoft = Color(0xFF2A2110);
  static const warnBorder = Color(0xFF8A6A14); // mock was #7A5C10 (2.5:1); raised to pass 3:1
  static const warnTitle = Color(0xFFFDE68A);
  static const warnBody = Color(0xFFE3D49A);
  static const bugBody = Color(0xFFE8C3C3);
  static const chevron = Color(0xFF8E8E98);
}

/// Text style shortcut: Inter, no decoration.
TextStyle fs(
  double size, {
  FontWeight w = FontWeight.w400,
  Color c = FluoColors.fg,
  double? h,
  double? ls,
}) =>
    TextStyle(
      fontFamily: FluoFonts.body,
      fontSize: size,
      fontWeight: w,
      color: c,
      height: h,
      letterSpacing: ls,
      decoration: TextDecoration.none,
    );
