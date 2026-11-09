import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/edit/editor_state.dart';
import 'package:fluo/edit/hit_test.dart';
import 'package:fluo/edit/viewport.dart';
import 'package:path/path.dart' as p;

Annotation ann(String id, AnnotationKind k, Map<String, Object?> d) =>
    Annotation(id: id, shotId: 's', kind: k, data: d, z: 0);
Pin pn(String id, double x, double y) =>
    Pin(id: id, shotId: 's', number: 1, severity: Severity.bug, x: x, y: y, note: '');

void main() {
  late Directory tmp;
  late FluoRepo repo;
  late Shot shot;
  late EditorState st;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('fluo_editor_');
    repo = FluoRepo(FluoDb.openInMemory(), FileStore(Directory(p.join(tmp.path, 'app'))));
    final a = repo.createAlbum('A');
    final f = File(p.join(tmp.path, 'in.png'))..writeAsBytesSync(List.generate(64, (i) => i));
    shot = await repo.addShot(a.id, f);
    st = EditorState(repo, shot.id);
  });

  tearDown(() {
    st.dispose();
    repo.close();
    tmp.deleteSync(recursive: true);
  });

  group('adding marks', () {
    test('pin: stored, numbered, selected, takes the chosen severity', () {
      st.setNewPinSeverity(Severity.ux);
      final a = st.addPin(const Offset(.3, .4));
      final b = st.addPin(const Offset(.6, .7));
      expect((a.number, a.severity), (1, Severity.ux));
      expect(b.number, 2);
      expect(st.selectedId, b.id);
      expect(repo.pinsFor(shot.id).map((p) => (p.x, p.y)), [(.3, .4), (.6, .7)]);
    });

    test('pins outside the image are pulled back inside it', () {
      final p = st.addPin(const Offset(1.4, -.2));
      expect((p.x, p.y), (1.0, 0.0));
    });

    test('pen stroke is thinned and stored as normalised points', () {
      final a = st.addStroke([for (var i = 0; i <= 50; i++) Offset(.1 + i * .01, .5)])!;
      expect(a.kind, AnnotationKind.pen);
      final pts = a.data['points'] as List;
      expect(pts.length, 2, reason: 'a straight line needs two points');
      expect(pts.first, [.1, .5]);
    });

    test('a tap or a tiny drag stores nothing for pen, arrow, box and redact', () {
      expect(st.addStroke(const [Offset(.5, .5)]), isNull);
      expect(st.addStroke(const [Offset(.5, .5), Offset(.5004, .5)]), isNull);
      expect(st.addArrow(const Offset(.5, .5), const Offset(.505, .5)), isNull);
      expect(st.addRect(AnnotationKind.box, const Offset(.5, .5), const Offset(.505, .505)), isNull);
      expect(st.addRect(AnnotationKind.redact, const Offset(.5, .5), const Offset(.5, .9)), isNull,
          reason: 'zero width');
      expect(repo.annotationsFor(shot.id), isEmpty);
      expect(st.canUndo, isFalse);
    });

    test('arrow, box and redact are stored with their geometry; rect corners can be dragged any way', () {
      st.addArrow(const Offset(.1, .1), const Offset(.8, .2));
      st.addRect(AnnotationKind.box, const Offset(.7, .6), const Offset(.2, .3)); // bottom-right to top-left
      st.addRect(AnnotationKind.redact, const Offset(.1, .8), const Offset(.4, .9));
      final all = repo.annotationsFor(shot.id);
      expect(all.map((a) => a.kind), [AnnotationKind.arrow, AnnotationKind.box, AnnotationKind.redact]);
      expect(all[0].data, {'from': [.1, .1], 'to': [.8, .2]});
      expect(all[1].data['rect'], [.2, .3, .7, .6]);
    });
  });

  group('changing and removing', () {
    test('move a pin, change severity and note; numbers and ids stay', () {
      final p1 = st.addPin(const Offset(.2, .2));
      st.movePin(p1.id, const Offset(.9, .8));
      st.setNewPinSeverity(Severity.a11y); // applies to the selected pin
      st.setPinNote(p1.id, 'Low contrast');
      final r = repo.pinsFor(shot.id).single;
      expect((r.id, r.number, r.x, r.y, r.severity, r.note), (p1.id, 1, .9, .8, Severity.a11y, 'Low contrast'));
    });

    test('severity chosen with nothing selected only affects the next pin', () {
      final p1 = st.addPin(const Offset(.2, .2));
      st.select(null);
      st.setNewPinSeverity(Severity.ux);
      expect(repo.pinsFor(shot.id).single.severity, Severity.bug);
      expect(st.addPin(const Offset(.3, .3)).severity, Severity.ux);
      expect(p1.severity, Severity.bug);
    });

    test('nudge moves the selected pin and keeps it inside the image', () {
      final p1 = st.addPin(const Offset(.99, .5));
      st.nudgeSelected(.05, 0);
      expect(repo.pinsFor(shot.id).single.x, 1.0);
      st.select(null);
      st.nudgeSelected(.05, 0); // nothing selected: nothing happens
      expect(repo.pinsFor(shot.id).single.id, p1.id);
    });

    test('delete removes the selected pin (renumbering the rest) or annotation', () {
      final p1 = st.addPin(const Offset(.1, .1));
      st.addPin(const Offset(.2, .2));
      st.select(p1.id);
      st.deleteSelected();
      expect(repo.pinsFor(shot.id).map((p) => p.number), [1]);
      final box = st.addRect(AnnotationKind.box, const Offset(.1, .1), const Offset(.5, .5))!;
      expect(st.selectedId, box.id);
      st.deleteSelected();
      expect(repo.annotationsFor(shot.id), isEmpty);
      expect(st.selectedId, isNull);
      st.deleteSelected(); // nothing selected: harmless
    });

    test('undo removes marks in reverse order of adding and ignores what was deleted', () {
      final p1 = st.addPin(const Offset(.1, .1));
      final box = st.addRect(AnnotationKind.box, const Offset(.1, .1), const Offset(.5, .5))!;
      final arr = st.addArrow(const Offset(.1, .1), const Offset(.9, .9))!;
      st.select(box.id);
      st.deleteSelected();
      expect(st.canUndo, isTrue);
      st.undo(); // the arrow
      expect(repo.annotationsFor(shot.id), isEmpty);
      expect(arr.id, isNotEmpty);
      st.undo(); // the pin, since the box was deleted already
      expect(repo.pinsFor(shot.id), isEmpty);
      expect(p1.id, isNotEmpty);
      expect(st.canUndo, isFalse);
      st.undo(); // nothing left
    });

    test('caption is saved on the shot', () {
      st.setCaption('Cart: total changes after shipping');
      expect(repo.getShot(shot.id)!.caption, 'Cart: total changes after shipping');
    });
  });

  group('without dragging', () {
    test('a box, redaction or arrow can be added from a button, centred and selected', () {
      final box = st.addDefaultShape(AnnotationKind.box)!;
      final red = st.addDefaultShape(AnnotationKind.redact)!;
      final arrow = st.addDefaultShape(AnnotationKind.arrow)!;
      expect(st.addDefaultShape(AnnotationKind.pen), isNull, reason: 'a freehand line needs a finger');
      final r = (box.data['rect'] as List).cast<double>();
      expect((r[0] + r[2]) / 2, closeTo(.5, 1e-9));
      expect((r[1] + r[3]) / 2, closeTo(.5, 1e-9));
      expect(st.selectedId, arrow.id);
      expect(red.kind, AnnotationKind.redact);
      expect(st.canUndo, isTrue);
    });

    test('with a crop, the shape lands in the middle of what is visible', () {
      st.setTool(EditTool.crop);
      st.setCropDraft(const CropRect(.5, .5, 1, 1));
      st.applyCrop();
      final r = (st.addDefaultShape(AnnotationKind.redact)!.data['rect'] as List).cast<double>();
      expect((r[0] + r[2]) / 2, closeTo(.75, 1e-9));
      expect((r[1] + r[3]) / 2, closeTo(.75, 1e-9));
    });

    test('nudge moves a box, an arrow and a pen stroke, and stops at the image edge', () {
      final box = st.addRect(AnnotationKind.box, const Offset(.1, .1), const Offset(.3, .2))!;
      st.nudgeSelected(.1, .05);
      expect((repo.annotationsFor(shot.id).single.data['rect'] as List), [closeTo(.2, 1e-9), closeTo(.15, 1e-9), closeTo(.4, 1e-9), closeTo(.25, 1e-9)]);
      st.nudgeSelected(5, 0); // far too much: slides to the edge, keeps its size
      final r = (repo.annotationsFor(shot.id).single.data['rect'] as List).cast<double>();
      expect(r[2], closeTo(1, 1e-9));
      expect(r[2] - r[0], closeTo(.2, 1e-9));
      expect(box.id, isNotEmpty);

      final arrow = st.addArrow(const Offset(.2, .5), const Offset(.4, .5))!;
      st.nudgeSelected(0, .1);
      expect(((repo.annotationsFor(shot.id).firstWhere((a) => a.id == arrow.id).data['from']) as List)[1], closeTo(.6, 1e-9));

      final pen = st.addStroke([for (var i = 0; i <= 20; i++) Offset(.4 + i * .01, .4 + i * .01)])!;
      st.nudgeSelected(-1, -1);
      final pts = (repo.annotationsFor(shot.id).firstWhere((a) => a.id == pen.id).data['points'] as List);
      expect((pts.first as List)[0], closeTo(0, 1e-9));
      expect((pts.first as List)[1], closeTo(0, 1e-9));
    });

    test('resize grows and shrinks a box around its centre, within limits', () {
      st.addRect(AnnotationKind.redact, const Offset(.4, .4), const Offset(.6, .5));
      st.resizeSelected(.1, 0);
      var r = (repo.annotationsFor(shot.id).single.data['rect'] as List).cast<double>();
      expect(r[2] - r[0], closeTo(.3, 1e-9));
      expect((r[0] + r[2]) / 2, closeTo(.5, 1e-9));
      st.resizeSelected(0, -.5); // cannot vanish
      r = (repo.annotationsFor(shot.id).single.data['rect'] as List).cast<double>();
      expect(r[3] - r[1], closeTo(.04, 1e-9));
      st.resizeSelected(5, 5); // cannot leave the image
      r = (repo.annotationsFor(shot.id).single.data['rect'] as List).cast<double>();
      expect([r[0], r[1], r[2], r[3]], [0.0, 0.0, 1.0, 1.0]);
    });

    test('resize lengthens an arrow along its direction and never to nothing', () {
      st.addArrow(const Offset(.2, .5), const Offset(.4, .5));
      st.resizeSelected(.2, 0);
      var a = repo.annotationsFor(shot.id).single.data;
      expect((a['to'] as List)[0], closeTo(.6, 1e-9));
      expect((a['from'] as List)[0], .2, reason: 'the tail stays put');
      st.resizeSelected(-5, 0);
      a = repo.annotationsFor(shot.id).single.data;
      expect((a['to'] as List)[0], closeTo(.6, 1e-9), reason: 'refused: it would be a dot');
    });

    test('nudge and resize do nothing with nothing selected', () {
      st.addRect(AnnotationKind.box, const Offset(.1, .1), const Offset(.3, .2));
      st.select(null);
      st.nudgeSelected(.1, .1);
      st.resizeSelected(.1, .1);
      expect((repo.annotationsFor(shot.id).single.data['rect'] as List).first, closeTo(.1, 1e-9));
    });
  });

  group('crop', () {
    test('opening the tool starts from the saved crop, or the whole image', () {
      st.setTool(EditTool.crop);
      expect(st.cropDraft, const CropRect(0, 0, 1, 1));
      st.setCropDraft(const CropRect(.1, .1, .9, .9));
      st.applyCrop();
      expect(st.tool, EditTool.pin);
      st.setTool(EditTool.crop);
      expect(st.cropDraft, const CropRect(.1, .1, .9, .9));
    });

    test('apply saves it as data; the whole image clears it', () {
      st.setTool(EditTool.crop);
      st.setCropDraft(const CropRect(.2, .1, .8, .6));
      st.applyCrop();
      expect(repo.getShot(shot.id)!.crop, const CropRect(.2, .1, .8, .6));
      st.setTool(EditTool.crop);
      st.setCropDraft(const CropRect(0, 0, 1, 1));
      expect(st.cropIsFull, isTrue);
      st.applyCrop();
      expect(repo.getShot(shot.id)!.crop, isNull);
    });

    test('a crop cannot be dragged smaller than 10% or outside the image', () {
      st.setTool(EditTool.crop);
      st.setCropDraft(const CropRect(.5, .5, .52, .51));
      final c = st.cropDraft!;
      expect(c.right - c.left, closeTo(.1, 1e-9));
      expect(c.bottom - c.top, closeTo(.1, 1e-9));
      st.setCropDraft(const CropRect(-.3, -.2, 1.4, 1.2));
      expect(st.cropDraft, const CropRect(0, 0, 1, 1));
      st.setCropDraft(const CropRect(.95, .95, 1, 1));
      expect(st.cropDraft!.left, closeTo(.9, 1e-9));
    });

    test('reset clears the saved crop', () {
      st.setTool(EditTool.crop);
      st.setCropDraft(const CropRect(.2, .2, .8, .8));
      st.applyCrop();
      st.resetCrop();
      expect(repo.getShot(shot.id)!.crop, isNull);
    });

    test('switching tools clears the selection', () {
      final p1 = st.addPin(const Offset(.1, .1));
      expect(st.selectedId, p1.id);
      st.setTool(EditTool.box);
      expect(st.selectedId, isNull);
    });
  });

  test('none of this ever changes the original file', () {
    String h() => sha256.convert(File(shot.originalPath).readAsBytesSync()).toString();
    final before = h();
    final mtime = File(shot.originalPath).lastModifiedSync();
    st.addPin(const Offset(.5, .5));
    st.addStroke([for (var i = 0; i < 30; i++) Offset(.1 + i * .02, .1 + (i % 3) * .05)]);
    st.addRect(AnnotationKind.redact, const Offset(.1, .1), const Offset(.6, .3));
    st.setTool(EditTool.crop);
    st.setCropDraft(const CropRect(.1, .1, .9, .9));
    st.applyCrop();
    st.undo();
    st.setCaption('x');
    expect(h(), before);
    expect(File(shot.originalPath).lastModifiedSync(), mtime);
  });

  test('state reloads from the database: a new EditorState sees the saved edit', () {
    st.addPin(const Offset(.4, .4));
    st.addRect(AnnotationKind.redact, const Offset(.1, .1), const Offset(.3, .3));
    st.setTool(EditTool.crop);
    st.setCropDraft(const CropRect(.1, .1, .9, .9));
    st.applyCrop();
    final fresh = EditorState(repo, shot.id);
    expect(fresh.pins, hasLength(1));
    expect(fresh.annotations.single.kind, AnnotationKind.redact);
    expect(fresh.shot.crop, const CropRect(.1, .1, .9, .9));
    fresh.dispose();
  });

  group('hitTest', () {
    final vp = EditViewport(box: const Size(400, 400), imageSize: const Size(400, 400));

    test('pins win over shapes and a finger-sized area counts', () {
      final box = ann('box', AnnotationKind.box, {'rect': [.1, .1, .9, .9]});
      expect(hitTest(vp, const Offset(160, 160), [box], [pn('pin', .4, .4)]), 'pin');
      expect(hitTest(vp, const Offset(160 + 20, 160), [box], [pn('pin', .4, .4)]), 'pin', reason: '22px reach');
      expect(hitTest(vp, const Offset(160 + 40, 160), [box], [pn('pin', .4, .4)]), isNull);
    });

    test('a box is hit on its outline only, so taps inside reach what is beneath', () {
      final box = ann('box', AnnotationKind.box, {'rect': [.1, .1, .9, .9]});
      expect(hitTest(vp, const Offset(200, 44), [box], []), 'box'); // top edge at y=40
      expect(hitTest(vp, const Offset(200, 200), [box], []), isNull);
    });

    test('a redaction is hit anywhere inside it', () {
      final r = ann('red', AnnotationKind.redact, {'rect': [.2, .2, .6, .6]});
      expect(hitTest(vp, const Offset(160, 160), [], []), isNull);
      expect(hitTest(vp, const Offset(160, 160), [r], []), 'red');
      expect(hitTest(vp, const Offset(300, 300), [r], []), isNull);
    });

    test('arrows and strokes are hit near their line; later marks win', () {
      final arrow = ann('arrow', AnnotationKind.arrow, {'from': [.1, .5], 'to': [.9, .5]});
      final pen = ann('pen', AnnotationKind.pen, {'points': [[.5, .2], [.5, .8]]});
      expect(hitTest(vp, const Offset(100, 205), [arrow], []), 'arrow');
      expect(hitTest(vp, const Offset(100, 230), [arrow], []), isNull);
      expect(hitTest(vp, const Offset(203, 120), [arrow, pen], []), 'pen');
      expect(hitTest(vp, const Offset(200, 200), [arrow, pen], []), 'pen', reason: 'the later mark is on top');
      expect(hitTest(vp, const Offset(200, 200), [pen, arrow], []), 'arrow');
    });

    test('works through a crop', () {
      final cvp = EditViewport(
          box: const Size(400, 400), imageSize: const Size(400, 400), crop: const CropRect(.5, .5, 1, 1));
      // Normalised (.75,.75) sits at the middle of the cropped view.
      expect(hitTest(cvp, const Offset(200, 200), [], [pn('p', .75, .75)]), 'p');
      expect(hitTest(cvp, const Offset(200, 200), [], [pn('p', .25, .25)]), isNull);
    });
  });
}
