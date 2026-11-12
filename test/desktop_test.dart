import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/desktop/desktop_shell.dart';
import 'package:fluo/main.dart';
import 'package:fluo/screens/albums.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:fluo/ui/kit.dart' show FluoButton;
import 'support/fake_source.dart';
import 'support/harness.dart';

void setWide(WidgetTester t, {double w = 1280, double h = 800}) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pumpApp(WidgetTester t, repo, {bool desktop = true}) async {
  await t.pumpWidget(FluoApp(
    repo: repo,
    source: FakeSource(),
    exports: testExports(),
    reduceMotion: true,
    desktop: desktop,
    splash: Duration.zero,
  ));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the sidebar session card shows full-width buttons and the album list', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    await seedShots(t, repo, a.id, 2);
    repo.startSession(a.id);
    await pumpApp(t, repo);
    expect(find.text('Session'), findsNothing);
    expect(find.text('Review 2 new'), findsWidgets);
    expect(find.text('Pause'), findsOneWidget);
    // Stacked buttons are full width, so their labels are never cut off.
    final pauseBtn = find.ancestor(of: find.text('Pause'), matching: find.byType(FluoButton));
    expect(t.getSize(pauseBtn).width, greaterThan(200));
    expect(find.text('Onboarding audit'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a wide desktop window shows sidebar, grid and inspector', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedKeptPngShots(t, repo, a.id, 3);
    await pumpApp(t, repo);
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(AlbumsScreen), findsNothing);
    expect(find.text('Checkout flow review'), findsWidgets); // sidebar and header
    expect(find.text('Onboarding audit'), findsOneWidget);
    expect(find.text('Inspector'), findsNothing); // a label, not text
    expect(find.text('Export album'), findsOneWidget); // inspector summary
    expect(shots.length, 3);
  });

  testWidgets('a narrow desktop window and a non-desktop build keep the phone Albums screen', (t) async {
    setPhone(t);
    await pumpApp(t, seeded());
    expect(find.byType(AlbumsScreen), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
    setWide(t);
    await pumpApp(t, seeded(), desktop: false);
    expect(find.byType(AlbumsScreen), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
  });

  testWidgets('clicking a screen shows it in the inspector; Escape clears', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedKeptPngShots(t, repo, a.id, 3);
    await pumpApp(t, repo);
    await t.tap(find.byKey(ValueKey('tile-${shots[1].id}')));
    await t.pumpAndSettle();
    expect(find.text('Screen 2 of 3'), findsOneWidget);
    expect(find.text('Edit marks'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Screen 2 of 3'), findsNothing);
  });

  testWidgets('arrow keys move the selection and Space adds to it', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    await seedKeptPngShots(t, repo, a.id, 3);
    await pumpApp(t, repo);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.text('Screen 1 of 3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.text('Screen 2 of 3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // back to 1
    await t.sendKeyEvent(LogicalKeyboardKey.space); // toggles it off
    await t.pumpAndSettle();
    expect(find.text('Screen 1 of 3'), findsNothing);
  });

  testWidgets('Select mode, Select all, then Discard waits out the undo fuse', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedKeptPngShots(t, repo, a.id, 3);
    await pumpApp(t, repo);
    await t.tap(find.text('Select all'));
    await t.pumpAndSettle();
    expect(find.text('3 screens selected'), findsOneWidget);
    await t.tap(find.text('Discard 3 screens'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300)); // not settled: the fuse is still burning
    expect(find.textContaining('Discarded 3 screens'), findsOneWidget);
    // Still in the database until the fuse burns.
    expect(repo.getShot(shots[0].id), isNotNull);
    await t.tap(find.text('Undo'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Discarded 3 screens'), findsNothing);
    expect(repo.shotsIn(a.id, status: ShotStatus.kept).length, 3);
  });

  testWidgets('a discard is final once the fuse burns', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedKeptPngShots(t, repo, a.id, 2);
    await pumpApp(t, repo);
    await t.tap(find.byKey(ValueKey('tile-${shots[0].id}')));
    await t.pump(const Duration(milliseconds: 100));
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Discarded 1 screen'), findsOneWidget);
    await t.pump(const Duration(seconds: 7));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
    expect(repo.getShot(shots[0].id), isNull);
    expect(repo.getShot(shots[1].id), isNotNull);
  });

  testWidgets('single-key shortcuts do nothing while a name is being typed', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedKeptPngShots(t, repo, a.id, 2);
    await pumpApp(t, repo);
    await t.tap(find.byKey(ValueKey('tile-${shots[0].id}')));
    await t.pumpAndSettle();
    await t.tap(find.byType(EditableText).first); // the Screen name field
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.sendKeyEvent(LogicalKeyboardKey.keyG);
    await t.pumpAndSettle();
    expect(find.textContaining('Discarded 1 screen'), findsNothing);
    expect(find.text('Screen 1 of 2'), findsOneWidget);
  });

  testWidgets('Triage on desktop: K keeps, D discards, typing a name does neither', (t) async {
    setWide(t);
    final repo = seeded();
    final a = repo.listAlbums().first.album;
    final shots = await seedShots(t, repo, a.id, 3);
    await pumpApp(t, repo);
    await t.tap(find.text('Review').first);
    await t.pumpAndSettle();
    expect(find.text('Triage'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.pumpAndSettle();
    expect(repo.getShot(shots[0].id)!.status, ShotStatus.kept);
    await t.sendKeyEvent(LogicalKeyboardKey.keyD);
    await t.pumpAndSettle();
    expect(repo.getShot(shots[1].id)!.status, ShotStatus.discarded);
    await t.tap(find.byType(EditableText).first);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.pumpAndSettle();
    expect(repo.getShot(shots[2].id)!.status, ShotStatus.pending);
  });
}
