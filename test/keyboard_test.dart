import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/editor.dart';
import 'package:fluo/screens/triage.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

/// The on-screen keyboard is not part of the layout by itself: Flutter only
/// reports its height. These tests raise a 323dp keyboard (a typical phone
/// keyboard with its suggestion strip) and check that a focused field, and the
/// buttons that go with it, stay above it.
void main() {
  const keyboard = 323.0;
  const screenHeight = 844.0;
  const keyboardTop = screenHeight - keyboard;

  void raiseKeyboard(WidgetTester t) {
    t.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
    addTearDown(t.view.resetViewInsets);
  }

  testWidgets('Triage keeps the name field and the Keep and Discard buttons above the keyboard', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    await seedShots(tester, repo, album.id, 3);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    final cardBefore = tester.getSize(find.byKey(const ValueKey('triage-card'))).height;

    raiseKeyboard(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(keyboardTop));
    for (final label in ['Keep', 'Discard']) {
      expect(tester.getRect(find.text(label)).bottom, lessThanOrEqualTo(keyboardTop), reason: label);
    }
    // The card gives up height; the controls do not move off screen.
    final cardAfter = tester.getSize(find.byKey(const ValueKey('triage-card'))).height;
    expect(cardAfter, lessThan(cardBefore));
    expect(cardAfter, greaterThanOrEqualTo(180));
  });

  testWidgets('Triage uses the full 500dp card when nothing covers the screen', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    await seedShots(tester, repo, album.id, 2);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('triage-card'))).height, lessThanOrEqualTo(500));
    expect(tester.getRect(find.text('Keep')).bottom, lessThanOrEqualTo(screenHeight));
  });

  testWidgets('the editor caption field stays above the keyboard', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Checkout');
    final shot = (await seedKeptPngShots(tester, repo, album.id, 1)).first;
    await tester.pumpWidget(host(EditorScreen(shotId: shot.id), repo: repo));
    for (var i = 0; i < 20 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    raiseKeyboard(tester);
    await tester.ensureVisible(find.byType(TextField));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(keyboardTop));
  });

  testWidgets('the New album dialog stays above the keyboard', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    await tester.pumpWidget(host(const AlbumsScreen(), repo: repo));
    await tester.pumpAndSettle();
    raiseKeyboard(tester);
    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(keyboardTop));
    expect(tester.getRect(find.text('Create')).bottom, lessThanOrEqualTo(keyboardTop));
  });

  testWidgets('the keyboard action key keeps the shot, goes to the next card and keeps the keyboard up', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    final shots = await seedShots(tester, repo, album.id, 3);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse, reason: 'opening Triage does not raise the keyboard');

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Cart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo.getShot(shots[0].id)!.status, ShotStatus.kept);
    expect(repo.getShot(shots[0].id)!.name, 'Cart');
    expect(find.textContaining('2 of 3'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue, reason: 'the next name field is already focused');

    // Type, enter, type, enter.
    await tester.enterText(find.byType(TextField), 'Pay');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.getShot(shots[1].id)!.name, 'Pay');
    expect(find.textContaining('3 of 3'), findsOneWidget);
  });

  testWidgets('the hint under the buttons says which way keeps and which discards', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    await seedShots(tester, repo, album.id, 1);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    expect(find.text('Flick right to keep, left to discard, or use the buttons'), findsOneWidget);
  });

  testWidgets('keeping with the button does not raise the keyboard on the next card', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    await seedShots(tester, repo, album.id, 2);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 2'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('keeping the last shot with the keyboard action key lands on All sorted', (tester) async {
    setPhone(tester);
    final repo = memRepo();
    final album = repo.createAlbum('Adwam S2');
    await seedShots(tester, repo, album.id, 1);
    await tester.pumpWidget(host(TriageScreen(albumId: album.id), repo: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Open album'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
