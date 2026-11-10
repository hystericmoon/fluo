import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'motion.dart';

/// A border with a bright spot that travels around it, for something that is
/// live (a running review session). It decorates and never carries meaning on
/// its own: the card still says "Session on". With reduced motion, or when
/// [active] is false, it is a plain still border.
class FluoStarBorder extends StatefulWidget {
  const FluoStarBorder({
    super.key,
    required this.child,
    required this.color,
    required this.active,
    this.radius = 16,
    this.width = 1.5,
    this.period = const Duration(milliseconds: 3600),
  });

  final Widget child;
  final Color color;
  final bool active;
  final double radius;
  final double width;
  final Duration period;

  @override
  State<FluoStarBorder> createState() => _FluoStarBorderState();
}

class _FluoStarBorderState extends State<FluoStarBorder> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: widget.period);

  void _sync() {
    final run = widget.active && !reducedMotion(context);
    if (run && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!run && _ctl.isAnimating) {
      _ctl.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(FluoStarBorder old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _StarPainter(_ctl, widget.color, widget.radius, widget.width, widget.active),
      child: widget.child,
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.t, this.color, this.radius, this.width, this.active) : super(repaint: t);
  final Animation<double> t;
  final Color color;
  final double radius;
  final double width;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // The still border: always there, so the card is bounded without motion.
    canvas.drawRRect(
      rr,
      Paint()
        ..color = color.withValues(alpha: active ? 0.55 : 1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
    if (!active || !t.isAnimating) return;
    // The bright spot: a short sweep gradient rotating around the centre.
    final angle = t.value * 2 * math.pi;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(angle),
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0),
        color,
        const Color(0xFFFFFFFF),
        color.withValues(alpha: 0),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 0.55, 0.78, 0.84, 0.92, 1],
    ).createShader(rect);
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.color != color || old.radius != radius || old.width != width || old.active != active;
}
