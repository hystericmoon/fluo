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

/// WCAG 1.4.4: text can be enlarged to 200% without losing function.
///
/// Flutter's overflow errors are not available here: shadcn_flutter ships its
/// own Row and Column, which do not report them (checked: an obvious overflow
/// raises nothing). So this measures what matters instead: at large text,
/// every control still has a name and a target of at least 44dp (a squeezed
/// button is how a broken layout shows up), and the controls are all still
/// there.
void main() {
  late FluoRepo repo;
  late Album album;
  late List<Shot> shots;

  Future<void> setup(WidgetTester tester, double scale) async {
    setPhone(tester);
    tester.view.physicalSize = const Size(390 * 3, 3200 * 3); // tall: large text makes pages long
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repo = memRepo();
    album = repo.createAlbum('Checkout flow review with a rather long name');
    shots = await seedKeptPngShots(tester, repo, album.id, 3);
    repo.renameShot(shots[0].id, 'A screen with a long name');
    repo.addPin(shots[0].id, Severity.bug, .5, .5, note: 'A long note about the problem on this screen');
    repo.addAnnotation(shots[0].id, AnnotationKind.redact, {'rect': [.1, .5, .5, .6]});
    repo.startSession(album.id);
    await seedShots(tester, repo, album.id, 2);
  }

  Future<void> check(WidgetTester tester, double scale, Widget Function() screen, {Future<void> Function()? then}) async {
    await setup(tester, scale);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(screen(), repo: repo));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (then != null) await then();
    await tester.pump();
    final at = '${(scale * 100).round()}% text';
    final unnamed = unlabeledControls(tester);
    final small = smallTargets(tester);
    final found = tapNodes;
    semantics.dispose();
    expect(unnamed, isEmpty, reason: at);
    expect(small, isEmpty, reason: '$at: a control was squeezed below 44dp');
    expect(found, greaterThan(1), reason: '$at: nothing to check');
  }

  for (final scale in [1.3, 2.0]) {
    group('text at ${(scale * 100).round()}%', () {
      testWidgets('Albums', (t) => check(t, scale, () => const AlbumsScreen()));
      testWidgets('Triage', (t) => check(t, scale, () => TriageScreen(albumId: album.id)));
      testWidgets('Album', (t) => check(t, scale, () => AlbumScreen(albumId: album.id)));
      testWidgets('Album in reorder mode', (t) => check(t, scale, () => AlbumScreen(albumId: album.id), then: () async {
            await t.tap(find.text('Reorder screens'));
            await t.pump();
          }));
      testWidgets('Editor', (t) => check(t, scale, () => EditorScreen(shotId: shots[0].id)));
      testWidgets('Editor with a pin selected', (t) => check(t, scale, () => EditorScreen(shotId: shots[0].id), then: () async {
            await t.tap(find.text('Add pin in the middle'));
            await t.pump();
          }));
      testWidgets('Export', (t) => check(t, scale, () => ExportScreen(albumId: album.id)));
      testWidgets('Settings', (t) => check(t, scale, () => const SettingsScreen()));
    });
  }
}
