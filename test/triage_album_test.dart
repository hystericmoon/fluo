import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/screens/album.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/triage.dart';
import 'package:fluo/ui/swipe_card.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

void main() {
  group('Triage screen', () {
    testWidgets('shows the first screenshot, its place in the pass and an enabled Keep', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('Checkout flow review');
      await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      expect(find.text('Checkout flow review · 1 of 3'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.byType(SwipeCard), findsOneWidget);
    });

    testWidgets('Undo is disabled until something was decided', (tester) async {
      setPhone(tester);
      final handle = tester.ensureSemantics();
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      expect(tester.getSemantics(find.bySemanticsLabel('Undo last choice')).flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.bySemanticsLabel('Undo last choice')).flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      handle.dispose();
    });

    testWidgets('Keep and Discard buttons sort the shots and move on', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('A · 2 of 3'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('A · 3 of 3'), findsOneWidget);
      expect(repo.getShot(s[0].id)!.status, ShotStatus.kept);
      expect(repo.getShot(s[1].id)!.status, ShotStatus.discarded);
      expect(repo.getShot(s[2].id)!.status, ShotStatus.pending);
    });

    testWidgets('Undo brings the last shot back', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Undo last choice'));
      await tester.pumpAndSettle();
      expect(find.text('A · 1 of 2'), findsOneWidget);
      expect(repo.getShot(s[0].id)!.status, ShotStatus.pending);
    });

    testWidgets('typing a name saves it, and it is back after Undo', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      await tester.enterText(find.byType(TextField), 'Cart');
      expect(repo.getShot(s[0].id)!.name, 'Cart', reason: 'saved as you type');

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).initialValue ?? '', '', reason: 'new shot, empty name');
      await tester.tap(find.bySemanticsLabel('Undo last choice'));
      await tester.pumpAndSettle();
      expect(find.text('Cart'), findsOneWidget, reason: 'the saved name reappears');
    });

    testWidgets('flicking the card right keeps it, left discards it', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));

      await tester.fling(find.byType(SwipeCard), const Offset(300, 0), 1500);
      await tester.pumpAndSettle();
      expect(repo.getShot(s[0].id)!.status, ShotStatus.kept);

      await tester.fling(find.byType(SwipeCard), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(repo.getShot(s[1].id)!.status, ShotStatus.discarded);
      expect(find.text('A · 3 of 3'), findsOneWidget);
    });

    testWidgets('a short slow drag springs back and decides nothing', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      final g = await tester.startGesture(tester.getCenter(find.byType(SwipeCard)));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(repo.getShot(s[0].id)!.status, ShotStatus.pending);
      expect(find.text('A · 1 of 2'), findsOneWidget);
    });

    testWidgets('dragging shows the word and icon for the choice, not only a colour', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      final g = await tester.startGesture(tester.getCenter(find.byType(SwipeCard)));
      await g.moveBy(const Offset(-70, 0));
      await tester.pump();
      expect(find.descendant(of: find.byType(SwipeCard), matching: find.text('Discard')), findsOneWidget);
      await g.moveBy(const Offset(140, 0));
      await tester.pump();
      expect(find.descendant(of: find.byType(SwipeCard), matching: find.text('Keep')), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('screen readers get Keep and Discard as actions on the card', (tester) async {
      setPhone(tester);
      final handle = tester.ensureSemantics();
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^Screenshot 1 of 2')).first);
      expect(node.getSemanticsData().customSemanticsActionIds, isNotNull);
      final labels = [
        for (final id in node.getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label
      ];
      expect(labels, containsAll(['Keep', 'Discard']));
      handle.dispose();
      expect(repo.getShot(s[0].id)!.status, ShotStatus.pending);
    });

    testWidgets('finishing shows "All sorted" with the counts, and Undo still works', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('All sorted'), findsOneWidget);
      expect(find.text('1 kept, 1 discarded'), findsOneWidget);
      expect(find.text('Open album'), findsOneWidget);
      expect(find.byType(SwipeCard), findsNothing);
      await tester.tap(find.bySemanticsLabel('Undo last choice'));
      await tester.pumpAndSettle();
      expect(find.text('All sorted'), findsNothing);
      expect(find.text('A · 2 of 2'), findsOneWidget);
    });

    testWidgets('leaving Triage deletes what was discarded, files included', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      final s = await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.getShot(s[1].id), isNotNull, reason: 'still there while Triage is open, so Undo works');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(repo.getShot(s[1].id), isNull);
      expect(File(s[1].originalPath).existsSync(), isFalse);
      expect(repo.getShot(s[0].id)!.status, ShotStatus.kept);
      expect(repo.getShot(s[2].id)!.status, ShotStatus.pending);
    });

    testWidgets('with motion on, the next card settles into place and then everything is still', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo, reduceMotion: false));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Keep'));
      await tester.pump(); // the next card starts tilted and eases in
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('A · 2 of 3'), findsOneWidget);
    });

    testWidgets('with reduced motion the next card appears at once', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await seedShots(tester, repo, a.id, 3);
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      await tester.tap(find.text('Keep'));
      await tester.pump();
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('A · 2 of 3'), findsOneWidget);
    });

    testWidgets('an album with nothing pending says so', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('A');
      await tester.pumpWidget(host(TriageScreen(albumId: a.id), repo: repo));
      expect(find.text('Nothing to review'), findsOneWidget);
    });

    testWidgets('Done opens the album, and Back from there returns to Albums', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('Checkout');
      repo.startSession(a.id);
      await seedShots(tester, repo, a.id, 1);
      await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
      await tester.tap(find.text('Review 1 new'));
      await tester.pumpAndSettle();
      expect(find.text('Triage'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open album'));
      await tester.pumpAndSettle();
      expect(find.text('Flow order'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back to albums'));
      await tester.pumpAndSettle();
      expect(find.text('Albums'), findsOneWidget, reason: 'Triage was replaced, not stacked');
      expect(find.text('1 screen · Today'), findsOneWidget);
    });
  });

  group('Album screen', () {
    Future<(dynamic, Album, List<Shot>)> kept(WidgetTester tester, int n) async {
      final repo = memRepo();
      final a = repo.createAlbum('Checkout');
      final s = await seedShots(tester, repo, a.id, n);
      for (final x in s) {
        repo.setStatus(x.id, ShotStatus.kept);
      }
      return (repo, a, s);
    }

    testWidgets('lists only kept screens in flow order with numbers and names', (tester) async {
      setPhone(tester);
      final (repo, a, s) = await kept(tester, 3);
      repo.renameShot(s[0].id, 'Welcome');
      repo.renameShot(s[1].id, 'Cart');
      repo.setStatus(s[2].id, ShotStatus.discarded);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Cart'), findsOneWidget);
      expect(find.text('2 screens'), findsOneWidget, reason: 'the discarded shot is not counted');
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('unnamed screens read "Untitled"', (tester) async {
      setPhone(tester);
      final (repo, a, _) = await kept(tester, 1);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('Untitled'), findsOneWidget);
    });

    testWidgets('Grid hides the flow numbers and Flow order shows them', (tester) async {
      setPhone(tester);
      final (repo, a, _) = await kept(tester, 2);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Grid'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
      await tester.tap(find.text('Flow order'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('with no pins the severity filters stay hidden and a plain screen count shows', (tester) async {
      setPhone(tester);
      final (repo, a, _) = await kept(tester, 3);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('3 screens'), findsOneWidget);
      expect(find.textContaining('Bug'), findsNothing);
      expect(find.textContaining('UX'), findsNothing);
      expect(find.textContaining('A11y'), findsNothing);
      expect(find.textContaining('All '), findsNothing);
    });

    testWidgets('severity chips count screens, filter them, and keep the flow numbers', (tester) async {
      setPhone(tester);
      final (repo, a, s) = await kept(tester, 4);
      for (var i = 0; i < 4; i++) {
        repo.renameShot(s[i].id, 'S${i + 1}');
      }
      repo.addPin(s[1].id, Severity.bug, .1, .1);
      repo.addPin(s[1].id, Severity.bug, .2, .2); // two bugs on one screen: counts once
      repo.addPin(s[3].id, Severity.bug, .1, .1);
      repo.addPin(s[2].id, Severity.a11y, .1, .1);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));

      expect(find.text('All 4'), findsOneWidget);
      expect(find.text('Bug 2'), findsOneWidget);
      expect(find.text('UX 0'), findsOneWidget);
      expect(find.text('A11y 1'), findsOneWidget);

      await tester.tap(find.text('Bug 2'));
      await tester.pumpAndSettle();
      expect(find.text('S2'), findsOneWidget);
      expect(find.text('S4'), findsOneWidget);
      expect(find.text('S1'), findsNothing);
      expect(find.text('S3'), findsNothing);
      expect(find.text('4'), findsOneWidget, reason: 'S4 keeps its place in the flow');

      await tester.tap(find.text('UX 0'));
      await tester.pumpAndSettle();
      expect(find.text('No screens with UX pins'), findsOneWidget);

      await tester.tap(find.text('All 4'));
      await tester.pumpAndSettle();
      expect(find.text('S1'), findsOneWidget);
    });

    testWidgets('pin letters show on the tile', (tester) async {
      setPhone(tester);
      final (repo, a, s) = await kept(tester, 1);
      repo.addPin(s[0].id, Severity.ux, .1, .1);
      repo.addPin(s[0].id, Severity.a11y, .1, .1);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('U'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('an empty album explains itself and a pending banner opens Triage', (tester) async {
      setPhone(tester);
      final repo = memRepo();
      final a = repo.createAlbum('Fresh');
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('No screens yet'), findsOneWidget);
      expect(find.text('Flow order'), findsNothing, reason: 'no controls for nothing');

      await seedShots(tester, repo, a.id, 2);
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(find.text('2 new screenshots to review'), findsOneWidget);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Triage'), findsOneWidget);
    });

    testWidgets('Export is off for an empty album', (tester) async {
      setPhone(tester);
      final handle = tester.ensureSemantics();
      final repo = memRepo();
      final a = repo.createAlbum('Fresh');
      await tester.pumpWidget(host(AlbumScreen(albumId: a.id), repo: repo));
      expect(tester.getSemantics(find.bySemanticsLabel('Export')).flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      handle.dispose();
    });
  });

  group('every tap target is at least 44dp, with real shots', () {
    for (final name in ['Triage', 'Triage done', 'Album']) {
      testWidgets(name, (tester) async {
        setPhone(tester);
        final handle = tester.ensureSemantics();
        final repo = memRepo();
        final a = repo.createAlbum('A');
        final s = await seedShots(tester, repo, a.id, 4);
        repo.addPin(s[0].id, Severity.bug, .1, .1);
        Widget page = TriageScreen(albumId: a.id);
        if (name == 'Triage done') {
          for (final x in s) {
            repo.setStatus(x.id, ShotStatus.kept);
          }
        }
        if (name == 'Album') {
          repo.setStatus(s[0].id, ShotStatus.kept);
          repo.setStatus(s[1].id, ShotStatus.kept);
          page = AlbumScreen(albumId: a.id);
        }
        await tester.pumpWidget(host(page, repo: repo));
        await tester.pump(const Duration(milliseconds: 100));
        expect(smallTargets(tester), isEmpty);
        expect(tapNodes, greaterThan(2));
        handle.dispose();
      });
    }
  });

  testWidgets('end to end: a 10-shot session is sorted into an album', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final a = repo.createAlbum('Checkout flow review');
    repo.startSession(a.id);
    final s = await seedShots(tester, repo, a.id, 10);
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));

    expect(find.text('Review 10 new'), findsOneWidget);
    await tester.tap(find.text('Review 10 new'));
    await tester.pumpAndSettle();

    // Keep 1, 2, 4, 5, 7, 9. Discard 3, 6, 8, 10. Mix buttons and flicks.
    // Name the first two. Change mind once on shot 6.
    const keepers = {0, 1, 3, 4, 6, 8};
    for (var i = 0; i < 10; i++) {
      expect(find.text('Checkout flow review · ${i + 1} of 10'), findsOneWidget);
      if (i == 0) await tester.enterText(find.byType(TextField), 'Welcome');
      if (i == 1) await tester.enterText(find.byType(TextField), 'Cart');
      final keep = keepers.contains(i);
      if (i == 5) {
        await tester.tap(find.text('Keep')); // oops
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Undo last choice'));
        await tester.pumpAndSettle();
        expect(find.text('Checkout flow review · 6 of 10'), findsOneWidget);
      }
      if (i.isEven) {
        await tester.tap(find.text(keep ? 'Keep' : 'Discard'));
      } else {
        await tester.fling(find.byType(SwipeCard), Offset(keep ? 300 : -300, 0), 1500);
      }
      await tester.pumpAndSettle();
    }

    expect(find.text('All sorted'), findsOneWidget);
    expect(find.text('6 kept, 4 discarded'), findsOneWidget);
    expect([for (final x in s) repo.getShot(x.id)!.status].where((x) => x == ShotStatus.pending), isEmpty);

    await tester.tap(find.text('Open album'));
    await tester.pumpAndSettle();
    expect(find.text('6 screens'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Untitled'), findsNWidgets(4));
    expect(find.textContaining('new screenshot'), findsNothing, reason: 'nothing is left to review');

    // The same truth through the data layer, as a restart would see it.
    final summary = repo.listAlbums().single;
    expect((summary.keptCount, summary.pendingCount), (6, 0));
    expect(repo.shotsIn(a.id, status: ShotStatus.kept).map((x) => x.id), [for (final i in keepers.toList()..sort()) s[i].id]);
  });
}
