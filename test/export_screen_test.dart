import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/screens/export.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:fluo/ui/kit.dart' show fluoRoute;
import 'support/fake_share.dart';
import 'support/harness.dart';

void main() {
  late FluoRepo repo;
  late Album album;
  late List<Shot> shots;
  late FakeShare share;

  /// A kept album: 3 screens, 2 pins, [redactions] redactions.
  Future<void> setup(WidgetTester tester, {int redactions = 1, int n = 3}) async {
    setPhone(tester);
    // Tall enough to see the whole screen, so taps do not land below the fold.
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    repo = memRepo();
    share = FakeShare();
    album = repo.createAlbum('Checkout');
    shots = await seedKeptPngShots(tester, repo, album.id, n);
    if (n >= 1) {
      repo.renameShot(shots[0].id, 'Cart');
      repo.addPin(shots[0].id, Severity.bug, .5, .5, note: 'Wrong total');
      repo.addPin(shots[0].id, Severity.ux, .2, .2);
    }
    for (var i = 0; i < redactions; i++) {
      repo.addAnnotation(shots[0].id, AnnotationKind.redact, {'rect': [.1, .1 + i * .2, .5, .2 + i * .2]});
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host(ExportScreen(albumId: album.id), repo: repo, exports: testExports(share)));
  }

  /// Real file work happens in the real async zone; give it time and pump.
  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 20));
      if (until != null && until()) break;
    }
    await tester.pump();
  }

  group('what it shows', () {
    testWidgets('real counts and the default choices', (tester) async {
      await setup(tester);
      await open(tester);
      expect(find.text('Checkout · 3 screens · 2 pins'), findsOneWidget);
      expect(find.text('Claude pack'), findsOneWidget);
      expect(find.text('Best for Claude'), findsOneWidget);
      expect(find.text('Export Claude pack'), findsOneWidget);
    });

    testWidgets('redactions are counted and described as baked in', (tester) async {
      await setup(tester, redactions: 2);
      await open(tester);
      expect(find.text('2 redactions are baked in'), findsOneWidget);
      expect(find.text('Exported images show them as solid blocks. The hidden content is not included.'), findsOneWidget);
    });

    testWidgets('with nothing redacted it says so rather than claiming a redaction', (tester) async {
      await setup(tester, redactions: 0);
      await open(tester);
      expect(find.text('Nothing is hidden'), findsOneWidget);
      expect(find.textContaining('redaction is baked in'), findsNothing);
      expect(find.textContaining('redactions are baked in'), findsNothing);
    });

    testWidgets('including originals warns loudly when something was hidden', (tester) async {
      await setup(tester, redactions: 1);
      await open(tester);
      await tester.tap(find.text('Include original screenshots'));
      await tester.pumpAndSettle();
      expect(find.text('Originals still contain what you hid'), findsOneWidget);
      expect(find.textContaining('show the hidden content'), findsOneWidget);
    });

    testWidgets('including originals with nothing hidden is just stated', (tester) async {
      await setup(tester, redactions: 0);
      await open(tester);
      await tester.tap(find.text('Include original screenshots'));
      await tester.pumpAndSettle();
      expect(find.text('Originals are included'), findsOneWidget);
      expect(find.text('Originals still contain what you hid'), findsNothing);
    });

    testWidgets('the action label follows the format', (tester) async {
      await setup(tester);
      await open(tester);
      for (final (card, label) in [('PDF', 'Export PDF'), ('Long image', 'Export long image')]) {
        await tester.tap(find.text(card));
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Share images'));
      await tester.pumpAndSettle();
      expect(find.text('Share images'), findsNWidgets(2), reason: 'the card and the button');
    });
  });

  group('options that do not apply', () {
    testWidgets('PDF and long image cannot include originals, and the notice does not claim they do', (tester) async {
      await setup(tester, redactions: 1);
      await open(tester);
      await tester.tap(find.text('Include original screenshots')); // on, for the Claude pack
      await tester.pumpAndSettle();
      expect(find.text('Originals still contain what you hid'), findsOneWidget);

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Originals still contain what you hid'), findsNothing,
          reason: 'a PDF carries no originals, whatever the switch says');
      expect(find.text('1 redaction is baked in'), findsOneWidget);
      expect(find.textContaining('Not used for PDF'), findsOneWidget);
      // Tapping the disabled switch changes nothing.
      await tester.tap(find.text('Include original screenshots'));
      await tester.pumpAndSettle();
      expect(find.text('1 redaction is baked in'), findsOneWidget);

      await tester.tap(find.text('Claude pack'));
      await tester.pumpAndSettle();
      expect(find.text('Originals still contain what you hid'), findsOneWidget, reason: 'the choice was remembered');
    });

    testWidgets('the brief is for the Claude pack and the PDF only', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('Long image'));
      await tester.pumpAndSettle();
      expect(find.text('Not used for Long image.'), findsOneWidget);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('A short summary of what to look at, at the start.'), findsOneWidget);
    });
  });

  group('exporting', () {
    testWidgets('Claude pack: builds the ZIP, shares it once, and returns to ready', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('Export Claude pack'));
      await tester.pump();
      expect(find.textContaining('Exporting'), findsOneWidget);
      await settle(tester, until: () => share.shared.isNotEmpty);

      expect(share.shared, hasLength(1));
      final f = share.shared.single.files.single;
      expect(f.name, 'fluo-checkout-review.zip');
      final names = ZipDecoder().decodeBytes(File(f.path).readAsBytesSync()).files.map((x) => x.name).toList();
      expect(names, ['review.md', 'images/01-cart.png', 'images/02-screen.png', 'images/03-screen.png']);
      expect(find.text('Export Claude pack'), findsOneWidget, reason: 'ready for another go');
    });

    testWidgets('originals go in only when the switch was on', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('Include original screenshots'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export Claude pack'));
      await settle(tester, until: () => share.shared.isNotEmpty);
      final names = ZipDecoder().decodeBytes(File(share.shared.single.files.single.path).readAsBytesSync()).files.map((x) => x.name);
      expect(names.where((n) => n.startsWith('originals/')), hasLength(3));
    });

    testWidgets('a PDF and a long image can be exported too', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await settle(tester, until: () => share.shared.isNotEmpty);
      expect(share.shared.single.files.single.mime, 'application/pdf');

      await tester.tap(find.text('Long image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export long image'));
      await settle(tester, until: () => share.shared.length == 2);
      expect(share.shared.last.files.first.mime, 'image/png');
    });

    testWidgets('a failure shows a plain message, shares nothing and lets you try again', (tester) async {
      await setup(tester);
      share.failWith = Exception('share sheet unavailable');
      await open(tester);
      await tester.tap(find.text('Export Claude pack'));
      await settle(tester, until: () => find.textContaining('Could not export').evaluate().isNotEmpty);
      expect(find.textContaining('Could not export. Nothing was shared.'), findsOneWidget);
      expect(find.text('Export Claude pack'), findsOneWidget);
      expect(share.shared, isEmpty);

      share.failWith = null;
      await tester.tap(find.text('Export Claude pack'));
      await settle(tester, until: () => share.shared.isNotEmpty);
      expect(share.shared, hasLength(1));
      expect(find.textContaining('Could not export'), findsNothing, reason: 'the message clears on a new attempt');
    });

    testWidgets('a second tap while exporting does nothing', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('Export Claude pack'));
      await tester.pump();
      await tester.tap(find.textContaining('Exporting'), warnIfMissed: false);
      await tester.pump();
      await settle(tester, until: () => share.shared.isNotEmpty);
      await settle(tester);
      expect(share.shared, hasLength(1));
    });

    testWidgets('formats cannot be switched mid-export', (tester) async {
      await setup(tester);
      await open(tester);
      await tester.tap(find.text('Export Claude pack'));
      await tester.pump();
      await tester.tap(find.text('PDF'), warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('Exporting'), findsOneWidget);
      await settle(tester, until: () => share.shared.isNotEmpty);
      expect(share.shared.single.files.single.name, endsWith('.zip'));
    });

    testWidgets('an album with no kept screens cannot be exported', (tester) async {
      setPhone(tester);
      repo = memRepo();
      share = FakeShare();
      album = repo.createAlbum('Empty');
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(find.text('Empty · 0 screens · 0 pins'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Export Claude pack')).flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      handle.dispose();
    });
  });

  testWidgets('every tap target is at least 44dp, with originals on and off', (tester) async {
    await setup(tester);
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(smallTargets(tester), isEmpty);
    expect(tapNodes, greaterThan(5));
    await tester.tap(find.text('Include original screenshots'));
    await tester.pumpAndSettle();
    expect(smallTargets(tester), isEmpty);
    handle.dispose();
  });

  testWidgets('Close goes back', (tester) async {
    await setup(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const Text('home'), repo: repo));
    tester.state<NavigatorState>(find.byType(Navigator)).push(fluoRoute(ExportScreen(albumId: album.id)));
    await tester.pumpAndSettle();
    expect(find.text('Export album'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close export'));
    await tester.pumpAndSettle();
    expect(find.text('Export album'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    handle.dispose();
  });
}
