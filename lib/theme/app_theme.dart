import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'tokens.dart';

/// Dark theme. [accent] is the user-selectable colour (Settings, session 9);
/// the logo never uses it and stays lime.
ThemeData fluoTheme({Color accent = FluoColors.lime}) {
  final scheme = ColorSchemes.darkZinc.copyWith(
    background: () => FluoColors.bg,
    card: () => FluoColors.surface,
    primary: () => accent,
    primaryForeground: () => FluoColors.onLime,
    border: () => FluoColors.border,
    ring: () => accent,
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
