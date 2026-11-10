import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluo/data/db.dart';
import 'package:fluo/data/file_store.dart';
import 'package:fluo/data/models.dart';
import 'package:fluo/data/repository.dart';
import 'package:fluo/data/triage_session.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late FluoRepo repo;
  late Album album;

  Future<List<Shot>> addShots(int n, {Album? to}) async {
    final out = <Shot>[];
    for (var i = 0; i < n; i++) {
      final f = File(p.join(tmp.path, 'in', '${DateTime.now().microsecondsSinceEpoch}_$i.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([i]);
      out.add(await repo.addShot((to ?? album).id, f));
    }
    return out;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fluo_triage_');
    repo = FluoRepo(FluoDb.openInMemory(), FileStore(Directory(p.join(tmp.path, 'app'))));
    album = repo.createAlbum('Checkout');
  });

  tearDown(() {
    repo.close();
    tmp.deleteSync(recursive: true);
  });

  test('starts on the oldest pending shot and counts the pass', () async {
    final shots = await addShots(3);
    final t = TriageSession(repo, album.id);
    expect((t.total, t.position, t.isDone), (3, 1, false));
    expect(t.current!.id, shots.first.id);
  });

  test('keep and discard write to the database and move on', () async {
    final s = await addShots(3);
    final t = TriageSession(repo, album.id);
    t.keep();
    t.discard();
    expect(repo.getShot(s[0].id)!.status, ShotStatus.kept);
    expect(repo.getShot(s[1].id)!.status, ShotStatus.discarded);
    expect(repo.getShot(s[2].id)!.status, ShotStatus.pending);
    expect((t.position, t.keptCount, t.discardedCount), (3, 1, 1));
    t.keep();
    expect(t.isDone, isTrue);
    expect(t.current, isNull);
    expect((t.keptCount, t.discardedCount), (2, 1));
  });

  test('keep and discard do nothing once everything is sorted', () async {
    await addShots(1);
    final t = TriageSession(repo, album.id)..keep();
    t.keep();
    t.discard();
    expect((t.keptCount, t.discardedCount, t.canUndo), (1, 0, true));
  });

  test('undo restores the last decision and returns that shot to the top', () async {
    final s = await addShots(3);
    final t = TriageSession(repo, album.id);
    expect(t.canUndo, isFalse);
    t.keep();
    t.discard();
    t.undo();
    expect(repo.getShot(s[1].id)!.status, ShotStatus.pending);
    expect(t.current!.id, s[1].id);
    expect((t.position, t.discardedCount), (2, 0));
    t.undo();
    expect(t.current!.id, s[0].id);
    expect(repo.getShot(s[0].id)!.status, ShotStatus.pending);
    expect(t.canUndo, isFalse);
    t.undo(); // nothing left: harmless
    expect(t.current!.id, s[0].id);
  });

  test('undo works after the last shot is sorted', () async {
    final s = await addShots(2);
    final t = TriageSession(repo, album.id)..keep();
    t.discard();
    expect(t.isDone, isTrue);
    t.undo();
    expect(t.isDone, isFalse);
    expect(t.current!.id, s[1].id);
  });

  test('a changed mind costs nothing: re-deciding after undo uses the new choice', () async {
    final s = await addShots(1);
    final t = TriageSession(repo, album.id)..keep();
    t.undo();
    t.discard();
    expect(repo.getShot(s[0].id)!.status, ShotStatus.discarded);
    expect((t.keptCount, t.discardedCount), (0, 1));
  });

  test('names are saved on the shot on top and survive undo', () async {
    final s = await addShots(2);
    final t = TriageSession(repo, album.id);
    t.rename('  Cart ');
    t.keep();
    t.rename('Payment');
    expect(repo.getShot(s[0].id)!.name, 'Cart');
    expect(repo.getShot(s[1].id)!.name, 'Payment');
    t.undo();
    expect(t.current!.name, 'Cart');
    t.rename('');
    expect(repo.getShot(s[0].id)!.name, '');
  });

  test('rename with nothing on top does nothing', () async {
    final t = TriageSession(repo, album.id);
    t.rename('x');
    expect(t.isDone, isTrue);
  });

  test('only this album and only pending shots are in the pass', () async {
    final other = repo.createAlbum('Other');
    final mine = await addShots(2);
    await addShots(2, to: other);
    repo.setStatus(mine[0].id, ShotStatus.kept); // sorted in an earlier pass
    final t = TriageSession(repo, album.id);
    expect(t.total, 1);
    expect(t.current!.id, mine[1].id);
  });

  test('an empty album is done straight away', () {
    final t = TriageSession(repo, album.id);
    expect((t.isDone, t.total, t.current), (true, 0, null));
  });

  test('absorbNew adds screenshots that arrive mid-pass and never repeats one', () async {
    final first = await addShots(2);
    final t = TriageSession(repo, album.id);
    t.keep();
    final late = await addShots(2);
    expect(t.absorbNew(), 2);
    expect(t.total, 4);
    expect(t.absorbNew(), 0, reason: 'already known');
    t.keep();
    t.keep();
    expect(t.current!.id, late[1].id);
    expect(repo.getShot(first[0].id)!.status, ShotStatus.kept);
  });

  test('a half-finished pass keeps its decisions and leaves the rest pending', () async {
    final s = await addShots(4);
    TriageSession(repo, album.id)
      ..keep()
      ..discard(); // user leaves here
    final again = TriageSession(repo, album.id);
    expect(again.total, 2);
    expect(again.current!.id, s[2].id);
    expect(repo.listAlbums().single.keptCount, 1);
  });

  test('pinsInAlbum groups pins by shot in pin order', () async {
    final s = await addShots(2);
    repo.addPin(s[0].id, Severity.bug, .1, .1);
    repo.addPin(s[0].id, Severity.ux, .2, .2);
    repo.addPin(s[1].id, Severity.a11y, .3, .3);
    final m = repo.pinsInAlbum(album.id);
    expect(m[s[0].id]!.map((p) => p.number), [1, 2]);
    expect(m[s[1].id]!.single.severity, Severity.a11y);
    expect(repo.pinsInAlbum(repo.createAlbum('Empty').id), isEmpty);
  });
}
