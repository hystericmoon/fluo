import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/export/export_service.dart';
import 'package:fluo/export/long_image.dart';
import 'package:fluo/export/markdown.dart';
import 'package:fluo/export/model.dart';
import 'package:fluo/export/render_shot.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;

import 'support/fake_share.dart';
import 'support/harness.dart';

/// A fine red/blue checkerboard: anything left showing through a redaction
/// would be a coloured pixel, not black.
Future<Uint8List> checkerPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final red = Paint()..color = const Color(0xFFFF0000);
  final blue = Paint()..color = const Color(0xFF0000FF);
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 2), ((x + y) ~/ 2).isEven ? red : blue);
    }
  }
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

class Pix {
  Pix(this.w, this.h, this.data);
  final int w, h;
  final ByteData data;
  Color at(int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool black(int x, int y) {
    final c = at(x, y);
    return c.r < .02 && c.g < .02 && c.b < .02 && c.a > .98;
  }
}

Future<Pix> decode(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  final img = (await codec.getNextFrame()).image;
  return Pix(img.width, img.height, (await img.toByteData())!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FluoRepo repo;
  late Album album;
  late FakeShare share;
  late ExportService svc;
  const w = 200, h = 400;

  /// [n] kept screens, each a checkerboard; the first has a redaction over
  /// x .25-.75, y .25-.5 and a crop only if [cropFirst].
  Future<List<Shot>> seed(int n, {bool redactFirst = true}) async {
    final bytes = await checkerPng(w, h);
    final shots = <Shot>[];
    for (var i = 0; i < n; i++) {
      final f = File(p.join(tmp.path, 'in', 'shot$i.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final s = await repo.addShot(album.id, f, width: w, height: h);
      repo.setStatus(s.id, ShotStatus.kept);
      shots.add(s);
    }
    if (redactFirst) {
      repo.addAnnotation(shots.first.id, AnnotationKind.redact, {'rect': [.25, .25, .75, .5]});
    }
    return shots;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fluo_export_');
    repo = memRepo();
    album = repo.createAlbum('Checkout flow review');
    share = FakeShare();
    svc = ExportService(
      repo,
      ExportServices(share: share, workDir: () async => Directory(p.join(tmp.path, 'out')), pdfFont: () async => pw.Font.helvetica()),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('names and text', () {
    test('slugify makes safe file names', () {
      expect(slugify('Cart'), 'cart');
      expect(slugify('  Review order / step 2! '), 'review-order-step-2');
      expect(slugify('../../etc/passwd'), 'etc-passwd');
      expect(slugify('日本語', fallback: 'screen'), 'screen');
      expect(slugify(''), 'item');
      expect(slugify('a' * 80).length, 40);
    });

    test('entries are numbered in flow order and named from the shot', () async {
      final s = await seed(3, redactFirst: false);
      repo.renameShot(s[1].id, 'Cart');
      final es = svc.entries(album.id);
      expect(es.map((e) => e.number), [1, 2, 3]);
      expect(es.map((e) => e.title), ['Screen 1', 'Cart', 'Screen 3']);
      expect(es.map((e) => e.fileStem), ['01-screen', '02-cart', '03-screen']);
    });

    test('only kept screens are exported', () async {
      final s = await seed(3, redactFirst: false);
      repo.setStatus(s[1].id, ShotStatus.discarded);
      repo.setStatus(s[2].id, ShotStatus.pending);
      expect(svc.entries(album.id).map((e) => e.shot.id), [s[0].id]);
    });

    test('pinLocation is relative to the crop and null when the crop cut the pin out', () {
      Pin pin(double x, double y) =>
          Pin(id: 'p', shotId: 's', number: 1, severity: Severity.bug, x: x, y: y, note: '');
      expect(pinLocation(pin(.72, .55), null), '72% across, 55% down');
      expect(pinLocation(pin(.5, .5), const CropRect(.25, .25, .75, .75)), '50% across, 50% down');
      expect(pinLocation(pin(.1, .5), const CropRect(.25, .25, .75, .75)), isNull);
    });

    test('markdown: brief, captions, pins, redaction note and image links', () async {
      final s = await seed(2);
      repo.renameShot(s[0].id, 'Cart');
      repo.setCaption(s[0].id, 'Cart: total changes');
      repo.addPin(s[0].id, Severity.bug, .72, .55, note: 'Total changes after shipping');
      repo.addPin(s[0].id, Severity.a11y, .2, .9);
      final es = svc.entries(album.id);
      final md = buildMarkdown(
        albumName: album.name,
        entries: es,
        imagePaths: {1: 'images/01-cart.png', 2: 'images/02-screen.png'},
        originalPaths: const {},
        includeBrief: true,
      );
      expect(md, startsWith('# Checkout flow review: screenshot review'));
      expect(md, contains('## Review brief'));
      expect(md, contains('2 pins across 1 screen: 1 bug, 0 UX, 1 accessibility.'));
      expect(md, contains('## 1. Cart'));
      expect(md, contains('![Cart](images/01-cart.png)'));
      expect(md, contains('Caption: Cart: total changes'));
      expect(md, contains('- **B1** Bug, 72% across, 55% down: Total changes after shipping'));
      expect(md, contains('- **A2** Accessibility, 20% across, 90% down'));
      expect(md, contains('1 area was hidden on this screen before sharing.'));
      expect(md, contains('## 2. Screen 2'));
      expect(md, isNot(contains('Original screenshot')));
      expect(md.indexOf('## 1. Cart'), lessThan(md.indexOf('## 2. Screen 2')));
    });

    test('markdown without the brief starts straight at the screens; links to originals only when given', () async {
      await seed(1, redactFirst: false);
      final es = svc.entries(album.id);
      final md = buildMarkdown(
        albumName: 'A',
        entries: es,
        imagePaths: {1: 'images/01-screen.png'},
        originalPaths: {1: 'originals/01-screen.png'},
        includeBrief: false,
      );
      expect(md, isNot(contains('Review brief')));
      expect(md, contains('Original screenshot: [originals/01-screen.png](originals/01-screen.png)'));
    });

    test('a title with brackets cannot break the image link', () async {
      final s = await seed(1, redactFirst: false);
      repo.renameShot(s[0].id, 'Sign in [v2]');
      final md = buildMarkdown(
        albumName: 'A',
        entries: svc.entries(album.id),
        imagePaths: {1: 'images/01-sign-in-v2.png'},
        originalPaths: const {},
        includeBrief: false,
      );
      expect(md, contains('![Sign in v2](images/01-sign-in-v2.png)'));
    });
  });

  group('rendering bakes edits into pixels', () {
    test('a redaction is solid black in the output, with nothing of the image showing through', () async {
      final s = await seed(1);
      final e = svc.entries(album.id).single;
      final r = await renderShotPng(s.first, e.annotations, e.pins);
      final px = await decode(r.png);
      expect((px.w, px.h), (w, h));
      for (var y = 101; y < 199; y++) {
        for (var x = 51; x < 149; x++) {
          expect(px.black(x, y), isTrue, reason: 'pixel $x,$y');
        }
      }
      expect(px.black(20, 20), isFalse, reason: 'outside it the checkerboard is intact');
    });

    test('the crop sets the output size; a wide image is scaled down to maxWidth', () async {
      final s = await seed(1, redactFirst: false);
      repo.setCrop(s.first.id, const CropRect(.25, .25, .75, .75));
      final shot = repo.getShot(s.first.id)!;
      final r = await renderShotPng(shot, const [], const []);
      expect((r.width, r.height), (100, 200));
      final small = await renderShotPng(shot, const [], const [], maxWidth: 50);
      expect((small.width, small.height), (50, 100));
    });

    test('a redaction outside the crop is not in the output; one inside still is', () async {
      final s = await seed(1, redactFirst: false);
      repo.setCrop(s.first.id, const CropRect(.5, 0, 1, 1));
      final shot = repo.getShot(s.first.id)!;
      Annotation red(List<double> r) =>
          Annotation(id: 'r', shotId: shot.id, kind: AnnotationKind.redact, data: {'rect': r}, z: 0);
      final out = await decode((await renderShotPng(shot, [red([0, 0, .25, 1])], const [])).png);
      expect(out.black(10, 10), isFalse);
      final inn = await decode((await renderShotPng(shot, [red([.5, 0, .75, 1])], const [])).png);
      expect(inn.black(10, 10), isTrue);
      expect(inn.black(90, 10), isFalse);
    });
  });

  group('Claude pack', () {
    Future<Archive> open(ExportResult r) async => ZipDecoder().decodeBytes(await File(r.files.single.path).readAsBytes());

    test('has review.md and annotated images in flow order, and no originals by default', () async {
      final s = await seed(3);
      repo.renameShot(s[0].id, 'Cart');
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.claude));
      expect(r.files.single.name, 'fluo-checkout-flow-review-review.zip');
      expect(r.files.single.mime, 'application/zip');
      final names = (await open(r)).files.map((f) => f.name).toList();
      expect(names, ['review.md', 'images/01-cart.png', 'images/02-screen.png', 'images/03-screen.png']);
      expect(names.any((n) => n.startsWith('originals')), isFalse);
    });

    test('no byte of the original screenshots is in the pack by default', () async {
      final s = await seed(1);
      final original = await File(s.first.originalPath).readAsBytes();
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.claude));
      for (final f in (await open(r)).files) {
        final data = f.content as List<int>;
        expect(data.length == original.length && _same(data, original), isFalse, reason: f.name);
      }
      // And the redacted area of the exported image is black.
      final img = (await open(r)).files.firstWhere((f) => f.name.startsWith('images/'));
      final px = await decode(img.content as List<int>);
      expect(px.black(100, 150), isTrue);
    });

    test('originals are added only when asked, byte for byte, and the markdown links them', () async {
      final s = await seed(2);
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.claude, includeOriginals: true));
      final zip = await open(r);
      final orig = zip.files.firstWhere((f) => f.name == 'originals/01-screen.png');
      expect(_same(orig.content as List<int>, await File(s.first.originalPath).readAsBytes()), isTrue);
      expect(zip.files.where((f) => f.name.startsWith('originals/')), hasLength(2));
      final md = String.fromCharCodes(zip.files.firstWhere((f) => f.name == 'review.md').content as List<int>);
      expect(md, contains('originals/01-screen.png'));
    });

    test('the brief can be left out', () async {
      await seed(1);
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.claude, includeBrief: false));
      final md = String.fromCharCodes((await open(r)).files.firstWhere((f) => f.name == 'review.md').content as List<int>);
      expect(md, isNot(contains('Review brief')));
    });

    test('every image the markdown links to is in the ZIP', () async {
      final s = await seed(3);
      repo.renameShot(s[1].id, 'Weird / name?');
      final zip = await open(await svc.build(album.id, const ExportOptions(format: ExportFormat.claude)));
      final md = String.fromCharCodes(zip.files.firstWhere((f) => f.name == 'review.md').content as List<int>);
      final links = RegExp(r'!\[[^\]]*\]\(([^)]+)\)').allMatches(md).map((m) => m.group(1)!).toList();
      expect(links, hasLength(3));
      for (final l in links) {
        expect(zip.files.any((f) => f.name == l), isTrue, reason: l);
      }
    });

    test('progress counts up to the number of screens', () async {
      await seed(3, redactFirst: false);
      final seen = <(int, int)>[];
      await svc.build(album.id, const ExportOptions(format: ExportFormat.claude), onProgress: (d, t) => seen.add((d, t)));
      expect(seen, [(1, 3), (2, 3), (3, 3)]);
    });
  });

  group('PDF', () {
    test('is a PDF with one page per screen plus a cover when the brief is on', () async {
      await seed(3);
      final withBrief = await svc.build(album.id, const ExportOptions(format: ExportFormat.pdf));
      final bytes = await File(withBrief.files.single.path).readAsBytes();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(withBrief.files.single.mime, 'application/pdf');
      expect(RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length, 4);

      final without = await svc.build(album.id, const ExportOptions(format: ExportFormat.pdf, includeBrief: false));
      final b2 = String.fromCharCodes(await File(without.files.single.path).readAsBytes());
      expect(RegExp(r'/Type\s*/Page\b').allMatches(b2).length, 3);
    });

    test('is built from the baked images, never from the originals', () async {
      await seed(2);
      final used = <String>[];
      final spy = ExportService(repo, ExportServices(share: share, workDir: () async => Directory(p.join(tmp.path, 'out2')), pdfFont: () async => pw.Font.helvetica()),
          render: (e) async {
        final r = await renderShotPng(e.shot, e.annotations, e.pins);
        used.add('${r.width}x${r.height}');
        return r;
      });
      await spy.build(album.id, const ExportOptions(format: ExportFormat.pdf));
      expect(used, ['200x400', '200x400']);
    });
  });

  group('long image', () {
    const layout = LongLayout();

    test('plan: one part when it fits, a new part when it would not', () {
      final sizes = List.generate(3, (_) => const ui.Size(600, 1000)); // block = 56 + 1000 + 28
      expect(planLongImage(sizes, layout), [[0, 1, 2]]);
      final many = List.generate(10, (_) => const ui.Size(600, 1000));
      final parts = planLongImage(many, layout);
      expect(parts.length, greaterThan(1));
      expect(parts.expand((e) => e).toList(), List.generate(10, (i) => i), reason: 'every screen once, in order');
      for (final part in parts) {
        final height = layout.pad * 2 + part.length * layout.blockHeight(600, 1000);
        expect(height, lessThanOrEqualTo(layout.maxHeight + layout.gap));
      }
    });

    test('plan: a screen taller than a part still gets one, and nothing is empty', () {
      final parts = planLongImage(const [ui.Size(100, 50000), ui.Size(600, 1000)], layout);
      expect(parts, [[0], [1]]);
      expect(planLongImage(const [], layout), isEmpty);
    });

    test('stitches the screens under their names on a dark background; redactions stay black', () async {
      await seed(2);
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.long));
      expect(r.files.single.name, 'fluo-checkout-flow-review-long.png');
      final px = await decode(await File(r.files.single.path).readAsBytes());
      expect(px.w, 648);
      // Each screen: header 56 + 1200 tall at 600 wide (200x400 scaled 3x) + gap 28.
      expect(px.h, (24 + 2 * (56 + 1200 + 28) + 24 - 28).ceil());
      expect(px.at(2, 2), const Color(0xFF09090B), reason: 'app background');
      // Redaction in screen 1: x .25-.75, y .25-.5 of the picture, which starts at y=24+56.
      expect(px.black(24 + 300, 24 + 56 + 450), isTrue);
      expect(px.black(24 + 10, 24 + 56 + 10), isFalse);
      // The second screen has none.
      expect(px.black(24 + 300, 24 + 56 + 1200 + 28 + 56 + 450), isFalse);
    });

    test('a long album comes out as several numbered parts', () async {
      await seed(10, redactFirst: false);
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.long));
      expect(r.files.length, greaterThan(1));
      expect(r.files.map((f) => f.name).first, 'fluo-checkout-flow-review-long-1.png');
    });
  });

  group('Share images', () {
    test('annotated images and a captions text; no originals by default', () async {
      final s = await seed(2);
      repo.renameShot(s[0].id, 'Cart');
      repo.setCaption(s[0].id, 'Total changes');
      repo.addPin(s[0].id, Severity.bug, .5, .5, note: 'Wrong total');
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.share));
      expect(r.files.map((f) => f.name), ['01-cart.png', '02-screen.png']);
      expect(r.text, contains('1. Cart: Total changes'));
      expect(r.text, contains('B1 Bug, 50% across, 50% down: Wrong total'));
      final px = await decode(await File(r.files.first.path).readAsBytes());
      expect(px.black(100, 150), isTrue, reason: 'redaction baked in');
    });

    test('originals are attached only when asked', () async {
      await seed(2, redactFirst: false);
      final r = await svc.build(album.id, const ExportOptions(format: ExportFormat.share, includeOriginals: true));
      expect(r.files.map((f) => f.name), ['01-screen.png', '01-screen-original.png', '02-screen.png', '02-screen-original.png']);
    });

    test('exportAndShare hands the result to the share sheet once', () async {
      await seed(1);
      await svc.exportAndShare(album.id, const ExportOptions(format: ExportFormat.share));
      expect(share.shared, hasLength(1));
      expect(share.shared.single.files.single.name, '01-screen.png');
    });
  });

  group('options only apply where they make sense', () {
    test('PDF and long image never include originals, even if the switch is on', () async {
      await seed(1, redactFirst: false);
      for (final f in [ExportFormat.pdf, ExportFormat.long]) {
        expect(ExportOptions(format: f, includeOriginals: true).originalsActuallyIncluded, isFalse);
      }
      expect(const ExportOptions(format: ExportFormat.claude, includeOriginals: true).originalsActuallyIncluded, isTrue);
      expect(const ExportOptions(format: ExportFormat.share, includeOriginals: true).originalsActuallyIncluded, isTrue);
      expect(const ExportOptions(format: ExportFormat.long).briefActuallyIncluded, isFalse);
      expect(const ExportOptions(format: ExportFormat.pdf).briefActuallyIncluded, isTrue);
    });

    test('the default is no originals', () {
      for (final f in ExportFormat.values) {
        expect(ExportOptions(format: f).includeOriginals, isFalse);
      }
    });
  });

  group('service', () {
    test('summary counts screens, pins and redactions of kept screens only', () async {
      final s = await seed(3);
      repo.addPin(s[0].id, Severity.bug, .1, .1);
      repo.addPin(s[1].id, Severity.ux, .1, .1);
      repo.addAnnotation(s[1].id, AnnotationKind.redact, {'rect': [0, 0, .1, .1]});
      repo.setStatus(s[2].id, ShotStatus.discarded);
      repo.addPin(s[2].id, Severity.a11y, .1, .1);
      final sum = svc.summary(album.id);
      expect((sum.screens, sum.pins, sum.redactions), (2, 2, 2));
    });

    test('an album with no kept screens cannot be exported', () async {
      await expectLater(svc.build(album.id, const ExportOptions(format: ExportFormat.claude)), throwsStateError);
    });

    test('each export replaces the previous one, so old copies do not pile up', () async {
      await seed(1, redactFirst: false);
      final first = await svc.build(album.id, const ExportOptions(format: ExportFormat.claude));
      expect(File(first.files.single.path).existsSync(), isTrue);
      final second = await svc.build(album.id, const ExportOptions(format: ExportFormat.pdf));
      expect(File(first.files.single.path).existsSync(), isFalse);
      expect(File(second.files.single.path).existsSync(), isTrue);
      await svc.clearWorkDir();
      expect(File(second.files.single.path).existsSync(), isFalse);
      await svc.clearWorkDir(); // nothing there: fine
    });

    test('exporting never changes the originals', () async {
      final s = await seed(2);
      final before = [for (final x in s) await File(x.originalPath).readAsBytes()];
      for (final f in ExportFormat.values) {
        await svc.build(album.id, ExportOptions(format: f, includeOriginals: true));
      }
      for (var i = 0; i < s.length; i++) {
        expect(_same(await File(s[i].originalPath).readAsBytes(), before[i]), isTrue);
      }
    });
  });
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
