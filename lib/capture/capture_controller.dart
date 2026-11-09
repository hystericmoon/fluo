import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'capture_source.dart';

/// What the session card should tell the user.
enum CaptureStatus {
  /// No session is running.
  off,
  watching,
  paused,
  needsPermission,

  /// Permission was refused for good; the user must use system Settings.
  needsSettings,

  /// Android 14 "selected photos": cannot see new screenshots.
  limitedAccess,
  unsupported,
}

/// Owns the review session lifecycle and moves captured screenshots from the
/// platform inbox into the active album as pending shots.
class CaptureController extends ChangeNotifier {
  CaptureController(this._repo, this._source) {
    _sub = _source.captured.listen((_) => importPending());
  }

  final FluoRepo _repo;
  final CaptureSource _source;
  StreamSubscription<void>? _sub;

  CaptureStatus _status = CaptureStatus.off;
  CaptureStatus get status => _status;

  /// Bumps whenever screenshots were imported, so lists can reload.
  final ValueNotifier<int> imported = ValueNotifier(0);

  bool _importing = false;
  bool _again = false;
  bool _disposed = false;

  ReviewSession? get session => _repo.activeSession();

  void _set(CaptureStatus s) {
    if (_disposed || s == _status) return;
    _status = s;
    notifyListeners();
  }

  /// Makes the platform watcher match the stored session. Safe to call often
  /// (app start, resume, after a permission change).
  Future<void> sync({bool askPermission = false}) async {
    final s = _repo.activeSession();
    if (s == null) {
      await _source.stop();
      _set(CaptureStatus.off);
      return;
    }
    if (!_source.supported) {
      _set(CaptureStatus.unsupported);
      return;
    }
    if (s.paused) {
      await _source.stop();
      _set(CaptureStatus.paused);
      return;
    }
    var p = await _source.permission();
    if (p != CapturePermission.granted && askPermission && p == CapturePermission.denied) {
      p = await _source.requestPermission();
    }
    switch (p) {
      case CapturePermission.granted:
        await _source.start();
        _set(CaptureStatus.watching);
        await importPending();
      case CapturePermission.limited:
        await _source.stop();
        _set(CaptureStatus.limitedAccess);
      case CapturePermission.permanentlyDenied:
        await _source.stop();
        _set(CaptureStatus.needsSettings);
      case CapturePermission.denied:
        await _source.stop();
        _set(CaptureStatus.needsPermission);
      case CapturePermission.unsupported:
        _set(CaptureStatus.unsupported);
    }
  }

  /// Starts a session that captures into [albumId] and asks for access.
  Future<void> begin(String albumId) async {
    _repo.startSession(albumId);
    await sync(askPermission: true);
  }

  Future<void> pause() async {
    _repo.setSessionPaused(true);
    await sync();
  }

  Future<void> resume() async {
    _repo.setSessionPaused(false);
    await sync(askPermission: true);
  }

  /// The card's permission button: ask, or open Settings if asking is over.
  Future<void> fixAccess() async {
    final p = await _source.permission();
    if (p == CapturePermission.denied) {
      await sync(askPermission: true);
    } else {
      await _source.openSettings();
    }
  }

  /// Moves everything in the inbox into the active session's album.
  /// Returns how many screenshots were added.
  Future<int> importPending() async {
    if (_importing) {
      _again = true; // another screenshot arrived mid-import; go round again
      return 0;
    }
    _importing = true;
    var added = 0;
    try {
      do {
        _again = false;
        final incoming = await _source.drain();
        if (incoming.isEmpty) continue;
        final s = _repo.activeSession();
        final take = s != null && !s.paused;
        final done = <String>[];
        for (final shot in incoming) {
          if (!take) {
            // No session wants it. The original is still in the gallery.
            done.add(shot.path);
            continue;
          }
          try {
            await _repo.addShot(
              s.albumId,
              File(shot.path),
              width: shot.width,
              height: shot.height,
              capturedAt: shot.capturedAt,
            );
            await _source.ack([shot.path]); // ack at once: smallest duplicate window
            added++;
          } catch (e) {
            // Leave it in the inbox and try again next time.
            debugPrint('Fluo: could not import ${shot.path}: $e');
          }
        }
        if (done.isNotEmpty) await _source.ack(done);
      } while (_again && !_disposed);
    } finally {
      _importing = false;
    }
    if (added > 0 && !_disposed) {
      imported.value++;
      notifyListeners();
    }
    return added;
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    imported.dispose();
    super.dispose();
  }
}
