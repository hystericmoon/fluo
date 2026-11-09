import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/models.dart';
import '../data/repo_scope.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/shot_image.dart';
import 'editor.dart';
import 'export.dart';
import 'triage.dart';

enum _Mode { grid, flow }

/// The album's kept screenshots: Grid or Flow order, with severity filters.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  _Mode _mode = _Mode.flow;
  Severity? _filter; // null = All

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(fluoRoute(page));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final album = repo.getAlbum(widget.albumId);
    final kept = repo.shotsIn(widget.albumId, status: ShotStatus.kept);
    final pending = repo.shotsIn(widget.albumId, status: ShotStatus.pending).length;
    final pins = repo.pinsInAlbum(widget.albumId);
    final flow = _mode == _Mode.flow;

    // Flow numbers count the kept screens only, in order.
    final numbered = [for (var i = 0; i < kept.length; i++) (i + 1, kept[i])];
    int screensWith(Severity s) =>
        kept.where((k) => (pins[k.id] ?? const []).any((p) => p.severity == s)).length;
    final shown = _filter == null
        ? numbered
        : [
            for (final e in numbered)
              if ((pins[e.$2.id] ?? const []).any((p) => p.severity == _filter)) e,
          ];

    return ScreenFrame(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: album?.name ?? 'Album',
            leading: backButton(context, label: 'Back to albums'),
            trailing: [
              FluoButton(
                label: 'Export',
                icon: LucideIcons.upload,
                kind: BtnKind.primary,
                onPressed: kept.isEmpty ? null : () => _push(const ExportScreen()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (pending > 0) ...[
            _PendingBanner(
              count: pending,
              onReview: () => _push(TriageScreen(albumId: widget.albumId)),
            ),
            const SizedBox(height: 14),
          ],
          if (kept.isNotEmpty) ...[
            _Segmented(
              flow: flow,
              onChanged: (f) => setState(() => _mode = f ? _Mode.flow : _Mode.grid),
            ),
            const SizedBox(height: 14),
            // Wraps instead of scrolling: a chip half off-screen is not found.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FluoChip(
                  label: 'All ${kept.length}',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final s in Severity.values)
                  FluoChip(
                    label: '${s.label} ${screensWith(s)}',
                    leading: SeverityDot(s),
                    selected: _filter == s,
                    onTap: () => setState(() => _filter = _filter == s ? null : s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: kept.isEmpty
                ? _EmptyAlbum(hasPending: pending > 0)
                : shown.isEmpty
                    ? Center(
                        child: Text('No screens with ${_filter!.label} pins',
                            style: fs(14, c: FluoColors.fgMuted)),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 190 + 6 + 18,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final (n, shot) = shown[i];
                          return _Tile(
                            shot: shot,
                            number: flow ? n : null,
                            pins: pins[shot.id] ?? const [],
                            onTap: () => _push(EditorScreen(shotId: shot.id)),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.shot, required this.number, required this.pins, required this.onTap});
  final Shot shot;
  final int? number;
  final List<Pin> pins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = shot.name.isEmpty ? 'Untitled' : shot.name;
    final pinText = pins.isEmpty
        ? 'no pins'
        : '${pins.length} ${pins.length == 1 ? 'pin' : 'pins'}: ${pins.map((p) => p.severity.label).join(', ')}';
    return Pressable(
      radius: 10,
      label: '${number != null ? 'Screen $number: ' : ''}$name, $pinText',
      onTap: onTap,
      builder: (_, _) => ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 190,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: FluoColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3F3F46)),
            ),
            child: Stack(fit: StackFit.expand, children: [
              ShotImage(path: shot.originalPath, cacheWidth: 330),
              if (number != null)
                Positioned(left: 6, top: 6, child: PinBadge('$number', FluoColors.lime, size: 26, ringed: true)),
              if (pins.isNotEmpty)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final p in pins)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: PinBadge(p.severity.letter, p.severity.color, size: 22, ringed: true),
                      ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fs(13, w: FontWeight.w500, c: shot.name.isEmpty ? FluoColors.fgMuted : FluoColors.fg)),
        ]),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count, required this.onReview});
  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: FluoColors.limeTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FluoColors.lime),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            count == 1 ? '1 new screenshot to review' : '$count new screenshots to review',
            style: fs(14, w: FontWeight.w500, c: FluoColors.limeSoft),
          ),
        ),
        const SizedBox(width: 10),
        FluoButton(label: 'Review', kind: BtnKind.primary, hPad: 16, onPressed: onReview),
      ]),
    );
  }
}

class _EmptyAlbum extends StatelessWidget {
  const _EmptyAlbum({required this.hasPending});
  final bool hasPending;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(LucideIcons.images, size: 40, color: FluoColors.fgMuted),
        const SizedBox(height: 16),
        Text('No screens yet', style: fs(17, w: FontWeight.w600)),
        const SizedBox(height: 4),
        SizedBox(
          width: 260,
          child: Text(
            hasPending
                ? 'Review the new screenshots and keep the ones you want here.'
                : 'Take screenshots while a session is on, then keep the ones you want here.',
            textAlign: TextAlign.center,
            style: fs(14, c: FluoColors.fgMuted, h: 1.4),
          ),
        ),
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.flow, required this.onChanged});
  final bool flow;
  final ValueChanged<bool> onChanged;

  Widget _seg(String label, bool on, VoidCallback tap) => Expanded(
        child: Pressable(
          onTap: tap,
          selected: on,
          radius: 8,
          builder: (_, _) => Container(
            height: 44,
            alignment: Alignment.center,
            color: on ? FluoColors.lime : null,
            child: Text(label,
                style: fs(15, w: FontWeight.w500, c: on ? FluoColors.onLime : FluoColors.fg)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FluoColors.borderStrong),
        ),
        child: Row(children: [
          _seg('Grid', !flow, () => onChanged(false)),
          _seg('Flow order', flow, () => onChanged(true)),
        ]),
      );
}
