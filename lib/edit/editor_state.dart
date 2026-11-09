import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'geometry.dart';

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

  // ---- changing and removing --------------------------------------------

  void movePin(String id, Offset to) {
    final c = _clamp(to);
    _repo.updatePin(id, x: c.dx, y: c.dy);
    _changed();
  }

  /// Moves the selected pin by a fraction of the image (keyboard and screen
  /// reader users cannot drag).
  void nudgeSelectedPin(double dx, double dy) {
    final p = selectedPin;
    if (p != null) movePin(p.id, Offset(p.x + dx, p.y + dy));
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
