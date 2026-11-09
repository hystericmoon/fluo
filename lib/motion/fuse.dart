import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'motion.dart';

/// The undo bar after a delete: a message, an Undo button and a fuse that
/// burns down. When it is gone, [onBurnt] makes the delete final.
///
/// Time limits must be adjustable (WCAG 2.2.1), so the fuse is three times
/// longer when a screen reader or switch access is on, and it stops burning
/// while Undo is pressed. Reduced motion replaces the burning line with a
/// plain countdown in words.
class UndoFuse extends StatefulWidget {
  const UndoFuse({
    super.key,
    required this.message,
    required this.onUndo,
    required this.onBurnt,
    this.duration = const Duration(seconds: 6),
  });

  final String message;
  final VoidCallback onUndo;
  final VoidCallback onBurnt;
  final Duration duration;

  @override
  State<UndoFuse> createState() => _UndoFuseState();
}

class _UndoFuseState extends State<UndoFuse> with SingleTickerProviderStateMixin {
  AnimationController? _ctl;
  Timer? _tick;
  int _left = 0; // whole seconds, for the reduced-motion text
  bool _done = false;

  Duration get _total {
    final assistive = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
    return assistive ? widget.duration * 3 : widget.duration;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctl != null) return;
    final c = AnimationController(vsync: this, duration: _total);
    _ctl = c;
    _left = _total.inSeconds;
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _burn();
    });
    c.forward();
    // Counted tick by tick (not read from the animation), so the words stay
    // right even if a frame is late.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _left > 0) setState(() => _left--);
    });
  }

  void _burn() {
    if (_done) return;
    _done = true;
    widget.onBurnt();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ctl?.dispose();
    super.dispose();
  }

  void _undo() {
    if (_done) return;
    _done = true;
    widget.onUndo();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reducedMotion(context);
    final c = _ctl!;
    return Semantics(
      liveRegion: true,
      container: true,
      explicitChildNodes: true, // Undo stays its own control
      label: widget.message,
      child: Container(
        decoration: BoxDecoration(
          color: FluoColors.surfaceHi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FluoColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(children: [
              Expanded(
                // The container above already says it (once) to a screen reader.
                child: ExcludeSemantics(
                  child: Text(
                    reduce ? '${widget.message} ($_left s)' : widget.message,
                    style: fs(14, w: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FluoButton(label: 'Undo', hPad: 14, onPressed: _undo),
            ]),
          ),
          // The fuse: shrinks towards the left as time runs out.
          if (!reduce)
            AnimatedBuilder(
              animation: c,
              builder: (context, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 1 - c.value,
                  child: Container(height: 3, color: FluoColors.lime),
                ),
              ),
            )
          else
            const SizedBox(height: 3),
        ]),
      ),
    );
  }
}
