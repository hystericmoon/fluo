import 'package:flutter/gestures.dart';

/// A pan recognizer that claims the gesture after 8px.
///
/// The stock [PanGestureRecognizer] needs twice the touch slop, so a page's
/// vertical scroll view (18px) beats it for any mostly-vertical drag and the
/// page scrolls instead of the stroke being drawn. On the editor canvas the
/// drag is always meant for the canvas.
class QuickPanGestureRecognizer extends PanGestureRecognizer {
  QuickPanGestureRecognizer({super.debugOwner});

  static const double slop = 8;

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > slop;
}
