import 'models.dart';
import 'repository.dart';

class _Decision {
  const _Decision(this.shotId, this.status);
  final String shotId;
  final ShotStatus status;
}

/// One pass through an album's pending screenshots: Keep, Discard, Undo and
/// naming. Every decision is written to the database straight away, so
/// leaving the screen half way loses nothing, and what is left stays pending.
class TriageSession {
  TriageSession(this._repo, this.albumId) {
    _queue.addAll(_repo.shotsIn(albumId, status: ShotStatus.pending).map((s) => s.id));
  }

  final FluoRepo _repo;
  final String albumId;
  final List<String> _queue = [];
  final List<_Decision> _history = [];
  int _cursor = 0;

  /// The screenshot on top, or null when everything has been sorted.
  Shot? get current => _cursor < _queue.length ? _repo.getShot(_queue[_cursor]) : null;

  /// How many this pass covers, and which one is on top (1-based).
  int get total => _queue.length;
  int get position => _cursor + 1;

  int get keptCount => _history.where((d) => d.status == ShotStatus.kept).length;
  int get discardedCount => _history.where((d) => d.status == ShotStatus.discarded).length;
  bool get canUndo => _history.isNotEmpty;
  bool get isDone => _cursor >= _queue.length;

  void keep() => _decide(ShotStatus.kept);
  void discard() => _decide(ShotStatus.discarded);

  void _decide(ShotStatus status) {
    if (isDone) return;
    final id = _queue[_cursor];
    _repo.setStatus(id, status);
    _history.add(_Decision(id, status));
    _cursor++;
  }

  /// Puts the last decision back: that screenshot is pending again and on top.
  void undo() {
    if (_history.isEmpty) return;
    final d = _history.removeLast();
    _repo.setStatus(d.shotId, ShotStatus.pending);
    _cursor--;
  }

  /// Names the screenshot on top. A blank name clears it.
  void rename(String name) {
    final id = isDone ? null : _queue[_cursor];
    if (id != null) _repo.renameShot(id, name);
  }

  /// Adds screenshots that arrived while this screen was open to the end of
  /// the queue. Returns how many were added.
  int absorbNew() {
    final known = _queue.toSet();
    final fresh = [
      for (final s in _repo.shotsIn(albumId, status: ShotStatus.pending))
        if (!known.contains(s.id)) s.id,
    ];
    _queue.addAll(fresh);
    return fresh.length;
  }
}
