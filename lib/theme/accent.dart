import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// One selectable colour theme. The app is always dark; the accent is what
/// changes: primary buttons, selected chips, focus rings, the live border.
/// The FLUO wordmark and app icon stay lime in every theme.
class Accent {
  const Accent({
    required this.id,
    required this.name,
    required this.color,
    required this.soft,
    required this.text,
    this.onColor = FluoColors.onLime,
  });

  final String id;
  final String name;

  /// The accent itself: fills, borders, rings.
  final Color color;

  /// A very dark tint of it, for selected fills and the live session card.
  final Color soft;

  /// Readable text on [soft].
  final Color text;

  /// Text and icons on top of [color].
  final Color onColor;

  static const lime = Accent(
      id: 'lime', name: 'Neon lime', color: FluoColors.lime, soft: FluoColors.limeTint, text: FluoColors.limeSoft);
  static const violet = Accent(
      id: 'violet', name: 'Violet', color: Color(0xFF8B7CF6), soft: Color(0xFF1F1B3A), text: Color(0xFFC9C2FF));
  static const cyan =
      Accent(id: 'cyan', name: 'Cyan', color: Color(0xFF22D3EE), soft: Color(0xFF0B2A30), text: Color(0xFF8BE8F7));
  static const orange = Accent(
      id: 'orange', name: 'Orange', color: Color(0xFFFF8A3D), soft: Color(0xFF2E1A0B), text: Color(0xFFFFC08F));
  static const pink =
      Accent(id: 'pink', name: 'Pink', color: Color(0xFFFF5FA2), soft: Color(0xFF2E0F1F), text: Color(0xFFFFA8CD));

  /// In the order Settings shows them. Neon lime is the default.
  static const all = [lime, violet, cyan, orange, pink];

  static Accent byId(String? id) => all.firstWhere((a) => a.id == id, orElse: () => lime);
}

/// Hands the current accent to widgets. Widgets that use the accent depend on
/// this, so changing the theme rebuilds exactly those.
class AccentScope extends InheritedWidget {
  const AccentScope({super.key, required this.accent, required super.child});
  final Accent accent;

  static Accent of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccentScope>()?.accent ?? Accent.lime;

  @override
  bool updateShouldNotify(AccentScope old) => accent != old.accent;
}

extension AccentContext on BuildContext {
  Accent get accent => AccentScope.of(this);
}
