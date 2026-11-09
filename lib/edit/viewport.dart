import 'dart:math' as math;
import 'dart:ui';

import '../data/models.dart';

/// Maps between normalised image coordinates (0..1 of the original, which is
/// how marks are stored) and a box on screen or in an export. If a crop is
/// set, only that part of the image is shown, fitted into the box.
class EditViewport {
  EditViewport({required this.box, required this.imageSize, this.crop});

  final Size box;

  /// Pixel size of the image (any resolution: only the aspect matters).
  final Size imageSize;
  final CropRect? crop;

  /// The visible part of the image, normalised.
  Rect get region =>
      crop == null ? const Rect.fromLTRB(0, 0, 1, 1) : Rect.fromLTRB(crop!.left, crop!.top, crop!.right, crop!.bottom);

  double get regionAspect =>
      (region.width * imageSize.width) / (region.height * imageSize.height);

  /// Where the region is drawn inside [box], centred and letterboxed.
  Rect get display {
    final boxAspect = box.width / box.height;
    final double w, h;
    if (regionAspect >= boxAspect) {
      w = box.width;
      h = w / regionAspect;
    } else {
      h = box.height;
      w = h * regionAspect;
    }
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset toWidget(Offset n) {
    final d = display;
    return Offset(
      d.left + (n.dx - region.left) / region.width * d.width,
      d.top + (n.dy - region.top) / region.height * d.height,
    );
  }

  Offset toNorm(Offset w) {
    final d = display;
    return Offset(
      region.left + (w.dx - d.left) / d.width * region.width,
      region.top + (w.dy - d.top) / d.height * region.height,
    );
  }

  /// Keeps a normalised point inside the visible region.
  Offset clampToRegion(Offset n) => Offset(
        n.dx.clamp(region.left, region.right).toDouble(),
        n.dy.clamp(region.top, region.bottom).toDouble(),
      );

  /// Screen pixels per full image width. Marks are sized as a fraction of the
  /// image width so they look the same on screen and in an export.
  double get pxPerImageWidth => display.width / region.width;

  /// Source rectangle in image pixels for drawing the region.
  Rect get sourceRect => Rect.fromLTWH(
        region.left * imageSize.width,
        region.top * imageSize.height,
        region.width * imageSize.width,
        region.height * imageSize.height,
      );

  static double distance(Offset a, Offset b) => (a - b).distance;

  /// Size of a pin on screen: a fraction of the image width, never below
  /// [minPx] so it can be seen and touched.
  double pinDiameter({double minPx = 0}) => math.max(0.045 * pxPerImageWidth, minPx);

  double get strokePx => math.max(0.007 * pxPerImageWidth, 2);
}
