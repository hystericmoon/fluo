import 'package:flutter/widgets.dart';

import 'update_controller.dart';

class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({super.key, required UpdateController controller, required super.child})
      : super(notifier: controller);

  static UpdateController of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<UpdateScope>();
    assert(s != null, 'No UpdateScope above this context');
    return s!.notifier!;
  }
}
