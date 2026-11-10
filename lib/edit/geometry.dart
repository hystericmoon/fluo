import 'dart:math' as math;
import 'dart:ui';

/// Distance from [p] to the segment a-b.
double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double distToPolyline(Offset p, List<Offset> pts) {
  if (pts.isEmpty) return double.infinity;
  if (pts.length == 1) return (p - pts.first).distance;
  var best = double.infinity;
  for (var i = 0; i < pts.length - 1; i++) {
    best = math.min(best, distToSegment(p, pts[i], pts[i + 1]));
  }
  return best;
}

/// Distance from [p] to the outline of [r] (0 on the edge, not inside).
double distToRectBorder(Offset p, Rect r) {
  final inside = r.contains(p);
  final dx = math.min((p.dx - r.left).abs(), (p.dx - r.right).abs());
  final dy = math.min((p.dy - r.top).abs(), (p.dy - r.bottom).abs());
  if (inside) return math.min(dx, dy);
  final cx = p.dx.clamp(r.left, r.right).toDouble();
  final cy = p.dy.clamp(r.top, r.bottom).toDouble();
  return (p - Offset(cx, cy)).distance;
}

/// Thins a freehand stroke: drops points closer than [minStep] to the last
/// kept one, then runs Ramer-Douglas-Peucker with [epsilon]. Keeps the first
/// and last point. Works in normalised coordinates.
List<Offset> simplifyStroke(List<Offset> pts, {double minStep = 0.0015, double epsilon = 0.0012, int maxPoints = 400}) {
  if (pts.length <= 2) return List.of(pts);
  final thinned = <Offset>[pts.first];
  for (final p in pts.skip(1)) {
    if ((p - thinned.last).distance >= minStep) thinned.add(p);
  }
  if (thinned.last != pts.last) thinned.add(pts.last);
  var out = _rdp(thinned, epsilon);
  var eps = epsilon;
  while (out.length > maxPoints) {
    eps *= 1.5;
    out = _rdp(out, eps);
  }
  return out;
}

List<Offset> _rdp(List<Offset> pts, double eps) {
  if (pts.length < 3) return pts;
  var maxD = 0.0;
  var idx = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = distToSegment(pts[i], pts.first, pts.last);
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD <= eps) return [pts.first, pts.last];
  final left = _rdp(pts.sublist(0, idx + 1), eps);
  final right = _rdp(pts.sublist(idx), eps);
  return [...left.sublist(0, left.length - 1), ...right];
}

/// A rectangle from two corners in any order.
Rect rectFrom(Offset a, Offset b) => Rect.fromPoints(a, b);
