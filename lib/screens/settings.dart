import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../ui/kit.dart';

class _Theme {
  const _Theme(this.name, this.color, this.soft, this.text);
  final String name;
  final Color color, soft, text;
}

const _themes = [
  _Theme('Neon lime', Color(0xFFC8FF3D), Color(0xFF1B2508), Color(0xFFD8FF85)),
  _Theme('Violet', Color(0xFF8B7CF6), Color(0xFF1F1B3A), Color(0xFFC9C2FF)),
  _Theme('Cyan', Color(0xFF22D3EE), Color(0xFF0B2A30), Color(0xFF8BE8F7)),
  _Theme('Orange', Color(0xFFFF8A3D), Color(0xFF2E1A0B), Color(0xFFFFC08F)),
  _Theme('Pink', Color(0xFFFF5FA2), Color(0xFF2E0F1F), Color(0xFFFFA8CD)),
];

/// Settings. Theme choice only drives the local preview until session 9.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _theme = 0;
  bool _auto = true;
  bool _wifi = true;

  @override
  Widget build(BuildContext context) {
    final t = _themes[_theme];
    return ScreenFrame(
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ScreenHeader(
            title: 'Settings',
            big: true,
            leading: backButton(context, label: 'Back to albums'),
          ),
          const SizedBox(height: 16),
          _appearance(t),
          const SizedBox(height: 16),
          _updates(t),
        ]),
      ),
    );
  }

  Widget _appearance(_Theme t) => FluoCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text('Appearance', style: fs(15, w: FontWeight.w600))),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true, // controls inside stay separately focusable
            label: 'Color theme',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Color theme', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, box) {
                final w = (box.maxWidth - 8) / 2;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _themes.length; i++)
                    SizedBox(width: w, child: _themeButton(i)),
                ]);
              }),
              const SizedBox(height: 8),
              Text('Neon lime is the default theme.', style: fs(13, c: FluoColors.fgMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Preview', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FluoColors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FluoColors.border),
              ),
              child: Row(children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.color, borderRadius: BorderRadius.circular(10)),
                  child: Text('Export', style: fs(15, w: FontWeight.w500, c: FluoColors.onLime)),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.soft,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.color),
                  ),
                  child: Text('All 19', style: fs(14, w: FontWeight.w500, c: t.text)),
                ),
                const SizedBox(width: 10),
                PinBadge('1', t.color, size: 24),
              ]),
            ),
          ),
        ]),
      );

  Widget _themeButton(int i) {
    final th = _themes[i];
    final on = i == _theme;
    return Pressable(
      radius: 12,
      selected: on,
      label: th.name,
      onTap: () => setState(() => _theme = i),
      builder: (_, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? th.soft : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? th.color : FluoColors.borderStrong),
        ),
        child: ExcludeSemantics(
          child: Row(children: [
            Container(width: 18, height: 18, decoration: BoxDecoration(color: th.color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(th.name, style: fs(14, w: FontWeight.w500))),
            if (on) Icon(LucideIcons.check, size: 16, color: th.text),
          ]),
        ),
      ),
    );
  }

  Widget _updates(_Theme t) => FluoCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(header: true, child: Text('Updates', style: fs(15, w: FontWeight.w600))),
          const SizedBox(height: 4),
          SwitchRow(
            title: 'Auto-update',
            help: 'Download and install new versions in the background.',
            value: _auto,
            accent: t.color,
            padding: const EdgeInsets.symmetric(vertical: 10),
            onChanged: (v) => setState(() => _auto = v),
          ),
          if (_auto) ...[
            Container(height: 1, color: FluoColors.border),
            SwitchRow(
              title: 'Wi-Fi only',
              help: 'Skip mobile data when downloading updates.',
              value: _wifi,
              accent: t.color,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onChanged: (v) => setState(() => _wifi = v),
            ),
          ],
          Container(height: 1, color: FluoColors.border),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Version 0.1.0', style: fs(15, w: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      _auto ? 'Up to date. Auto-update is on.' : 'Auto-update is off. Check manually.',
                      style: fs(13, c: FluoColors.fgMuted, h: 1.4),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                FluoButton(label: 'Check for updates', onPressed: () {}),
              ]),
            ),
          ),
        ]),
      );
}
