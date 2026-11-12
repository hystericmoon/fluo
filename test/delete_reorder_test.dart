import 'dart:io';

import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/main.dart';
import 'package:fluo/screens/album.dart';
import 'package:fluo/screens/albums.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/fake_source.dart';
import 'support/harness.dart';

void main() {
  late FluoRepo repo;

  Future<Album> album(WidgetTester tester, String name, {int shots = 0}) async {
    final a = repo.createAlbum(name, now: DateTime.now());
    if (shots > 0) await seedKeptPngShots(tester, repo, a.id, shots);
    return a;
  }

  Future<void> openAlbums(WidgetTester tester, {FakeSource? source, bool reduce = true}) async {
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo, source: source, reduceMotion: reduce));
  }

  setUp(() {});

  group('deleting an album from the list', () {
    testWidgets('a swipe hides it and offers Undo; Undo brings it back untouched', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout', shots: 2);
      await album(tester, 'Onboarding');
      await openAlbums(tester);

      await tester.fling(find.text('Checkout'), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Checkout'), findsNothing);
      expect(find.textContaining('Deleted Checkout'), findsOneWidget);
      expect(find.text('Onboarding'), findsOneWidget);
      expect(repo.getAlbum(a.id), isNotNull, reason: 'not deleted yet: the fuse is burning');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Checkout'), findsOneWidget);
      expect(find.textContaining('Deleted'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.getAlbum(a.id), isNotNull);
      expect(repo.shotsIn(a.id), hasLength(2));
    });

    testWidgets('when the fuse burns the album, its shots and their files are really gone', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout', shots: 2);
      final files = [for (final s in repo.shotsIn(a.id)) s.originalPath];
      await openAlbums(tester);
      await tester.fling(find.text('Checkout'), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.getAlbum(a.id), isNull);
      expect(repo.shotsIn(a.id), isEmpty);
      for (final f in files) {
        expect(File(f).existsSync(), isFalse);
      }
      expect(find.textContaining('Deleted'), findsNothing, reason: 'the bar goes away with it');
      expect(find.text('No albums yet'), findsOneWidget);
    });

    testWidgets('a second delete finishes the first one straight away', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'First');
      final b = await album(tester, 'Second');
      await openAlbums(tester);
      await tester.fling(find.text('First'), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.fling(find.text('Second'), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.getAlbum(a.id), isNull, reason: 'the first is final now');
      expect(repo.getAlbum(b.id), isNotNull, reason: 'the second can still be undone');
      expect(find.textContaining('Deleted Second'), findsOneWidget);
    });

    testWidgets('deleting the album a session is capturing into ends the session', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final src = FakeSource();
      final a = await album(tester, 'Checkout');
      repo.startSession(a.id);
      await openAlbums(tester, source: src);
      await tester.fling(find.text('Checkout').last, const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Active session'), findsNothing, reason: 'its card goes with it');
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.activeSession(), isNull);
      expect(src.watching, isFalse);
    });

    testWidgets('leaving the screen before the fuse burns keeps the album (the safe way to fail)', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout');
      await openAlbums(tester);
      await tester.fling(find.text('Checkout'), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(repo.getAlbum(a.id), isNotNull);
    });

    testWidgets('screen readers delete with the row\'s "Delete album" action, with the same Undo', (tester) async {
      setPhone(tester);
      final handle = tester.ensureSemantics();
      repo = memRepo();
      await album(tester, 'Checkout');
      await openAlbums(tester);
      final row = find.bySemanticsLabel(RegExp('^Checkout, '));
      final data = tester.getSemantics(row).getSemanticsData();
      final labels = [for (final id in data.customSemanticsActionIds ?? <int>[]) CustomSemanticsAction.getAction(id)!.label ?? ''];
      expect(labels, contains('Delete album'));
      tester.semantics.performAction(find.semantics.byLabel(RegExp('^Checkout, ')), SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Delete album')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Deleted Checkout'), findsWidgets);
      handle.dispose();
    });
  });

  /// Opens the menu in the album header that holds Delete.
  Future<void> openAlbumOptions(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Album options'));
    await tester.pumpAndSettle();
  }

  group('deleting from inside an album (the button route)', () {
    Future<void> openThroughAlbums(WidgetTester tester, String name) async {
      await openAlbums(tester);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('hold-to-delete hands over to Albums, which shows the same Undo bar', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout', shots: 1);
      await openThroughAlbums(tester, 'Checkout');
      expect(find.text('Hold to delete album'), findsNothing, reason: 'delete lives in the Album options menu, away from the grid');
      await openAlbumOptions(tester);
      expect(find.text('Hold to delete album'), findsOneWidget);

      // Without holding: tap to arm, tap to confirm.
      await tester.tap(find.text('Hold to delete album'));
      await tester.pump();
      expect(find.text('Tap again to confirm'), findsOneWidget);
      expect(repo.getAlbum(a.id), isNotNull);
      await tester.tap(find.text('Tap again to confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // the menu closes
      await tester.pump(const Duration(milliseconds: 400)); // then the album screen

      expect(find.text('Albums'), findsOneWidget, reason: 'back on the list');
      expect(find.textContaining('Deleted Checkout'), findsOneWidget);
      expect(repo.getAlbum(a.id), isNotNull, reason: 'still undoable');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Checkout'), findsOneWidget);
    });

    testWidgets('actually holding works too', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout', shots: 1);
      await openThroughAlbums(tester, 'Checkout');
      await openAlbumOptions(tester);
      final g = await tester.startGesture(tester.getCenter(find.text('Hold to delete album')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Deleted Checkout'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.getAlbum(a.id), isNull);
    });

    testWidgets('an empty album can be deleted too', (tester) async {
      setPhone(tester);
      repo = memRepo();
      await album(tester, 'Empty');
      await openThroughAlbums(tester, 'Empty');
      expect(find.text('No screens yet'), findsOneWidget);
      await openAlbumOptions(tester);
      expect(find.text('Hold to delete album'), findsOneWidget);
    });

    testWidgets('Close leaves the album alone', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout', shots: 1);
      await openThroughAlbums(tester, 'Checkout');
      await openAlbumOptions(tester);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Hold to delete album'), findsNothing);
      expect(find.bySemanticsLabel('Album options'), findsOneWidget, reason: 'back on the album, with its menu button');
      expect(repo.getAlbum(a.id), isNotNull);
    });
  });

  group('reordering screens', () {
    Future<List<Shot>> setupAlbum(WidgetTester tester, {int n = 3}) async {
      setPhone(tester);
      repo = memRepo();
      final a = repo.createAlbum('Checkout');
      final s = await seedKeptPngShots(tester, repo, a.id, n);
      for (var i = 0; i < s.length; i++) {
        repo.renameShot(s[i].id, 'S${i + 1}');
      }
      return s;
    }

    List<String> order() => [for (final x in repo.shotsIn(repo.listAlbums().single.album.id, status: ShotStatus.kept)) x.name];

    testWidgets('Reorder screens shows move buttons on every tile; the ends have one disabled', (tester) async {
      final handle = tester.ensureSemantics();
      final s = await setupAlbum(tester);
      await tester.pumpWidget(host(AlbumScreen(albumId: repo.listAlbums().single.album.id), repo: repo));
      expect(find.bySemanticsLabel(RegExp('^Move s1')), findsNothing);
      await tester.tap(find.text('Reorder screens'));
      await tester.pumpAndSettle();
      expect(find.text('Done reordering'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Move s1 earlier')).flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Move s1 later')).flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Move s3 later')).flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(s, hasLength(3));
      handle.dispose();
    });

    testWidgets('Move later and Move earlier change the order, the numbers and the database', (tester) async {
      await setupAlbum(tester);
      await tester.pumpWidget(host(AlbumScreen(albumId: repo.listAlbums().single.album.id), repo: repo));
      await tester.tap(find.text('Reorder screens'));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Move s1 later'));
      await tester.pumpAndSettle();
      expect(order(), ['S2', 'S1', 'S3']);
      await tester.tap(find.bySemanticsLabel('Move s3 earlier'));
      await tester.pumpAndSettle();
      expect(order(), ['S2', 'S3', 'S1']);
      handle.dispose();
    });

    testWidgets('TalkBack gets Move earlier and Move later as actions on each tile, without reorder mode', (tester) async {
      await setupAlbum(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(AlbumScreen(albumId: repo.listAlbums().single.album.id), repo: repo));
      List<String> actions(String label) => [
            for (final id in tester.getSemantics(find.bySemanticsLabel(RegExp(label))).getSemanticsData().customSemanticsActionIds ?? <int>[])
              CustomSemanticsAction.getAction(id)!.label ?? ''
          ];
      expect(actions('^Screen 1: S1'), ['Move later'], reason: 'the first cannot move earlier');
      expect(actions('^Screen 2: S2'), unorderedEquals(['Move earlier', 'Move later']));
      expect(actions('^Screen 3: S3'), ['Move earlier']);
      tester.semantics.performAction(find.semantics.byLabel(RegExp('^Screen 2: S2')), SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Move earlier')));
      await tester.pumpAndSettle();
      expect(order(), ['S2', 'S1', 'S3']);
      handle.dispose();
    });

    testWidgets('no reorder in Grid mode, with a filter on, or for a single screen', (tester) async {
      final s = await setupAlbum(tester);
      repo.addPin(s[0].id, Severity.bug, .5, .5);
      final id = repo.listAlbums().single.album.id;
      await tester.pumpWidget(host(AlbumScreen(albumId: id), repo: repo));
      expect(find.text('Reorder screens'), findsOneWidget);
      await tester.tap(find.text('Bug 1'));
      await tester.pumpAndSettle();
      expect(find.text('Reorder screens'), findsNothing, reason: 'numbers would not match positions');
      await tester.tap(find.text('All 3'));
      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      expect(find.text('Reorder screens'), findsNothing);
    });

    testWidgets('a single screen has nothing to reorder', (tester) async {
      await setupAlbum(tester, n: 1);
      await tester.pumpWidget(host(AlbumScreen(albumId: repo.listAlbums().single.album.id), repo: repo));
      expect(find.text('Reorder screens'), findsNothing);
    });

    testWidgets('the new order is what an export uses', (tester) async {
      await setupAlbum(tester);
      final id = repo.listAlbums().single.album.id;
      repo.moveKept(id, repo.shotsIn(id).first.id, 1);
      expect(order(), ['S2', 'S1', 'S3']);
    });
  });

  group('the live border on the session card', () {
    Future<void> openApp(WidgetTester tester, {required bool reduce}) async {
      setPhone(tester);
      repo = memRepo();
      final a = await album(tester, 'Checkout');
      repo.startSession(a.id);
      await tester.pumpWidget(FluoApp(
        repo: repo,
        source: FakeSource(),
        exports: testExports(),
        reduceMotion: reduce,
        splash: Duration.zero,
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('animates while a session is on, when motion is allowed', (tester) async {
      await openApp(tester, reduce: false);
      expect(find.text('Session on'), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('is a still border when motion is reduced', (tester) async {
      await openApp(tester, reduce: true);
      expect(find.text('Session on'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('stops when the session is paused', (tester) async {
      await openApp(tester, reduce: false);
      await tester.tap(find.text('Pause'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Session paused'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
