import '../data/models.dart';
import 'model.dart';

/// Where a pin sits in the exported picture ("72% across, 55% down"), or
/// null if the crop cut it out.
String? pinLocation(Pin p, CropRect? crop) {
  final c = crop ?? const CropRect(0, 0, 1, 1);
  if (p.x < c.left || p.x > c.right || p.y < c.top || p.y > c.bottom) return null;
  final x = (p.x - c.left) / (c.right - c.left);
  final y = (p.y - c.top) / (c.bottom - c.top);
  return '${(x * 100).round()}% across, ${(y * 100).round()}% down';
}

String severityWord(Severity s) => switch (s) {
      Severity.bug => 'Bug',
      Severity.ux => 'UX',
      Severity.a11y => 'Accessibility',
    };

/// `Bug, 72% across, 55% down: note`
String pinDetail(Pin p, CropRect? crop) => '${severityWord(p.severity)}, '
    '${pinLocation(p, crop) ?? 'outside the crop'}'
    '${p.note.trim().isEmpty ? '' : ': ${p.note.trim()}'}';

/// One line per pin: `B1 Bug, 72% across, 55% down: note`.
List<String> pinLines(ExportEntry e) => [
      for (final p in e.pins) '${p.severity.letter}${p.number} ${pinDetail(p, e.shot.crop)}',
    ];

String briefText(String albumName, List<ExportEntry> entries) {
  var bug = 0, ux = 0, a11y = 0;
  var withPins = 0;
  for (final e in entries) {
    if (e.pins.isNotEmpty) withPins++;
    for (final p in e.pins) {
      switch (p.severity) {
        case Severity.bug:
          bug++;
        case Severity.ux:
          ux++;
        case Severity.a11y:
          a11y++;
      }
    }
  }
  final pins = bug + ux + a11y;
  return 'This is a set of ${entries.length} ${entries.length == 1 ? 'screenshot' : 'screenshots'} '
      'from a mobile app, in the order a person moves through them. Each screen has a caption '
      'and numbered pins that mark things to look at.\n\n'
      'Pin letters: B is a bug (something is broken), U is a UX problem (confusing or awkward), '
      'A is an accessibility problem (hard to use for some people).\n\n'
      '${pins == 0 ? 'There are no pins yet.' : '$pins ${pins == 1 ? 'pin' : 'pins'} across $withPins '
          '${withPins == 1 ? 'screen' : 'screens'}: $bug bug, $ux UX, $a11y accessibility.'}\n\n'
      'For each screen, say what you make of the pinned issues, point out anything the pins missed, '
      'and suggest fixes, most important first.';
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// The Markdown file inside the Claude pack. [imagePaths] and [originalPaths]
/// map an entry number to its path inside the ZIP.
String buildMarkdown({
  required String albumName,
  required List<ExportEntry> entries,
  required Map<int, String> imagePaths,
  required Map<int, String> originalPaths,
  required bool includeBrief,
}) {
  final b = StringBuffer()..writeln('# $albumName: screenshot review')..writeln();
  if (includeBrief) {
    b
      ..writeln('## Review brief')
      ..writeln()
      ..writeln(briefText(albumName, entries))
      ..writeln()
      ..writeln('---')
      ..writeln();
  }
  for (final e in entries) {
    b
      ..writeln('## ${e.number}. ${e.title}')
      ..writeln()
      ..writeln('![${e.title.replaceAll(RegExp(r'[\[\]]'), '')}](${imagePaths[e.number]})')
      ..writeln();
    if (e.caption.isNotEmpty) b..writeln('Caption: ${e.caption}')..writeln();
    if (e.pins.isNotEmpty) {
      b.writeln('${_plural(e.pins.length, 'pin', 'pins')}:');
      for (final p in e.pins) {
        b.writeln('- **${p.severity.letter}${p.number}** ${pinDetail(p, e.shot.crop)}');
      }
      b.writeln();
    }
    if (e.redactionCount > 0) {
      b
        ..writeln('Note: ${_plural(e.redactionCount, 'area was', 'areas were')} hidden on this screen before sharing.')
        ..writeln();
    }
    final orig = originalPaths[e.number];
    if (orig != null) b..writeln('Original screenshot: [$orig]($orig)')..writeln();
  }
  return '${b.toString().trimRight()}\n';
}

/// The text sent with "Share images".
String captionsText(String albumName, List<ExportEntry> entries) {
  final b = StringBuffer()..writeln(albumName);
  for (final e in entries) {
    b.write('\n${e.number}. ${e.title}');
    if (e.caption.isNotEmpty) b.write(': ${e.caption}');
    for (final l in pinLines(e)) {
      b.write('\n   $l');
    }
  }
  return b.toString();
}
