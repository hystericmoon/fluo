import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import '../data/repository.dart';
import 'claude_pack.dart';
import 'long_image.dart';
import 'markdown.dart';
import 'model.dart';
import 'pdf_export.dart';
import 'render_shot.dart';
import 'share_service.dart';

/// Where exports are written and how they are shared. Passed down the tree
/// so tests can swap in a fake share sheet and a temp folder.
class ExportServices {
  const ExportServices({this.share = const SharePlusShareService(), required this.workDir, this.pdfFont});
  final ShareService share;

  /// Folder for the files being exported (cleared before each export).
  final Future<Directory> Function() workDir;

  /// For tests: skip loading the bundled font.
  final Future<pw.Font> Function()? pdfFont;
}

/// Builds exports from an album's kept screens.
class ExportService {
  ExportService(this.repo, this.services, {this._render});

  final FluoRepo repo;
  final ExportServices services;
  final Future<RenderedShot> Function(ExportEntry e)? _render;

  Future<RenderedShot> _renderEntry(ExportEntry e) =>
      (_render ?? (x) => renderShotPng(x.shot, x.annotations, x.pins))(e);

  /// The kept screens in flow order, numbered from 1. With [only], just those
  /// screens (still in flow order, renumbered from 1).
  List<ExportEntry> entries(String albumId, {Set<String>? only}) {
    final kept = [
      for (final s in repo.shotsIn(albumId, status: ShotStatus.kept))
        if (only == null || only.contains(s.id)) s,
    ];
    final pins = repo.pinsInAlbum(albumId);
    return [
      for (var i = 0; i < kept.length; i++)
        ExportEntry(
          number: i + 1,
          shot: kept[i],
          pins: pins[kept[i].id] ?? const [],
          annotations: repo.annotationsFor(kept[i].id),
        ),
    ];
  }

  ExportSummary summary(String albumId, {Set<String>? only}) {
    final es = entries(albumId, only: only);
    return ExportSummary(
      screens: es.length,
      pins: es.fold(0, (n, e) => n + e.pins.length),
      redactions: es.fold(0, (n, e) => n + e.redactionCount),
    );
  }

  /// Removes the files of earlier exports. They can hold copies of
  /// screenshots, so they are not kept around.
  Future<void> clearWorkDir() async {
    final dir = await services.workDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Writes the export to the work folder and returns its files.
  Future<ExportResult> build(
    String albumId,
    ExportOptions options, {
    void Function(int done, int total)? onProgress,
    Set<String>? only,
  }) async {
    final album = repo.getAlbum(albumId)!;
    final es = entries(albumId, only: only);
    if (es.isEmpty) throw StateError('Nothing to export: no kept screens');

    await clearWorkDir();
    final dir = await services.workDir();
    await dir.create(recursive: true);
    final base = slugify(album.name, fallback: 'album');

    Future<ExportFile> write(String name, List<int> bytes, String mime) async {
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(bytes, flush: true);
      return ExportFile(path: f.path, name: name, mime: mime);
    }

    switch (options.format) {
      case ExportFormat.claude:
        final zip = await buildClaudePack(
            album: album, entries: es, options: options, render: _renderEntry, onProgress: onProgress);
        return ExportResult(
          files: [await write('fluo-$base-review.zip', zip, 'application/zip')],
          screens: es.length,
          subject: '${album.name}: screenshot review',
        );
      case ExportFormat.pdf:
        final font = await (services.pdfFont ?? _bundledFont)();
        final pdf = await buildPdf(
            album: album, entries: es, options: options, render: _renderEntry, font: font, onProgress: onProgress);
        return ExportResult(
          files: [await write('fluo-$base-review.pdf', pdf, 'application/pdf')],
          screens: es.length,
          subject: '${album.name}: screenshot review',
        );
      case ExportFormat.long:
        final parts = await buildLongImages(entries: es, render: _renderEntry, onProgress: onProgress);
        return ExportResult(
          files: [
            for (var i = 0; i < parts.length; i++)
              await write(parts.length == 1 ? 'fluo-$base-long.png' : 'fluo-$base-long-${i + 1}.png', parts[i], 'image/png'),
          ],
          screens: es.length,
          subject: album.name,
        );
      case ExportFormat.share:
        final files = <ExportFile>[];
        var done = 0;
        for (final e in es) {
          final r = await _renderEntry(e);
          files.add(await write('${e.fileStem}.png', r.png, 'image/png'));
          if (options.originalsActuallyIncluded) {
            final ext = p.extension(e.shot.originalPath).toLowerCase();
            final name = '${e.fileStem}-original${ext.isEmpty ? '.png' : ext}';
            files.add(await write(name, await File(e.shot.originalPath).readAsBytes(), _mimeFor(ext)));
          }
          onProgress?.call(++done, es.length);
        }
        return ExportResult(files: files, screens: es.length, text: captionsText(album.name, es), subject: album.name);
    }
  }

  Future<void> exportAndShare(
    String albumId,
    ExportOptions options, {
    void Function(int done, int total)? onProgress,
    Set<String>? only,
  }) async {
    final r = await build(albumId, options, onProgress: onProgress, only: only);
    await services.share.share(r);
  }

  static String _mimeFor(String ext) => switch (ext) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        _ => 'image/png',
      };

  static Future<pw.Font> _bundledFont() async => pw.Font.ttf(await rootBundle.load('assets/fonts/Lexend.ttf'));
}
