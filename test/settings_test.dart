import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/main.dart';
import 'package:fluo/motion/motion.dart';
import 'package:fluo/screens/settings.dart';
import 'package:fluo/settings/app_settings.dart';
import 'package:fluo/theme/accent.dart';
import 'package:fluo/theme/tokens.dart';
import 'package:fluo/ui/wordmark.dart';
import 'package:fluo/update/update_source.dart' show UpdatePhase;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/fake_source.dart';
import 'support/fake_update.dart';
import 'support/harness.dart';

/// The colour a primary FluoButton is filled with.
Color? buttonFill(WidgetTester t, String label) {
  final box = find.ancestor(of: find.text(label), matching: find.byType(Container)).evaluate().map((e) => e.widget as Container);
  for (final c in box) {
    final d = c.decoration;
    if (d is BoxDecoration && d.color != null) return d.color;
  }
  return null;
}

void main() {
  late FluoRepo repo;

  group('AppSettings', () {
    test('defaults: lime, motion normal, auto-update on, Wi-Fi only on', () {
      repo = memRepo();
      final s = AppSettings(repo);
      expect(s.accent, Accent.lime);
      expect((s.reduceMotion, s.autoUpdate, s.wifiOnly), (false, true, true));
      expect(s.lastUpdateCheck, isNull);
    });

    test('every change is saved and notifies, and a new instance reads it back', () {
      repo = memRepo();
      final s = AppSettings(repo);
      var n = 0;
      s.addListener(() => n++);
      s.setAccent(Accent.violet);
      s.setReduceMotion(true);
      s.setAutoUpdate(false);
      s.setWifiOnly(false);
      s.lastUpdateCheck = DateTime(2026, 11, 9, 10);
      expect(n, 4, reason: 'one notification per real change');
      final again = AppSettings(repo);
      expect(again.accent, Accent.violet);
      expect((again.reduceMotion, again.autoUpdate, again.wifiOnly), (true, false, false));
      expect(again.lastUpdateCheck, DateTime(2026, 11, 9, 10));
    });

    test('setting the same value does nothing', () {
      repo = memRepo();
      final s = AppSettings(repo);
      var n = 0;
      s.addListener(() => n++);
      s.setAccent(Accent.lime);
      s.setReduceMotion(false);
      s.setAutoUpdate(true);
      s.setWifiOnly(true);
      expect(n, 0);
      expect(repo.getSetting('accent'), isNull, reason: 'nothing written either');
    });

    test('an unknown stored theme falls back to lime', () {
      repo = memRepo();
      repo.setSetting('accent', 'chartreuse');
      expect(AppSettings(repo).accent, Accent.lime);
    });

    test('the last check time can be cleared', () {
      repo = memRepo();
      final s = AppSettings(repo)..lastUpdateCheck = DateTime(2026);
      s.lastUpdateCheck = null;
      expect(AppSettings(repo).lastUpdateCheck, isNull);
    });
  });

  group('themes', () {
    test('five themes, lime first, ids unique', () {
      expect(Accent.all.map((a) => a.id), ['lime', 'violet', 'cyan', 'orange', 'pink']);
      expect(Accent.byId('pink'), Accent.pink);
      expect(Accent.byId(null), Accent.lime);
    });

    testWidgets('choosing a theme recolours the whole app at once, and the logo stays lime', (tester) async {
      setPhone(tester);
      repo = memRepo();
      repo.createAlbum('Checkout');
      await tester.pumpWidget(FluoApp(repo: repo, source: FakeSource(), exports: testExports(), reduceMotion: true, splash: Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(buttonFill(tester, 'New album'), Accent.lime.color);

      await tester.tap(find.byIcon(LucideIcons.slidersHorizontal));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      await tester.tap(find.text('Violet'));
      await tester.pumpAndSettle();
      // The screen behind it, which we go back to, is already violet.
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      expect(buttonFill(tester, 'New album'), Accent.violet.color);
      expect(repo.getSetting('accent'), 'violet');
    });

    testWidgets('the choice is remembered after a restart', (tester) async {
      setPhone(tester);
      repo = memRepo();
      repo.createAlbum('Checkout');
      repo.setSetting('accent', 'orange');
      await tester.pumpWidget(FluoApp(repo: repo, source: FakeSource(), exports: testExports(), reduceMotion: true, splash: Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(buttonFill(tester, 'New album'), Accent.orange.color);
    });

    testWidgets('the wordmark and the app icon are lime in every theme', (tester) async {
      for (final a in Accent.all) {
        await tester.pumpWidget(host(const Column(children: [FluoWordmark(), FluoIcon()]), settings: AppSettings(memRepo())..setAccent(a)));
        final texts = tester.widgetList<Text>(find.descendant(of: find.byType(FluoWordmark), matching: find.byType(Text)));
        expect(texts.single.style!.color, FluoColors.lime, reason: a.name);
        final icon = tester.widgetList<Text>(find.descendant(of: find.byType(FluoIcon), matching: find.byType(Text)));
        expect(icon.map((t) => t.style!.color).toSet(), {FluoColors.lime}, reason: a.name);
      }
    });

    testWidgets('the focus ring, selected chips and switches use the chosen accent', (tester) async {
      setPhone(tester);
      repo = memRepo();
      final st = AppSettings(repo)..setAccent(Accent.cyan);
      await tester.pumpWidget(host(const SettingsScreen(), repo: repo, settings: st));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final rings = find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border is Border &&
          ((w.decoration as BoxDecoration).border as Border).top.width == 2 &&
          ((w.decoration as BoxDecoration).border as Border).top.color == Accent.cyan.color);
      expect(rings, findsWidgets);
    });
  });

  group('Settings screen', () {
    Future<AppSettings> open(WidgetTester tester, {FakeUpdateSource? update, bool reduce = true}) async {
      setPhone(tester);
      tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
      repo = memRepo();
      final st = AppSettings(repo);
      await tester.pumpWidget(host(const SettingsScreen(), repo: repo, settings: st, update: update, reduceMotion: reduce));
      await tester.pump();
      return st;
    }

    testWidgets('shows the five themes with the current one marked, and saves a pick', (tester) async {
      final st = await open(tester);
      for (final a in Accent.all) {
        expect(find.text(a.name), findsOneWidget);
      }
      await tester.tap(find.text('Cyan'));
      await tester.pumpAndSettle();
      expect(st.accent, Accent.cyan);
      expect(find.text('Neon lime is the default theme. The FLUO logo stays lime.'), findsOneWidget);
    });

    testWidgets('privacy statement is shown and the bundled font licences open offline', (tester) async {
      await open(tester);
      expect(find.textContaining('Nothing leaves the phone except what you choose to share'), findsOneWidget);
      expect(find.textContaining('SIL Open Font License'), findsWidgets);
      await tester.ensureVisible(find.text('Show font licences'));
      await tester.pump();
      await tester.tap(find.text('Show font licences'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The Lexend Project Authors'), findsOneWidget);
      expect(find.textContaining('The Inter Project Authors'), findsOneWidget);
      expect(find.text('Hide font licences'), findsOneWidget);
    });

    testWidgets('the Reduce motion switch turns motion off app-wide and is saved', (tester) async {
      final st = await open(tester, reduce: false); // the test harness reduces motion unless told not to
      expect(reducedMotionOf(tester), isFalse);
      await tester.tap(find.text('Reduce motion'));
      await tester.pumpAndSettle();
      expect(st.reduceMotion, isTrue);
      expect(repo.getSetting('reduce_motion'), 'true');
    });

    testWidgets('Auto-update off hides the Wi-Fi row and says to check manually', (tester) async {
      final st = await open(tester);
      expect(find.text('Wi-Fi only'), findsOneWidget);
      expect(find.text('Auto-update is on.'), findsOneWidget);
      await tester.tap(find.text('Auto-update'));
      await tester.pumpAndSettle();
      expect(st.autoUpdate, isFalse);
      expect(find.text('Wi-Fi only'), findsNothing);
      expect(find.text('Auto-update is off. Check manually.'), findsOneWidget);
    });

    testWidgets('the Wi-Fi switch is saved', (tester) async {
      final st = await open(tester);
      await tester.tap(find.text('Wi-Fi only'));
      await tester.pumpAndSettle();
      expect(st.wifiOnly, isFalse);
      expect(repo.getSetting('wifi_only'), 'false');
    });

    testWidgets('the real version is shown', (tester) async {
      await open(tester);
      await tester.pump();
      expect(find.text('Version 0.1.0 (1)'), findsOneWidget);
    });

    testWidgets('Check for updates: up to date', (tester) async {
      final src = FakeUpdateSource();
      await open(tester, update: src);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(src.checks, 1);
      expect(find.text('Up to date.'), findsOneWidget);
    });

    testWidgets('an available update offers Download, then shows progress, then Restart', (tester) async {
      final src = FakeUpdateSource()..available = true;
      await open(tester, update: src);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('A new version is available.'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      src.emit(UpdatePhase.downloading);
      await tester.idle(); // let the stream deliver
      await tester.pump();
      expect(find.text('Downloading the update…'), findsOneWidget);
      expect(find.text('Downloading…'), findsOneWidget);
      src.emit(UpdatePhase.downloaded);
      await tester.idle();
      await tester.pump();
      expect(find.text('The update is ready. Restart to finish.'), findsOneWidget);
      await tester.tap(find.text('Restart to update'));
      await tester.pump();
      expect(src.installs, 1);
    });

    testWidgets('a sideloaded copy says updates come through Google Play', (tester) async {
      final src = FakeUpdateSource()..unsupported = true;
      await open(tester, update: src);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Updates come through Google Play'), findsOneWidget);
    });

    testWidgets('a failed check says so and can be retried', (tester) async {
      final src = FakeUpdateSource()..checkError = Exception('offline');
      await open(tester, update: src);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Could not check for updates. Try again later.'), findsOneWidget);
      src.checkError = null;
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Up to date.'), findsOneWidget);
    });
  });
}

/// Whether the screen is being told to reduce motion.
bool reducedMotionOf(WidgetTester t) {
  late bool v;
  final ctx = t.element(find.byType(SettingsScreen));
  v = reducedMotion(ctx);
  return v;
}
