import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// A row you can swipe left to delete. The delete is not final: the caller
/// shows an undo bar (see `UndoFuse`). Screen readers get a "Delete" action on
/// the row, and the screen has a button for the same thing, so no one needs
/// the swipe.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.child,
    required this.onDelete,
    this.actionLabel = 'Delete',
  });

  final Widget child;
  final VoidCallback onDelete;
  final String actionLabel;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this);
  double _dx = 0, _from = 0, _to = 0;
  double _width = 0;
  bool _leaving = false;
  VoidCallback? _after;

  static const _commitFraction = 0.4;
  static const _commitVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() => _dx = _from + (_to - _from) * Curves.easeOut.transform(_ctl.value)));
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        final a = _after;
        _after = null;
        a?.call();
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _animate(double to, {VoidCallback? then}) {
    if (reducedMotion(context)) {
      setState(() => _dx = to);
      then?.call();
      return;
    }
    _from = _dx;
    _to = to;
    _after = then;
    _ctl.duration = const Duration(milliseconds: 180);
    _ctl.forward(from: 0);
  }

  void _commit() {
    if (_leaving) return;
    _leaving = true;
    _animate(-_width, then: widget.onDelete);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: widget.actionLabel): _commit},
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) {
            if (_leaving) return;
            setState(() => _dx = (_dx + d.delta.dx).clamp(-_width, 0.0));
          },
          onHorizontalDragEnd: (d) {
            if (_leaving) return;
            final flung = d.velocity.pixelsPerSecond.dx < -_commitVelocity;
            // From the current offset, not the last build: drag events can
            // arrive faster than frames are drawn.
            final shown = (-_dx / _width).clamp(0.0, 1.0);
            if (shown > _commitFraction || flung) {
              _commit();
            } else {
              _animate(0);
            }
          },
          child: Stack(children: [
            // The action underneath: words and an icon, not just a colour.
            Positioned.fill(
              child: ExcludeSemantics(
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: _dx < 0 ? FluoTints.bugSoft : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _dx < -8
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(LucideIcons.trash2, size: 18, color: FluoColors.bug),
                          const SizedBox(width: 8),
                          Text(widget.actionLabel, style: fs(14, w: FontWeight.w600, c: FluoTints.bugInk)),
                        ])
                      : null,
                ),
              ),
            ),
            Transform.translate(offset: Offset(_dx, 0), child: widget.child),
          ]),
        );
      }),
    );
  }
}
