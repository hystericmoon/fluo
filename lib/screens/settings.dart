import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../settings/app_settings.dart';
import '../settings/settings_scope.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../update/update_controller.dart';
import '../update/update_scope.dart';

/// Theme, motion and updates. Each choice is saved and applies at once.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final updates = UpdateScope.of(context);
    return ScreenFrame(
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ScreenHeader(
            title: 'Settings',
            big: true,
            leading: backButton(context, label: 'Back to albums'),
          ),
          const SizedBox(height: 16),
          FluoCard(
            radius: 16,
            padding: const EdgeInsets.all(16),
            child: _Appearance(settings: settings),
          ),
          const SizedBox(height: 16),
          FluoCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _Updates(settings: settings, updates: updates),
          ),
        ]),
      ),
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final current = context.accent;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text('Appearance', style: fs(15, w: FontWeight.w600))),
      const SizedBox(height: 12),
      Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Color theme',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Color theme', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in Accent.all) SizedBox(width: w, child: _themeButton(a, a == current)),
            ]);
          }),
          const SizedBox(height: 8),
          Text('Neon lime is the default theme. The FLUO logo stays lime.',
              style: fs(13, c: FluoColors.fgMuted)),
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
              decoration: BoxDecoration(color: current.color, borderRadius: BorderRadius.circular(10)),
              child: Text('Export', style: fs(15, w: FontWeight.w500, c: current.onColor)),
            ),
            const SizedBox(width: 10),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current.soft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: current.color),
              ),
              child: Text('All 19', style: fs(14, w: FontWeight.w500, c: current.text)),
            ),
            const SizedBox(width: 10),
            PinBadge('1', current.color, size: 24),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Container(height: 1, color: FluoColors.border),
      SwitchRow(
        title: 'Reduce motion',
        help: 'Skip animations. Your system setting is followed too.',
        value: settings.reduceMotion,
        padding: const EdgeInsets.symmetric(vertical: 10),
        onChanged: (v) => settings.setReduceMotion(v),
      ),
    ]);
  }

  Widget _themeButton(Accent a, bool on) {
    return Pressable(
      radius: 12,
      selected: on,
      label: a.name,
      onTap: () => settings.setAccent(a),
      builder: (_, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? a.soft : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? a.color : FluoColors.borderStrong),
        ),
        child: ExcludeSemantics(
          child: Row(children: [
            Container(width: 18, height: 18, decoration: BoxDecoration(color: a.color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(a.name, style: fs(14, w: FontWeight.w500))),
            if (on) Icon(LucideIcons.check, size: 16, color: a.text),
          ]),
        ),
      ),
    );
  }
}

class _Updates extends StatelessWidget {
  const _Updates({required this.settings, required this.updates});
  final AppSettings settings;
  final UpdateController updates;

  String _status() => switch (updates.state) {
        UpdateState.idle => settings.autoUpdate ? 'Auto-update is on.' : 'Auto-update is off. Check manually.',
        UpdateState.checking => 'Checking for updates…',
        UpdateState.upToDate => 'Up to date.',
        UpdateState.available => 'A new version is available.',
        UpdateState.downloading => 'Downloading the update…',
        UpdateState.ready => 'The update is ready. Restart to finish.',
        UpdateState.unavailable => 'Updates come through Google Play. This copy was not installed from there.',
        UpdateState.failed => 'Could not check for updates. Try again later.',
      };

  @override
  Widget build(BuildContext context) {
    final busy = updates.state == UpdateState.checking || updates.state == UpdateState.downloading;
    final (label, action) = switch (updates.state) {
      UpdateState.available => ('Download', updates.download),
      UpdateState.ready => ('Restart to update', updates.install),
      UpdateState.checking => ('Checking…', null),
      UpdateState.downloading => ('Downloading…', null),
      _ => ('Check for updates', updates.checkNow),
    };
    final auto = settings.autoUpdate;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text('Updates', style: fs(15, w: FontWeight.w600))),
      const SizedBox(height: 4),
      SwitchRow(
        title: 'Auto-update',
        help: 'Download and install new versions in the background.',
        value: auto,
        padding: const EdgeInsets.symmetric(vertical: 10),
        onChanged: (v) => settings.setAutoUpdate(v),
      ),
      if (auto) ...[
        Container(height: 1, color: FluoColors.border),
        SwitchRow(
          title: 'Wi-Fi only',
          help: 'Skip mobile data when downloading updates.',
          value: settings.wifiOnly,
          padding: const EdgeInsets.symmetric(vertical: 10),
          onChanged: (v) => settings.setWifiOnly(v),
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
                Text('Version ${updates.info ?? '…'}', style: fs(15, w: FontWeight.w500)),
                const SizedBox(height: 2),
                Semantics(
                  liveRegion: true,
                  child: Text(_status(), style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            FluoButton(label: label, onPressed: busy ? null : action),
          ]),
        ),
      ),
    ]);
  }
}
