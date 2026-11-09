import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'file_store.dart';
import 'models.dart';

/// All reads and writes for albums, screenshots, pins and edits.
///
/// Edits are non-destructive: crop and annotations are rows of vector data
/// and the original file is never touched.
class FluoRepo {
  FluoRepo(this._fdb, this._files);

  final FluoDb _fdb;
  final FileStore _files;
  Database get _db => _fdb.db;

  static final _rng = Random.secure();
  static String newId() =>
      List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static DateTime _t(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int);
  static int _ms(DateTime t) => t.millisecondsSinceEpoch;

  T _tx<T>(T Function() body) {
    _db.execute('BEGIN');
    try {
      final r = body();
      _db.execute('COMMIT');
      return r;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _fdb.close();

  // ---- Albums ------------------------------------------------------------

  Album createAlbum(String name, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final id = newId();
    _db.execute('INSERT INTO albums (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [id, name.trim(), _ms(t), _ms(t)]);
    return Album(id: id, name: name.trim(), createdAt: t, updatedAt: t);
  }

  Album _album(Row r) => Album(
        id: r['id'] as String,
        name: r['name'] as String,
        createdAt: _t(r['created_at']),
        updatedAt: _t(r['updated_at']),
      );

  Album? getAlbum(String id) {
    final rows = _db.select('SELECT * FROM albums WHERE id = ?', [id]);
    return rows.isEmpty ? null : _album(rows.first);
  }

  /// Newest activity first.
  List<AlbumSummary> listAlbums() {
    final rows = _db.select('''
      SELECT a.*,
        (SELECT COUNT(*) FROM shots s WHERE s.album_id = a.id AND s.status = 'kept')    AS kept,
        (SELECT COUNT(*) FROM shots s WHERE s.album_id = a.id AND s.status = 'pending') AS pending
      FROM albums a
      ORDER BY a.updated_at DESC, a.created_at DESC
    ''');
    return [
      for (final r in rows)
        AlbumSummary(
          album: _album(r),
          keptCount: r['kept'] as int,
          pendingCount: r['pending'] as int,
          thumbnailPaths: [
            for (final t in _db.select(
                "SELECT original_path FROM shots WHERE album_id = ? AND status = 'kept' ORDER BY position LIMIT 3",
                [r['id']]))
              _files.resolve(t['original_path'] as String),
          ],
        ),
    ];
  }

  void renameAlbum(String id, String name, {DateTime? now}) {
    _db.execute('UPDATE albums SET name = ?, updated_at = ? WHERE id = ?',
        [name.trim(), _ms(now ?? DateTime.now()), id]);
  }

  /// Deletes the album, its rows (cascade) and its original files.
  Future<void> deleteAlbum(String id) async {
    final files = [
      for (final r in _db.select('SELECT original_path FROM shots WHERE album_id = ?', [id]))
        r['original_path'] as String,
    ];
    _db.execute('DELETE FROM albums WHERE id = ?', [id]);
    for (final f in files) {
      await _files.delete(f);
    }
  }

  void _touch(String albumId, [DateTime? now]) => _db.execute(
      'UPDATE albums SET updated_at = ? WHERE id = ?', [_ms(now ?? DateTime.now()), albumId]);

  // ---- Shots -------------------------------------------------------------

  Shot _shot(Row r) => Shot(
        id: r['id'] as String,
        albumId: r['album_id'] as String,
        name: r['name'] as String,
        caption: r['caption'] as String,
        position: r['position'] as int,
        status: ShotStatus.values.byName(r['status'] as String),
        originalPath: _files.resolve(r['original_path'] as String),
        width: r['width'] as int?,
        height: r['height'] as int?,
        crop: r['crop'] == null ? null : CropRect.fromJson(r['crop'] as String),
        capturedAt: _t(r['captured_at']),
        createdAt: _t(r['created_at']),
      );

  /// Copies [source] into the file store and adds it to the album as pending.
  /// The source file is left alone.
  Future<Shot> addShot(
    String albumId,
    File source, {
    int? width,
    int? height,
    DateTime? capturedAt,
    DateTime? now,
  }) async {
    final id = newId();
    final rel = await _files.importOriginal(source, id);
    final t = now ?? DateTime.now();
    try {
      _tx(() {
        final pos = _db
            .select('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM shots WHERE album_id = ?', [albumId])
            .first['p'] as int;
        _db.execute('''
          INSERT INTO shots (id, album_id, position, original_path, width, height, captured_at, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [id, albumId, pos, rel, width, height, _ms(capturedAt ?? t), _ms(t)]);
        _touch(albumId, t);
      });
    } catch (_) {
      await _files.delete(rel); // do not orphan the copy if the row failed
      rethrow;
    }
    return getShot(id)!;
  }

  Shot? getShot(String id) {
    final rows = _db.select('SELECT * FROM shots WHERE id = ?', [id]);
    return rows.isEmpty ? null : _shot(rows.first);
  }

  /// Shots in flow order, optionally limited to one [status].
  List<Shot> shotsIn(String albumId, {ShotStatus? status}) {
    final rows = status == null
        ? _db.select('SELECT * FROM shots WHERE album_id = ? ORDER BY position', [albumId])
        : _db.select('SELECT * FROM shots WHERE album_id = ? AND status = ? ORDER BY position',
            [albumId, status.name]);
    return [for (final r in rows) _shot(r)];
  }

  void setStatus(String shotId, ShotStatus status) {
    _tx(() {
      _db.execute('UPDATE shots SET status = ? WHERE id = ?', [status.name, shotId]);
      final a = getShot(shotId)?.albumId;
      if (a != null) _touch(a);
    });
  }

  void renameShot(String shotId, String name) =>
      _db.execute('UPDATE shots SET name = ? WHERE id = ?', [name.trim(), shotId]);

  void setCaption(String shotId, String caption) =>
      _db.execute('UPDATE shots SET caption = ? WHERE id = ?', [caption, shotId]);

  void setCrop(String shotId, CropRect? crop) =>
      _db.execute('UPDATE shots SET crop = ? WHERE id = ?', [crop?.toJson(), shotId]);

  /// Sets flow order. [orderedIds] must be exactly the album's shots.
  void reorder(String albumId, List<String> orderedIds) {
    _tx(() {
      final existing = {
        for (final r in _db.select('SELECT id FROM shots WHERE album_id = ?', [albumId])) r['id'] as String
      };
      if (existing.length != orderedIds.length || !existing.containsAll(orderedIds)) {
        throw ArgumentError('orderedIds must list every shot in the album exactly once');
      }
      for (var i = 0; i < orderedIds.length; i++) {
        _db.execute('UPDATE shots SET position = ? WHERE id = ?', [i, orderedIds[i]]);
      }
      _touch(albumId);
    });
  }

  Future<void> deleteShot(String shotId) async {
    final s = getShot(shotId);
    if (s == null) return;
    final rel = _db.select('SELECT original_path FROM shots WHERE id = ?', [shotId]).first['original_path'] as String;
    _tx(() {
      _db.execute('DELETE FROM shots WHERE id = ?', [shotId]);
      // Close the gap so positions stay 0..n-1.
      final ids = [
        for (final r in _db.select('SELECT id FROM shots WHERE album_id = ? ORDER BY position', [s.albumId]))
          r['id'] as String
      ];
      for (var i = 0; i < ids.length; i++) {
        _db.execute('UPDATE shots SET position = ? WHERE id = ?', [i, ids[i]]);
      }
      _touch(s.albumId);
    });
    await _files.delete(rel);
  }

  // ---- Pins --------------------------------------------------------------

  Pin _pin(Row r) => Pin(
        id: r['id'] as String,
        shotId: r['shot_id'] as String,
        number: r['number'] as int,
        severity: Severity.values.byName(r['severity'] as String),
        x: (r['x'] as num).toDouble(),
        y: (r['y'] as num).toDouble(),
        note: r['note'] as String,
      );

  Pin addPin(String shotId, Severity severity, double x, double y, {String note = ''}) {
    final id = newId();
    return _tx(() {
      final n = _db.select('SELECT COALESCE(MAX(number), 0) + 1 AS n FROM pins WHERE shot_id = ?', [shotId])
          .first['n'] as int;
      _db.execute(
          'INSERT INTO pins (id, shot_id, number, severity, x, y, note) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [id, shotId, n, severity.name, x, y, note]);
      return _pin(_db.select('SELECT * FROM pins WHERE id = ?', [id]).first);
    });
  }

  List<Pin> pinsFor(String shotId) => [
        for (final r in _db.select('SELECT * FROM pins WHERE shot_id = ? ORDER BY number', [shotId])) _pin(r)
      ];

  void updatePin(String pinId, {Severity? severity, double? x, double? y, String? note}) {
    final r = _db.select('SELECT * FROM pins WHERE id = ?', [pinId]);
    if (r.isEmpty) return;
    final p = _pin(r.first);
    _db.execute('UPDATE pins SET severity = ?, x = ?, y = ?, note = ? WHERE id = ?',
        [(severity ?? p.severity).name, x ?? p.x, y ?? p.y, note ?? p.note, pinId]);
  }

  /// Deletes a pin and renumbers the rest so numbers stay 1..n.
  void deletePin(String pinId) {
    _tx(() {
      final r = _db.select('SELECT shot_id FROM pins WHERE id = ?', [pinId]);
      if (r.isEmpty) return;
      final shotId = r.first['shot_id'] as String;
      _db.execute('DELETE FROM pins WHERE id = ?', [pinId]);
      final ids = [
        for (final x in _db.select('SELECT id FROM pins WHERE shot_id = ? ORDER BY number', [shotId]))
          x['id'] as String
      ];
      for (var i = 0; i < ids.length; i++) {
        _db.execute('UPDATE pins SET number = ? WHERE id = ?', [i + 1, ids[i]]);
      }
    });
  }

  /// Pin counts per severity across the album's kept shots (filter chips).
  Map<Severity, int> pinCounts(String albumId) {
    final rows = _db.select('''
      SELECT p.severity AS s, COUNT(*) AS c
      FROM pins p JOIN shots s ON s.id = p.shot_id
      WHERE s.album_id = ? AND s.status = 'kept'
      GROUP BY p.severity
    ''', [albumId]);
    return {
      for (final sev in Severity.values) sev: 0,
      for (final r in rows) Severity.values.byName(r['s'] as String): r['c'] as int,
    };
  }

  // ---- Annotations -------------------------------------------------------

  Annotation _ann(Row r) => Annotation(
        id: r['id'] as String,
        shotId: r['shot_id'] as String,
        kind: AnnotationKind.values.byName(r['kind'] as String),
        data: (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(),
        z: r['z'] as int,
      );

  Annotation addAnnotation(String shotId, AnnotationKind kind, Map<String, Object?> data) {
    final id = newId();
    return _tx(() {
      final z = _db.select('SELECT COALESCE(MAX(z), -1) + 1 AS z FROM annotations WHERE shot_id = ?', [shotId])
          .first['z'] as int;
      _db.execute('INSERT INTO annotations (id, shot_id, kind, data, z) VALUES (?, ?, ?, ?, ?)',
          [id, shotId, kind.name, jsonEncode(data), z]);
      return _ann(_db.select('SELECT * FROM annotations WHERE id = ?', [id]).first);
    });
  }

  List<Annotation> annotationsFor(String shotId) => [
        for (final r in _db.select('SELECT * FROM annotations WHERE shot_id = ? ORDER BY z', [shotId])) _ann(r)
      ];

  void deleteAnnotation(String id) => _db.execute('DELETE FROM annotations WHERE id = ?', [id]);

  // ---- Edits -------------------------------------------------------------

  /// Crop, pins and annotations for the Editor and the exporters.
  ShotEdit? loadEdit(String shotId) {
    final s = getShot(shotId);
    if (s == null) return null;
    return ShotEdit(shot: s, pins: pinsFor(shotId), annotations: annotationsFor(shotId));
  }
}
