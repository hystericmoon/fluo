import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/main.dart';
import 'package:fluo/screens/album.dart';
import 'package:fluo/screens/albums.dart';
import 'package:fluo/screens/editor.dart';
import 'package:fluo/screens/export.dart';
import 'package:fluo/screens/settings.dart';
import 'package:fluo/screens/triage.dart';
import 'package:fluo/theme/app_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Widget _host(Widget home) => ShadcnApp(
      debugShowCheckedModeBanner: false,
      theme: fluoTheme(),
      home: home,
    );

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
  testWidgets('splash then Albums with session card and list', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const FluoApp());
    expect(find.text('FLUO'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Review 7 new'), findsOneWidget);
    expect(find.text('Onboarding audit'), findsOneWidget);
  });

  testWidgets('empty Albums shows the empty state', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const AlbumsScreen(albums: [])));
    expect(find.text('No albums yet'), findsOneWidget);
  });

  testWidgets('navigation: Albums to Triage to Album to Editor, and Export', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(_host(const AlbumsScreen()));
    await tester.tap(find.text('Review 7 new'));
    await tester.pumpAndSettle();
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
        await tester.pumpWidget(_host(e.value));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_smallTargets(tester), isEmpty);
        expect(_tapNodes, greaterThan(2), reason: 'no tap targets found');
        handle.dispose();
      });
    }
  });
}
