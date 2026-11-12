import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_scope.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/repo_scope.dart';
import '../data/triage_session.dart';
import '../desktop/desktop_scope.dart';
import '../motion/motion.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/shot_image.dart';
import '../ui/swipe_card.dart';
import 'album.dart';
import '../theme/accent.dart';

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
  FluoRepo? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepoScope.of(context);
    _repo = repo;
    CaptureScope.of(context); // rebuild when new screenshots are imported
    final t = _t;
    if (t == null) {
      _t = TriageSession(repo, widget.albumId);
    } else {
      t.absorbNew(); // shots taken while this screen is open join the end
    }
  }

  @override
  void dispose() {
    // Leaving Triage settles it: what was discarded is deleted from the app,
    // so rejected screenshots do not pile up on the phone. (Undo reaches back
    // only within one visit.)
    try {
      _repo?.purgeDiscarded(albumId: widget.albumId);
    } catch (_) {
      // The app is shutting down and the database is already closed: nothing
      // to do. The next start purges leftovers anyway.
    }
    super.dispose();
  }

  /// True after the keyboard's action key kept a shot: the next card's name
  /// field then takes focus, so naming a batch is type, enter, type, enter and
  /// the keyboard never closes. Any other action (the buttons) clears it, so
  /// the keyboard does not pop up by itself.
  bool _typing = false;

  void _do(void Function(TriageSession t) action) {
    _typing = false;
    setState(() => action(_t!));
  }

  /// The keyboard's action key (a check mark, like the Keep button): keep this
  /// shot and go straight to the next one.
  void _keepFromKeyboard() {
    setState(() {
      _typing = true;
      _t!.keep();
    });
  }

  void _done() {
    // The desktop shell already shows the album beside this screen.
    if (DesktopScope.isWide(context)) {
      Navigator.of(context).maybePop();
      return;
    }
    // Replace this screen so Back from the album returns to Albums.
    Navigator.of(context)
        .pushReplacement(fluoRoute(AlbumScreen(albumId: widget.albumId)));
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

    final frame = ScreenFrame(
      child: LayoutBuilder(
        builder: (context, box) {
          // The card takes the room the rest of the screen leaves, so with the
          // keyboard up the name field and the Keep and Discard buttons stay
          // in view (the card gets shorter, never the controls). Everything
          // but the card is about 260dp at normal text size.
          final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
          final cardHeight = (box.maxHeight - 260 * textScale).clamp(180.0, 500.0);
          return SingleChildScrollView(
          // The name field's focus ring is drawn 3dp outside the field; the
          // default clip would cut it at the screen margin.
          clipBehavior: Clip.none,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  title: 'Triage',
                  subtitle: subtitle,
                  leading: backButton(context, label: 'Back to albums'),
                  trailing: [
                    FluoButton(label: 'Done', hPad: 18, onPressed: _done),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  key: const ValueKey('triage-card'),
                  height: cardHeight,
                  child: cur == null
                      ? _AllSorted(
                          kept: t.keptCount,
                          discarded: t.discardedCount,
                          none: t.total == 0,
                        )
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
                    autocorrect: false,
                    autofocus: _typing,
                    onSubmitted: _keepFromKeyboard,
                    onChanged: t.rename,
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 10),
                if (cur != null)
                  Center(
                    child: Text(
                      DesktopScope.isDesktop(context)
                          ? 'K or → keeps, D or ← discards, ⌘Z undoes, Esc goes back'
                          : 'Flick right to keep, left to discard, or use the buttons',
                      textAlign: TextAlign.center,
                      style: fs(13, c: FluoColors.fgMuted),
                    ),
                  ),
              ],
            ),
          ),
        );
        },
      ),
    );
    if (!DesktopScope.isDesktop(context)) return frame;
    // Desktop keyboard route: every key has a button on screen as well. Single
    // keys do nothing while a text field has focus, so naming a shot is safe.
    void guarded(VoidCallback f) {
      if (!typingInTextField()) f();
    }

    final cur2 = t.current;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        if (cur2 != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyK): () => guarded(() => _do((t) => t.keep())),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => guarded(() => _do((t) => t.keep())),
          const SingleActivator(LogicalKeyboardKey.keyD): () => guarded(() => _do((t) => t.discard())),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => guarded(() => _do((t) => t.discard())),
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            guarded(() {
              if (t.canUndo) _do((t) => t.undo());
            }),
      },
      child: Focus(autofocus: true, child: frame),
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
        child: Stack(
          children: [
            if (position < total) _back(const Color(0xFF202024), -4),
            if (position < total) _back(FluoColors.surface, 3),
            // The next card settles into place: it was the one behind, tilted.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motionDuration(
                context,
                const Duration(milliseconds: 200),
              ),
              curve: Curves.easeOut,
              builder: (context, t, child) => Transform.rotate(
                angle: (1 - t) * 3 * 3.14159265 / 180,
                child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
              ),
              child: Semantics(
                image: true,
                label:
                    'Screenshot $position of $total${shot.name.isEmpty ? '' : ', named ${shot.name}'}',
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
            ),
          ],
        ),
      ),
    );
  }
}

class _AllSorted extends StatelessWidget {
  const _AllSorted({
    required this.kept,
    required this.discarded,
    required this.none,
  });
  final int kept;
  final int discarded;
  final bool none;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: context.accent.soft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              none ? LucideIcons.images : LucideIcons.check,
              size: 28,
              color: context.accent.color,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              none ? 'Nothing to review' : 'All sorted',
              style: fs(20, w: FontWeight.w600),
            ),
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
        ],
      ),
    );
  }
}
