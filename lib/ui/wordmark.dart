import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// FLUO in Lexend 600, +0.14em tracking. Always lime, in every theme.
class FluoWordmark extends StatelessWidget {
  const FluoWordmark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Fluo',
      excludeSemantics: true,
      child: Padding(
        // Trailing tracking is added after the last glyph; offset it so the
        // word stays optically centred.
        padding: EdgeInsets.only(left: size * 0.14),
        child: Text(
          'FLUO',
          style: FluoFonts.lexend(size, tracking: 0.14).copyWith(
            color: FluoColors.lime,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Stacked "F L / U O" on a dark tile.
class FluoIcon extends StatelessWidget {
  const FluoIcon({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = FluoFonts.lexend(size * 0.375, weight: 800).copyWith(
      color: FluoColors.lime,
      height: 0.9,
    );
    Widget row(String a, String b) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(a, style: style), Text(b, style: style)],
        );
    return Semantics(
      label: 'Fluo app icon',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FluoColors.bg,
          borderRadius: BorderRadius.circular(size * 0.229),
          border: Border.all(color: FluoColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [row('F', 'L'), row('U', 'O')],
        ),
      ),
    );
  }
}
