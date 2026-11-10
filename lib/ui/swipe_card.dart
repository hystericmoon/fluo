import 'dart:math' as math;

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../theme/accent.dart';

/// A card you can flick right to keep or left to discard. The buttons beside
/// it do the same thing (WCAG 2.5.1), and TalkBack gets both as actions.
///
/// Give it a new `key` for each shot so its drag state starts fresh.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.child,
    required this.onKeep,
    required this.onDiscard,
  });
  final Widget child;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;

  @override
  State<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<SwipeCard> with SingleTickerProviderStateMixin {
  static const _commitDistance = 96.0;
  static const _commitVelocity = 700.0;

  late final AnimationController _ctl = AnimationController(vsync: this);
  double _dx = 0;
  double _from = 0, _to = 0;
  VoidCallback? _afterFly;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() {
      setState(() => _dx = _from + (_to - _from) * Curves.easeOut.transform(_ctl.value));
    });
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        final done = _afterFly;
        _afterFly = null;
        _busy = false;
        done?.call();
      }
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _animateTo(double target, {VoidCallback? then}) {
    if (_reduced) {
      setState(() => _dx = target);
      _busy = false;
      then?.call();
      return;
    }
    _from = _dx;
    _to = target;
    _afterFly = then;
    _busy = true;
    _ctl.duration = Duration(milliseconds: then == null ? 160 : 180);
    _ctl.forward(from: 0);
  }

  void _fly(bool keep) {
    final w = MediaQuery.sizeOf(context).width;
    _animateTo(keep ? w : -w, then: keep ? widget.onKeep : widget.onDiscard);
  }

  void _end(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    final far = _dx.abs() > _commitDistance;
    final flick = v.abs() > _commitVelocity && v.sign == _dx.sign;
    if (far || flick) {
      _fly(_dx > 0);
    } else {
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (_dx / 160).clamp(-1.0, 1.0);
    final keep = t > 0.15;
    final discard = t < -0.15;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Keep'): widget.onKeep,
        const CustomSemanticsAction(label: 'Discard'): widget.onDiscard,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          if (_busy) return;
          setState(() => _dx += d.delta.dx);
        },
        onHorizontalDragEnd: (d) {
          if (!_busy) _end(d);
        },
        child: Transform.translate(
          offset: Offset(_dx, 0),
          child: Transform.rotate(
            angle: t * 0.12,
            child: Stack(children: [
              widget.child,
              // Words and icons, not only colour: which way is which.
              if (keep) _stamp('Keep', LucideIcons.check, context.accent.color, Alignment.topLeft, t),
              if (discard) _stamp('Discard', LucideIcons.trash2, FluoColors.bug, Alignment.topRight, -t),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stamp(String text, IconData icon, Color c, Alignment at, double strength) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: at,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Opacity(
              opacity: math.min(1, strength * 1.6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: FluoColors.bg.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c, width: 2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18, color: c),
                  const SizedBox(width: 6),
                  Text(text, style: fs(15, w: FontWeight.w600, c: c)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
