import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/motion/fuse.dart';
import 'package:fluo/motion/hold_button.dart';
import 'package:fluo/motion/motion.dart';
import 'package:fluo/motion/star_border.dart';
import 'package:fluo/motion/swipe_row.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'support/harness.dart';

Widget wrap(Widget child, {bool reduce = false, bool assistive = false}) => host(
      MediaQuery(
        data: MediaQueryData(accessibleNavigation: assistive),
        child: Center(child: SizedBox(width: 320, child: child)),
      ),
      reduceMotion: reduce,
    );

void main() {
  group('reducedMotion', () {
    testWidgets('is on for the system setting or the in-app switch, off otherwise', (tester) async {
      late bool a, b, c;
      Widget probe(void Function(bool) out) => Builder(builder: (ctx) {
            out(reducedMotion(ctx));
            return const SizedBox();
          });
      await tester.pumpWidget(MotionScope(reduce: false, child: probe((v) => a = v)));
      await tester.pumpWidget(MotionScope(reduce: true, child: probe((v) => b = v)));
      await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(disableAnimations: true), child: MotionScope(reduce: false, child: probe((v) => c = v))));
      expect((a, b, c), (false, true, true));
    });
  });

  group('HoldButton', () {
    testWidgets('holding for long enough confirms, once', (tester) async {
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++)));
      final g = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump(); // the ticker's first frame is its time zero
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Keep holding…'), findsOneWidget);
      expect(n, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(n, 1);
      await tester.pump(const Duration(seconds: 2)); // still holding: no second fire
      await g.up();
      await tester.pump();
      expect(n, 1);
      expect(find.text('Hold to delete'), findsOneWidget);
    });

    testWidgets('letting go part-way does nothing', (tester) async {
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++)));
      final g = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump(); // the ticker's first frame is its time zero
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pump(const Duration(seconds: 5));
      expect(n, 0);
      expect(find.text('Hold to delete'), findsOneWidget, reason: 'not armed either');
    });

    testWidgets('without holding: tap once to arm, tap again to confirm', (tester) async {
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++)));
      await tester.tap(find.byType(HoldButton));
      await tester.pump();
      expect(find.text('Tap again to confirm'), findsOneWidget);
      expect(n, 0);
      await tester.tap(find.byType(HoldButton));
      await tester.pump();
      expect(n, 1);
      expect(find.text('Hold to delete'), findsOneWidget, reason: 'back to normal');
    });

    testWidgets('an armed button disarms after a few seconds', (tester) async {
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++)));
      await tester.tap(find.byType(HoldButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Hold to delete'), findsOneWidget);
      await tester.tap(find.byType(HoldButton)); // arms again, does not confirm
      await tester.pump();
      expect(n, 0);
    });

    testWidgets('a screen reader double-tap works as the same two steps, and says so', (tester) async {
      final handle = tester.ensureSemantics();
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++)));
      expect(tester.getSemantics(find.bySemanticsLabel('Hold to delete')).hint, contains('tap twice'));
      tester.semantics.tap(find.semantics.byLabel('Hold to delete'));
      await tester.pump();
      expect(n, 0);
      expect(find.bySemanticsLabel('Confirm: Hold to delete'), findsOneWidget, reason: 'announced as a live region');
      tester.semantics.tap(find.semantics.byLabel('Confirm: Hold to delete'));
      await tester.pump();
      expect(n, 1);
      handle.dispose();
    });

    testWidgets('reduced motion: no filling animation, but the hold is still required', (tester) async {
      var n = 0;
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () => n++), reduce: true));
      final g = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump(); // the ticker's first frame is its time zero
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FractionallySizedBox), findsNothing, reason: 'no fill to watch');
      expect(find.text('Keep holding…'), findsOneWidget);
      expect(n, 0);
      await tester.pump(const Duration(milliseconds: 600));
      expect(n, 1);
      await g.up();
    });

    testWidgets('with motion, a fill grows while holding', (tester) async {
      await tester.pumpWidget(wrap(HoldButton(label: 'Hold to delete', onConfirmed: () {})));
      final g = await tester.startGesture(tester.getCenter(find.byType(HoldButton)));
      await tester.pump(); // the ticker's first frame is its time zero
      await tester.pump(const Duration(milliseconds: 450));
      final w = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor!;
      expect(w, closeTo(0.5, 0.1));
      await g.up();
      await tester.pump();
    });
  });

  group('SwipeRow', () {
    Widget row(void Function() onDelete, {bool reduce = false}) =>
        wrap(SwipeRow(actionLabel: 'Delete album', onDelete: onDelete, child: Container(height: 80, color: const Color(0xFF222222), child: const Text('Row'))), reduce: reduce);

    testWidgets('a long swipe left deletes after sliding away', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      await tester.drag(find.byType(SwipeRow), const Offset(-200, 0));
      await tester.pump();
      expect(find.text('Delete album'), findsOneWidget, reason: 'the action shows while swiping: words and an icon');
      await tester.pumpAndSettle();
      expect(n, 1);
    });

    testWidgets('a quick flick deletes even when short', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      await tester.fling(find.byType(SwipeRow), const Offset(-60, 0), 2500);
      await tester.pumpAndSettle();
      expect(n, 1);
    });

    testWidgets('a short slow swipe springs back and deletes nothing', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      final before = tester.getTopLeft(find.text('Row'));
      await tester.drag(find.byType(SwipeRow), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(n, 0);
      expect(tester.getTopLeft(find.text('Row')), before);
    });

    testWidgets('swiping right does nothing', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      await tester.drag(find.byType(SwipeRow), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(n, 0);
    });

    testWidgets('reduced motion: commits at once, no slide', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++, reduce: true));
      await tester.drag(find.byType(SwipeRow), const Offset(-200, 0));
      await tester.pump();
      expect(n, 1);
    });

    testWidgets('screen readers get a Delete action, so the swipe is never required', (tester) async {
      final handle = tester.ensureSemantics();
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      final data = tester.getSemantics(find.byType(SwipeRow)).getSemanticsData();
      final labels = [for (final id in data.customSemanticsActionIds ?? <int>[]) CustomSemanticsAction.getAction(id)!.label];
      expect(labels, contains('Delete album'));
      tester.semantics.performAction(find.semantics.byAction(SemanticsAction.customAction), SemanticsAction.customAction, args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Delete album')));
      await tester.pumpAndSettle();
      expect(n, 1);
      handle.dispose();
    });

    testWidgets('a second swipe while leaving is ignored', (tester) async {
      var n = 0;
      await tester.pumpWidget(row(() => n++));
      await tester.fling(find.byType(SwipeRow), const Offset(-300, 0), 3000);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.fling(find.byType(SwipeRow), const Offset(-300, 0), 3000);
      await tester.pumpAndSettle();
      expect(n, 1);
    });
  });

  group('UndoFuse', () {
    Widget fuse({required void Function() undo, required void Function() burnt, bool reduce = false, bool assistive = false}) =>
        wrap(UndoFuse(message: 'Deleted Checkout', onUndo: undo, onBurnt: burnt), reduce: reduce, assistive: assistive);

    testWidgets('burns after its time, once', (tester) async {
      var burnt = 0, undone = 0;
      await tester.pumpWidget(fuse(undo: () => undone++, burnt: () => burnt++));
      expect(find.text('Deleted Checkout'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(burnt, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(burnt, 1);
      await tester.pump(const Duration(seconds: 10));
      expect((burnt, undone), (1, 0));
    });

    testWidgets('Undo before it burns cancels the delete for good', (tester) async {
      var burnt = 0, undone = 0;
      await tester.pumpWidget(fuse(undo: () => undone++, burnt: () => burnt++));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect((burnt, undone), (0, 1));
    });

    testWidgets('the fuse shrinks as time passes', (tester) async {
      await tester.pumpWidget(fuse(undo: () {}, burnt: () {}));
      double f() => tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor!;
      expect(f(), closeTo(1, 0.01));
      await tester.pump(const Duration(seconds: 3));
      expect(f(), closeTo(0.5, 0.05));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a screen reader gets three times as long (WCAG 2.2.1)', (tester) async {
      var burnt = 0;
      await tester.pumpWidget(fuse(undo: () {}, burnt: () => burnt++, assistive: true));
      await tester.pump(const Duration(seconds: 7));
      expect(burnt, 0);
      await tester.pump(const Duration(seconds: 12));
      expect(burnt, 1);
    });

    testWidgets('reduced motion: a plain countdown in words instead of a burning line', (tester) async {
      var burnt = 0;
      await tester.pumpWidget(fuse(undo: () {}, burnt: () => burnt++, reduce: true));
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.textContaining('Deleted Checkout (6 s)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('(4 s)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(burnt, 1);
    });

    testWidgets('leaving the screen before it burns neither deletes nor leaks a timer', (tester) async {
      var burnt = 0;
      await tester.pumpWidget(fuse(undo: () {}, burnt: () => burnt++));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      expect(burnt, 0, reason: 'the album stays: the safe way to fail');
    });

    testWidgets('is announced as a live region with Undo as its own control', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(fuse(undo: () {}, burnt: () {}));
      expect(find.bySemanticsLabel('Undo'), findsOneWidget);
      expect(find.bySemanticsLabel('Deleted Checkout'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      handle.dispose();
    });
  });

  group('FluoStarBorder', () {
    Widget border({required bool active, bool reduce = false}) => wrap(
          FluoStarBorder(active: active, color: const Color(0xFFC8FF3D), child: const SizedBox(height: 100, child: Text('Card'))),
          reduce: reduce,
        );

    testWidgets('animates while active', (tester) async {
      await tester.pumpWidget(border(active: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('is still when not active, and when motion is reduced', (tester) async {
      await tester.pumpWidget(border(active: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(border(active: true, reduce: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('stops when it stops being live', (tester) async {
      await tester.pumpWidget(border(active: true));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(border(active: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
