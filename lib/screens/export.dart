import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../ui/kit.dart';

class _Format {
  const _Format(this.id, this.title, this.desc, this.action, {this.best = false});
  final String id, title, desc, action;
  final bool best;
}

const _formats = [
  _Format('claude', 'Claude pack', 'Markdown and images in a ZIP: captions, pins and a review brief as text', 'Export Claude pack', best: true),
  _Format('pdf', 'PDF', 'One page per screen, with caption and pins', 'Export PDF'),
  _Format('long', 'Long image', 'One scrolling image for quick sharing in chat', 'Export long image'),
  _Format('share', 'Share images', 'Send annotated images with captions through the share sheet', 'Share images'),
];

/// Export options. The button is inert until session 7.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  String _fmt = 'claude';
  bool _orig = false;
  bool _brief = true;

  @override
  Widget build(BuildContext context) {
    final cur = _formats.firstWhere((f) => f.id == _fmt);
    return ScreenFrame(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ScreenHeader(
                title: 'Export album',
                subtitle: 'Checkout flow review · 19 screens · 10 pins',
                leading: FluoIconButton(
                  icon: LucideIcons.x,
                  label: 'Close export',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                label: 'Format',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Format', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
                  const SizedBox(height: 8),
                  for (final f in _formats) ...[
                    _formatCard(f),
                    if (f != _formats.last) const SizedBox(height: 8),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              FluoCard(
                child: Column(children: [
                  SwitchRow(
                    title: 'Include original screenshots',
                    help: 'Off by default. Edits are baked into the exported images.',
                    value: _orig,
                    onChanged: (v) => setState(() => _orig = v),
                  ),
                  Container(height: 1, color: FluoColors.border),
                  SwitchRow(
                    title: 'Add a review brief',
                    help: 'A short summary of what to look at, at the start.',
                    value: _brief,
                    onChanged: (v) => setState(() => _brief = v),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _notice(),
              const SizedBox(height: 16),
              FluoButton(
                label: cur.action,
                icon: LucideIcons.upload,
                kind: BtnKind.primary,
                height: 52,
                radius: 12,
                fontSize: 16,
                weight: FontWeight.w600,
                expand: true,
                onPressed: () {},
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _formatCard(_Format f) {
    final on = f.id == _fmt;
    return Pressable(
      radius: 14,
      checked: on,
      label: '${f.title}. ${f.desc}${f.best ? '. Best for Claude' : ''}',
      onTap: () => setState(() => _fmt = f.id),
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? FluoColors.limeTint : FluoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? FluoColors.lime : FluoColors.border),
        ),
        child: ExcludeSemantics(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: on ? FluoColors.lime : FluoColors.borderStrong, width: 2),
                ),
                alignment: Alignment.center,
                child: on
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: FluoColors.lime, shape: BoxShape.circle))
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(f.title, style: fs(16, w: FontWeight.w500)),
                  if (f.best)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: FluoColors.limeTint,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: FluoColors.lime),
                      ),
                      child: Text('Best for Claude',
                          style: fs(12, w: FontWeight.w500, c: FluoColors.limeSoft)),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(f.desc, style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _notice() {
    final warn = _orig;
    final ink = warn ? FluoTints.bugInk : FluoTints.warnTitle;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warn ? FluoTints.bugSoft : FluoTints.warnSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: warn ? FluoColors.bug : FluoTints.warnBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.eyeOff, size: 20, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                warn ? 'Originals still contain what you hid' : '2 redactions are baked in',
                style: fs(14, w: FontWeight.w600, c: ink),
              ),
              const SizedBox(height: 3),
              Text(
                warn
                    ? 'Annotated images are safe, but the original screenshots show the hidden content. Share only with people who can see it.'
                    : 'Exported images show them as solid blocks. The hidden content is not included.',
                style: fs(13, c: warn ? FluoTints.bugBody : FluoTints.warnBody, h: 1.4),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
