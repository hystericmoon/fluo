import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/capture/capture_controller.dart';
import 'package:fluo/capture/capture_scope.dart';
import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/repo_scope.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/main.dart';
import 'package:fluo/screens/album.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/editor.dart';
import 'package:fluo/screens/export.dart';
import 'package:fluo/screens/settings.dart';
import 'package:fluo/screens/triage.dart';
import 'package:fluo/theme/app_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/fake_source.dart';

FluoRepo _memRepo() {
  final dir = Directory.systemTemp.createTempSync('fluo_ui_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final repo = FluoRepo(FluoDb.openInMemory(), FileStore(dir));
  addTearDown(repo.close);
  return repo;
}

Widget _host(Widget home, {FluoRepo? repo, FakeSource? source}) {
  final r = repo ?? _memRepo();
  final c = CaptureController(r, source ?? FakeSource());
  addTearDown(c.dispose);
  return RepoScope(
    repo: r,
    child: CaptureScope(
      controller: c,
      child: ShadcnApp(
        debugShowCheckedModeBanner: false,
        theme: fluoTheme(),
        home: home,
      ),
    ),
  );
}

/// Albums with a few kept screens, like a used app.
final _fixedNow = DateTime(2026, 11, 9, 15); // a Monday

FluoRepo _seeded() {
  final r = _memRepo();
  r.createAlbum('Checkout flow review', now: _fixedNow);
  r.createAlbum('Onboarding audit', now: DateTime(2026, 10, 20));
  return r;
}

void _setPhone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

/// Every node with a tap action must be at least 44x44 dp.
int _tapNodes = 0;

List<String> _smallTargets(WidgetTester t) {
  _tapNodes = 0;
  final bad = <String>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.hasAction(SemanticsAction.tap) && !n.isInvisible) _tapNodes++;
    if (d.hasAction(SemanticsAction.tap) &&
        !n.isInvisible &&
        (n.rect.width < 44 - 0.5 || n.rect.height < 44 - 0.5)) {
      bad.add('${d.label.isEmpty ? '(no label)' : d.label} ${n.rect.size}');
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return bad;
}

void main() {
  testWidgets('splash then an empty Albums screen on a fresh install', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(FluoApp(repo: _memRepo(), source: FakeSource()));
    expect(find.text('FLUO'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('No albums yet'), findsOneWidget);
    expect(find.text('Review 7 new'), findsNothing);
  });

  testWidgets('Albums lists real albums with screen counts and dates', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(AlbumsScreen(now: _fixedNow), repo: _seeded()));
    expect(find.text('Checkout flow review'), findsOneWidget);
    expect(find.text('0 screens · Today'), findsOneWidget);
    expect(find.text('Onboarding audit'), findsOneWidget);
    expect(find.text('0 screens · Oct 20'), findsOneWidget);
  });

  testWidgets('New album asks for a name, creates it and refuses a blank name', (tester) async {
    _setPhone(tester);
    final repo = _memRepo();
    await tester.pumpWidget(_host(const AlbumsScreen(), repo: repo));
    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create')); // blank: nothing happens
    await tester.pumpAndSettle();
    expect(repo.listAlbums(), isEmpty);
    expect(find.text('Album name'), findsWidgets, reason: 'dialog stays open');

    await tester.enterText(find.byType(TextField), '  Search and filters ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(repo.listAlbums().single.album.name, 'Search and filters');
    expect(repo.activeSession()!.albumId, repo.listAlbums().single.album.id,
        reason: 'a new album starts a session in it');
    expect(find.text('Search and filters'), findsNWidgets(2), reason: 'session card and list row');
    expect(find.text('Session on'), findsOneWidget);
    expect(find.text('No albums yet'), findsNothing);
  });

  testWidgets('Cancel leaves the albums alone', (tester) async {
    _setPhone(tester);
    final repo = _memRepo();
    await tester.pumpWidget(_host(const AlbumsScreen(), repo: repo));
    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.listAlbums(), isEmpty);
  });

  testWidgets('session card counts pending screenshots and only shows with a session', (tester) async {
    _setPhone(tester);
    final repo = _memRepo();
    final a = repo.createAlbum('Checkout flow review');
    final f = File('${Directory.systemTemp.path}/fluo_ui_shot_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => f.deleteSync());
    await tester.runAsync(() async {
      await repo.addShot(a.id, f);
      await repo.addShot(a.id, f);
    });

    await tester.pumpWidget(_host(const AlbumsScreen(), repo: repo));
    expect(find.text('Session on'), findsNothing, reason: 'pending shots alone are not a session');
    expect(find.text('Review 2 new'), findsNothing);

    repo.startSession(a.id);
    await tester.pumpWidget(_host(const AlbumsScreen(), repo: repo));
    expect(find.text('Review 2 new'), findsOneWidget);
  });

  group('session card states', () {
    Future<FakeSource> startAlbum(WidgetTester tester, FakeSource src) async {
      _setPhone(tester);
      await tester.pumpWidget(_host(const AlbumsScreen(), source: src));
      await tester.tap(find.text('New album'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Checkout');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      return src;
    }

    testWidgets('watching: Pause then Resume', (tester) async {
      final src = await startAlbum(tester, FakeSource());
      expect(find.text('Session on'), findsOneWidget);
      expect(find.text('Nothing new yet'), findsOneWidget);
      expect(src.watching, isTrue);

      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Session paused'), findsOneWidget);
      expect(src.watching, isFalse);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Session on'), findsOneWidget);
      expect(src.watching, isTrue);
    });

    testWidgets('permission refused: explains and offers to ask again', (tester) async {
      final src = FakeSource(perm: CapturePermission.denied)..afterRequest = CapturePermission.denied;
      await startAlbum(tester, src);
      expect(find.text('Needs photo access'), findsOneWidget);
      expect(find.text('Allow photo access'), findsOneWidget);
      expect(find.text('Pause'), findsNothing, reason: 'the fix is the only action');

      src.afterRequest = CapturePermission.granted;
      await tester.tap(find.text('Allow photo access'));
      await tester.pumpAndSettle();
      expect(find.text('Session on'), findsOneWidget);
    });

    testWidgets('permanently refused: sends the user to Settings', (tester) async {
      final src = await startAlbum(tester, FakeSource(perm: CapturePermission.permanentlyDenied));
      expect(find.text('Open Settings'), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(src.settings, 1);
    });

    testWidgets('limited access: says why it would miss screenshots', (tester) async {
      await startAlbum(tester, FakeSource(perm: CapturePermission.limited));
      expect(find.textContaining('would miss new screenshots'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('no capture on this platform: no Pause, no promise to capture', (tester) async {
      await startAlbum(tester, FakeSource(isSupported: false));
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('New screenshots land here automatically'), findsNothing);
    });

    testWidgets('the card meets the 44dp floor in every state', (tester) async {
      final handle = tester.ensureSemantics();
      for (final perm in [CapturePermission.granted, CapturePermission.denied, CapturePermission.limited]) {
        final src = FakeSource(perm: perm)..afterRequest = perm;
        await startAlbum(tester, src);
        expect(_smallTargets(tester), isEmpty, reason: '$perm');
      }
      handle.dispose();
    });
  });

  testWidgets('app start and resume pick the session back up and import waiting shots', (tester) async {
    _setPhone(tester);
    final repo = _memRepo();
    final a = repo.createAlbum('Checkout flow review');
    repo.startSession(a.id); // left over from the last run
    final src = FakeSource(perm: CapturePermission.denied);
    final f = File('${Directory.systemTemp.path}/fluo_ui_resume_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync([9, 9, 9]);
    addTearDown(() => f.deleteSync());
    src.inbox.add(IncomingShot(path: f.path, capturedAt: DateTime(2026, 11, 9)));

    await tester.pumpWidget(FluoApp(repo: repo, source: src));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Needs photo access'), findsOneWidget, reason: 'denied at launch');
    expect(src.watching, isFalse);

    // The user grants access in system Settings and comes back to Fluo.
    src.perm = CapturePermission.granted;
    // Real file copies only complete in the real async zone, so resume there.
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Session on'), findsOneWidget);
    expect(src.watching, isTrue);
    expect(find.text('Review 1 new'), findsOneWidget, reason: 'the waiting screenshot was imported');
  });

  testWidgets('navigation: Triage to Album to Editor', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const TriageScreen()));
    expect(find.text('Triage'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Flow order'), findsOneWidget);
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Pin 1'), findsOneWidget);
  });

  testWidgets('album filter narrows the grid and Grid hides flow numbers', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const AlbumScreen(title: 'Checkout flow review')));
    expect(find.text('Welcome'), findsOneWidget);
    await tester.tap(find.text('Bug 3'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsNothing);
    expect(find.text('Cart'), findsOneWidget);
    await tester.tap(find.text('All 19'));
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('export notice changes when originals are included', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const ExportScreen()));
    expect(find.text('2 redactions are baked in'), findsOneWidget);
    await tester.tap(find.text('Include original screenshots'));
    await tester.pumpAndSettle();
    expect(find.text('Originals still contain what you hid'), findsOneWidget);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Export PDF'), findsOneWidget);
  });

  testWidgets('settings: Wi-Fi row hides when auto-update is off', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const SettingsScreen()));
    expect(find.text('Wi-Fi only'), findsOneWidget);
    await tester.tap(find.text('Auto-update'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi only'), findsNothing);
  });

  group('every tap target is at least 44dp', () {
    final screens = <String, Widget>{
      'Albums': const AlbumsScreen(),
      'Triage': const TriageScreen(),
      'Album': const AlbumScreen(title: 'Checkout flow review'),
      'Editor': const EditorScreen(),
      'Export': const ExportScreen(),
      'Settings': const SettingsScreen(),
    };
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        _setPhone(tester);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(_host(e.value, repo: _seeded()));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_smallTargets(tester), isEmpty);
        expect(_tapNodes, greaterThan(2), reason: 'no tap targets found');
        handle.dispose();
      });
    }
  });
}
