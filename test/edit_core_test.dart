import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/edit/geometry.dart';
import 'package:fluo/edit/render.dart';
import 'package:fluo/edit/viewport.dart';

Annotation ann(AnnotationKind k, Map<String, Object?> data, {String id = 'a', int z = 0}) =>
    Annotation(id: id, shotId: 's', kind: k, data: data, z: z);

Pin pin(double x, double y, {Severity sev = Severity.bug, int n = 1, String id = 'p'}) =>
    Pin(id: id, shotId: 's', number: n, severity: sev, x: x, y: y, note: '');

/// A solid-colour image of the given size.
Future<ui.Image> solid(int w, int h, Color c) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = c);
  return rec.endRecording().toImage(w, h);
}

/// Left half [l], right half [r].
Future<ui.Image> halves(int w, int h, Color l, Color r) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w / 2, h.toDouble()), Paint()..color = l);
  c.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()), Paint()..color = r);
  return rec.endRecording().toImage(w, h);
}

class Raster {
  Raster(this.w, this.bytes);
  final int w;
  final ByteData bytes;
  Color at(int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  }
}

Future<Raster> render(
  ui.Image img, {
  required Size box,
  CropRect? crop,
  List<Annotation> anns = const [],
  List<Pin> pins = const [],
  String? selected,
  double pinMinPx = 0,
}) async {
  final vp = EditViewport(box: box, imageSize: Size(img.width.toDouble(), img.height.toDouble()), crop: crop);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Offset.zero & box, Paint()..color = const Color(0xFF00FF00)); // letterbox colour
  paintEdit(canvas, vp, img, annotations: anns, pins: pins, selectedId: selected, pinMinPx: pinMinPx);
  final out = await rec.endRecording().toImage(box.width.round(), box.height.round());
  return Raster(box.width.round(), (await out.toByteData())!);
}

bool isBlack(Color c) => c.r < .02 && c.g < .02 && c.b < .02 && c.a > .98;
bool near(Color a, Color b, [double tol = .06]) =>
    (a.r - b.r).abs() < tol && (a.g - b.g).abs() < tol && (a.b - b.b).abs() < tol;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditViewport', () {
    test('same aspect fills the box and maps corners', () {
      final v = EditViewport(box: const Size(100, 200), imageSize: const Size(1000, 2000));
      expect(v.display, const Rect.fromLTWH(0, 0, 100, 200));
      expect(v.toWidget(const Offset(0, 0)), Offset.zero);
      expect(v.toWidget(const Offset(1, 1)), const Offset(100, 200));
      expect(v.toNorm(const Offset(50, 100)), const Offset(0.5, 0.5));
    });

    test('a tall image in a wide box is letterboxed left and right', () {
      final v = EditViewport(box: const Size(400, 200), imageSize: const Size(100, 200));
      expect(v.display, const Rect.fromLTWH(150, 0, 100, 200));
      expect(v.toWidget(const Offset(0, 0)), const Offset(150, 0));
    });

    test('a wide image in a tall box is letterboxed top and bottom', () {
      final v = EditViewport(box: const Size(200, 400), imageSize: const Size(200, 100));
      expect(v.display, const Rect.fromLTWH(0, 150, 200, 100));
    });

    test('a crop shows only that region and maps through it', () {
      final v = EditViewport(
          box: const Size(100, 100), imageSize: const Size(200, 200), crop: const CropRect(.5, .5, 1, 1));
      expect(v.display, const Rect.fromLTWH(0, 0, 100, 100));
      expect(v.toWidget(const Offset(.5, .5)), Offset.zero);
      expect(v.toWidget(const Offset(1, 1)), const Offset(100, 100));
      expect(v.toWidget(const Offset(.75, .75)), const Offset(50, 50));
      expect(v.sourceRect, const Rect.fromLTWH(100, 100, 100, 100));
    });

    test('toNorm undoes toWidget, with and without a crop', () {
      for (final crop in [null, const CropRect(.1, .2, .8, .9)]) {
        final v = EditViewport(box: const Size(390, 400), imageSize: const Size(1080, 2400), crop: crop);
        for (final p in [const Offset(.3, .4), const Offset(.55, .6)]) {
          final back = v.toNorm(v.toWidget(p));
          expect((back - p).distance, lessThan(1e-9));
        }
      }
    });

    test('clampToRegion keeps points inside the visible region', () {
      final v = EditViewport(
          box: const Size(100, 100), imageSize: const Size(100, 100), crop: const CropRect(.2, .2, .6, .6));
      expect(v.clampToRegion(const Offset(0, 1)), const Offset(.2, .6));
    });

    test('pins and strokes scale with the image but never get unusably small', () {
      final small = EditViewport(box: const Size(100, 200), imageSize: const Size(1000, 2000));
      final big = EditViewport(box: const Size(1000, 2000), imageSize: const Size(1000, 2000));
      expect(small.pinDiameter(minPx: 26), 26);
      expect(big.pinDiameter(), closeTo(45, 1e-9));
      expect(small.strokePx, 2, reason: 'floor of 2px');
      expect(big.strokePx, closeTo(7, 1e-9));
    });
  });

  group('geometry', () {
    test('distToSegment: on, beside, past the end, degenerate', () {
      expect(distToSegment(const Offset(5, 0), const Offset(0, 0), const Offset(10, 0)), 0);
      expect(distToSegment(const Offset(5, 3), const Offset(0, 0), const Offset(10, 0)), 3);
      expect(distToSegment(const Offset(14, 3), const Offset(0, 0), const Offset(10, 0)), 5);
      expect(distToSegment(const Offset(3, 4), const Offset(0, 0), const Offset(0, 0)), 5);
    });

    test('distToPolyline picks the nearest segment', () {
      final pts = [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)];
      expect(distToPolyline(const Offset(12, 5), pts), 2);
      expect(distToPolyline(const Offset(5, 1), pts), 1);
      expect(distToPolyline(const Offset(0, 0), const []), double.infinity);
    });

    test('distToRectBorder: edge is 0, inside measures to the nearest edge, outside to the rect', () {
      const r = Rect.fromLTRB(0, 0, 100, 50);
      expect(distToRectBorder(const Offset(50, 0), r), 0);
      expect(distToRectBorder(const Offset(50, 10), r), 10);
      expect(distToRectBorder(const Offset(110, 25), r), 10);
      expect(distToRectBorder(const Offset(103, 54), r), 5);
    });

    test('simplifyStroke thins a straight line to its ends and keeps a corner', () {
      final line = [for (var i = 0; i <= 100; i++) Offset(i / 100, 0.5)];
      expect(simplifyStroke(line), [line.first, line.last]);
      final corner = [
        for (var i = 0; i <= 50; i++) Offset(i / 100, 0.5),
        for (var i = 1; i <= 50; i++) Offset(0.5, 0.5 + i / 100),
      ];
      final out = simplifyStroke(corner);
      expect(out.first, corner.first);
      expect(out.last, corner.last);
      expect(out, contains(const Offset(0.5, 0.5)));
      expect(out.length, 3);
    });

    test('simplifyStroke handles tiny input and caps long scribbles', () {
      expect(simplifyStroke(const []), isEmpty);
      expect(simplifyStroke(const [Offset(.1, .1)]), const [Offset(.1, .1)]);
      final zig = [for (var i = 0; i < 4000; i++) Offset(i / 4000, i.isEven ? .3 : .31)];
      expect(simplifyStroke(zig, minStep: 0, epsilon: 0.0001).length, lessThanOrEqualTo(400));
    });
  });

  group('paintEdit pixels', () {
    const box = Size(100, 200);

    test('no marks: the image shows as it is', () async {
      final img = await solid(100, 200, const Color(0xFFFFFFFF));
      final r = await render(img, box: box);
      expect(near(r.at(50, 100), const Color(0xFFFFFFFF)), isTrue);
    });

    test('a redaction is solid black over the image and over other marks', () async {
      final img = await solid(100, 200, const Color(0xFFFFFFFF));
      final r = await render(img, box: box, anns: [
        ann(AnnotationKind.pen, {'points': [[0.1, 0.5], [0.9, 0.5]]}, id: 'pen', z: 0),
        ann(AnnotationKind.redact, {'rect': [0.2, 0.4, 0.8, 0.6]}, id: 'red', z: 1),
      ]);
      for (final (x, y) in [(25, 85), (50, 100), (75, 115), (21, 81), (79, 119)]) {
        expect(isBlack(r.at(x, y)), isTrue, reason: 'inside the redaction at $x,$y');
      }
      expect(near(r.at(10, 100), const Color(0xFFFFFFFF)), isFalse, reason: 'the pen shows outside it');
      expect(near(r.at(50, 60), const Color(0xFFFFFFFF)), isTrue, reason: 'untouched area');
    });

    test('a redaction drawn before a pen still ends up on top of it', () async {
      final img = await solid(100, 200, const Color(0xFFFFFFFF));
      final r = await render(img, box: box, anns: [
        ann(AnnotationKind.redact, {'rect': [0.2, 0.4, 0.8, 0.6]}, id: 'red', z: 0),
        ann(AnnotationKind.pen, {'points': [[0.1, 0.5], [0.9, 0.5]]}, id: 'pen', z: 1),
      ]);
      expect(isBlack(r.at(50, 100)), isTrue, reason: 'the pen stroke cannot show through');
    });

    test('a redaction hides detail completely, no partial transparency at any pixel', () async {
      // A fine checkerboard would show through any translucent or soft edge.
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 100; x++) {
          if ((x + y).isEven) c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), Paint()..color = const Color(0xFFFF0000));
        }
      }
      final img = await rec.endRecording().toImage(100, 200);
      final r = await render(img, box: box, anns: [
        ann(AnnotationKind.redact, {'rect': [0.25, 0.25, 0.75, 0.75]}),
      ]);
      for (var y = 51; y < 149; y++) {
        for (var x = 26; x < 74; x++) {
          expect(isBlack(r.at(x, y)), isTrue, reason: 'pixel $x,$y');
        }
      }
    });

    test('a crop shows only the cropped part, scaled to fill', () async {
      final img = await halves(100, 200, const Color(0xFFFF0000), const Color(0xFF0000FF));
      final r = await render(img, box: const Size(50, 200), crop: const CropRect(.5, 0, 1, 1));
      expect(near(r.at(5, 100), const Color(0xFF0000FF)), isTrue);
      expect(near(r.at(45, 100), const Color(0xFF0000FF)), isTrue);
    });

    test('marks are placed relative to the original, so they follow the crop', () async {
      final img = await solid(100, 100, const Color(0xFFFFFFFF));
      // Crop to the right half; a 50x100 box has the same aspect, so no bars.
      const box = Size(50, 100);
      const crop = CropRect(.5, 0, 1, 1);
      // A redaction over the left quarter of the original is outside the crop.
      final r = await render(img, box: box, crop: crop, anns: [
        ann(AnnotationKind.redact, {'rect': [0.0, 0.0, 0.25, 1.0]}),
      ]);
      expect(near(r.at(10, 50), const Color(0xFFFFFFFF)), isTrue);
      expect(near(r.at(40, 50), const Color(0xFFFFFFFF)), isTrue);
      // One over x .5 to .75 of the original is the left half of the crop.
      final r2 = await render(img, box: box, crop: crop, anns: [
        ann(AnnotationKind.redact, {'rect': [0.5, 0.0, 0.75, 1.0]}),
      ]);
      expect(isBlack(r2.at(10, 50)), isTrue);
      expect(near(r2.at(40, 50), const Color(0xFFFFFFFF)), isTrue);
    });

    test('marks outside the crop are clipped, and the letterbox stays untouched', () async {
      final img = await solid(100, 100, const Color(0xFFFFFFFF));
      final r = await render(img,
          box: const Size(200, 100), // image is square: bars left and right
          anns: [ann(AnnotationKind.redact, {'rect': [0.0, 0.0, 1.0, 1.0]})]);
      expect(near(r.at(10, 50), const Color(0xFF00FF00)), isTrue, reason: 'letterbox not painted over');
      expect(isBlack(r.at(100, 50)), isTrue);
    });

    test('a box draws its outline in the mark colour and leaves the inside alone', () async {
      final img = await solid(200, 200, const Color(0xFFFFFFFF));
      final r = await render(img, box: const Size(200, 200), anns: [
        ann(AnnotationKind.box, {'rect': [0.25, 0.25, 0.75, 0.75]}),
      ]);
      expect(near(r.at(100, 50), markColor, .12), isTrue, reason: 'top edge');
      expect(near(r.at(100, 100), const Color(0xFFFFFFFF)), isTrue, reason: 'inside untouched');
    });

    test('an arrow reaches from tail to tip', () async {
      final img = await solid(200, 200, const Color(0xFFFFFFFF));
      final r = await render(img, box: const Size(200, 200), anns: [
        ann(AnnotationKind.arrow, {'from': [0.1, 0.5], 'to': [0.9, 0.5]}),
      ]);
      expect(near(r.at(40, 100), markColor, .15), isTrue);
      expect(near(r.at(150, 100), markColor, .15), isTrue);
      expect(near(r.at(100, 20), const Color(0xFFFFFFFF)), isTrue);
    });

    test('pins draw their severity colour at their position, in three different shapes', () async {
      final img = await solid(400, 400, const Color(0xFFFFFFFF));
      Future<Raster> one(Severity s) =>
          render(img, box: const Size(400, 400), pins: [pin(.5, .5, sev: s)], pinMinPx: 40);
      final bug = await one(Severity.bug), ux = await one(Severity.ux), a11y = await one(Severity.a11y);
      bool fill(Raster r, int dx, int dy, Severity s) => near(r.at(200 + dx, 200 + dy), s.color, .1);

      // Just above the letter (tests draw text as solid blocks): every pin is
      // filled in its own colour.
      expect(fill(bug, 0, -14, Severity.bug), isTrue);
      expect(fill(ux, 0, -14, Severity.ux), isTrue);
      expect(fill(a11y, 0, -14, Severity.a11y), isTrue);

      // Diagonal point 16px out each way (22.6 from the centre): inside a
      // rounded square, outside a circle, outside a diamond.
      expect(fill(ux, -16, -16, Severity.ux), isTrue, reason: 'UX is a rounded square');
      expect(fill(bug, -16, -16, Severity.bug), isFalse, reason: 'Bug is a circle');
      expect(fill(a11y, -16, -16, Severity.a11y), isFalse, reason: 'A11y is a diamond');

      // 22px along an axis: inside the diamond's point, outside the circle.
      expect(fill(a11y, 22, 0, Severity.a11y), isTrue);
      expect(fill(bug, 22, 0, Severity.bug), isFalse);
    });

    test('selection adds a ring only for the selected mark', () async {
      final img = await solid(200, 200, const Color(0xFFFFFFFF));
      final a = [ann(AnnotationKind.box, {'rect': [0.3, 0.3, 0.7, 0.7]}, id: 'b')];
      final plain = await render(img, box: const Size(200, 200), anns: a);
      final sel = await render(img, box: const Size(200, 200), anns: a, selected: 'b');
      final other = await render(img, box: const Size(200, 200), anns: a, selected: 'nope');
      var diffSel = 0, diffOther = 0;
      for (var y = 0; y < 200; y += 2) {
        for (var x = 0; x < 200; x += 2) {
          if (plain.at(x, y) != sel.at(x, y)) diffSel++;
          if (plain.at(x, y) != other.at(x, y)) diffOther++;
        }
      }
      expect(diffSel, greaterThan(20));
      expect(diffOther, 0);
    });

    test('annotation helpers read stored data and tolerate bad data', () {
      expect(pointsOf(ann(AnnotationKind.pen, {'points': [[0.1, 0.2], [0.3, 0.4]]})), const [Offset(.1, .2), Offset(.3, .4)]);
      expect(pointsOf(ann(AnnotationKind.pen, {})), isEmpty);
      expect(rectOf(ann(AnnotationKind.box, {'rect': [0, 0, 1]})), isNull);
      expect(arrowOf(ann(AnnotationKind.arrow, {'from': [0, 0]})), isNull);
    });
  });
}
