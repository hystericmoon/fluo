import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/fake_data.dart';
import '../theme/tokens.dart';
import '../ui/fake_shot.dart';
import '../ui/kit.dart';

enum _Tool { crop, pen, arrow, box, pin, redact }

/// Editor with fake annotations. Drawing arrives in session 6.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  _Tool _tool = _Tool.pin;
  Severity _sev = Severity.bug;

  static const _icons = {
    _Tool.crop: (LucideIcons.crop, 'Crop'),
    _Tool.pen: (LucideIcons.pencil, 'Pen'),
    _Tool.arrow: (LucideIcons.moveUpRight, 'Arrow'),
    _Tool.box: (LucideIcons.square, 'Box'),
    _Tool.pin: (LucideIcons.mapPin, 'Pin'),
    _Tool.redact: (LucideIcons.eyeOff, 'Redact'),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluoColors.bg,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(children: [
                      ScreenHeader(
                        title: 'Cart',
                        subtitle: '2 of 19 · Checkout flow review',
                        leading: backButton(context, label: 'Back to album'),
                        trailing: [
                          FluoButton(
                            label: 'Done',
                            kind: BtnKind.primary,
                            hPad: 18,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _canvas(),
                      const SizedBox(height: 12),
                      _toolbar(),
                      const SizedBox(height: 12),
                    ]),
                  ),
                  Expanded(child: _panel()),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas() => Container(
        height: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF121215),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FluoColors.border),
        ),
        child: Center(
          child: Semantics(
            image: true,
            label:
                'Cart screenshot with pin 1 on the order total, pin 2 on the second item, a red box around the Pay now button and a redacted block over the email line',
            child: ExcludeSemantics(child: EditorShot()),
          ),
        ),
      );

  Widget _toolbar() => Semantics(
        container: true,
        label: 'Edit tools',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final t in _Tool.values) ...[
            if (t != _Tool.crop) const SizedBox(width: 8),
            Pressable(
              radius: 12,
              label: _icons[t]!.$2,
              toggled: _tool == t,
              onTap: () => setState(() => _tool = t),
              builder: (_, _) {
                final on = _tool == t;
                return Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: on ? FluoColors.lime : FluoColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? FluoColors.lime : FluoColors.border),
                  ),
                  child: Icon(_icons[t]!.$1,
                      size: 22, color: on ? FluoColors.onLime : FluoColors.fg),
                );
              },
            ),
          ],
        ]),
      );

  Widget _sevButton(Severity s) {
    final on = _sev == s;
    return Pressable(
      radius: 10,
      selected: on,
      onTap: () => setState(() => _sev = s),
      builder: (_, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? FluoTints.bugSoft : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? s.color : FluoColors.borderStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SeverityDot(s),
          const SizedBox(width: 7),
          Text(s.label, style: fs(14, w: FontWeight.w500, c: on ? s.color : FluoColors.fg)),
        ]),
      ),
    );
  }

  Widget _panel() => Semantics(
        container: true,
        label: 'Pin details',
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: const BoxDecoration(
            color: FluoColors.surface,
            border: Border(top: BorderSide(color: FluoColors.border)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Semantics(header: true, child: Text('Pin 1', style: fs(15, w: FontWeight.w600))),
              ),
              for (final s in Severity.values) ...[
                _sevButton(s),
                const SizedBox(width: 8),
              ],
              FluoIconButton(
                icon: LucideIcons.trash2,
                label: 'Delete pin 1',
                onPressed: () {},
              ),
            ]),
            const SizedBox(height: 12),
            const FluoField(label: 'Note on this pin', initial: 'Total changes after shipping is added'),
            const SizedBox(height: 12),
            const FluoField(label: 'Caption for this screen', initial: 'Cart: order total changes after shipping'),
          ]),
        ),
      );
}
