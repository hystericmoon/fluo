import 'package:flutter/widgets.dart';

import 'capture_controller.dart';

/// Gives screens the capture controller and rebuilds them when it changes.
class CaptureScope extends InheritedNotifier<CaptureController> {
  const CaptureScope({super.key, required CaptureController controller, required super.child})
      : super(notifier: controller);

  static CaptureController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<CaptureScope>();
    assert(s != null, 'No CaptureScope above this context');
    return s!.notifier!;
  }
}
