import 'dart:io';

import 'package:flutter/widgets.dart' show EditableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/ui/shared_intake.dart';
import 'package:fluo/screens/albums.dart';

import 'support/fake_source.dart';
import 'support/harness.dart';

void main() {
  IncomingShot shared(FakeSource src, String name) {
    final dir = Directory.systemTemp.createTempSync('fluo_shared_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
    final s = IncomingShot(path: f.path, capturedAt: DateTime(2026, 11, 9, 13));
    src.shared.add(s);
    return s;
  }

  testWidgets('a shared screenshot asks for an album and lands there as a new screen',
      (tester) async {
    final repo = seeded();
    final src = FakeSource();
    shared(src, 'a.png');
    await tester.pumpWidget(host(
      const SharedIntake(child: AlbumsScreen()),
      repo: repo,
      source: src,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Add this screenshot to…'), findsOneWidget);
    await tester.tap(find.text('Onboarding audit').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    final album = repo.listAlbums().firstWhere((a) => a.album.name == 'Onboarding audit');
    expect(repo.shotsIn(album.album.id), hasLength(1));
    expect(src.shared, isEmpty);
  });

  testWidgets('Cancel throws the shared copy away and adds nothing', (tester) async {
    final repo = seeded();
    final src = FakeSource();
    shared(src, 'b.png');
    await tester.pumpWidget(host(
      const SharedIntake(child: AlbumsScreen()),
      repo: repo,
      source: src,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(src.shared, isEmpty);
    for (final a in repo.listAlbums()) {
      expect(repo.shotsIn(a.album.id), isEmpty);
    }
  });

  testWidgets('New album creates one and puts the screenshot in it', (tester) async {
    final repo = seeded();
    final src = FakeSource();
    shared(src, 'c.png');
    await tester.pumpWidget(host(
      const SharedIntake(child: AlbumsScreen()),
      repo: repo,
      source: src,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New album').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Fresh');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    final fresh = repo.listAlbums().firstWhere((a) => a.album.name == 'Fresh');
    expect(repo.shotsIn(fresh.album.id), hasLength(1));
    expect(repo.activeSession(), isNull); // sharing does not start a session
  });
}
