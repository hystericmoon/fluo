import 'package:sqlite3/sqlite3.dart';

/// Opens the SQLite database and brings its schema up to date.
///
/// Migrations are append-only: add a new entry to [_migrations], never edit
/// an old one. `PRAGMA user_version` records how many have run.
class FluoDb {
  FluoDb._(this.db);
  final Database db;

  /// [upTo] stops migrating early. Only for tests that need an old schema.
  static FluoDb open(String path, {int? upTo}) =>
      FluoDb._(_prepare(sqlite3.open(path), upTo ?? _migrations.length));

  static FluoDb openInMemory() =>
      FluoDb._(_prepare(sqlite3.openInMemory(), _migrations.length));

  static int get schemaVersion => _migrations.length;

  static Database _prepare(Database db, int target) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    final current = db.select('PRAGMA user_version').first.values.first as int;
    if (current > _migrations.length) {
      db.close();
      throw StateError(
        'Database is version $current but this app only knows up to '
        '${_migrations.length}. Update Fluo.',
      );
    }
    for (var v = current; v < target; v++) {
      db.execute('BEGIN');
      try {
        db.execute(_migrations[v]);
        db.execute('PRAGMA user_version = ${v + 1}');
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        db.close(); // do not leak a connection when the app cannot start
        rethrow;
      }
    }
    return db;
  }

  void close() => db.close();
}

const _migrations = <String>[
  // 1: albums, shots, pins, annotations.
  '''
  CREATE TABLE albums (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );

  CREATE TABLE shots (
    id            TEXT PRIMARY KEY,
    album_id      TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    name          TEXT NOT NULL DEFAULT '',
    caption       TEXT NOT NULL DEFAULT '',
    position      INTEGER NOT NULL,
    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'kept', 'discarded')),
    original_path TEXT NOT NULL,           -- relative to the file store root
    width         INTEGER,
    height        INTEGER,
    crop          TEXT,                    -- JSON [l, t, r, b], 0..1, or NULL
    captured_at   INTEGER NOT NULL,
    created_at    INTEGER NOT NULL
  );
  CREATE INDEX shots_by_album ON shots(album_id, position);

  CREATE TABLE pins (
    id       TEXT PRIMARY KEY,
    shot_id  TEXT NOT NULL REFERENCES shots(id) ON DELETE CASCADE,
    number   INTEGER NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('bug', 'ux', 'a11y')),
    x        REAL NOT NULL,
    y        REAL NOT NULL,
    note     TEXT NOT NULL DEFAULT ''
  );
  CREATE INDEX pins_by_shot ON pins(shot_id, number);

  CREATE TABLE annotations (
    id      TEXT PRIMARY KEY,
    shot_id TEXT NOT NULL REFERENCES shots(id) ON DELETE CASCADE,
    kind    TEXT NOT NULL CHECK (kind IN ('pen', 'arrow', 'box', 'redact')),
    data    TEXT NOT NULL,                 -- JSON vector data, 0..1 coords
    z       INTEGER NOT NULL
  );
  CREATE INDEX annotations_by_shot ON annotations(shot_id, z);
  ''',
  // 2: review sessions. At most one is active (ended_at IS NULL): new
  // screenshots land in its album unless it is paused.
  '''
  CREATE TABLE sessions (
    id         TEXT PRIMARY KEY,
    album_id   TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    started_at INTEGER NOT NULL,
    ended_at   INTEGER,
    paused     INTEGER NOT NULL DEFAULT 0 CHECK (paused IN (0, 1))
  );
  CREATE UNIQUE INDEX one_active_session ON sessions((1)) WHERE ended_at IS NULL;
  ''',
];
