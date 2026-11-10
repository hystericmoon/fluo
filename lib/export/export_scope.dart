import 'package:flutter/widgets.dart';

import 'export_service.dart';

/// Hands the export settings (share sheet, work folder) to screens.
class ExportScope extends InheritedWidget {
  const ExportScope({super.key, required this.services, required super.child});
  final ExportServices services;

  static ExportServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ExportScope>();
    assert(s != null, 'No ExportScope above this context');
    return s!.services;
  }

  @override
  bool updateShouldNotify(ExportScope old) => services != old.services;
}
