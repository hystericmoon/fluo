import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'accent.dart';
import 'tokens.dart';

/// Dark theme with the chosen [accent]. The logo never uses it and stays lime.
ThemeData fluoTheme({Accent accent = Accent.lime}) {
  final scheme = ColorSchemes.darkZinc.copyWith(
    background: () => FluoColors.bg,
    card: () => FluoColors.surface,
    primary: () => accent.color,
    primaryForeground: () => accent.onColor,
    border: () => FluoColors.border,
    ring: () => accent.color,
    mutedForeground: () => FluoColors.fgMuted,
  );
  return ThemeData(
    colorScheme: scheme,
    radius: 0.6,
    typography: const Typography.geist(
      sans: TextStyle(fontFamily: FluoFonts.body),
    ),
  );
}
