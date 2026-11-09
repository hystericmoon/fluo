import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/capture/capture_controller.dart';
import 'package:fluo/capture/capture_source.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:path/path.dart' as p;

import 'support/fake_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FluoRepo repo;
  late FakeSource src;
  late CaptureController c;

  IncomingShot arrive(String name, {int w = 1080, int h = 2400, DateTime? at}) {
    final f = File(p.join(tmp.path, 'inbox', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    final s = IncomingShot(path: f.path, capturedAt: at ?? DateTime(2026, 11, 9, 12), width: w, height: h);
    src.inbox.add(s);
    return s;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fluo_cap_');
    repo = FluoRepo(FluoDb.openInMemory(), FileStore(Directory(p.join(tmp.path, 'app'))));
    src = FakeSource();
    c = CaptureController(repo, src);
  });

  tearDown(() {
    c.dispose();
    repo.close();
    tmp.deleteSync(recursive: true);
  });

  group('session and status', () {
    test('no session means off and nothing is watched', () async {
      await c.sync();
      expect(c.status, CaptureStatus.off);
      expect(src.watching, isFalse);
    });

    test('begin starts a session, asks nothing when already granted, and watches', () async {
      final a = repo.createAlbum('Checkout');
      await c.begin(a.id);
      expect(c.status, CaptureStatus.watching);
      expect(src.watching, isTrue);
      expect(src.requests, 0);
      expect(repo.activeSession()!.albumId, a.id);
    });

    test('begin asks for access when denied and watches once it is granted', () async {
      src.perm = CapturePermission.denied;
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      expect(src.requests, 1);
      expect(c.status, CaptureStatus.watching);
    });

    test('a refusal leaves a session that needs permission and does not watch', () async {
      src.perm = CapturePermission.denied;
      src.afterRequest = CapturePermission.denied;
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      expect(c.status, CaptureStatus.needsPermission);
      expect(src.watching, isFalse);
      expect(repo.activeSession(), isNotNull, reason: 'the session is kept so the user can fix access');
    });

    test('a permanent refusal points at Settings and fixAccess opens it', () async {
      src.perm = CapturePermission.permanentlyDenied;
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      expect(c.status, CaptureStatus.needsSettings);
      expect(src.requests, 0, reason: 'the prompt would not show');
      await c.fixAccess();
      expect(src.settings, 1);
    });

    test('limited access is reported and not watched', () async {
      src.perm = CapturePermission.limited;
      await c.begin(repo.createAlbum('A').id);
      expect(c.status, CaptureStatus.limitedAccess);
      expect(src.watching, isFalse);
    });

    test('fixAccess asks when the prompt can still show, then starts watching', () async {
      src.perm = CapturePermission.denied;
      src.afterRequest = CapturePermission.denied;
      await c.begin(repo.createAlbum('A').id);
      src.afterRequest = CapturePermission.granted;
      await c.fixAccess();
      expect(c.status, CaptureStatus.watching);
    });

    test('pause stops watching and resume starts again', () async {
      await c.begin(repo.createAlbum('A').id);
      await c.pause();
      expect(c.status, CaptureStatus.paused);
      expect(src.watching, isFalse);
      expect(repo.activeSession()!.paused, isTrue);
      await c.resume();
      expect(c.status, CaptureStatus.watching);
      expect(src.watching, isTrue);
    });

    test('a failed start shows failed (not Paused) and Resume recovers once it works', () async {
      await c.begin(repo.createAlbum('A').id);
      await c.pause();
      src.startError = PlatformException(code: 'start_failed', message: 'boom');
      await c.resume();
      expect(c.status, CaptureStatus.failed);
      expect(c.lastError, contains('boom'));
      expect(repo.activeSession()!.paused, isFalse);
      src.startError = null;
      await c.fixAccess(); // the card's "Try again"
      expect(c.status, CaptureStatus.watching);
      expect(c.lastError, isNull);
    });

    test('an unsupported platform reports it and never starts', () async {
      c.dispose();
      src = FakeSource(isSupported: false);
      c = CaptureController(repo, src);
      await c.begin(repo.createAlbum('A').id);
      expect(c.status, CaptureStatus.unsupported);
      expect(src.starts, 0);
    });

    test('sync after a restart resumes watching from the stored session', () async {
      final a = repo.createAlbum('A');
      repo.startSession(a.id); // a previous run left this behind
      await c.sync();
      expect(c.status, CaptureStatus.watching);
      expect(src.watching, isTrue);
    });
  });

  group('importing', () {
    test('screenshots become pending shots in the session album, oldest first', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      arrive('1.png', w: 1080, h: 2400, at: DateTime(2026, 11, 9, 12, 0, 1));
      arrive('2.png', w: 1080, h: 2340, at: DateTime(2026, 11, 9, 12, 0, 2));
      final n = await c.importPending();

      expect(n, 2);
      final shots = repo.shotsIn(a.id);
      expect(shots.map((s) => s.status), [ShotStatus.pending, ShotStatus.pending]);
      expect(shots.map((s) => s.height), [2400, 2340]);
      expect(shots.first.capturedAt, DateTime(2026, 11, 9, 12, 0, 1));
      expect(File(shots.first.originalPath).readAsBytesSync(), [1, 2, 3]);
      expect(src.inbox, isEmpty, reason: 'acked after storing');
      expect(repo.listAlbums().single.pendingCount, 2);
    });

    test('a ping from the platform imports without being asked', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      arrive('1.png');
      src.ping();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.shotsIn(a.id), hasLength(1));
    });

    test('screenshots waiting when the app starts are imported by sync', () async {
      final a = repo.createAlbum('A');
      repo.startSession(a.id);
      arrive('while_closed.png');
      await c.sync();
      expect(repo.shotsIn(a.id), hasLength(1));
    });

    test('with no session the inbox is cleared and nothing is stored', () async {
      final a = repo.createAlbum('A');
      arrive('1.png');
      final n = await c.importPending();
      expect(n, 0);
      expect(repo.shotsIn(a.id), isEmpty);
      expect(src.inbox, isEmpty);
    });

    test('while paused, screenshots are dropped, not queued', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      await c.pause();
      arrive('1.png');
      await c.importPending();
      expect(repo.shotsIn(a.id), isEmpty);
      await c.resume();
      expect(repo.shotsIn(a.id), isEmpty);
    });

    test('one bad file stays in the inbox and does not block the others', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      src.inbox.add(IncomingShot(path: p.join(tmp.path, 'missing.png'), capturedAt: DateTime(2026)));
      arrive('good.png');
      final n = await c.importPending();
      expect(n, 1);
      expect(repo.shotsIn(a.id), hasLength(1));
      expect(src.inbox.map((s) => p.basename(s.path)), ['missing.png'], reason: 'kept for a retry');
    });

    test('a screenshot that arrives mid-import is picked up in the same run', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      arrive('1.png');
      final first = c.importPending();
      arrive('2.png'); // lands while the first import is still running
      final second = await c.importPending(); // refused: busy, marks "again"
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second, 0);
      expect(repo.shotsIn(a.id), hasLength(2));
      expect(src.inbox, isEmpty);
    });

    test('imported ticks only when something was added', () async {
      final a = repo.createAlbum('A');
      await c.begin(a.id);
      final before = c.imported.value;
      await c.importPending();
      expect(c.imported.value, before);
      arrive('1.png');
      await c.importPending();
      expect(c.imported.value, before + 1);
    });
  });

  group('AndroidCaptureSource channel adapter', () {
    const ch = MethodChannel('app.fluo/capture');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'permission':
            return 'limited';
          case 'requestPermission':
            return 'permanentlyDenied';
          case 'drain':
            return [
              {'path': '/x/1_1700000000000_1080x2400.png', 'capturedAtMs': 1700000000000, 'width': 1080, 'height': 2400},
              {'path': '/x/2_1700000001000_0x0.jpg', 'capturedAtMs': 1700000001000},
            ];
        }
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null));

    test('maps permission strings, drain maps and ack paths', () async {
      final s = AndroidCaptureSource();
      expect(await s.permission(), CapturePermission.limited);
      expect(await s.requestPermission(), CapturePermission.permanentlyDenied);
      final d = await s.drain();
      expect(d, hasLength(2));
      expect(d.first.path, '/x/1_1700000000000_1080x2400.png');
      expect(d.first.capturedAt.millisecondsSinceEpoch, 1700000000000);
      expect((d.first.width, d.first.height), (1080, 2400));
      expect((d.last.width, d.last.height), (null, null));
      await s.ack(['/x/a.png']);
      await s.start();
      await s.stop();
      await s.openSettings();
      expect(calls.map((c) => c.method),
          ['permission', 'requestPermission', 'drain', 'ack', 'start', 'stop', 'openSettings']);
      expect(calls[3].arguments, ['/x/a.png']);
    });
  });

  group('shared screenshots', () {
    IncomingShot share(String name) {
      final f = File(p.join(tmp.path, 'shared', name))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final s = IncomingShot(path: f.path, capturedAt: DateTime(2026, 11, 9, 13));
      src.shared.add(s);
      return s;
    }

    test('addShared stores them as pending shots in the chosen album and clears the folder', () async {
      final a = repo.createAlbum('Checkout');
      final one = share('shared_1_0.png');
      final two = share('shared_1_1.png');
      final waiting = await c.sharedWaiting();
      expect(waiting, hasLength(2));
      expect(await c.addShared(a.id, waiting), 2);
      expect(repo.shotsIn(a.id), hasLength(2));
      expect(src.sharedAcked, containsAll([one.path, two.path]));
      expect(src.shared, isEmpty);
    });

    test('works with no active session', () async {
      final a = repo.createAlbum('Loose');
      expect(repo.activeSession(), isNull);
      share('shared_2_0.png');
      expect(await c.addShared(a.id, await c.sharedWaiting()), 1);
    });

    test('discardShared removes them without adding anything', () async {
      final a = repo.createAlbum('A');
      share('shared_3_0.png');
      await c.discardShared(await c.sharedWaiting());
      expect(src.shared, isEmpty);
      expect(repo.shotsIn(a.id), isEmpty);
    });

    test('a share while the app is open bumps sharedArrived', () async {
      var bumps = 0;
      c.sharedArrived.addListener(() => bumps++);
      src.pingShared();
      await Future<void>.delayed(Duration.zero);
      expect(bumps, 1);
    });
  });
}

