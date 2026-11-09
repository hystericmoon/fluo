import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/gestures.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/models.dart';
import '../theme/tokens.dart';
import 'editor_state.dart';
import '../motion/motion.dart';
import 'quick_pan.dart';
import 'viewport.dart';

enum _Handle { tl, tr, bl, br, move }

/// The crop frame: drag a corner to resize, drag inside to move. Screen
/// reader users get the same edits as actions, in 5% steps.
class CropOverlay extends StatefulWidget {
  const CropOverlay({super.key, required this.state, required this.viewport});
  final EditorState state;
  final EditViewport viewport; // the full image, uncropped

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay>
    with SingleTickerProviderStateMixin {
  _Handle? _active;
  // Refine Frame: the frame eases from the whole image to the crop on entry.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  static const _grab = 36.0;

  @override
  void initState() {
    super.initState();
    _enter.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enter.isCompleted && _enter.value == 1 && !_started) {
      _started = true;
      if (!reducedMotion(context) && !widget.state.cropIsFull) {
        _enter.forward(from: 0);
      }
    }
  }

  bool _started = false;

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  CropRect get _crop => widget.state.cropDraft ?? const CropRect(0, 0, 1, 1);

  Rect _widgetRect(EditViewport vp, CropRect c) => Rect.fromPoints(
    vp.toWidget(Offset(c.left, c.top)),
    vp.toWidget(Offset(c.right, c.bottom)),
  );

  void _start(DragStartDetails d) {
    final vp = widget.viewport;
    final r = _widgetRect(vp, _crop);
    final p = d.localPosition;
    final corners = {
      _Handle.tl: r.topLeft,
      _Handle.tr: r.topRight,
      _Handle.bl: r.bottomLeft,
      _Handle.br: r.bottomRight,
    };
    _Handle? best;
    var bestD = _grab;
    corners.forEach((h, c) {
      final dist = (c - p).distance;
      if (dist < bestD) {
        bestD = dist;
        best = h;
      }
    });
    _active = best ?? (r.contains(p) ? _Handle.move : null);
  }

  void _update(DragUpdateDetails d) {
    final h = _active;
    if (h == null) return;
    final vp = widget.viewport;
    final dn = Offset(
      d.delta.dx / vp.display.width,
      d.delta.dy / vp.display.height,
    );
    final c = _crop;
    var l = c.left, t = c.top, r = c.right, b = c.bottom;
    switch (h) {
      case _Handle.tl:
        l += dn.dx;
        t += dn.dy;
      case _Handle.tr:
        r += dn.dx;
        t += dn.dy;
      case _Handle.bl:
        l += dn.dx;
        b += dn.dy;
      case _Handle.br:
        r += dn.dx;
        b += dn.dy;
      case _Handle.move:
        final mx = dn.dx.clamp(-l, 1 - r).toDouble();
        final my = dn.dy.clamp(-t, 1 - b).toDouble();
        l += mx;
        r += mx;
        t += my;
        b += my;
    }
    widget.state.setCropDraft(CropRect(l, t, r, b));
  }

  // Screen reader and keyboard route: each edge moves in 5% steps.
  void _trim(double l, double t, double r, double b) {
    final c = _crop;
    widget.state.setCropDraft(
      CropRect(c.left + l, c.top + t, c.right + r, c.bottom + b),
    );
  }

  @override
  Widget build(BuildContext context) {
    const s = 0.05;
    return Semantics(
      label: 'Crop frame',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Trim more from the left'): () =>
            _trim(s, 0, 0, 0),
        const CustomSemanticsAction(label: 'Trim less from the left'): () =>
            _trim(-s, 0, 0, 0),
        const CustomSemanticsAction(label: 'Trim more from the right'): () =>
            _trim(0, 0, -s, 0),
        const CustomSemanticsAction(label: 'Trim less from the right'): () =>
            _trim(0, 0, s, 0),
        const CustomSemanticsAction(label: 'Trim more from the top'): () =>
            _trim(0, s, 0, 0),
        const CustomSemanticsAction(label: 'Trim less from the top'): () =>
            _trim(0, -s, 0, 0),
        const CustomSemanticsAction(label: 'Trim more from the bottom'): () =>
            _trim(0, 0, 0, -s),
        const CustomSemanticsAction(label: 'Trim less from the bottom'): () =>
            _trim(0, 0, 0, s),
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          QuickPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<QuickPanGestureRecognizer>(
                QuickPanGestureRecognizer.new,
                (r) => r
                  ..dragStartBehavior = DragStartBehavior
                      .down // grab the corner you touched
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = (_) => _active = null,
              ),
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _CropPainter(
            widget.viewport.display,
            () => _widgetRect(widget.viewport, _crop),
            _enter,
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.target, this.enter) : super(repaint: enter);
  final Rect image;
  final Rect Function() target;
  final Animation<double> enter;

  Rect get crop =>
      Rect.lerp(image, target(), Curves.easeOutCubic.transform(enter.value))!;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim everything outside the frame.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(image),
      Path()..addRect(crop),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0xB3000000));

    final edge = Paint()
      ..color = FluoColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(crop, edge);

    // Thirds guide.
    final guide = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        guide,
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        guide,
      );
    }

    // Corner brackets.
    final br = Paint()
      ..color = FluoColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const k = 18.0;
    void corner(Offset c, double sx, double sy) {
      canvas.drawLine(c, c + Offset(sx * k, 0), br);
      canvas.drawLine(c, c + Offset(0, sy * k), br);
    }

    corner(crop.topLeft, 1, 1);
    corner(crop.topRight, -1, 1);
    corner(crop.bottomLeft, 1, -1);
    corner(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
