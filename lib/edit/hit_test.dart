import 'dart:math' as math;
import 'dart:ui';

import '../data/models.dart';
import 'geometry.dart';
import 'render.dart';
import 'viewport.dart';

/// What a touch at [local] (widget coordinates) lands on: the id of a pin or
/// annotation, or null. Pins win over shapes, later marks over earlier ones.
/// Thin things get a [slop] of forgiveness so a finger can hit them; boxes
/// are hit on their outline only, so they do not swallow taps meant for what
/// is inside them.
String? hitTest(
  EditViewport vp,
  Offset local,
  List<Annotation> annotations,
  List<Pin> pins, {
  double pinMinPx = 26,
  double slop = 14,
}) {
  final pinR = math.max(vp.pinDiameter(minPx: pinMinPx) / 2, 22.0);
  for (final p in pins.reversed) {
    if ((local - vp.toWidget(Offset(p.x, p.y))).distance <= pinR) return p.id;
  }
  for (final a in annotations.reversed) {
    switch (a.kind) {
      case AnnotationKind.redact:
        final r = rectOf(a);
        if (r != null && Rect.fromPoints(vp.toWidget(r.topLeft), vp.toWidget(r.bottomRight)).contains(local)) {
          return a.id;
        }
      case AnnotationKind.box:
        final r = rectOf(a);
        if (r != null &&
            distToRectBorder(local, Rect.fromPoints(vp.toWidget(r.topLeft), vp.toWidget(r.bottomRight))) <= slop) {
          return a.id;
        }
      case AnnotationKind.arrow:
        final ar = arrowOf(a);
        if (ar != null && distToSegment(local, vp.toWidget(ar.$1), vp.toWidget(ar.$2)) <= slop) return a.id;
      case AnnotationKind.pen:
        final pts = [for (final p in pointsOf(a)) vp.toWidget(p)];
        if (pts.isNotEmpty && distToPolyline(local, pts) <= slop) return a.id;
    }
  }
  return null;
}
