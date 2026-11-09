import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/capture/capture_controller.dart';
import 'package:fluo/export/export_scope.dart';
import 'package:fluo/motion/motion.dart';
import 'package:fluo/export/export_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:fluo/capture/capture_scope.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repo_scope.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/theme/app_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'fake_share.dart';
import 'fake_source.dart';

FluoRepo memRepo() {
  final dir = Directory.systemTemp.createTempSync('fluo_ui_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final repo = FluoRepo(FluoDb.openInMemory(), FileStore(dir));
  addTearDown(repo.close);
  return repo;
}

/// Export settings for tests: a temp folder, a recording share sheet and a
/// built-in PDF font (so no asset loading).
ExportServices testExports([FakeShare? share]) {
  final dir = Directory.systemTemp.createTempSync('fluo_exp_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return ExportServices(
    share: share ?? FakeShare(),
    workDir: () async => Directory('${dir.path}/out'),
    pdfFont: () async => pw.Font.helvetica(),
  );
}

/// [reduceMotion] defaults to true so `pumpAndSettle` can finish: some
/// animations (the live border) never end. Motion tests turn it off.
Widget host(Widget home,
    {FluoRepo? repo, FakeSource? source, ExportServices? exports, bool reduceMotion = true}) {
  final r = repo ?? memRepo();
  final c = CaptureController(r, source ?? FakeSource());
  addTearDown(c.dispose);
  return RepoScope(
    repo: r,
    child: MotionScope(
      reduce: reduceMotion,
      child: ExportScope(
        services: exports ?? testExports(),
        child: CaptureScope(
          controller: c,
          child: ShadcnApp(
            debugShowCheckedModeBanner: false,
            theme: fluoTheme(),
            home: home,
          ),
        ),
      ),
    ),
  );
}

/// Albums with a few kept screens, like a used app.
final fixedNow = DateTime(2026, 11, 9, 15); // a Monday

FluoRepo seeded() {
  final r = memRepo();
  r.createAlbum('Checkout flow review', now: fixedNow);
  r.createAlbum('Onboarding audit', now: DateTime(2026, 10, 20));
  return r;
}

void setPhone(WidgetTester t) {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

/// Every node with a tap action must be at least 44x44 dp.
int tapNodes = 0;

List<String> smallTargets(WidgetTester t) {
  tapNodes = 0;
  final bad = <String>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (d.hasAction(SemanticsAction.tap) && !n.isInvisible) tapNodes++;
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

/// Adds [n] pending screenshots to the album. Real file copies only finish in
/// the real async zone, hence runAsync.
Future<List<Shot>> seedShots(WidgetTester tester, FluoRepo repo, String albumId, int n,
    {List<int> bytes = const [1, 2, 3]}) async {
  final dir = Directory.systemTemp.createTempSync('fluo_seed_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return (await tester.runAsync(() async {
    final out = <Shot>[];
    for (var i = 0; i < n; i++) {
      final f = File('${dir.path}/s$i.png')..writeAsBytesSync([...bytes, i]);
      out.add(await repo.addShot(albumId, f, width: 1080, height: 2400));
    }
    return out;
  }))!;
}

/// A real, decodable PNG: a light background with a dark header bar.
Future<List<int>> pngBytes(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFF4F4F5));
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h * 0.08), Paint()..color = const Color(0xFF27272A));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Like [seedShots] but with real images, and already kept.
Future<List<Shot>> seedKeptPngShots(WidgetTester tester, FluoRepo repo, String albumId, int n,
    {int w = 200, int h = 400}) async {
  final dir = Directory.systemTemp.createTempSync('fluo_png_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final out = (await tester.runAsync(() async {
    final shots = <Shot>[];
    final bytes = await pngBytes(w, h);
    for (var i = 0; i < n; i++) {
      final f = File('${dir.path}/s$i.png')..writeAsBytesSync(bytes);
      shots.add(await repo.addShot(albumId, f, width: w, height: h));
    }
    return shots;
  }))!;
  for (final s in out) {
    repo.setStatus(s.id, ShotStatus.kept);
  }
  return out;
}

/// Controls a screen reader would land on that have no name: a tap target, a
/// toggle or a text field with an empty label. A nameless control is
/// "unlabelled button" to TalkBack.
List<String> unlabeledControls(WidgetTester t) {
  final bad = <String>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    final interactive = d.hasAction(SemanticsAction.tap) ||
        d.flagsCollection.isTextField ||
        d.flagsCollection.isButton ||
        d.flagsCollection.isToggled.toBoolOrNull() != null ||
        d.flagsCollection.isChecked != ui.CheckedState.none;
    if (interactive && !n.isInvisible && d.label.trim().isEmpty && d.value.trim().isEmpty) {
      bad.add('nameless control at ${n.rect}: textField=${d.flagsCollection.isTextField}, button=${d.flagsCollection.isButton}, tap=${d.hasAction(SemanticsAction.tap)}, hint=${d.hint}, value=${d.value}');
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return bad;
}

/// Every custom action label offered on any node, for "is there an
/// alternative to this gesture" checks.
Set<String> customActionLabels(WidgetTester t) {
  final out = <String>{};
  void visit(SemanticsNode n) {
    for (final id in n.getSemanticsData().customSemanticsActionIds ?? const <int>[]) {
      final l = CustomSemanticsAction.getAction(id)?.label;
      if (l != null) out.add(l);
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return out;
}
