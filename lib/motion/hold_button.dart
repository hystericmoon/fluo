import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import 'motion.dart';

/// A button for something hard to undo: hold it to confirm.
///
/// Holding is not for everyone, so the same confirmation works without it:
/// tap once to arm the button ("Tap again to confirm"), tap again within a
/// few seconds. Keyboard and screen readers take that route. Reduced motion
/// removes the filling animation but keeps the hold.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon,
    this.holdFor = const Duration(milliseconds: 900),
    this.armedFor = const Duration(seconds: 4),
    this.height = 44,
    this.expand = true,
  });

  final String label;
  final VoidCallback onConfirmed;
  final IconData? icon;
  final Duration holdFor;
  final Duration armedFor;
  final double height;
  final bool expand;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this, duration: widget.holdFor);
  Timer? _disarm;
  bool _armed = false;
  bool _holding = false;
  bool _fired = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _fill.addStatusListener((s) {
      if (s == AnimationStatus.completed && _holding) _confirm();
    });
  }

  @override
  void dispose() {
    _disarm?.cancel();
    _fill.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_fired) return;
    _fired = true;
    _disarm?.cancel();
    setState(() {
      _holding = false;
      _armed = false;
    });
    _fill.value = 0;
    widget.onConfirmed();
  }

  void _arm() {
    setState(() => _armed = true);
    _disarm?.cancel();
    _disarm = Timer(widget.armedFor, () {
      if (mounted) setState(() => _armed = false);
    });
  }

  /// A plain activation: tap, Enter, Space or a screen reader's double tap.
  void _activate() {
    if (_armed) {
      _confirm();
    } else {
      _arm();
    }
  }

  void _down() {
    _fired = false;
    setState(() => _holding = true);
    if (reducedMotion(context)) {
      // No fill to watch: just count the hold.
      _fill.duration = widget.holdFor;
    }
    _fill.forward(from: 0);
  }

  void _up() {
    if (!_holding) return;
    final completed = _fill.isCompleted;
    final held = _fill.value;
    setState(() => _holding = false);
    _fill.value = 0;
    if (!completed && held < 0.25) _activate(); // a tap, not a hold
  }

  void _cancel() {
    if (_holding) setState(() => _holding = false);
    _fill.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reducedMotion(context);
    final label = _armed
        ? 'Tap again to confirm'
        : _holding
            ? 'Keep holding…'
            : widget.label;
    final hint = 'Hold to confirm. Or tap twice.';
    return Semantics(
      button: true,
      label: _armed ? 'Confirm: ${widget.label}' : widget.label,
      hint: hint,
      liveRegion: _armed,
      onTap: _activate,
      child: FocusableActionDetector(
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _activate();
            return null;
          }),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _down(),
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _cancel(),
          child: ExcludeSemantics(
            child: Stack(clipBehavior: Clip.none, children: [
              AnimatedBuilder(
                animation: _fill,
                builder: (context, _) => Container(
                  height: widget.height,
                  width: widget.expand ? double.infinity : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _armed ? FluoTints.bugSoft : null,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FluoColors.bug, width: _armed ? 2 : 1),
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    if (_holding && !reduce)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _fill.value,
                            child: Container(color: FluoColors.bug.withValues(alpha: 0.28)),
                          ),
                        ),
                      ),
                    Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: FluoColors.bug),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: fs(15, w: FontWeight.w500, c: _armed ? FluoTints.bugInk : FluoColors.bug)),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (_focused)
                Positioned(
                  left: -4,
                  top: -4,
                  right: -4,
                  bottom: -4,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: FluoColors.lime, width: 2),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
