import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/edit/render.dart';
import 'package:fluo/screens/editor.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

final _painter = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is EditPainter);

EditPainter _p(WidgetTester t) => t.widget<CustomPaint>(_painter).painter! as EditPainter;

/// Where a normalised image point is on screen right now.
Offset at(WidgetTester t, double nx, double ny) =>
    t.getTopLeft(_painter) + _p(t).viewport.toWidget(Offset(nx, ny));

/// Opens the editor and waits for the image to decode.
Future<void> openEditor(WidgetTester tester, FluoRepo repo, String shotId) async {
  await tester.pumpWidget(host(EditorScreen(shotId: shotId), repo: repo));
  for (var i = 0; i < 20 && _painter.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(_painter, findsOneWidget, reason: 'the image decoded');
}

/// A drag in [steps] small moves. A real finger moves a few pixels at a time,
/// which matters: gesture recognizers decide as soon as the slop is passed.
Future<void> drag(WidgetTester tester, Offset from, Offset to, {int steps = 6}) async {
  final g = await tester.startGesture(from);
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

void main() {
  late FluoRepo repo;
  late Shot shot;

  Future<void> setup(WidgetTester tester) async {
    setPhone(tester);
    repo = memRepo();
    final a = repo.createAlbum('Checkout flow review');
    shot = (await seedKeptPngShots(tester, repo, a.id, 3)).first;
    repo.renameShot(shot.id, 'Cart');
  }

  /// A widget test with semantics on and a seeded album, shot and repo.
  void editorTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await setup(tester);
        await body(tester);
      } finally {
        semantics.dispose();
      }
    });
  }

  group('placing and editing pins', () {
    editorTest('opens on the pin tool with the shot name and its place in the album', (tester) async {
      await openEditor(tester, repo, shot.id);
      expect(find.text('Cart'), findsOneWidget);
      expect(find.text('1 of 3 · Checkout flow review'), findsOneWidget);
      expect(find.text('Tap the screenshot to drop a pin. Tap a mark to edit it.'), findsOneWidget);
    });

    editorTest('tapping the image drops a pin there and opens its details', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .4, .5));
      await tester.pumpAndSettle();
      final pin = repo.pinsFor(shot.id).single;
      expect(pin.x, closeTo(.4, .02));
      expect(pin.y, closeTo(.5, .02));
      expect(pin.severity, Severity.bug);
      expect(find.text('Pin B1'), findsOneWidget);
      expect(find.text('Note on this pin'), findsOneWidget);
    });

    editorTest('tapping outside the picture places nothing', (tester) async {
      await openEditor(tester, repo, shot.id);
      final left = tester.getTopLeft(_painter) + const Offset(5, 200); // in the letterbox bar
      await tester.tapAt(left);
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id), isEmpty);
    });

    editorTest('severity buttons recolour the selected pin; new pins use the last choice', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A11y'));
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id).single.severity, Severity.a11y);
      expect(find.text('Pin A1'), findsOneWidget, reason: 'the letter in the name follows the severity');
      await tester.tapAt(at(tester, .7, .7));
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id).map((p) => p.severity), [Severity.a11y, Severity.a11y]);
    });

    editorTest('a note and a caption are saved as you type', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .5, .5));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Total changes after shipping');
      await tester.enterText(find.byType(TextField).last, 'Cart: order total changes');
      expect(repo.pinsFor(shot.id).single.note, 'Total changes after shipping');
      expect(repo.getShot(shot.id)!.caption, 'Cart: order total changes');
    });

    editorTest('dragging a pin moves it; the preview follows the finger', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await drag(tester, at(tester, .3, .3), at(tester, .6, .7));
      final p = repo.pinsFor(shot.id).single;
      expect(p.x, closeTo(.6, .04));
      expect(p.y, closeTo(.7, .04));
      expect(repo.pinsFor(shot.id), hasLength(1), reason: 'moved, not duplicated');
    });

    editorTest('delete removes the pin', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .5, .5));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Delete pin B1'));
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id), isEmpty);
      expect(find.text('Note on this pin'), findsNothing);
    });

    editorTest('without touching the image: add a pin in the middle, then nudge it', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.text('Add pin in the middle'));
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id).single.x, .5);
      await tester.tap(find.bySemanticsLabel('Move pin right'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Move pin up'));
      await tester.pumpAndSettle();
      final p = repo.pinsFor(shot.id).single;
      expect(p.x, closeTo(.52, 1e-9));
      expect(p.y, closeTo(.48, 1e-9));
    });
  });

  group('drawing', () {
    Future<void> useTool(WidgetTester tester, String tool) async {
      await tester.tap(find.bySemanticsLabel(tool));
      await tester.pumpAndSettle();
    }

    editorTest('box, arrow, redact and pen drags are saved with their geometry', (tester) async {
      await openEditor(tester, repo, shot.id);
      await useTool(tester, 'Box');
      await drag(tester, at(tester, .2, .2), at(tester, .6, .4));
      await useTool(tester, 'Arrow');
      await drag(tester, at(tester, .2, .6), at(tester, .8, .6));
      await useTool(tester, 'Redact');
      await drag(tester, at(tester, .1, .75), at(tester, .5, .85));
      await useTool(tester, 'Pen');
      await drag(tester, at(tester, .2, .9), at(tester, .8, .95));

      final all = repo.annotationsFor(shot.id);
      expect(all.map((a) => a.kind), [AnnotationKind.box, AnnotationKind.arrow, AnnotationKind.redact, AnnotationKind.pen]);
      final box = (all[0].data['rect'] as List).cast<double>();
      expect(box[0], closeTo(.2, .05));
      expect(box[3], closeTo(.4, .05));
      final red = (all[2].data['rect'] as List).cast<double>();
      expect(red[2], closeTo(.5, .05));
    });

    editorTest('a mostly vertical stroke draws; it does not scroll the page', (tester) async {
      // A short phone, so the page can scroll: that is when it competes.
      tester.view.physicalSize = const Size(390 * 3, 640 * 3);
      await openEditor(tester, repo, shot.id);
      await useTool(tester, 'Arrow');
      final before = tester.getTopLeft(_painter);
      await drag(tester, at(tester, .5, .15), at(tester, .52, .85), steps: 40);
      final a = repo.annotationsFor(shot.id).single;
      expect(a.kind, AnnotationKind.arrow);
      expect((a.data['from'] as List)[1], closeTo(.15, .03), reason: 'starts where the finger landed');
      expect((a.data['to'] as List)[1], closeTo(.85, .03));
      expect(tester.getTopLeft(_painter), before, reason: 'the page did not move');
    });

    editorTest('a pin is grabbed where the finger lands even when dragged mostly vertically', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .4, .2));
      await tester.pumpAndSettle();
      await drag(tester, at(tester, .4, .2), at(tester, .42, .8), steps: 40);
      final p = repo.pinsFor(shot.id).single;
      expect(p.y, closeTo(.8, .04));
      expect(repo.pinsFor(shot.id), hasLength(1));
    });

    editorTest('a tap or a tiny drag with a drawing tool saves nothing', (tester) async {
      await openEditor(tester, repo, shot.id);
      for (final t in ['Box', 'Arrow', 'Redact', 'Pen']) {
        await useTool(tester, t);
        await tester.tapAt(at(tester, .5, .5));
        await tester.pump();
        await drag(tester, at(tester, .5, .5), at(tester, .5, .5) + const Offset(2, 1));
      }
      expect(repo.annotationsFor(shot.id), isEmpty);
    });

    editorTest('the shape is previewed while dragging', (tester) async {
      await openEditor(tester, repo, shot.id);
      await useTool(tester, 'Redact');
      final g = await tester.startGesture(at(tester, .2, .3));
      await g.moveTo(at(tester, .6, .5));
      await tester.pump();
      expect(_p(tester).annotations.where((a) => a.id == 'draft'), hasLength(1));
      expect(repo.annotationsFor(shot.id), isEmpty, reason: 'not saved until the finger lifts');
      await g.up();
      await tester.pump();
      expect(_p(tester).annotations.where((a) => a.id == 'draft'), isEmpty);
      expect(repo.annotationsFor(shot.id), hasLength(1));
    });

    editorTest('tapping a mark selects it, shows its panel and can delete it', (tester) async {
      await openEditor(tester, repo, shot.id);
      await useTool(tester, 'Redact');
      await drag(tester, at(tester, .2, .3), at(tester, .6, .5));
      await useTool(tester, 'Pin');
      expect(find.text('Hidden in every export'), findsNothing, reason: 'changing tool clears the selection');
      await tester.tapAt(at(tester, .4, .4)); // inside the redaction
      await tester.pumpAndSettle();
      expect(find.text('Redaction'), findsWidgets);
      expect(find.text('Hidden in every export'), findsOneWidget);
      expect(repo.pinsFor(shot.id), isEmpty, reason: 'selected, did not drop a pin');
      await tester.tap(find.bySemanticsLabel('Delete redaction'));
      await tester.pumpAndSettle();
      expect(repo.annotationsFor(shot.id), isEmpty);
    });

    editorTest('tapping empty space clears the selection with a drawing tool active', (tester) async {
      await openEditor(tester, repo, shot.id);
      await useTool(tester, 'Box');
      await drag(tester, at(tester, .2, .2), at(tester, .6, .4)); // selected on creation
      expect(_p(tester).selectedId, isNotNull);
      await tester.tapAt(at(tester, .9, .9));
      await tester.pumpAndSettle();
      expect(_p(tester).selectedId, isNull);
    });

    editorTest('undo removes the last mark and is disabled when there is nothing to undo', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await useTool(tester, 'Box');
      await drag(tester, at(tester, .2, .6), at(tester, .6, .8));
      expect(repo.annotationsFor(shot.id), hasLength(1));
      await tester.tap(find.bySemanticsLabel('Undo last mark'));
      await tester.pumpAndSettle();
      expect(repo.annotationsFor(shot.id), isEmpty);
      expect(repo.pinsFor(shot.id), hasLength(1));
      await tester.tap(find.bySemanticsLabel('Undo last mark'));
      await tester.pumpAndSettle();
      expect(repo.pinsFor(shot.id), isEmpty);
    });

    editorTest('the marks list selects any mark without touching the image', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await tester.tapAt(at(tester, .7, .7));
      await tester.pumpAndSettle();
      expect(find.text('Pin B2'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Pin B1, Bug'));
      await tester.pumpAndSettle();
      expect(find.text('Pin B1'), findsWidgets);
      expect(_p(tester).selectedId, repo.pinsFor(shot.id).first.id);
    });
  });

  group('without dragging', () {
    editorTest('a redaction can be added, moved and resized with buttons alone', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Redact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a redaction in the middle'));
      await tester.pumpAndSettle();
      var a = repo.annotationsFor(shot.id).single;
      expect(a.kind, AnnotationKind.redact);
      expect(find.text('Hidden in every export'), findsOneWidget);

      final before = (a.data['rect'] as List).cast<double>();
      await tester.tap(find.bySemanticsLabel('Move redaction down'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wider'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taller'));
      await tester.pumpAndSettle();
      a = repo.annotationsFor(shot.id).single;
      final after = (a.data['rect'] as List).cast<double>();
      expect(after[1] + after[3], greaterThan(before[1] + before[3]), reason: 'moved down');
      expect(after[2] - after[0], greaterThan(before[2] - before[0]), reason: 'wider');
      expect(after[3] - after[1], greaterThan(before[3] - before[1]), reason: 'taller');
    });

    editorTest('a box and an arrow can be added and adjusted the same way', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Box'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a box in the middle'));
      await tester.pumpAndSettle();
      expect(repo.annotationsFor(shot.id).single.kind, AnnotationKind.box);
      await tester.tap(find.text('Narrower'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Arrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an arrow in the middle'));
      await tester.pumpAndSettle();
      final arrow = repo.annotationsFor(shot.id).last;
      expect(arrow.kind, AnnotationKind.arrow);
      await tester.tap(find.text('Longer'));
      await tester.pumpAndSettle();
      final longer = repo.annotationsFor(shot.id).last.data;
      expect(((longer['to'] as List)[0] as double) - ((longer['from'] as List)[0] as double),
          greaterThan(((arrow.data['to'] as List)[0] as double) - ((arrow.data['from'] as List)[0] as double)));
    });

    editorTest('the pen has no button route (a freehand line needs a finger) and says to draw', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Pen'));
      await tester.pumpAndSettle();
      expect(find.text('Draw on the screenshot with your finger.'), findsOneWidget);
      expect(find.textContaining('in the middle'), findsNothing);
    });

    editorTest('every mark made by buttons is selectable from the marks list and deletable', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Redact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a redaction in the middle'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Pin'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden in every export'), findsNothing, reason: 'tool change clears the selection');
      await tester.tap(find.bySemanticsLabel('Redaction')); // marks list
      await tester.pumpAndSettle();
      expect(find.text('Hidden in every export'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Delete redaction'));
      await tester.pumpAndSettle();
      expect(repo.annotationsFor(shot.id), isEmpty);
    });
  });

  group('crop', () {
    editorTest('drag a corner, apply: saved as data and the picture is now cropped', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      expect(find.text('Apply crop'), findsOneWidget);
      final tl = at(tester, 0, 0), br = at(tester, 1, 1);
      await drag(tester, tl + const Offset(4, 4), tl + const Offset(44, 84)); // top-left corner inward
      await drag(tester, br - const Offset(4, 4), br - const Offset(24, 44));
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();
      final c = repo.getShot(shot.id)!.crop!;
      expect(c.left, greaterThan(.1));
      expect(c.top, greaterThan(.05));
      expect(c.right, lessThan(.95));
      expect(c.bottom, lessThan(.95));
      expect(_p(tester).viewport.crop, c, reason: 'the canvas now shows the crop');
    });

    editorTest('dragging inside the frame moves it', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      final tl = at(tester, 0, 0), br = at(tester, 1, 1);
      // Shrink from the bottom-right first so there is room to move.
      await drag(tester, br - const Offset(3, 3), br - const Offset(103, 203));
      final before = repo.getShot(shot.id)!.crop;
      expect(before, isNull, reason: 'nothing saved until Apply');
      final centre = Offset((tl.dx + br.dx) / 4 + tl.dx / 2, (tl.dy + br.dy) / 4 + tl.dy / 2);
      await drag(tester, centre, centre + const Offset(40, 60));
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();
      final c = repo.getShot(shot.id)!.crop!;
      expect(c.left, greaterThan(.1), reason: 'moved right');
      expect(c.right - c.left, closeTo(.5, .1), reason: 'size kept');
    });

    testWidgets('with motion on, the crop frame eases in from the whole image to the saved crop', (tester) async {
      setPhone(tester);
      final semantics = tester.ensureSemantics();
      repo = memRepo();
      final a = repo.createAlbum('A');
      shot = (await seedKeptPngShots(tester, repo, a.id, 1)).single;
      repo.setCrop(shot.id, const CropRect(.25, .25, .75, .75));
      await tester.pumpWidget(host(EditorScreen(shotId: shot.id), repo: repo, reduceMotion: false));
      for (var i = 0; i < 20 && _painter.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.bySemanticsLabel('Crop').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.hasRunningAnimations, isTrue, reason: 'the frame is moving');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isFalse, reason: 'and then it rests');
      semantics.dispose();
    });

    testWidgets('with reduced motion the crop frame is just there', (tester) async {
      setPhone(tester);
      final semantics = tester.ensureSemantics();
      repo = memRepo();
      final a = repo.createAlbum('A');
      shot = (await seedKeptPngShots(tester, repo, a.id, 1)).single;
      repo.setCrop(shot.id, const CropRect(.25, .25, .75, .75));
      await tester.pumpWidget(host(EditorScreen(shotId: shot.id), repo: repo));
      for (var i = 0; i < 20 && _painter.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.bySemanticsLabel('Crop').first);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      semantics.dispose();
    });

    editorTest('applying the whole image clears the crop; Reset also clears it', (tester) async {
      repo.setCrop(shot.id, const CropRect(.2, .2, .8, .8));
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(repo.getShot(shot.id)!.crop, isNull);
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();
      expect(repo.getShot(shot.id)!.crop, isNull);
    });

    editorTest('screen readers get trim actions for the frame', (tester) async {
      final handle = tester.ensureSemantics();
      await openEditor(tester, repo, shot.id);
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Crop frame')));
      final labels = [
        for (final id in node.getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label
      ];
      expect(labels, hasLength(8));
      expect(labels, contains('Trim more from the top'));
      handle.dispose();
    });

    editorTest('marks made before cropping are kept and follow the crop', (tester) async {
      repo.addPin(shot.id, Severity.ux, .5, .5);
      repo.setCrop(shot.id, const CropRect(.25, .25, .75, .75));
      await openEditor(tester, repo, shot.id);
      expect(_p(tester).viewport.crop, const CropRect(.25, .25, .75, .75));
      expect(_p(tester).pins, hasLength(1));
      await tester.tapAt(_p(tester).viewport.toWidget(const Offset(.5, .5)) + tester.getTopLeft(_painter));
      await tester.pumpAndSettle();
      expect(find.text('Pin U1'), findsWidgets, reason: 'the pin is hit through the crop');
    });
  });

  group('persistence and the original', () {
    editorTest('closing and reopening the editor shows the same edit', (tester) async {
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Box'));
      await tester.pumpAndSettle();
      await drag(tester, at(tester, .2, .6), at(tester, .6, .8));
      await tester.pumpWidget(const SizedBox());
      await openEditor(tester, repo, shot.id);
      expect(_p(tester).pins, hasLength(1));
      expect(_p(tester).annotations.map((a) => a.kind), [AnnotationKind.box]);
    });

    editorTest('editing never changes the original file', (tester) async {
      String h() => sha256.convert(File(shot.originalPath).readAsBytesSync()).toString();
      final before = h();
      final mtime = File(shot.originalPath).lastModifiedSync();
      await openEditor(tester, repo, shot.id);
      await tester.tapAt(at(tester, .3, .3));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Redact'));
      await tester.pumpAndSettle();
      await drag(tester, at(tester, .1, .1), at(tester, .5, .3));
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply crop'));
      await tester.pumpAndSettle();
      expect(h(), before);
      expect(File(shot.originalPath).lastModifiedSync(), mtime);
    });

    editorTest('an unreadable image says so instead of crashing', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = (await seedShots(tester, repo, a.id, 1)).single; // not a real image
      repo.setStatus(s.id, ShotStatus.kept);
      await tester.pumpWidget(host(EditorScreen(shotId: s.id), repo: repo));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.text("Couldn't open this screenshot"), findsOneWidget);
    });
  });

  group('tap targets', () {
    for (final state in ['pin tool', 'pin selected', 'box selected', 'crop']) {
      editorTest(state, (tester) async {
          // Tall enough that nothing is scrolled out of view (a clipped target
        // would be measured at its visible size).
        tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
        final handle = tester.ensureSemantics();
        repo.addPin(shot.id, Severity.ux, .3, .3);
        repo.addAnnotation(shot.id, AnnotationKind.box, {'rect': [.2, .6, .6, .8]});
        await openEditor(tester, repo, shot.id);
        if (state == 'pin selected') {
          await tester.tapAt(at(tester, .3, .3));
        } else if (state == 'box selected') {
          await tester.tapAt(at(tester, .2, .7)); // on the box's left edge
        } else if (state == 'crop') {
          await tester.tap(find.bySemanticsLabel('Crop'));
        }
        await tester.pumpAndSettle();
        expect(smallTargets(tester), isEmpty);
        expect(tapNodes, greaterThan(5));
        handle.dispose();
      });
    }
  });
}
