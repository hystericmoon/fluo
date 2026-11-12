import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Window width from which the desktop layout (sidebar, grid, inspector)
/// replaces the phone screens. Narrower windows keep the phone UI.
const double kDesktopMinWidth = 900;

/// Commands sent from the native macOS menu bar to the desktop shell.
class DesktopCommands {
  final _c = StreamController<String>.broadcast();
  Stream<String> get stream => _c.stream;
  void send(String command) => _c.add(command);
  void dispose() => _c.close();
}

/// Says whether this build uses the desktop layout at all (macOS only, set
/// from `main`). Tests and phones leave it off, so their widget tree is the
/// phone one.
class DesktopScope extends InheritedWidget {
  const DesktopScope({
    super.key,
    required this.enabled,
    required this.commands,
    required super.child,
  });
  final bool enabled;
  final DesktopCommands commands;

  static DesktopScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopScope>();

  /// Desktop build and a window wide enough for the desktop layout.
  static bool isWide(BuildContext context) =>
      (maybeOf(context)?.enabled ?? false) &&
      MediaQuery.sizeOf(context).width >= kDesktopMinWidth;

  /// Desktop build, whatever the window width (keyboard shortcuts, hover).
  static bool isDesktop(BuildContext context) => maybeOf(context)?.enabled ?? false;

  @override
  bool updateShouldNotify(DesktopScope old) => enabled != old.enabled;
}

/// True while a text field has keyboard focus. Single-key shortcuts (K, D,
/// arrows, Space...) must not fire then, or typing a name would trigger them.
bool typingInTextField() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}
