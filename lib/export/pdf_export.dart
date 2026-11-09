import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import 'claude_pack.dart' show RenderFn;
import 'markdown.dart';
import 'model.dart';

/// One page per screen: title, caption, the annotated image (redactions
/// baked in, so nothing hidden is in the file), and the pin notes. An optional
/// cover page carries the review brief.
///
/// [font] must cover the text you expect. The bundled Lexend covers Latin
/// scripts; other scripts would show as empty boxes.
Future<Uint8List> buildPdf({
  required Album album,
  required List<ExportEntry> entries,
  required ExportOptions options,
  required RenderFn render,
  required pw.Font font,
  void Function(int done, int total)? onProgress,
}) async {
  final doc = pw.Document(
    title: album.name,
    creator: 'Fluo',
    theme: pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font),
  );
  const margin = 36.0;
  const grey = PdfColor.fromInt(0xFF52525B);

  if (options.briefActuallyIncluded) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(album.name, style: const pw.TextStyle(fontSize: 22)),
        pw.SizedBox(height: 4),
        pw.Text('Screenshot review', style: const pw.TextStyle(fontSize: 12, color: grey)),
        pw.SizedBox(height: 20),
        pw.Text('Review brief', style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.Text(briefText(album.name, entries), style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
      ]),
    ));
  }

  var done = 0;
  for (final e in entries) {
    final r = await render(e);
    final image = pw.MemoryImage(r.png);
    final lines = pinLines(e);
    const maxLines = 10;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('${e.number}. ${e.title}', style: const pw.TextStyle(fontSize: 16)),
        if (e.caption.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(e.caption, style: const pw.TextStyle(fontSize: 11, color: grey)),
        ],
        pw.SizedBox(height: 10),
        pw.Expanded(child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))),
        if (lines.isNotEmpty) pw.SizedBox(height: 10),
        for (final l in lines.take(maxLines)) pw.Text(l, style: const pw.TextStyle(fontSize: 10)),
        if (lines.length > maxLines)
          pw.Text('and ${lines.length - maxLines} more', style: const pw.TextStyle(fontSize: 10, color: grey)),
        if (e.redactionCount > 0) ...[
          pw.SizedBox(height: 6),
          pw.Text('Some content was hidden on this screen before sharing.',
              style: const pw.TextStyle(fontSize: 9, color: grey)),
        ],
      ]),
    ));
    onProgress?.call(++done, entries.length);
  }
  return doc.save();
}
