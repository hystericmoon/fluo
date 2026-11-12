import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/screens/album.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/editor.dart';
import 'package:fluo/screens/export.dart';
import 'package:fluo/screens/settings.dart';
import 'package:fluo/screens/triage.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

/// What can be checked without a screen reader. The floor from docs/spec.md:
/// every control has a name, every target is at least 44dp, every gesture has
/// a tap alternative, focus is visible and the keyboard reaches everything.
/// The rest (how TalkBack actually reads it) is the manual script in
/// docs/accessibility.md.
void main() {
  late FluoRepo repo;
  late Album album;
  late List<Shot> shots;

  /// A tall phone so nothing sits below the fold (a clipped target would be
  /// measured at its visible size).
  Future<void> setup(WidgetTester tester) async {
    setPhone(tester);
    tester.view.physicalSize = const Size(390 * 3, 1700 * 3);
    repo = memRepo();
    album = repo.createAlbum('Checkout flow review');
    shots = await seedKeptPngShots(tester, repo, album.id, 4);
    for (var i = 0; i < shots.length; i++) {
      repo.renameShot(shots[i].id, 'Screen ${i + 1}');
    }
    repo.addPin(shots[0].id, Severity.bug, .5, .5, note: 'n');
    repo.addAnnotation(shots[0].id, AnnotationKind.box, {'rect': [.1, .1, .5, .3]});
    repo.addAnnotation(shots[0].id, AnnotationKind.redact, {'rect': [.1, .5, .5, .6]});
    repo.startSession(album.id);
    await seedShots(tester, repo, album.id, 2); // pending, so Triage has work
  }

  Future<void> audit(WidgetTester tester, String state) async {
    expect(unlabeledControls(tester), isEmpty, reason: '$state: controls with no name');
    expect(smallTargets(tester), isEmpty, reason: '$state: targets under 44dp');
    expect(tapNodes, greaterThan(1), reason: '$state: found nothing to audit');
  }

  Future<void> settleImage(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('every control has a name and a 44dp target, in every state', () {
    testWidgets('Albums, and the new-album dialog', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
      await audit(tester, 'Albums');
      await tester.tap(find.text('New album'));
      await tester.pumpAndSettle();
      await audit(tester, 'New album dialog');
      h.dispose();
    });

    testWidgets('Triage in progress and done', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
      await audit(tester, 'Triage');
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await audit(tester, 'Triage done');
      h.dispose();
    });

    testWidgets('Album: flow, reorder mode, grid, empty', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(AlbumScreen(albumId: album.id), repo: repo));
      await audit(tester, 'Album flow');
      await tester.tap(find.text('Reorder screens'));
      await tester.pumpAndSettle();
      await audit(tester, 'Album reorder mode');
      await tester.tap(find.text('Done reordering'));
      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      await audit(tester, 'Album grid');
      final empty = repo.createAlbum('Empty');
      await tester.pumpWidget(host(AlbumScreen(albumId: empty.id), repo: repo));
      await audit(tester, 'Album empty');
      h.dispose();
    });

    testWidgets('Editor: every tool, a selected pin, box and redaction, and crop', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(EditorScreen(shotId: shots[0].id), repo: repo));
      await settleImage(tester);
      for (final tool in ['Pin', 'Pen', 'Arrow', 'Box', 'Redact']) {
        await tester.tap(find.bySemanticsLabel(tool).first); // the toolbar comes first
        await tester.pumpAndSettle();
        await audit(tester, 'Editor $tool tool');
      }
      await tester.tap(find.bySemanticsLabel('Pin').first);
      await tester.pumpAndSettle();
      for (final mark in ['Pin B1, Bug', 'Box', 'Redaction']) {
        await tester.tap(find.bySemanticsLabel(mark).last); // the marks list comes after the toolbar
        await tester.pumpAndSettle();
        await audit(tester, 'Editor $mark selected');
      }
      await tester.tap(find.bySemanticsLabel('Crop').first);
      await tester.pumpAndSettle();
      await audit(tester, 'Editor crop');
      h.dispose();
    });

    testWidgets('Export in each format', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(ExportScreen(albumId: album.id), repo: repo));
      for (final f in ['Claude pack', 'PDF', 'Long image', 'Share images']) {
        await tester.tap(find.text(f).first);
        await tester.pumpAndSettle();
        await audit(tester, 'Export $f');
      }
      h.dispose();
    });

    testWidgets('Settings', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(const SettingsScreen(), repo: repo));
      await audit(tester, 'Settings');
      h.dispose();
    });
  });

  group('every gesture has an alternative that needs no gesture', () {
    testWidgets('Triage flick: Keep and Discard buttons, Undo, and TalkBack actions on the card', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.bySemanticsLabel('Undo last choice'), findsOneWidget);
      expect(customActionLabels(tester), containsAll(['Keep', 'Discard']));
      h.dispose();
    });

    testWidgets('Album row swipe: a "Delete album" action, and Hold-to-delete in the album menu', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
      expect(customActionLabels(tester), contains('Delete album'));
      await tester.pumpWidget(host(AlbumScreen(albumId: album.id), repo: repo));
      await tester.tap(find.bySemanticsLabel('Album options'));
      await tester.pumpAndSettle();
      expect(find.text('Hold to delete album'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Hold to delete album')).hint, contains('tap twice'));
      h.dispose();
    });

    testWidgets('Reordering: buttons in reorder mode and TalkBack actions on tiles', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(AlbumScreen(albumId: album.id), repo: repo));
      expect(find.text('Reorder screens'), findsOneWidget);
      expect(customActionLabels(tester), containsAll(['Move earlier', 'Move later']));
      h.dispose();
    });

    testWidgets('Editor: pins, shapes and crop can all be made and changed without dragging', (tester) async {
      await setup(tester);
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(EditorScreen(shotId: shots[1].id), repo: repo));
      await settleImage(tester);
      expect(find.text('Add pin in the middle'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Box').first);
      await tester.pumpAndSettle();
      expect(find.text('Add a box in the middle'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Arrow'));
      await tester.pumpAndSettle();
      expect(find.text('Add an arrow in the middle'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Redact'));
      await tester.pumpAndSettle();
      expect(find.text('Add a redaction in the middle'), findsOneWidget, reason: 'hiding something private needs no finger gesture');
      await tester.tap(find.text('Add a redaction in the middle'));
      await tester.pumpAndSettle();
      for (final l in ['Move redaction left', 'Move redaction right', 'Move redaction up', 'Move redaction down']) {
        expect(find.bySemanticsLabel(l), findsOneWidget, reason: l);
      }
      expect(find.text('Wider'), findsOneWidget);
      expect(find.text('Taller'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Crop'));
      await tester.pumpAndSettle();
      expect(customActionLabels(tester).where((l) => l.startsWith('Trim')), hasLength(8));
      h.dispose();
    });

    testWidgets('the only thing left that needs a finger is a freehand pen stroke, and the editor says so', (tester) async {
      await setup(tester);
      await tester.pumpWidget(host(EditorScreen(shotId: shots[1].id), repo: repo));
      await settleImage(tester);
      await tester.tap(find.bySemanticsLabel('Pen'));
      await tester.pumpAndSettle();
      expect(find.text('Draw on the screenshot with your finger.'), findsOneWidget);
    });
  });

  group('keyboard', () {
    testWidgets('Tab reaches controls, Enter activates one, and the focused control shows a ring', (tester) async {
      await setup(tester);
      await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
      // Make Flutter treat input as keyboard so focus is highlighted.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final seen = <FocusNode?>{};
      for (var i = 0; i < 12; i++) {
        seen.add(FocusManager.instance.primaryFocus);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(seen.length, greaterThan(4), reason: 'Tab moves through several different controls');

      // Walk back to "New album" and open it with Enter.
      var opened = false;
      for (var i = 0; i < 30 && !opened; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        opened = find.text('Album name').evaluate().isNotEmpty;
      }
      expect(opened, isTrue, reason: 'some control opened the new-album dialog with Enter');
    });

    testWidgets('a focused control is drawn with a visible ring', (tester) async {
      await setup(tester);
      await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // The ring is a 2dp lime border on a positioned overlay.
      final rings = find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border is Border &&
          ((w.decoration as BoxDecoration).border as Border).top.width == 2 &&
          ((w.decoration as BoxDecoration).border as Border).top.color == const Color(0xFFC8FF3D));
      expect(rings, findsWidgets);
    });
  });
}
