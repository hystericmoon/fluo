import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../theme/accent.dart';

/// The person's choices, kept in the local database. Changing one saves it
/// and tells the app, so the theme or motion change applies at once.
class AppSettings extends ChangeNotifier {
  AppSettings(this._repo)
      : _accent = Accent.byId(_repo.getSetting(_kAccent)),
        _reduceMotion = _repo.getSetting(_kReduceMotion) == 'true',
        _autoUpdate = _repo.getSetting(_kAutoUpdate) != 'false', // on unless turned off
        _wifiOnly = _repo.getSetting(_kWifiOnly) != 'false'; // on unless turned off

  static const _kAccent = 'accent';
  static const _kReduceMotion = 'reduce_motion';
  static const _kAutoUpdate = 'auto_update';
  static const _kWifiOnly = 'wifi_only';
  static const _kLastUpdateCheck = 'last_update_check';

  final FluoRepo _repo;
  Accent _accent;
  bool _reduceMotion;
  bool _autoUpdate;
  bool _wifiOnly;

  Accent get accent => _accent;

  /// The in-app switch. The system "remove animations" setting applies on top.
  bool get reduceMotion => _reduceMotion;

  /// Check for new versions on launch and download them in the background.
  bool get autoUpdate => _autoUpdate;

  /// With auto-update on, only download on an unmetered connection.
  bool get wifiOnly => _wifiOnly;

  void setAccent(Accent a) {
    if (a == _accent) return;
    _accent = a;
    _repo.setSetting(_kAccent, a.id);
    notifyListeners();
  }

  void setReduceMotion(bool v) {
    if (v == _reduceMotion) return;
    _reduceMotion = v;
    _repo.setSetting(_kReduceMotion, '$v');
    notifyListeners();
  }

  void setAutoUpdate(bool v) {
    if (v == _autoUpdate) return;
    _autoUpdate = v;
    _repo.setSetting(_kAutoUpdate, '$v');
    notifyListeners();
  }

  void setWifiOnly(bool v) {
    if (v == _wifiOnly) return;
    _wifiOnly = v;
    _repo.setSetting(_kWifiOnly, '$v');
    notifyListeners();
  }

  /// When the app last asked about updates, to avoid asking on every launch.
  DateTime? get lastUpdateCheck {
    final ms = int.tryParse(_repo.getSetting(_kLastUpdateCheck) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastUpdateCheck(DateTime? t) {
    if (t == null) {
      _repo.removeSetting(_kLastUpdateCheck);
    } else {
      _repo.setSetting(_kLastUpdateCheck, '${t.millisecondsSinceEpoch}');
    }
  }
}
