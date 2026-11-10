import 'dart:io';
import 'dart:typed_data';

import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/capture/mac_capture_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A minimal valid PNG header for a [w]x[h] image (enough for size sniffing).
Uint8List pngHeader(int w, int h) {
  final b = ByteData(24);
  const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(16, w);
  b.setUint32(20, h);
  return b.buffer.asUint8List();
}

void main() {
  macCopyTests();
  group('MacScreenshotFilter', () {
    test('accepts macOS screenshot names, old and localised', () {
      for (final n in [
        'Screenshot 2026-11-10 at 10.21.33.png',
        'Screen Shot 2020-01-01 at 9.00.00 AM.png',
        'Tangkapan Layar 2026-11-10 pukul 10.21.33.png',
        'Bildschirmfoto 2026-11-10 um 10.21.33.png',
        'screenshot.JPG',
      ]) {
        expect(MacScreenshotFilter.isScreenshot(n), isTrue, reason: n);
      }
    });

    test('rejects temp files, other images and other types', () {
      for (final n in [
        '.Screenshot 2026-11-10 at 10.21.33.png', // macOS still writing
        'holiday.png',
        'Screenshot notes.txt',
        'Screenshot.mov',
      ]) {
        expect(MacScreenshotFilter.isScreenshot(n), isFalse, reason: n);
      }
    });
  });

  group('MacCaptureSource', () {
    late Directory tmp;
    late Directory shots;
    late Directory inbox;
    late MacCaptureSource src;
    var clock = DateTime(2026, 11, 10, 10);

    File shot(String name, {DateTime? at, Uint8List? bytes}) {
      final f = File(p.join(shots.path, name))
        ..writeAsBytesSync(bytes ?? pngHeader(100, 200));
      f.setLastModifiedSync(at ?? clock);
      return f;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fluo_mac_');
      shots = Directory(p.join(tmp.path, 'Desktop'))..createSync();
      inbox = Directory(p.join(tmp.path, 'support', 'fluo', 'inbox'));
      clock = DateTime(2026, 11, 10, 10);
      src = MacCaptureSource(
        screenshotDir: () async => shots,
        inboxDir: () async => inbox,
        openSystemSettings: () async {},
        pollInterval: const Duration(milliseconds: 40),
        now: () => clock,
      );
    });

    tearDown(() async {
      await src.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('names the watched folder once it has looked at it', () async {
      expect(src.watchedFolder, isNull);
      await src.permission();
      expect(src.watchedFolder, 'Desktop');
    });

    Future<void> until(Future<bool> Function() ok) async {
      for (var i = 0; i < 100; i++) {
        if (await ok()) return;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      fail('condition not met in time');
    }

    test('is supported and can read an existing folder', () async {
      expect(src.supported, isTrue);
      expect(await src.permission(), CapturePermission.granted);
      expect(await src.requestPermission(), CapturePermission.granted);
    });

    test('a missing screenshot folder is not a permission problem', () async {
      shots.deleteSync();
      expect(await src.permission(), CapturePermission.granted);
    });

    test('copies a new screenshot into the inbox and announces it', () async {
      await src.start();
      var pings = 0;
      src.captured.listen((_) => pings++);

      shot(
        'Screenshot 2026-11-10 at 10.21.33.png',
        at: clock.add(const Duration(seconds: 5)),
      );
      await until(() async => (await src.drain()).isNotEmpty);

      final got = await src.drain();
      expect(got, hasLength(1));
      expect(got.single.width, 100);
      expect(got.single.height, 200);
      expect(got.single.capturedAt, clock.add(const Duration(seconds: 5)));
      await until(() async => pings > 0);
    });

    test('ignores screenshots that existed before the watch started', () async {
      shot('Screenshot old.png', at: clock.subtract(const Duration(hours: 1)));
      await src.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await src.drain(), isEmpty);
    });

    test(
      'ignores files that are not screenshots and macOS temp files',
      () async {
        await src.start();
        shot('holiday.png', at: clock.add(const Duration(seconds: 1)));
        shot('.Screenshot tmp.png', at: clock.add(const Duration(seconds: 1)));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await src.drain(), isEmpty);
      },
    );

    test('never copies the same screenshot twice', () async {
      await src.start();
      shot('Screenshot a.png', at: clock.add(const Duration(seconds: 1)));
      await until(() async => (await src.drain()).isNotEmpty);
      await Future<void>.delayed(
        const Duration(milliseconds: 250),
      ); // several polls
      expect(await src.drain(), hasLength(1));
    });

    test('drain is oldest first and ack removes only what was acked', () async {
      await src.start();
      shot('Screenshot b.png', at: clock.add(const Duration(seconds: 9)));
      shot('Screenshot a.png', at: clock.add(const Duration(seconds: 2)));
      await until(() async => (await src.drain()).length == 2);

      final got = await src.drain();
      expect(got.first.capturedAt.isBefore(got.last.capturedAt), isTrue);

      await src.ack([got.first.path]);
      final left = await src.drain();
      expect(left, hasLength(1));
      expect(left.single.path, got.last.path);
      // Acked shots are not copied again by later polls.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await src.drain(), hasLength(1));
    });

    test('drain skips half-copied .part files', () async {
      inbox.createSync(recursive: true);
      File(p.join(inbox.path, '1_ab.png.part')).writeAsBytesSync([1]);
      File(p.join(inbox.path, 'stray.txt')).writeAsBytesSync([1]);
      expect(await src.drain(), isEmpty);
    });

    test(
      'a shot taken while the app was closed is imported on the next launch',
      () async {
        // The cursor file is what a quit-without-stop leaves behind.
        inbox.createSync(recursive: true);
        File(p.join(inbox.parent.path, 'capture_cursor'))
            .writeAsStringSync('${clock.millisecondsSinceEpoch}');
        shot(
          'Screenshot while-closed.png',
          at: clock.add(const Duration(minutes: 2)),
        );
        await src.start();
        await until(() async => (await src.drain()).isNotEmpty);
        expect(await src.drain(), hasLength(1));
      },
    );

    test(
      'after stop and start, what happened in between is not imported',
      () async {
        await src.start();
        await src.stop();
        shot(
          'Screenshot while-paused.png',
          at: clock.add(const Duration(seconds: 3)),
        );
        clock = clock.add(const Duration(minutes: 5));
        await src.start();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(await src.drain(), isEmpty);
      },
    );

    test('stop ends the watch: later screenshots are not imported', () async {
      await src.start();
      await src.stop();
      shot('Screenshot late.png', at: clock.add(const Duration(seconds: 3)));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await src.drain(), isEmpty);
    });

    test('start twice is harmless', () async {
      await src.start();
      await src.start();
      shot('Screenshot once.png', at: clock.add(const Duration(seconds: 1)));
      await until(() async => (await src.drain()).isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await src.drain(), hasLength(1));
    });

    test('there is nothing shared to Fluo on desktop yet', () async {
      expect(await src.drainShared(), isEmpty);
      await src.ackShared(const []);
      expect(await src.sharedIn.isEmpty, isTrue);
    });

    test('openSettings calls the settings opener', () async {
      var opened = 0;
      final s = MacCaptureSource(
        screenshotDir: () async => shots,
        inboxDir: () async => inbox,
        openSystemSettings: () async => opened++,
      );
      await s.openSettings();
      expect(opened, 1);
      await s.dispose();
    });
  });
}

void macCopyTests() {
  group('CaptureCopy', () {
    test('the Mac wording never mentions phones, photos or a gallery', () {
      final c = CaptureCopy.mac;
      for (final t in [
        c.accessLabel,
        c.watching,
        c.checking,
        c.needsPermission,
        c.needsSettings,
        c.limited,
        c.failed,
        c.allowLabel,
      ]) {
        expect(t.toLowerCase(), isNot(contains('phone')), reason: t);
        expect(t.toLowerCase(), isNot(contains('photo')), reason: t);
        expect(t.toLowerCase(), isNot(contains('gallery')), reason: t);
      }
    });

    test('Mac watching text names the folder; the phone text never changes', () {
      final t = CaptureCopy.mac.watchingText('Desktop');
      expect(t, startsWith('Watching Desktop.'));
      expect(t, contains('clipboard'));
      expect(CaptureCopy.mac.watchingText(null), CaptureCopy.mac.watching);
      expect(CaptureCopy.mac.watchingText(''), CaptureCopy.mac.watching);
      expect(CaptureCopy.phone.watchingText('Desktop'), CaptureCopy.phone.watching);
      expect(
        CaptureCopy.phone.watching,
        'New screenshots land here automatically. Missed one? Share it to Fluo from your gallery.',
      );
      for (final s in [t]) {
        for (final w in ['phone', 'photo', 'gallery']) {
          expect(s.toLowerCase(), isNot(contains(w)));
        }
      }
    });

    test('each source picks its own wording', () {
      expect(MacCaptureSource().copy, same(CaptureCopy.mac));
      expect(NoCaptureSource().copy, same(CaptureCopy.phone));
    });
  });
}
