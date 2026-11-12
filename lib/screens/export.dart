import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/repo_scope.dart';
import '../export/export_scope.dart';
import '../export/export_service.dart';
import '../export/model.dart';
import '../desktop/desktop_scope.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../theme/accent.dart';

const _descriptions = {
  ExportFormat.claude: 'Markdown and images in a ZIP: captions, pins and a review brief as text',
  ExportFormat.pdf: 'One page per screen, with caption and pins',
  ExportFormat.long: 'One scrolling image for quick sharing in chat',
  ExportFormat.share: 'Send annotated images with captions through the share sheet',
};

String _actionLabel(ExportFormat f) => switch (f) {
      ExportFormat.claude => 'Export Claude pack',
      ExportFormat.pdf => 'Export PDF',
      ExportFormat.long => 'Export long image',
      ExportFormat.share => 'Share images',
    };

/// Export an album: pick a format, decide about originals and the brief, see
/// what is hidden, then send it through the share sheet.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.albumId, this.only});
  final String albumId;

  /// Export just these screens (desktop multi-select). Null exports the album.
  final Set<String>? only;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  ExportFormat _fmt = ExportFormat.claude;
  bool _orig = false;
  bool _brief = true;
  (int, int)? _progress; // done, total while exporting
  String? _error;

  bool get _busy => _progress != null;

  ExportOptions get _options => ExportOptions(format: _fmt, includeOriginals: _orig, includeBrief: _brief);

  Future<void> _export(ExportService svc) async {
    if (_busy) return;
    setState(() {
      _progress = (0, svc.summary(widget.albumId, only: widget.only).screens);
      _error = null;
    });
    try {
      await svc.exportAndShare(widget.albumId, _options, only: widget.only, onProgress: (d, t) {
        if (mounted) setState(() => _progress = (d, t));
      });
      if (mounted) setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Could not export. Nothing was shared. Try again, or try another format.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final svc = ExportService(repo, ExportScope.of(context));
    final album = repo.getAlbum(widget.albumId);
    final sum = svc.summary(widget.albumId, only: widget.only);
    final canExport = sum.screens > 0 && !_busy;
    final p = _progress;

    final header = ScreenHeader(
      title: widget.only == null ? 'Export album' : 'Export selection',
      subtitle:
          '${album?.name ?? ''} · ${sum.screens} ${sum.screens == 1 ? 'screen' : 'screens'} · ${sum.pins} ${sum.pins == 1 ? 'pin' : 'pins'}',
      leading: FluoIconButton(
        icon: LucideIcons.x,
        label: 'Close export',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
    final formats = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Format',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Format', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
        const SizedBox(height: 8),
        for (final f in ExportFormat.values) ...[
          _formatCard(f),
          if (f != ExportFormat.values.last) const SizedBox(height: 8),
        ],
      ]),
    );
    final options = FluoCard(
      child: Column(children: [
        SwitchRow(
          title: 'Include original screenshots',
          help: _fmt.canIncludeOriginals
              ? 'Off by default. Edits are baked into the exported images.'
              : 'Not used for ${_fmt.title}. Its pages show the edited screens only.',
          value: _orig && _fmt.canIncludeOriginals,
          enabled: _fmt.canIncludeOriginals && !_busy,
          onChanged: (v) => setState(() => _orig = v),
        ),
        Container(height: 1, color: FluoColors.border),
        SwitchRow(
          title: 'Add a review brief',
          help: _fmt.canIncludeBrief
              ? 'A short summary of what to look at, at the start.'
              : 'Not used for ${_fmt.title}.',
          value: _brief && _fmt.canIncludeBrief,
          enabled: _fmt.canIncludeBrief && !_busy,
          onChanged: (v) => setState(() => _brief = v),
        ),
      ]),
    );
    final action = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FluoButton(
        label: p == null ? _actionLabel(_fmt) : 'Exporting ${p.$1} of ${p.$2}…',
        icon: p == null ? LucideIcons.upload : null,
        kind: BtnKind.primary,
        height: 52,
        radius: 12,
        fontSize: 16,
        weight: FontWeight.w600,
        expand: true,
        onPressed: canExport ? () => _export(svc) : null,
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(_error!, style: fs(14, c: FluoTints.bugInk, h: 1.4)),
        ),
      ],
    ]);

    // Wide desktop window: formats on the left, options and the action on the
    // right, so nothing needs scrolling.
    if (DesktopScope.isWide(context)) {
      return ScreenFrame(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          const SizedBox(height: 20),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(child: formats)),
              const SizedBox(width: 28),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    options,
                    const SizedBox(height: 16),
                    _notice(sum),
                    const SizedBox(height: 16),
                    action,
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );
    }

    return ScreenFrame(
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              const SizedBox(height: 16),
              formats,
              const SizedBox(height: 16),
              options,
              const SizedBox(height: 16),
              _notice(sum),
              const SizedBox(height: 16),
              action,
            ]),
          ),
        ),
      ),
    );
  }

  Widget _formatCard(ExportFormat f) {
    final on = f == _fmt;
    final best = f == ExportFormat.claude;
    return Pressable(
      radius: 14,
      checked: on,
      label: '${f.title}. ${_descriptions[f]}${best ? '. Best for Claude' : ''}',
      onTap: _busy ? null : () => setState(() => _fmt = f),
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? context.accent.soft : FluoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? context.accent.color : FluoColors.border),
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
                  border: Border.all(color: on ? context.accent.color : FluoColors.borderStrong, width: 2),
                ),
                alignment: Alignment.center,
                child: on
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: context.accent.color, shape: BoxShape.circle))
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(f.title, style: fs(16, w: FontWeight.w500)),
                  if (best)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.accent.soft,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.accent.color),
                      ),
                      child: Text('Best for Claude', style: fs(12, w: FontWeight.w500, c: context.accent.text)),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(_descriptions[f]!, style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// What the person is about to send. Honest about redactions: baked into
  /// the images, but still readable in the originals if those are included.
  Widget _notice(ExportSummary sum) {
    final withOriginals = _orig && _fmt.canIncludeOriginals;
    final n = sum.redactions;
    final String title, body;
    final Color bg, border, titleInk, bodyInk;
    if (withOriginals && n > 0) {
      title = 'Originals still contain what you hid';
      body =
          'Annotated images are safe, but the original screenshots show the hidden content. Share only with people who can see it.';
      (bg, border, titleInk, bodyInk) = (FluoTints.bugSoft, FluoColors.bug, FluoTints.bugInk, FluoTints.bugBody);
    } else if (n > 0) {
      title = '$n ${n == 1 ? 'redaction is' : 'redactions are'} baked in';
      body = 'Exported images show them as solid blocks. The hidden content is not included.';
      (bg, border, titleInk, bodyInk) = (FluoTints.warnSoft, FluoTints.warnBorder, FluoTints.warnTitle, FluoTints.warnBody);
    } else if (withOriginals) {
      title = 'Originals are included';
      body = 'The untouched screenshots are added next to the edited ones.';
      (bg, border, titleInk, bodyInk) = (FluoColors.surface, FluoColors.borderStrong, FluoColors.fg, FluoColors.fgMuted);
    } else {
      title = 'Nothing is hidden';
      body = 'No redactions in this album. Exported images show the screens as they are, with your marks.';
      (bg, border, titleInk, bodyInk) = (FluoColors.surface, FluoColors.borderStrong, FluoColors.fg, FluoColors.fgMuted);
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.eyeOff, size: 20, color: titleInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: fs(14, w: FontWeight.w600, c: titleInk)),
              const SizedBox(height: 3),
              Text(body, style: fs(13, c: bodyInk, h: 1.4)),
            ]),
          ),
        ]),
      ),
    );
  }
}
