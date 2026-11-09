import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory inbox; // where "screenshots" come from, like the system folder
  late FluoRepo repo;

  FluoRepo openRepo() =>
      FluoRepo(FluoDb.open(p.join(tmp.path, 'fluo.db')), FileStore(Directory(p.join(tmp.path, 'app'))));

  File shot(String name, List<int> bytes) {
    final f = File(p.join(inbox.path, name))..writeAsBytesSync(bytes);
    return f;
  }

  String hash(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fluo_test_');
    inbox = Directory(p.join(tmp.path, 'inbox'))..createSync();
    repo = openRepo();
  });

  tearDown(() {
    try {
      repo.close();
    } catch (_) {}
    tmp.deleteSync(recursive: true);
  });

  group('albums', () {
    test('create, list newest activity first, rename, delete', () async {
      final a = repo.createAlbum('  Onboarding  ', now: DateTime(2026, 11, 1));
      final b = repo.createAlbum('Checkout', now: DateTime(2026, 11, 2));
      expect(a.name, 'Onboarding', reason: 'name is trimmed');
      expect(repo.listAlbums().map((s) => s.album.name), ['Checkout', 'Onboarding']);

      repo.renameAlbum(a.id, 'Onboarding audit', now: DateTime(2026, 11, 3));
      expect(repo.listAlbums().first.album.name, 'Onboarding audit');

      await repo.deleteAlbum(b.id);
      expect(repo.listAlbums().map((s) => s.album.name), ['Onboarding audit']);
      expect(repo.getAlbum(b.id), isNull);
    });

    test('summary counts only kept and pending shots and lists up to 3 thumbnails', () async {
      final a = repo.createAlbum('A');
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add((await repo.addShot(a.id, shot('s$i.png', [i, 1, 2]))).id);
      }
      repo.setStatus(ids[0], ShotStatus.kept);
      repo.setStatus(ids[1], ShotStatus.kept);
      repo.setStatus(ids[2], ShotStatus.kept);
      repo.setStatus(ids[3], ShotStatus.kept);
      repo.setStatus(ids[4], ShotStatus.discarded);

      final s = repo.listAlbums().single;
      expect(s.keptCount, 4);
      expect(s.pendingCount, 0);
      expect(s.thumbnailPaths, hasLength(3));
      expect(s.thumbnailPaths.every((t) => File(t).existsSync()), isTrue);
    });
  });

  group('shots and the file store', () {
    test('addShot copies the file, leaves the source alone and starts pending', () async {
      final a = repo.createAlbum('A');
      final src = shot('one.png', [1, 2, 3, 4]);
      final s = await repo.addShot(a.id, src, width: 1080, height: 2400);

      expect(s.status, ShotStatus.pending);
      expect(s.position, 0);
      expect(s.width, 1080);
      expect(s.originalPath, isNot(src.path));
      expect(File(s.originalPath).readAsBytesSync(), [1, 2, 3, 4]);
      expect(src.existsSync(), isTrue, reason: 'source is not moved');
      expect(File('${s.originalPath}.part').existsSync(), isFalse);
    });

    test('positions grow per album and reorder rewrites them', () async {
      final a = repo.createAlbum('A');
      final b = repo.createAlbum('B');
      final s1 = await repo.addShot(a.id, shot('1.png', [1]));
      final s2 = await repo.addShot(a.id, shot('2.png', [2]));
      final s3 = await repo.addShot(a.id, shot('3.png', [3]));
      final other = await repo.addShot(b.id, shot('4.png', [4]));
      expect([s1.position, s2.position, s3.position, other.position], [0, 1, 2, 0]);

      repo.reorder(a.id, [s3.id, s1.id, s2.id]);
      expect(repo.shotsIn(a.id).map((s) => s.id), [s3.id, s1.id, s2.id]);

      expect(() => repo.reorder(a.id, [s1.id, s2.id]), throwsArgumentError);
      expect(() => repo.reorder(a.id, [s1.id, s2.id, other.id]), throwsArgumentError);
      expect(repo.shotsIn(a.id).map((s) => s.id), [s3.id, s1.id, s2.id],
          reason: 'a rejected reorder changes nothing');
    });

    test('deleteShot removes the file and closes the position gap', () async {
      final a = repo.createAlbum('A');
      final s1 = await repo.addShot(a.id, shot('1.png', [1]));
      final s2 = await repo.addShot(a.id, shot('2.png', [2]));
      final s3 = await repo.addShot(a.id, shot('3.png', [3]));
      await repo.deleteShot(s2.id);

      expect(File(s2.originalPath).existsSync(), isFalse);
      expect(repo.shotsIn(a.id).map((s) => (s.id, s.position)), [(s1.id, 0), (s3.id, 1)]);
    });

    test('deleteAlbum cascades to shots, pins and annotations and removes files', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('1.png', [1]));
      repo.addPin(s.id, Severity.bug, .5, .5);
      repo.addAnnotation(s.id, AnnotationKind.box, {'rect': [0, 0, 1, 1]});
      await repo.deleteAlbum(a.id);

      expect(File(s.originalPath).existsSync(), isFalse);
      expect(repo.getShot(s.id), isNull);
      expect(repo.pinsFor(s.id), isEmpty);
      expect(repo.annotationsFor(s.id), isEmpty);
    });

    test('adding to a missing album fails and leaves no orphan file', () async {
      await expectLater(repo.addShot('nope', shot('1.png', [1])), throwsA(anything));
      final dir = Directory(p.join(tmp.path, 'app', 'originals'));
      expect(dir.listSync(), isEmpty);
    });

    test('name, caption and status updates', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('1.png', [1]));
      repo.renameShot(s.id, '  Cart ');
      repo.setCaption(s.id, 'Cart: total changes');
      repo.setStatus(s.id, ShotStatus.kept);
      final r = repo.getShot(s.id)!;
      expect((r.name, r.caption, r.status), ('Cart', 'Cart: total changes', ShotStatus.kept));
    });
  });

  group('pins', () {
    test('numbers run 1..n and stay contiguous after a delete', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('1.png', [1]));
      final p1 = repo.addPin(s.id, Severity.bug, .1, .1, note: 'first');
      final p2 = repo.addPin(s.id, Severity.ux, .2, .2);
      final p3 = repo.addPin(s.id, Severity.a11y, .3, .3);
      expect([p1.number, p2.number, p3.number], [1, 2, 3]);

      repo.deletePin(p1.id);
      expect(repo.pinsFor(s.id).map((p) => (p.id, p.number)), [(p2.id, 1), (p3.id, 2)]);
      expect(repo.addPin(s.id, Severity.bug, 0, 0).number, 3);
    });

    test('updatePin changes only the fields given', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('1.png', [1]));
      final p = repo.addPin(s.id, Severity.bug, .1, .2, note: 'n');
      repo.updatePin(p.id, severity: Severity.ux, note: 'changed');
      final r = repo.pinsFor(s.id).single;
      expect((r.severity, r.x, r.y, r.note), (Severity.ux, .1, .2, 'changed'));
    });

    test('pinCounts covers every severity and ignores discarded shots', () async {
      final a = repo.createAlbum('A');
      final kept = await repo.addShot(a.id, shot('1.png', [1]));
      final gone = await repo.addShot(a.id, shot('2.png', [2]));
      repo.setStatus(kept.id, ShotStatus.kept);
      repo.setStatus(gone.id, ShotStatus.discarded);
      repo.addPin(kept.id, Severity.bug, 0, 0);
      repo.addPin(kept.id, Severity.bug, 0, 0);
      repo.addPin(kept.id, Severity.a11y, 0, 0);
      repo.addPin(gone.id, Severity.ux, 0, 0);
      expect(repo.pinCounts(a.id), {Severity.bug: 2, Severity.ux: 0, Severity.a11y: 1});
    });
  });

  group('non-destructive edits', () {
    test('crop and annotations are data; the original bytes never change', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('1.png', List.generate(256, (i) => i)));
      final before = hash(s.originalPath);
      final mtime = File(s.originalPath).lastModifiedSync();

      repo.setCrop(s.id, const CropRect(.1, .2, .9, .8));
      repo.addPin(s.id, Severity.bug, .5, .5, note: 'x');
      repo.addAnnotation(s.id, AnnotationKind.redact, {'rect': [.1, .1, .4, .2]});
      repo.addAnnotation(s.id, AnnotationKind.pen, {'points': [[.1, .1], [.2, .3]]});
      repo.setCrop(s.id, null);
      repo.setCrop(s.id, const CropRect(0, 0, .5, .5));

      expect(hash(s.originalPath), before);
      expect(File(s.originalPath).lastModifiedSync(), mtime);
      final edit = repo.loadEdit(s.id)!;
      expect(edit.shot.crop, const CropRect(0, 0, .5, .5));
      expect(edit.pins, hasLength(1));
      expect(edit.annotations.map((a) => a.kind), [AnnotationKind.redact, AnnotationKind.pen]);
      expect(edit.annotations.map((a) => a.z), [0, 1]);
    });
  });

  group('survives a restart', () {
    test('albums, shots, order, pins, annotations, crop and files are all still there', () async {
      final a = repo.createAlbum('Checkout flow review', now: DateTime(2026, 11, 9, 10));
      final s1 = await repo.addShot(a.id, shot('cart.png', [10, 20, 30]), width: 1080, height: 2400);
      final s2 = await repo.addShot(a.id, shot('pay.png', [40, 50, 60]));
      repo.renameShot(s1.id, 'Cart');
      repo.setCaption(s1.id, 'Cart: total changes after shipping');
      repo.setStatus(s1.id, ShotStatus.kept);
      repo.setStatus(s2.id, ShotStatus.kept);
      repo.reorder(a.id, [s2.id, s1.id]);
      repo.setCrop(s1.id, const CropRect(.05, .1, .95, .9));
      repo.addPin(s1.id, Severity.bug, .7, .4, note: 'Total changes');
      repo.addPin(s1.id, Severity.ux, .2, .6);
      repo.addAnnotation(s1.id, AnnotationKind.box, {'rect': [.1, .8, .9, .95]});
      final hashBefore = hash(s1.originalPath);

      repo.close(); // the app is killed
      repo = openRepo(); // the app starts again

      final list = repo.listAlbums();
      expect(list, hasLength(1));
      expect(list.single.album.name, 'Checkout flow review');
      expect(list.single.keptCount, 2);

      final shots = repo.shotsIn(a.id);
      expect(shots.map((s) => s.name), ['', 'Cart'], reason: 'flow order kept');
      final cart = shots.last;
      expect(cart.caption, 'Cart: total changes after shipping');
      expect(cart.width, 1080);
      expect(cart.crop, const CropRect(.05, .1, .95, .9));
      expect(hash(cart.originalPath), hashBefore);
      expect(File(cart.originalPath).readAsBytesSync(), [10, 20, 30]);

      final edit = repo.loadEdit(cart.id)!;
      expect(edit.pins.map((p) => (p.number, p.severity, p.note)),
          [(1, Severity.bug, 'Total changes'), (2, Severity.ux, '')]);
      expect(edit.annotations.single.kind, AnnotationKind.box);
      expect(edit.annotations.single.data['rect'], [.1, .8, .9, .95]);
    });
  });

  group('schema', () {
    test('records its version and reopening does not re-run migrations', () {
      final v = repo; // opened in setUp
      expect(FluoDb.schemaVersion, 2);
      v.createAlbum('keep me');
      v.close();
      repo = openRepo();
      expect(repo.listAlbums(), hasLength(1));
    });

    test('refuses a database from a newer app instead of corrupting it', () {
      repo.close();
      final path = p.join(tmp.path, 'future.db');
      final d = FluoDb.open(path);
      d.db.execute('PRAGMA user_version = ${FluoDb.schemaVersion + 1}');
      d.close();
      expect(() => FluoDb.open(path), throwsStateError);
    });

    test('foreign keys are enforced: a pin for a missing shot is rejected', () {
      
      final a = repo.createAlbum('A');
      expect(a.id, isNotEmpty);
      expect(() => repo.addPin('no-such-shot', Severity.bug, 0, 0), throwsA(anything));
      expect(repo.listAlbums(), hasLength(1));
    });
  });

  group('moveKept', () {
    test('swaps a kept screen with its neighbour in the order people see', () async {
      final a = repo.createAlbum('A');
      final s = [for (var i = 0; i < 4; i++) await repo.addShot(a.id, shot('m$i.png', [i]))];
      for (final x in s) {
        repo.setStatus(x.id, ShotStatus.kept);
      }
      repo.moveKept(a.id, s[2].id, -1);
      expect(repo.shotsIn(a.id, status: ShotStatus.kept).map((x) => x.id), [s[0].id, s[2].id, s[1].id, s[3].id]);
      repo.moveKept(a.id, s[2].id, -1);
      repo.moveKept(a.id, s[2].id, -1); // already first: nothing happens
      expect(repo.shotsIn(a.id, status: ShotStatus.kept).first.id, s[2].id);
      repo.moveKept(a.id, s[3].id, 1); // already last
      expect(repo.shotsIn(a.id, status: ShotStatus.kept).last.id, s[3].id);
    });

    test('pending and discarded shots keep their places between kept ones', () async {
      final a = repo.createAlbum('A');
      final s = [for (var i = 0; i < 5; i++) await repo.addShot(a.id, shot('n$i.png', [i]))];
      repo.setStatus(s[0].id, ShotStatus.kept);
      repo.setStatus(s[2].id, ShotStatus.kept);
      repo.setStatus(s[4].id, ShotStatus.kept);
      repo.setStatus(s[1].id, ShotStatus.discarded);
      // s[3] stays pending
      repo.moveKept(a.id, s[4].id, -1);
      expect(repo.shotsIn(a.id).map((x) => x.id), [s[0].id, s[1].id, s[4].id, s[3].id, s[2].id],
          reason: 'only the kept slots (0, 2, 4) were reassigned');
      expect(repo.shotsIn(a.id, status: ShotStatus.kept).map((x) => x.id), [s[0].id, s[4].id, s[2].id]);
    });

    test('a shot that is not kept, or not in the album, is ignored', () async {
      final a = repo.createAlbum('A');
      final s = await repo.addShot(a.id, shot('o.png', [1]));
      repo.moveKept(a.id, s.id, 1);
      repo.moveKept(a.id, 'nope', -1);
      expect(repo.getShot(s.id)!.position, 0);
    });

    test('survives a restart', () async {
      final a = repo.createAlbum('A');
      final s = [for (var i = 0; i < 3; i++) await repo.addShot(a.id, shot('q$i.png', [i]))];
      for (final x in s) {
        repo.setStatus(x.id, ShotStatus.kept);
      }
      repo.moveKept(a.id, s[0].id, 1);
      repo.close();
      repo = openRepo();
      expect(repo.shotsIn(a.id, status: ShotStatus.kept).map((x) => x.id), [s[1].id, s[0].id, s[2].id]);
    });
  });

  test('updateAnnotation replaces the stored geometry', () async {
    final a = repo.createAlbum('A');
    final s = await repo.addShot(a.id, shot('u.png', [1]));
    final ann = repo.addAnnotation(s.id, AnnotationKind.box, {'rect': [.1, .1, .2, .2]});
    repo.updateAnnotation(ann.id, {'rect': [.3, .3, .6, .5]});
    expect(repo.annotationsFor(s.id).single.data['rect'], [.3, .3, .6, .5]);
  });

  group('purgeDiscarded', () {
    test('removes discarded shots, their pins and files, and closes the gaps; keeps the rest', () async {
      final a = repo.createAlbum('A');
      final s = [for (var i = 0; i < 5; i++) await repo.addShot(a.id, shot('p$i.png', [i]))];
      repo.setStatus(s[0].id, ShotStatus.kept);
      repo.setStatus(s[1].id, ShotStatus.discarded);
      repo.setStatus(s[2].id, ShotStatus.kept);
      repo.setStatus(s[3].id, ShotStatus.discarded);
      // s[4] stays pending
      repo.addPin(s[1].id, Severity.bug, .1, .1);

      expect(await repo.purgeDiscarded(), 2);
      expect(File(s[1].originalPath).existsSync(), isFalse);
      expect(File(s[3].originalPath).existsSync(), isFalse);
      expect(repo.getShot(s[1].id), isNull);
      expect(repo.pinsFor(s[1].id), isEmpty);
      expect(File(s[0].originalPath).existsSync(), isTrue);
      expect(File(s[4].originalPath).existsSync(), isTrue, reason: 'pending is not discarded');
      expect(repo.shotsIn(a.id).map((x) => (x.id, x.position)), [(s[0].id, 0), (s[2].id, 1), (s[4].id, 2)]);
    });

    test('one album only when asked, and nothing to do is fine', () async {
      final a = repo.createAlbum('A');
      final b = repo.createAlbum('B');
      final sa = await repo.addShot(a.id, shot('a.png', [1]));
      final sb = await repo.addShot(b.id, shot('b.png', [2]));
      repo.setStatus(sa.id, ShotStatus.discarded);
      repo.setStatus(sb.id, ShotStatus.discarded);
      expect(await repo.purgeDiscarded(albumId: a.id), 1);
      expect(repo.getShot(sa.id), isNull);
      expect(repo.getShot(sb.id), isNotNull);
      expect(await repo.purgeDiscarded(albumId: a.id), 0);
      expect(await repo.purgeDiscarded(), 1);
    });
  });

  group('migration v1 to v2', () {
    test('upgrades a real v1 database in place and keeps every row', () async {
      repo.close();
      final path = p.join(tmp.path, 'old.db');
      final store = FileStore(Directory(p.join(tmp.path, 'app')));

      // An install that never saw v2.
      final old = FluoRepo(FluoDb.open(path, upTo: 1), store);
      final a = old.createAlbum('Kept through the upgrade');
      final s1 = await old.addShot(a.id, shot('a.png', [1, 2, 3]));
      old.addPin(s1.id, Severity.ux, .3, .3, note: 'still here');
      expect(() => old.activeSession(), throwsA(anything), reason: 'v1 has no sessions table');
      old.close();

      // The app updates and opens it.
      repo = FluoRepo(FluoDb.open(path), store);
      expect(repo.listAlbums().single.album.name, 'Kept through the upgrade');
      expect(repo.shotsIn(a.id).single.id, s1.id);
      expect(repo.pinsFor(s1.id).single.note, 'still here');
      expect(repo.activeSession(), isNull);
      repo.startSession(a.id);
      expect(repo.activeSession()!.albumId, a.id);
    });

    test('a migration that fails half way is rolled back completely', () {
      repo.close();
      final path = p.join(tmp.path, 'v1.db');
      final raw = FluoDb.open(path, upTo: 1);
      // Migration 2 creates the sessions table, then an index. Take the index
      // name so the second statement fails after the first has succeeded.
      raw.db.execute('CREATE TABLE other (y)');
      raw.db.execute('CREATE INDEX one_active_session ON other(y)');
      raw.close();

      expect(() => FluoDb.open(path), throwsA(anything));

      final check = FluoDb.open(path, upTo: 1);
      final version = check.db.select('PRAGMA user_version').first.values.first;
      final tables = check.db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'])
          .toSet();
      check.close();
      expect(version, 1);
      expect(tables, isNot(contains('sessions')), reason: 'the created table was rolled back');
    });
  });

  group('sessions', () {
    test('only one session is active; starting another ends the first', () {
      final a = repo.createAlbum('A');
      final b = repo.createAlbum('B');
      repo.startSession(a.id);
      expect(repo.activeSession()!.albumId, a.id);
      repo.startSession(b.id);
      expect(repo.activeSession()!.albumId, b.id);
      repo.endSession();
      expect(repo.activeSession(), isNull);
    });

    test('pause and resume, and it survives a restart', () {
      final a = repo.createAlbum('A');
      repo.startSession(a.id, now: DateTime(2026, 11, 9, 9));
      repo.setSessionPaused(true);
      repo.close();
      repo = openRepo();
      final s = repo.activeSession()!;
      expect((s.albumId, s.paused, s.startedAt), (a.id, true, DateTime(2026, 11, 9, 9)));
      repo.setSessionPaused(false);
      expect(repo.activeSession()!.paused, isFalse);
    });

    test('deleting the album ends its session', () async {
      final a = repo.createAlbum('A');
      repo.startSession(a.id);
      await repo.deleteAlbum(a.id);
      expect(repo.activeSession(), isNull);
    });
  });
}
