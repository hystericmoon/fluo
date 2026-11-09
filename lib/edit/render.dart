import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../data/models.dart';
import '../theme/tokens.dart';
import 'viewport.dart';

const markColor = FluoColors.bug; // pen, arrow and box
const _redactColor = Color(0xFF000000);
const _halo = Color(0xFF18181B);
const _haloLight = Color(0xFFFFFFFF);

List<Offset> pointsOf(Annotation a) => [
      for (final p in (a.data['points'] as List? ?? const []))
        Offset((p as List)[0].toDouble(), p[1].toDouble()),
    ];

Rect? rectOf(Annotation a) {
  final r = a.data['rect'] as List?;
  if (r == null || r.length != 4) return null;
  return Rect.fromLTRB(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble());
}

(Offset, Offset)? arrowOf(Annotation a) {
  final f = a.data['from'] as List?, t = a.data['to'] as List?;
  if (f == null || t == null) return null;
  return (Offset(f[0].toDouble(), f[1].toDouble()), Offset(t[0].toDouble(), t[1].toDouble()));
}

/// Draws the edited screenshot: the (cropped) image, then every mark.
/// Used for the editor canvas and for exports, so what you see is what you
/// send. Redactions are plain opaque black, drawn last of the shapes so
/// nothing shows through.
void paintEdit(
  Canvas canvas,
  EditViewport vp,
  ui.Image image, {
  required List<Annotation> annotations,
  required List<Pin> pins,
  String? selectedId,
  double pinMinPx = 0,
}) {
  final d = vp.display;
  canvas.save();
  canvas.clipRect(d);
  canvas.drawImageRect(image, vp.sourceRect, d, Paint()..filterQuality = FilterQuality.medium);

  final stroke = vp.strokePx;
  final line = Paint()
    ..color = markColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // Shapes first, redactions on top of them (still under pins).
  for (final a in annotations.where((a) => a.kind != AnnotationKind.redact)) {
    switch (a.kind) {
      case AnnotationKind.pen:
        final pts = [for (final p in pointsOf(a)) vp.toWidget(p)];
        if (pts.length == 1) {
          canvas.drawCircle(pts.first, stroke / 2, line..style = PaintingStyle.fill);
          line.style = PaintingStyle.stroke;
        } else if (pts.length > 1) {
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (final p in pts.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, line);
        }
      case AnnotationKind.arrow:
        final ar = arrowOf(a);
        if (ar != null) _arrow(canvas, vp.toWidget(ar.$1), vp.toWidget(ar.$2), line, stroke);
      case AnnotationKind.box:
        final r = rectOf(a);
        if (r != null) {
          final tl = vp.toWidget(r.topLeft), br = vp.toWidget(r.bottomRight);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(tl, br), Radius.circular(stroke * 1.5)), line);
        }
      case AnnotationKind.redact:
        break;
    }
  }
  for (final a in annotations.where((a) => a.kind == AnnotationKind.redact)) {
    final r = rectOf(a);
    if (r == null) continue;
    final px = Rect.fromPoints(vp.toWidget(r.topLeft), vp.toWidget(r.bottomRight));
    // Opaque and square-cornered, grown by half a pixel so no edge pixel of
    // the hidden area survives anti-aliasing.
    canvas.drawRect(px.inflate(0.5), Paint()..color = _redactColor..isAntiAlias = false);
  }

  final dia = vp.pinDiameter(minPx: pinMinPx);
  for (final p in pins) {
    _pin(canvas, vp.toWidget(Offset(p.x, p.y)), dia, p);
  }
  canvas.restore();

  // Selection is drawn outside the clip so handles at the edge stay visible.
  if (selectedId != null) {
    final ring = Paint()
      ..color = FluoColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in pins.where((p) => p.id == selectedId)) {
      canvas.drawCircle(vp.toWidget(Offset(p.x, p.y)), dia / 2 + 7, ring);
    }
    for (final a in annotations.where((a) => a.id == selectedId)) {
      final b = _bounds(a, vp);
      if (b != null) _dashedRect(canvas, b.inflate(6), ring);
    }
  }
}

Rect? _bounds(Annotation a, EditViewport vp) {
  switch (a.kind) {
    case AnnotationKind.pen:
      final pts = [for (final p in pointsOf(a)) vp.toWidget(p)];
      if (pts.isEmpty) return null;
      return pts.map((p) => Rect.fromLTWH(p.dx, p.dy, 0, 0)).reduce((x, y) => x.expandToInclude(y));
    case AnnotationKind.arrow:
      final ar = arrowOf(a);
      return ar == null ? null : Rect.fromPoints(vp.toWidget(ar.$1), vp.toWidget(ar.$2));
    case AnnotationKind.box:
    case AnnotationKind.redact:
      final r = rectOf(a);
      return r == null ? null : Rect.fromPoints(vp.toWidget(r.topLeft), vp.toWidget(r.bottomRight));
  }
}

void _dashedRect(Canvas canvas, Rect r, Paint paint) {
  const dash = 6.0, gap = 4.0;
  void edge(Offset a, Offset b) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, len), paint);
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
}

void _arrow(Canvas canvas, Offset from, Offset to, Paint line, double stroke) {
  canvas.drawLine(from, to, line);
  final v = to - from;
  if (v.distance < 1) return;
  final ang = math.atan2(v.dy, v.dx);
  final head = math.max(stroke * 4, 12.0);
  for (final s in [-1, 1]) {
    final a = ang + math.pi - s * 0.5;
    canvas.drawLine(to, to + Offset(math.cos(a), math.sin(a)) * head, line);
  }
}

/// A pin: its shape and its letter say the severity, its number says which.
/// Bug is a circle, UX a rounded square, A11y a diamond; colour is a third cue.
void _pin(Canvas canvas, Offset c, double d, Pin p) {
  final r = d / 2;
  Path shape(double extra) => switch (p.severity) {
        Severity.bug => (Path()..addOval(Rect.fromCircle(center: c, radius: r + extra))),
        Severity.ux => (Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromCircle(center: c, radius: r + extra), Radius.circular((r + extra) * 0.35)))),
        Severity.a11y => (() {
            final k = (r + extra) * 1.25;
            return Path()
              ..moveTo(c.dx, c.dy - k)
              ..lineTo(c.dx + k, c.dy)
              ..lineTo(c.dx, c.dy + k)
              ..lineTo(c.dx - k, c.dy)
              ..close();
          })(),
      };
  // Halo: light then dark, so the pin reads on a white or a black screenshot.
  canvas.drawPath(shape(3.5), Paint()..color = _halo);
  canvas.drawPath(shape(1.5), Paint()..color = _haloLight);
  canvas.drawPath(shape(0), Paint()..color = p.severity.color);
  final tp = TextPainter(
    text: TextSpan(
      text: '${p.severity.letter}${p.number}',
      style: TextStyle(
        fontFamily: FluoFonts.body,
        fontSize: d * 0.42,
        fontWeight: FontWeight.w700,
        color: FluoColors.onLime,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
}

/// The editor canvas: paints [image] and marks through [paintEdit].
class EditPainter extends CustomPainter {
  EditPainter({
    required this.image,
    required this.viewport,
    required this.annotations,
    required this.pins,
    this.selectedId,
  });
  final ui.Image image;
  final EditViewport viewport;
  final List<Annotation> annotations;
  final List<Pin> pins;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) => paintEdit(
        canvas,
        viewport,
        image,
        annotations: annotations,
        pins: pins,
        selectedId: selectedId,
        pinMinPx: 26,
      );

  @override
  bool shouldRepaint(EditPainter old) => true;
}
