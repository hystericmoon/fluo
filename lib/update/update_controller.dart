import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import 'update_source.dart';

enum UpdateState {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// Downloaded; applying it restarts the app.
  ready,

  /// This copy cannot be updated from inside the app.
  unavailable,
  failed,
}

/// Runs update checks and downloads and tells Settings where things stand.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.settings,
    required this.source,
    required this.network,
    required this.appInfo,
    this.minGap = const Duration(hours: 12),
  }) {
    _sub = source.phases.listen(_onPhase, onError: (_) {});
    appInfo.load().then((i) {
      info = i;
      notifyListeners();
    }).catchError((_) {});
  }

  final AppSettings settings;
  final UpdateSource source;
  final NetworkInfo network;
  final AppInfoSource appInfo;

  /// The least time between automatic checks.
  final Duration minGap;

  StreamSubscription<UpdatePhase>? _sub;
  UpdateState _state = UpdateState.idle;
  AppInfo? info;
  bool _disposed = false;

  UpdateState get state => _state;

  void _set(UpdateState s) {
    if (_disposed) return;
    _state = s;
    notifyListeners();
  }

  void _onPhase(UpdatePhase p) {
    switch (p) {
      case UpdatePhase.downloading:
        if (_state != UpdateState.ready) _set(UpdateState.downloading);
      case UpdatePhase.downloaded:
        _set(UpdateState.ready);
      case UpdatePhase.failed:
        _set(UpdateState.failed);
    }
  }

  /// "Check for updates": ignores the Wi-Fi setting, since the person asked.
  Future<void> checkNow() async {
    if (_state == UpdateState.checking || _state == UpdateState.downloading) return;
    _set(UpdateState.checking);
    try {
      final available = await source.checkAvailable();
      _set(available ? UpdateState.available : UpdateState.upToDate);
    } on UpdateUnsupported {
      _set(UpdateState.unavailable);
    } catch (_) {
      _set(UpdateState.failed);
    }
  }

  /// Starts the download of an available update.
  Future<void> download() async {
    if (_state != UpdateState.available) return;
    _set(UpdateState.downloading);
    final started = await source.startDownload();
    if (!started && _state == UpdateState.downloading) _set(UpdateState.available);
  }

  Future<void> install() async {
    if (_state != UpdateState.ready) return;
    await source.installDownloaded();
  }

  /// On launch: if auto-update is on, not asked about recently, and the
  /// connection suits ("Wi-Fi only"), look for an update and download it.
  Future<void> autoCheck({DateTime? now}) async {
    if (!settings.autoUpdate) return;
    final t = now ?? DateTime.now();
    final last = settings.lastUpdateCheck;
    if (last != null && t.difference(last) < minGap) return;
    if (settings.wifiOnly && !await network.isUnmetered()) return; // try again next launch
    settings.lastUpdateCheck = t;
    await checkNow();
    if (_state == UpdateState.available) await download();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
