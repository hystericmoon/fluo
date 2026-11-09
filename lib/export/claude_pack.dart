import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../data/models.dart';
import 'markdown.dart';
import 'model.dart';
import 'render_shot.dart';

typedef RenderFn = Future<RenderedShot> Function(ExportEntry entry);

/// A ZIP with `review.md` and `images/` (annotated, redactions baked in).
/// Originals go in `originals/` only if asked for.
Future<Uint8List> buildClaudePack({
  required Album album,
  required List<ExportEntry> entries,
  required ExportOptions options,
  required RenderFn render,
  void Function(int done, int total)? onProgress,
}) async {
  final archive = Archive();
  final images = <int, String>{};
  final originals = <int, String>{};
  for (final e in entries) {
    images[e.number] = 'images/${e.fileStem}.png';
    if (options.originalsActuallyIncluded) {
      final ext = p.extension(e.shot.originalPath).toLowerCase();
      originals[e.number] = 'originals/${e.fileStem}${ext.isEmpty ? '.png' : ext}';
    }
  }

  final md = buildMarkdown(
    albumName: album.name,
    entries: entries,
    imagePaths: images,
    originalPaths: originals,
    includeBrief: options.briefActuallyIncluded,
  );
  final mdBytes = Uint8List.fromList(utf8.encode(md));
  archive.addFile(ArchiveFile('review.md', mdBytes.length, mdBytes));

  var done = 0;
  for (final e in entries) {
    final r = await render(e);
    archive.addFile(ArchiveFile(images[e.number]!, r.png.length, r.png));
    final orig = originals[e.number];
    if (orig != null) {
      final bytes = await File(e.shot.originalPath).readAsBytes();
      archive.addFile(ArchiveFile(orig, bytes.length, bytes));
    }
    onProgress?.call(++done, entries.length);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
