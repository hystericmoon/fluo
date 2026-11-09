import 'package:flutter/widgets.dart';

import 'app_settings.dart';

/// Gives screens the settings and rebuilds them when a choice changes.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child}) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(s != null, 'No SettingsScope above this context');
    return s!.notifier!;
  }
}
