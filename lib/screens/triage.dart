import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_scope.dart';
import '../data/models.dart';
import '../data/repo_scope.dart';
import '../data/triage_session.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/shot_image.dart';
import '../ui/swipe_card.dart';
import 'album.dart';

/// Sort the album's pending screenshots: keep or discard (buttons or flick),
/// undo, and name each one.
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key, required this.albumId});
  final String albumId;

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  TriageSession? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepoScope.of(context);
    CaptureScope.of(context); // rebuild when new screenshots are imported
    final t = _t;
    if (t == null) {
      _t = TriageSession(repo, widget.albumId);
    } else {
      t.absorbNew(); // shots taken while this screen is open join the end
    }
  }

  void _do(void Function(TriageSession t) action) => setState(() => action(_t!));

  void _done() {
    // Replace this screen so Back from the album returns to Albums.
    Navigator.of(context).pushReplacement(fluoRoute(AlbumScreen(albumId: widget.albumId)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final t = _t!;
    final album = repo.getAlbum(widget.albumId);
    final cur = t.current;
    final subtitle = cur == null
        ? '${album?.name ?? ''} · ${t.total == 0 ? 'nothing to review' : 'all sorted'}'
        : '${album?.name ?? ''} · ${t.position} of ${t.total}';

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
                  subtitle: subtitle,
                  leading: backButton(context, label: 'Back to albums'),
                  trailing: [FluoButton(label: 'Done', hPad: 18, onPressed: _done)],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 500,
                  child: cur == null
                      ? _AllSorted(kept: t.keptCount, discarded: t.discardedCount, none: t.total == 0)
                      : _Stack(
                          key: ValueKey(cur.id),
                          shot: cur,
                          position: t.position,
                          total: t.total,
                          onKeep: () => _do((t) => t.keep()),
                          onDiscard: () => _do((t) => t.discard()),
                        ),
                ),
                const SizedBox(height: 16),
                if (cur != null) ...[
                  FluoField(
                    key: ValueKey('name-${cur.id}'),
                    label: 'Screen name',
                    initial: cur.name,
                    placeholder: 'For example, Cart',
                    height: 48,
                    fill: FluoColors.surface,
                    fontSize: 16,
                    onChanged: t.rename,
                  ),
                  const SizedBox(height: 16),
                ],
                Row(children: [
                  if (cur != null)
                    Expanded(
                      child: FluoButton(
                        label: 'Discard',
                        icon: LucideIcons.trash2,
                        kind: BtnKind.danger,
                        height: 52,
                        radius: 12,
                        fontSize: 16,
                        expand: true,
                        onPressed: () => _do((t) => t.discard()),
                      ),
                    ),
                  if (cur != null) const SizedBox(width: 10),
                  FluoIconButton(
                    icon: LucideIcons.undo2,
                    label: 'Undo last choice',
                    size: 52,
                    radius: 12,
                    onPressed: t.canUndo ? () => _do((t) => t.undo()) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: cur != null
                        ? FluoButton(
                            label: 'Keep',
                            icon: LucideIcons.check,
                            kind: BtnKind.primary,
                            height: 52,
                            radius: 12,
                            fontSize: 16,
                            weight: FontWeight.w600,
                            expand: true,
                            onPressed: () => _do((t) => t.keep()),
                          )
                        : FluoButton(
                            label: 'Open album',
                            kind: BtnKind.primary,
                            height: 52,
                            radius: 12,
                            fontSize: 16,
                            weight: FontWeight.w600,
                            expand: true,
                            onPressed: _done,
                          ),
                  ),
                ]),
                const SizedBox(height: 10),
                if (cur != null)
                  Center(
                    child: Text('Flick the card left or right, or use the buttons',
                        textAlign: TextAlign.center, style: fs(13, c: FluoColors.fgMuted)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The top card with two shadows of cards behind it.
class _Stack extends StatelessWidget {
  const _Stack({
    super.key,
    required this.shot,
    required this.position,
    required this.total,
    required this.onKeep,
    required this.onDiscard,
  });
  final Shot shot;
  final int position;
  final int total;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;

  Widget _back(Color c, double angleDeg) => Transform.rotate(
        angle: angleDeg * 3.14159265 / 180,
        child: Container(
          width: 270,
          height: 500,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FluoColors.border),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 270,
        height: 500,
        child: Stack(children: [
          if (position < total) _back(const Color(0xFF202024), -4),
          if (position < total) _back(FluoColors.surface, 3),
          Semantics(
            image: true,
            label: 'Screenshot $position of $total${shot.name.isEmpty ? '' : ', named ${shot.name}'}',
            child: SwipeCard(
              onKeep: onKeep,
              onDiscard: onDiscard,
              child: Container(
                width: 270,
                height: 500,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: FluoColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3F3F46)),
                ),
                child: ExcludeSemantics(
                  child: ShotImage(
                    path: shot.originalPath,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    cacheWidth: 600,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AllSorted extends StatelessWidget {
  const _AllSorted({required this.kept, required this.discarded, required this.none});
  final int kept;
  final int discarded;
  final bool none;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: FluoColors.limeTint, shape: BoxShape.circle),
          child: Icon(none ? LucideIcons.images : LucideIcons.check, size: 28, color: FluoColors.lime),
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(none ? 'Nothing to review' : 'All sorted', style: fs(20, w: FontWeight.w600)),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 260,
          child: Text(
            none
                ? 'New screenshots will show up here while a session is on.'
                : '$kept kept, $discarded discarded',
            textAlign: TextAlign.center,
            style: fs(14, c: FluoColors.fgMuted, h: 1.4),
          ),
        ),
      ]),
    );
  }
}
