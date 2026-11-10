import 'package:flutter/widgets.dart';

/// App-level motion preference. The system "remove animations" setting always
/// wins; this adds an in-app switch (Settings, session 9).
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.reduce, required super.child});
  final bool reduce;

  static bool reduced(BuildContext context) {
    final system = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final app = context.dependOnInheritedWidgetOfExactType<MotionScope>()?.reduce ?? false;
    return system || app;
  }

  @override
  bool updateShouldNotify(MotionScope old) => reduce != old.reduce;
}

/// True when animations should be skipped (WCAG 2.3.3, and the user's choice).
bool reducedMotion(BuildContext context) => MotionScope.reduced(context);

/// [d] normally, zero when motion is reduced.
Duration motionDuration(BuildContext context, Duration d) => reducedMotion(context) ? Duration.zero : d;
