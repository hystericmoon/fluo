import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../ui/fake_shot.dart';
import '../ui/kit.dart';
import 'album.dart';

/// Card stack triage. Static for now: buttons are inert until session 5.
class TriageScreen extends StatelessWidget {
  const TriageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  title: 'Triage',
                  subtitle: 'Checkout flow review · 1 of 7',
                  leading: backButton(context, label: 'Back to albums'),
                  trailing: [
                    FluoButton(
                      label: 'Done',
                      hPad: 18,
                      onPressed: () => Navigator.of(context)
                          .push(fluoRoute(const AlbumScreen(title: 'Checkout flow review'))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 500,
                  child: Center(
                    child: Semantics(
                      image: true,
                      label:
                          'Screenshot 1 of 7: a cart screen with three items, a promo code field and a Pay now button',
                      child: ExcludeSemantics(
                        child: SizedBox(
                          width: 270,
                          height: 500,
                          child: Stack(children: [
                            Transform.rotate(
                              angle: -4 * 3.14159265 / 180,
                              child: _backCard(const Color(0xFF202024)),
                            ),
                            Transform.rotate(
                              angle: 3 * 3.14159265 / 180,
                              child: _backCard(FluoColors.surface),
                            ),
                            const TriageShot(),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const FluoField(
                  label: 'Screen name',
                  initial: 'Cart',
                  height: 48,
                  fill: FluoColors.surface,
                  fontSize: 16,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: FluoButton(
                      label: 'Discard',
                      icon: LucideIcons.trash2,
                      kind: BtnKind.danger,
                      height: 52,
                      radius: 12,
                      fontSize: 16,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                  const SizedBox(width: 10),
                  FluoIconButton(
                    icon: LucideIcons.undo2,
                    label: 'Undo last choice',
                    size: 52,
                    radius: 12,
                    onPressed: () {},
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FluoButton(
                      label: 'Keep',
                      icon: LucideIcons.check,
                      kind: BtnKind.primary,
                      height: 52,
                      radius: 12,
                      fontSize: 16,
                      weight: FontWeight.w600,
                      expand: true,
                      onPressed: () {},
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: Text('Flick the card left or right, or use the buttons',
                      textAlign: TextAlign.center,
                      style: fs(13, c: FluoColors.fgMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backCard(Color c) => Container(
        width: 270,
        height: 500,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: FluoColors.border),
        ),
      );
}
