import 'dart:typed_data';
import 'dart:ui' as ui;

import '../data/models.dart';
import '../edit/image_loader.dart';
import '../edit/render.dart';
import '../edit/viewport.dart';

class RenderedShot {
  const RenderedShot(this.png, this.width, this.height);
  final Uint8List png;
  final int width;
  final int height;
}

typedef ImageLoader = Future<ui.Image> Function(String path, {int maxWidth});

/// Renders one screenshot with its crop, marks, pins and redactions baked
/// into the pixels. Nothing of what was redacted survives in the output.
/// Same painter as the editor canvas, so the export matches what was seen.
Future<RenderedShot> renderShotPng(
  Shot shot,
  List<Annotation> annotations,
  List<Pin> pins, {
  int maxWidth = 1600,
  ImageLoader load = loadShotImage,
}) async {
  // Decode at (up to) full size; the output is scaled down afterwards if wide.
  final img = await load(shot.originalPath, maxWidth: 4096);
  try {
    final src = ui.Size(img.width.toDouble(), img.height.toDouble());
    final region = EditViewport(box: const ui.Size(1, 1), imageSize: src, crop: shot.crop).region;
    final regionW = region.width * src.width;
    final regionH = region.height * src.height;
    final scale = regionW > maxWidth ? maxWidth / regionW : 1.0;
    final w = (regionW * scale).round().clamp(1, 1 << 14);
    final h = (regionH * scale).round().clamp(1, 1 << 14);
    final vp = EditViewport(box: ui.Size(w.toDouble(), h.toDouble()), imageSize: src, crop: shot.crop);

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    paintEdit(canvas, vp, img, annotations: annotations, pins: pins, pinMinPx: 28);
    final picture = rec.endRecording();
    final out = await picture.toImage(w, h);
    picture.dispose();
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      return RenderedShot(data!.buffer.asUint8List(), w, h);
    } finally {
      out.dispose();
    }
  } finally {
    img.dispose();
  }
}
