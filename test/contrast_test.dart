import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/theme/contrast.dart';
import 'package:fluo/theme/tokens.dart';

/// Every foreground/background pair the app actually draws, checked against
/// WCAG AA. If a token changes and a pair drops below its floor, this fails.
void main() {
  group('contrastRatio', () {
    test('known values', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)), closeTo(21, 1e-9));
      expect(contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)), closeTo(1, 1e-9));
      expect(contrastRatio(const Color(0xFF767676), const Color(0xFFFFFFFF)), closeTo(4.54, 0.01)); // the classic AA grey
      expect(contrastRatio(const Color(0xFF123456), const Color(0xFFFEDCBA)),
          closeTo(contrastRatio(const Color(0xFFFEDCBA), const Color(0xFF123456)), 1e-12), reason: 'symmetric');
    });
  });

  void text(String name, Color fg, Color bg) =>
      test('text: $name', () => expect(contrastRatio(fg, bg), greaterThanOrEqualTo(minTextContrast), reason: '$name is ${contrastRatio(fg, bg).toStringAsFixed(2)}:1'));
  void ui(String name, Color fg, Color bg) =>
      test('control or icon: $name', () => expect(contrastRatio(fg, bg), greaterThanOrEqualTo(minUiContrast), reason: '$name is ${contrastRatio(fg, bg).toStringAsFixed(2)}:1'));

  group('body text', () {
    text('foreground on background', FluoColors.fg, FluoColors.bg);
    text('foreground on card', FluoColors.fg, FluoColors.surface);
    text('muted on background', FluoColors.fgMuted, FluoColors.bg);
    text('muted on card', FluoColors.fgMuted, FluoColors.surface);
    text('muted on the lime-tinted card', FluoColors.fgMuted, FluoColors.limeTint);
    text('foreground on the card pressed fill', FluoColors.fg, FluoColors.surfaceHi);
  });

  group('lime accents', () {
    text('dark text on lime buttons', FluoColors.onLime, FluoColors.lime);
    text('lime text on background (wordmark, headings)', FluoColors.lime, FluoColors.bg);
    text('soft lime on the lime tint (selected chip)', FluoColors.limeSoft, FluoColors.limeTint);
    text('lime on the lime tint', FluoColors.lime, FluoColors.limeTint);
    text('foreground on the lime tint', FluoColors.fg, FluoColors.limeTint);
  });

  group('severity colours', () {
    for (final (name, c) in [('bug', FluoColors.bug), ('ux', FluoColors.ux), ('a11y', FluoColors.a11y)]) {
      ui('$name on background', c, FluoColors.bg);
      ui('$name on card', c, FluoColors.surface);
      text('dark letter on $name badge', FluoColors.onLime, c);
    }
    text('bug text on the bug tint (selected severity)', FluoColors.bug, FluoTints.bugSoft);
    text('bug ink on the bug tint', FluoTints.bugInk, FluoTints.bugSoft);
    text('bug body on the bug tint', FluoTints.bugBody, FluoTints.bugSoft);
  });

  group('notices', () {
    text('warning title', FluoTints.warnTitle, FluoTints.warnSoft);
    text('warning body', FluoTints.warnBody, FluoTints.warnSoft);
    ui('warning border on its fill', FluoTints.warnBorder, FluoTints.warnSoft);
    ui('bug border on its fill', FluoColors.bug, FluoTints.bugSoft);
  });

  group('boundaries of controls', () {
    ui('strong border on background', FluoColors.borderStrong, FluoColors.bg);
    ui('strong border on card', FluoColors.borderStrong, FluoColors.surface);
    ui('lime border on background', FluoColors.lime, FluoColors.bg);
    ui('chevron on card', FluoTints.chevron, FluoColors.surface);
    ui('switch track edge (off) on card', FluoColors.borderStrong, FluoColors.surface);
    ui('focus ring on background', FluoColors.lime, FluoColors.bg);
    ui('focus ring on card', FluoColors.lime, FluoColors.surface);
  });

  test('the faint card borders are decoration, not the only boundary of anything interactive', () {
    // FluoColors.border (#2E2E33) is used for cards and dividers only.
    // Controls use borderStrong, which passes above. This documents the split.
    expect(contrastRatio(FluoColors.border, FluoColors.bg), lessThan(minUiContrast));
    expect(contrastRatio(FluoColors.borderStrong, FluoColors.bg), greaterThanOrEqualTo(minUiContrast));
  });
}
