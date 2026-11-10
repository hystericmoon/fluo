import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "A theme change applies across all screens" only holds if no screen draws
/// the accent from a constant. This fails if lime is hard-coded outside the
/// few places where it is meant to stay lime.
void main() {
  test('only the logo, the brand-coloured export, the theme definitions and the pin letters use lime constants', () {
    // path suffix: why it may use lime
    const allowed = {
      'lib/theme/tokens.dart': 'defines the constants',
      'lib/theme/accent.dart': 'the default theme is built from them',
      'lib/ui/wordmark.dart': 'the logo is lime in every theme',
      'lib/export/long_image.dart': 'exports keep the brand look, whatever theme the person uses',
      'lib/edit/render.dart': 'default selection ring colour, and dark letters on severity pins',
      'lib/ui/kit.dart': 'dark letters on severity pins (not the accent)',
    };
    final pattern = RegExp(r'FluoColors\.(lime(?!Tint|Soft)\b|limeTint|limeSoft|onLime)');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll('\\', '/');
      if (allowed.keys.any(path.endsWith)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('$path:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'use context.accent instead:\n${offenders.join('\n')}');
  });

  test('inside the allowed files, the accent-looking uses are only the ones intended', () {
    final kit = File('lib/ui/kit.dart').readAsStringSync();
    // kit.dart may only use onLime for the pin letter; everything else goes through context.accent.
    final uses = RegExp(r'FluoColors\.(lime(?!Tint|Soft)\b|limeTint|limeSoft|onLime)').allMatches(kit).map((m) => m.group(0)).toList();
    expect(uses, ['FluoColors.onLime'], reason: 'kit.dart: $uses');
    final render = File('lib/edit/render.dart').readAsStringSync();
    final ru = RegExp(r'FluoColors\.(lime(?!Tint|Soft)\b|limeTint|limeSoft|onLime)').allMatches(render).map((m) => m.group(0)).toList();
    expect(ru.toSet(), {'FluoColors.lime', 'FluoColors.onLime'});
  });
}
