import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/tokens.dart';
import 'claude_pack.dart' show RenderFn;
import 'model.dart';

/// Layout constants for the stitched image.
class LongLayout {
  const LongLayout({this.contentWidth = 600, this.pad = 24, this.gap = 28, this.header = 56, this.maxHeight = 7000});
  final double contentWidth;
  final double pad;
  final double gap;
  final double header;

  /// Phones and GPUs cannot make arbitrarily tall images, so a long album is
  /// cut into parts no taller than this.
  final double maxHeight;

  double get width => contentWidth + pad * 2;

  /// Height of one screen's block for a picture of [w] by [h].
  double blockHeight(double w, double h) => header + h * contentWidth / w + gap;
}

/// Groups screens (given as picture sizes) into parts that each fit under
/// [LongLayout.maxHeight]. A single very tall screen still gets its own part.
List<List<int>> planLongImage(List<ui.Size> sizes, LongLayout layout) {
  final parts = <List<int>>[];
  var cur = <int>[];
  var h = layout.pad;
  for (var i = 0; i < sizes.length; i++) {
    final block = layout.blockHeight(sizes[i].width, sizes[i].height);
    if (cur.isNotEmpty && h + block + layout.pad > layout.maxHeight) {
      parts.add(cur);
      cur = <int>[];
      h = layout.pad;
    }
    cur.add(i);
    h += block;
  }
  if (cur.isNotEmpty) parts.add(cur);
  return parts;
}

/// Stitches the screens, top to bottom in flow order, each with its number
/// and name above it, on the app's dark background. Returns one PNG, or
/// several if the album is too long for one.
Future<List<Uint8List>> buildLongImages({
  required List<ExportEntry> entries,
  required RenderFn render,
  LongLayout layout = const LongLayout(),
  void Function(int done, int total)? onProgress,
}) async {
  final images = <ui.Image>[];
  final sizes = <ui.Size>[];
  try {
    for (final e in entries) {
      final r = await render(e);
      final codec = await ui.instantiateImageCodec(r.png);
      final frame = await codec.getNextFrame();
      codec.dispose();
      images.add(frame.image);
      sizes.add(ui.Size(r.width.toDouble(), r.height.toDouble()));
      onProgress?.call(images.length, entries.length);
    }

    final parts = planLongImage(sizes, layout);
    final out = <Uint8List>[];
    for (final part in parts) {
      var height = layout.pad;
      for (final i in part) {
        height += layout.blockHeight(sizes[i].width, sizes[i].height);
      }
      height += layout.pad - layout.gap; // the last block's gap is the bottom margin
      final w = layout.width.round(), h = height.ceil();

      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = FluoColors.bg);
      var y = layout.pad;
      for (final i in part) {
        final e = entries[i];
        final tp = TextPainter(
          text: TextSpan(children: [
            TextSpan(text: '${e.number}  ', style: FluoFonts.lexend(20).copyWith(color: FluoColors.lime)),
            TextSpan(text: e.title, style: fs(18, w: FontWeight.w600)),
          ]),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: layout.contentWidth);
        tp.paint(c, Offset(layout.pad, y + (layout.header - tp.height) / 2));
        final dh = sizes[i].height * layout.contentWidth / sizes[i].width;
        final dst = Rect.fromLTWH(layout.pad, y + layout.header, layout.contentWidth, dh);
        c.drawImageRect(
          images[i],
          Rect.fromLTWH(0, 0, images[i].width.toDouble(), images[i].height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
        y += layout.blockHeight(sizes[i].width, sizes[i].height);
      }
      final pic = rec.endRecording();
      final img = await pic.toImage(w, h);
      pic.dispose();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      out.add(data!.buffer.asUint8List());
    }
    return out;
  } finally {
    for (final i in images) {
      i.dispose();
    }
  }
}
