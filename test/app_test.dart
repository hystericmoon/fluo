import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/main.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/export.dart';
import 'package:fluo/screens/settings.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/fake_source.dart';
import 'support/harness.dart';

void main() {
  testWidgets('splash then an empty Albums screen on a fresh install', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(FluoApp(repo: memRepo(), source: FakeSource()));
    expect(find.text('FLUO'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('No albums yet'), findsOneWidget);
    expect(find.text('Review 7 new'), findsNothing);
  });

  testWidgets('starting the app clears discarded screenshots left over from a cut-short visit', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final a = repo.createAlbum('A');
    final s = await seedShots(tester, repo, a.id, 2);
    repo.setStatus(s[0].id, ShotStatus.discarded);
    await tester.pumpWidget(FluoApp(repo: repo, source: FakeSource()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(repo.getShot(s[0].id), isNull);
    expect(File(s[0].originalPath).existsSync(), isFalse);
    expect(repo.getShot(s[1].id), isNotNull);
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('Albums lists real albums with screen counts and dates', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(host(AlbumsScreen(now: fixedNow), repo: seeded()));
    expect(find.text('Checkout flow review'), findsOneWidget);
    expect(find.text('0 screens · Today'), findsOneWidget);
    expect(find.text('Onboarding audit'), findsOneWidget);
    expect(find.text('0 screens · Oct 20'), findsOneWidget);
  });

  testWidgets('New album asks for a name, creates it and refuses a blank name', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
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
    setPhone(tester);
    final repo = memRepo();
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.listAlbums(), isEmpty);
  });

  testWidgets('session card counts pending screenshots and only shows with a session', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final a = repo.createAlbum('Checkout flow review');
    final f = File('${Directory.systemTemp.path}/fluo_ui_shot_${DateTime.now().microsecondsSinceEpoch}.png')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => f.deleteSync());
    await tester.runAsync(() async {
      await repo.addShot(a.id, f);
      await repo.addShot(a.id, f);
    });

    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
    expect(find.text('Session on'), findsNothing, reason: 'pending shots alone are not a session');
    expect(find.text('Review 2 new'), findsNothing);

    repo.startSession(a.id);
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
    expect(find.text('Review 2 new'), findsOneWidget);
  });

  testWidgets('before the first access check the card is neutral, not a false warning', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final a = repo.createAlbum('Checkout');
    repo.startSession(a.id); // status is still "off": sync has not run
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
    expect(find.text('Needs photo access'), findsNothing);
    expect(find.text('Checking photo access…'), findsOneWidget);
  });

  group('session card states', () {
    Future<FakeSource> startAlbum(WidgetTester tester, FakeSource src) async {
      setPhone(tester);
      await tester.pumpWidget(host(const AlbumsScreen(), source: src));
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
        expect(smallTargets(tester), isEmpty, reason: '$perm');
      }
      handle.dispose();
    });
  });

  testWidgets('app start and resume pick the session back up and import waiting shots', (tester) async {
    setPhone(tester);
    final repo = memRepo();
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

  testWidgets('export notice changes when originals are included', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(host(const ExportScreen()));
    expect(find.text('2 redactions are baked in'), findsOneWidget);
    await tester.tap(find.text('Include original screenshots'));
    await tester.pumpAndSettle();
    expect(find.text('Originals still contain what you hid'), findsOneWidget);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Export PDF'), findsOneWidget);
  });

  testWidgets('settings: Wi-Fi row hides when auto-update is off', (tester) async {
    setPhone(tester);
    await tester.pumpWidget(host(const SettingsScreen()));
    expect(find.text('Wi-Fi only'), findsOneWidget);
    await tester.tap(find.text('Auto-update'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi only'), findsNothing);
  });

  group('every tap target is at least 44dp', () {
    final screens = <String, Widget>{
      // Triage, Album and Editor need real shots: see their own test files.
      'Albums': const AlbumsScreen(),
      'Export': const ExportScreen(),
      'Settings': const SettingsScreen(),
    };
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        setPhone(tester);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(e.value, repo: seeded()));
        await tester.pump(const Duration(milliseconds: 100));
        expect(smallTargets(tester), isEmpty);
        expect(tapNodes, greaterThan(2), reason: 'no tap targets found');
        handle.dispose();
      });
    }
  });
}
