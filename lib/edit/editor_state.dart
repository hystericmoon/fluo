import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'geometry.dart';
import 'render.dart' show arrowOf, pointsOf, rectOf;

enum EditTool { crop, pen, arrow, box, pin, redact }

class _Added {
  const _Added(this.id, this.isPin);
  final String id;
  final bool isPin;
}

/// Everything the Editor does to one screenshot. Each change is written to
/// the database straight away; the original file is never touched.
class EditorState extends ChangeNotifier {
  EditorState(this._repo, this.shotId) {
    _reload();
  }

  final FluoRepo _repo;
  final String shotId;

  late ShotEdit edit;
  EditTool tool = EditTool.pin;
  String? selectedId;
  Severity newPinSeverity = Severity.bug;

  /// The crop being dragged while the crop tool is open.
  CropRect? cropDraft;

  final List<_Added> _history = [];

  static const minCropSize = 0.1;
  static const minShape = 0.02;

  void _reload() {
    edit = _repo.loadEdit(shotId)!;
  }

  void _changed() {
    _reload();
    notifyListeners();
  }

  List<Pin> get pins => edit.pins;
  List<Annotation> get annotations => edit.annotations;
  Shot get shot => edit.shot;

  Pin? get selectedPin => pins.where((p) => p.id == selectedId).firstOrNull;
  Annotation? get selectedAnnotation => annotations.where((a) => a.id == selectedId).firstOrNull;
  bool get canUndo => _history.isNotEmpty;

  // ---- tools and selection ----------------------------------------------

  void setTool(EditTool t) {
    tool = t;
    selectedId = null;
    cropDraft = t == EditTool.crop ? (shot.crop ?? const CropRect(0, 0, 1, 1)) : null;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void setNewPinSeverity(Severity s) {
    newPinSeverity = s;
    final p = selectedPin;
    if (p != null) _repo.updatePin(p.id, severity: s);
    _changed();
  }

  // ---- adding marks ------------------------------------------------------

  Offset _clamp(Offset o) => Offset(o.dx.clamp(0.0, 1.0).toDouble(), o.dy.clamp(0.0, 1.0).toDouble());

  Pin addPin(Offset at) {
    final c = _clamp(at);
    final p = _repo.addPin(shotId, newPinSeverity, c.dx, c.dy);
    _history.add(_Added(p.id, true));
    selectedId = p.id;
    _changed();
    return p;
  }

  Annotation? _add(AnnotationKind k, Map<String, Object?> data) {
    final a = _repo.addAnnotation(shotId, k, data);
    _history.add(_Added(a.id, false));
    selectedId = a.id;
    _changed();
    return a;
  }

  /// Returns null (and stores nothing) for an accidental tap or tiny drag.
  Annotation? addStroke(List<Offset> points) {
    final pts = simplifyStroke([for (final p in points) _clamp(p)]);
    if (pts.length < 2) return null;
    // A finger jitter while tapping is not a stroke.
    final bounds = pts.map((p) => Rect.fromLTWH(p.dx, p.dy, 0, 0)).reduce((a, b) => a.expandToInclude(b));
    if ((bounds.bottomRight - bounds.topLeft).distance < minShape / 2) return null;
    return _add(AnnotationKind.pen, {
      'points': [for (final p in pts) [p.dx, p.dy]],
    });
  }

  Annotation? addArrow(Offset from, Offset to) {
    final a = _clamp(from), b = _clamp(to);
    if ((a - b).distance < minShape) return null;
    return _add(AnnotationKind.arrow, {
      'from': [a.dx, a.dy],
      'to': [b.dx, b.dy],
    });
  }

  Annotation? addRect(AnnotationKind kind, Offset a, Offset b) {
    assert(kind == AnnotationKind.box || kind == AnnotationKind.redact);
    final r = Rect.fromPoints(_clamp(a), _clamp(b));
    if (r.width < minShape / 2 || r.height < minShape / 2 || (r.bottomRight - r.topLeft).distance < minShape) {
      return null;
    }
    return _add(kind, {
      'rect': [r.left, r.top, r.right, r.bottom],
    });
  }

  // ---- without dragging --------------------------------------------------

  /// A box, redaction or arrow made from a button: placed in the middle of
  /// the visible picture and selected, ready to move and resize with
  /// [nudgeSelected] and [resizeSelected].
  Annotation? addDefaultShape(AnnotationKind kind) {
    final c = shot.crop ?? const CropRect(0, 0, 1, 1);
    final cx = (c.left + c.right) / 2, cy = (c.top + c.bottom) / 2;
    final w = c.right - c.left, h = c.bottom - c.top;
    switch (kind) {
      case AnnotationKind.box:
      case AnnotationKind.redact:
        return addRect(kind, Offset(cx - w * .25, cy - h * .06), Offset(cx + w * .25, cy + h * .06));
      case AnnotationKind.arrow:
        return addArrow(Offset(cx - w * .2, cy), Offset(cx + w * .2, cy));
      case AnnotationKind.pen:
        return null; // a freehand line needs a finger
    }
  }

  /// Moves the selected pin or mark by a fraction of the image, keeping it
  /// inside the picture.
  void nudgeSelected(double dx, double dy) {
    final pin = selectedPin;
    if (pin != null) {
      movePin(pin.id, Offset(pin.x + dx, pin.y + dy));
      return;
    }
    final a = selectedAnnotation;
    if (a == null) return;
    final pts = <Offset>[
      ...pointsOf(a),
      if (rectOf(a) != null) ...[rectOf(a)!.topLeft, rectOf(a)!.bottomRight],
      if (arrowOf(a) != null) ...[arrowOf(a)!.$1, arrowOf(a)!.$2],
    ];
    if (pts.isEmpty) return;
    // Shift as far as it can go without any point leaving the image.
    final minX = pts.map((p) => p.dx).reduce((x, y) => x < y ? x : y);
    final maxX = pts.map((p) => p.dx).reduce((x, y) => x > y ? x : y);
    final minY = pts.map((p) => p.dy).reduce((x, y) => x < y ? x : y);
    final maxY = pts.map((p) => p.dy).reduce((x, y) => x > y ? x : y);
    final mx = dx.clamp(-minX, 1 - maxX).toDouble();
    final my = dy.clamp(-minY, 1 - maxY).toDouble();
    Offset m(Offset o) => Offset(o.dx + mx, o.dy + my);
    _repo.updateAnnotation(a.id, switch (a.kind) {
      AnnotationKind.pen => {'points': [for (final p in pointsOf(a)) [m(p).dx, m(p).dy]]},
      AnnotationKind.arrow => {
          'from': [m(arrowOf(a)!.$1).dx, m(arrowOf(a)!.$1).dy],
          'to': [m(arrowOf(a)!.$2).dx, m(arrowOf(a)!.$2).dy],
        },
      AnnotationKind.box || AnnotationKind.redact => {
          'rect': [m(rectOf(a)!.topLeft).dx, m(rectOf(a)!.topLeft).dy, m(rectOf(a)!.bottomRight).dx, m(rectOf(a)!.bottomRight).dy],
        },
    });
    _changed();
  }

  /// Grows or shrinks the selected box or redaction around its centre by
  /// [dw] and [dh] (fractions of the image), or lengthens an arrow by [dw].
  void resizeSelected(double dw, double dh) {
    final a = selectedAnnotation;
    if (a == null) return;
    final r = rectOf(a);
    if (r != null) {
      const minSize = 0.04;
      final w = (r.width + dw).clamp(minSize, 1.0).toDouble();
      final h = (r.height + dh).clamp(minSize, 1.0).toDouble();
      var left = r.center.dx - w / 2, top = r.center.dy - h / 2;
      left = left.clamp(0.0, 1 - w).toDouble(); // slide back in rather than crop
      top = top.clamp(0.0, 1 - h).toDouble();
      _repo.updateAnnotation(a.id, {'rect': [left, top, left + w, top + h]});
      _changed();
      return;
    }
    final ar = arrowOf(a);
    if (ar != null) {
      final v = ar.$2 - ar.$1;
      final len = v.distance;
      if (len == 0) return;
      final newLen = (len + dw).clamp(minShape, 1.5).toDouble();
      final tip = _clamp(ar.$1 + v / len * newLen);
      if ((tip - ar.$1).distance < minShape) return;
      _repo.updateAnnotation(a.id, {
        'from': [ar.$1.dx, ar.$1.dy],
        'to': [tip.dx, tip.dy],
      });
      _changed();
    }
  }

  // ---- changing and removing --------------------------------------------

  void movePin(String id, Offset to) {
    final c = _clamp(to);
    _repo.updatePin(id, x: c.dx, y: c.dy);
    _changed();
  }

  void setPinNote(String id, String note) {
    _repo.updatePin(id, note: note);
    _reload(); // no rebuild per keystroke
  }

  void setCaption(String caption) {
    _repo.setCaption(shotId, caption);
    _reload();
  }

  void deleteSelected() {
    final id = selectedId;
    if (id == null) return;
    if (selectedPin != null) {
      _repo.deletePin(id);
    } else if (selectedAnnotation != null) {
      _repo.deleteAnnotation(id);
    }
    _history.removeWhere((h) => h.id == id);
    selectedId = null;
    _changed();
  }

  /// Removes the mark added last. Moves, notes and deletions are not undone.
  void undo() {
    if (_history.isEmpty) return;
    final h = _history.removeLast();
    if (h.isPin) {
      _repo.deletePin(h.id);
    } else {
      _repo.deleteAnnotation(h.id);
    }
    if (selectedId == h.id) selectedId = null;
    _changed();
  }

  // ---- crop --------------------------------------------------------------

  void setCropDraft(CropRect r) {
    cropDraft = _fixCrop(r);
    notifyListeners();
  }

  static CropRect _fixCrop(CropRect r) {
    var l = r.left.clamp(0.0, 1 - minCropSize).toDouble();
    var t = r.top.clamp(0.0, 1 - minCropSize).toDouble();
    var rt = r.right.clamp(l + minCropSize, 1.0).toDouble();
    var b = r.bottom.clamp(t + minCropSize, 1.0).toDouble();
    return CropRect(l, t, rt, b);
  }

  bool get cropIsFull {
    final c = cropDraft;
    return c == null || (c.left <= 0 && c.top <= 0 && c.right >= 1 && c.bottom >= 1);
  }

  /// Saves the dragged crop (or clears it if it is the whole image) and
  /// returns to the pin tool.
  void applyCrop() {
    _repo.setCrop(shotId, cropIsFull ? null : cropDraft);
    tool = EditTool.pin;
    cropDraft = null;
    _changed();
  }

  void resetCrop() {
    _repo.setCrop(shotId, null);
    cropDraft = const CropRect(0, 0, 1, 1);
    _changed();
  }
}
