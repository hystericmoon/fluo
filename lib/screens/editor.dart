import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/models.dart';
import '../data/repo_scope.dart';
import '../edit/crop_overlay.dart';
import '../edit/editor_state.dart';
import '../edit/hit_test.dart';
import '../edit/image_loader.dart';
import '../edit/quick_pan.dart';
import '../edit/render.dart';
import '../edit/viewport.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Edit one screenshot: crop, draw, pin, redact and caption. Everything is
/// saved as it happens and the original file is never changed.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.shotId});
  final String shotId;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorState? _s;
  ui.Image? _img;
  bool _failed = false;

  static const _tools = {
    EditTool.crop: (LucideIcons.crop, 'Crop'),
    EditTool.pen: (LucideIcons.pencil, 'Pen'),
    EditTool.arrow: (LucideIcons.moveUpRight, 'Arrow'),
    EditTool.box: (LucideIcons.square, 'Box'),
    EditTool.pin: (LucideIcons.mapPin, 'Pin'),
    EditTool.redact: (LucideIcons.eyeOff, 'Redact'),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s != null) return;
    final repo = RepoScope.of(context);
    final s = EditorState(repo, widget.shotId);
    _s = s;
    loadShotImage(s.shot.originalPath).then((i) {
      if (!mounted) {
        i.dispose();
        return;
      }
      setState(() => _img = i);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _s?.dispose();
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s!;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final repo = RepoScope.of(context);
        final album = repo.getAlbum(s.shot.albumId);
        final kept = repo.shotsIn(s.shot.albumId, status: ShotStatus.kept);
        final idx = kept.indexWhere((k) => k.id == s.shot.id);
        final name = s.shot.name.isEmpty ? 'Untitled' : s.shot.name;
        return Container(
          color: FluoColors.bg,
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(children: [
                          ScreenHeader(
                            title: name,
                            subtitle: '${idx < 0 ? '' : '${idx + 1} of ${kept.length} · '}${album?.name ?? ''}',
                            leading: backButton(context, label: 'Back to album'),
                            trailing: [
                              FluoIconButton(
                                icon: LucideIcons.undo2,
                                label: 'Undo last mark',
                                onPressed: s.canUndo ? s.undo : null,
                              ),
                              FluoButton(
                                label: 'Done',
                                kind: BtnKind.primary,
                                hPad: 18,
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _canvas(s),
                          const SizedBox(height: 12),
                          _toolbar(s),
                          const SizedBox(height: 12),
                        ]),
                      ),
                      Expanded(child: _panel(s)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _canvas(EditorState s) {
    final summary =
        '${s.shot.name.isEmpty ? 'Screenshot' : s.shot.name} with ${s.pins.length} ${s.pins.length == 1 ? 'pin' : 'pins'} and ${s.annotations.length} other ${s.annotations.length == 1 ? 'mark' : 'marks'}';
    return Container(
      height: 400,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF121215),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FluoColors.border),
      ),
      child: _failed
          ? Center(child: Text("Couldn't open this screenshot", style: fs(14, c: FluoColors.fgMuted)))
          : _img == null
              ? const SizedBox.shrink()
              : Semantics(
                  label: summary,
                  image: true,
                  child: _Canvas(state: s, image: _img!),
                ),
    );
  }

  Widget _toolbar(EditorState s) => Semantics(
        container: true,
        explicitChildNodes: true, // controls inside stay separately focusable
        label: 'Edit tools',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final t in EditTool.values) ...[
            if (t != EditTool.crop) const SizedBox(width: 8),
            Pressable(
              radius: 12,
              label: _tools[t]!.$2,
              toggled: s.tool == t,
              onTap: () => s.setTool(t),
              builder: (_, _) {
                final on = s.tool == t;
                return Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: on ? FluoColors.lime : FluoColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: on ? FluoColors.lime : FluoColors.border),
                  ),
                  child: Icon(_tools[t]!.$1, size: 22, color: on ? FluoColors.onLime : FluoColors.fg),
                );
              },
            ),
          ],
        ]),
      );

  // ---- panel -------------------------------------------------------------

  Widget _panel(EditorState s) {
    final Widget top;
    if (s.tool == EditTool.crop) {
      top = _cropPanel(s);
    } else if (s.selectedPin != null) {
      top = _pinPanel(s, s.selectedPin!);
    } else if (s.selectedAnnotation != null) {
      top = _markPanel(s, s.selectedAnnotation!);
    } else {
      top = _hintPanel(s);
    }
    return Semantics(
      container: true,
      explicitChildNodes: true, // controls inside stay separately focusable
      label: 'Details',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(
          color: FluoColors.surface,
          border: Border(top: BorderSide(color: FluoColors.border)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          top,
          if (s.tool != EditTool.crop && (s.pins.isNotEmpty || s.annotations.isNotEmpty)) ...[
            const SizedBox(height: 12),
            _marksList(s),
          ],
          const SizedBox(height: 12),
          FluoField(
            key: ValueKey('caption-${s.shot.id}'),
            label: 'Caption for this screen',
            initial: s.shot.caption,
            onChanged: s.setCaption,
          ),
        ]),
      ),
    );
  }

  Widget _sevButton(EditorState s, Severity sev, Severity current) {
    final on = sev == current;
    return Pressable(
      radius: 10,
      selected: on,
      onTap: () => s.setNewPinSeverity(sev),
      builder: (_, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? FluoTints.bugSoft : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? sev.color : FluoColors.borderStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SeverityDot(sev),
          const SizedBox(width: 7),
          Text(sev.label, style: fs(14, w: FontWeight.w500, c: on ? sev.color : FluoColors.fg)),
        ]),
      ),
    );
  }

  Widget _pinPanel(EditorState s, Pin p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Pin ${p.severity.letter}${p.number}', style: fs(15, w: FontWeight.w600)),
          ),
        ),
        for (final sev in Severity.values) ...[
          _sevButton(s, sev, p.severity),
          const SizedBox(width: 8),
        ],
        FluoIconButton(
          icon: LucideIcons.trash2,
          label: 'Delete pin ${p.severity.letter}${p.number}',
          onPressed: s.deleteSelected,
        ),
      ]),
      const SizedBox(height: 12),
      FluoField(
        key: ValueKey('note-${p.id}'),
        label: 'Note on this pin',
        initial: p.note,
        onChanged: (v) => s.setPinNote(p.id, v),
      ),
      const SizedBox(height: 12),
      _movePad(s, 'pin'),
    ]);
  }

  String _kindName(AnnotationKind k) => switch (k) {
        AnnotationKind.pen => 'Pen stroke',
        AnnotationKind.arrow => 'Arrow',
        AnnotationKind.box => 'Box',
        AnnotationKind.redact => 'Redaction',
      };

  Widget _markPanel(EditorState s, Annotation a) {
    final name = _kindName(a.kind);
    final sizes = switch (a.kind) {
      AnnotationKind.box || AnnotationKind.redact => [
          ('Wider', () => s.resizeSelected(0.04, 0)),
          ('Narrower', () => s.resizeSelected(-0.04, 0)),
          ('Taller', () => s.resizeSelected(0, 0.04)),
          ('Shorter', () => s.resizeSelected(0, -0.04)),
        ],
      AnnotationKind.arrow => [
          ('Longer', () => s.resizeSelected(0.04, 0)),
          ('Shorter', () => s.resizeSelected(-0.04, 0)),
        ],
      AnnotationKind.pen => const <(String, VoidCallback)>[],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(name, style: fs(15, w: FontWeight.w600))),
            if (a.kind == AnnotationKind.redact)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Hidden in every export', style: fs(13, c: FluoColors.fgMuted)),
              ),
          ]),
        ),
        FluoIconButton(icon: LucideIcons.trash2, label: 'Delete ${name.toLowerCase()}', onPressed: s.deleteSelected),
      ]),
      const SizedBox(height: 12),
      _movePad(s, name.toLowerCase()),
      if (sizes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, tap) in sizes)
            FluoButton(label: label, onPressed: tap),
        ]),
      ],
    ]);
  }

  /// Move the selected pin or mark with buttons: the same thing as dragging.
  Widget _movePad(EditorState s, String what) {
    Widget b(IconData icon, String dir, double dx, double dy) => FluoIconButton(
          icon: icon,
          label: 'Move $what $dir',
          onPressed: () => s.nudgeSelected(dx, dy),
        );
    return Row(children: [
      // Flexes and ellipsizes, so large system text never squeezes the buttons.
      Expanded(
        child: Text('Move $what',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
      ),
      const SizedBox(width: 8),
      b(LucideIcons.arrowLeft, 'left', -0.02, 0),
      const SizedBox(width: 8),
      b(LucideIcons.arrowUp, 'up', 0, -0.02),
      const SizedBox(width: 8),
      b(LucideIcons.arrowDown, 'down', 0, 0.02),
      const SizedBox(width: 8),
      b(LucideIcons.arrowRight, 'right', 0.02, 0),
    ]);
  }

  Widget _hintPanel(EditorState s) {
    final hint = switch (s.tool) {
      EditTool.pin => 'Tap the screenshot to drop a pin. Tap a mark to edit it.',
      EditTool.pen => 'Draw on the screenshot with your finger.',
      EditTool.arrow => 'Drag from the tail to the tip.',
      EditTool.box => 'Drag to draw a box around something.',
      EditTool.redact => 'Drag over anything private. It is blacked out in every export.',
      EditTool.crop => '',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(hint, style: fs(14, c: FluoColors.fgMuted, h: 1.4))),
      ]),
      if (s.tool == EditTool.box || s.tool == EditTool.redact || s.tool == EditTool.arrow) ...[
        const SizedBox(height: 12),
        // The same thing as dragging: a shape in the middle, then move and
        // resize it with the buttons that appear.
        FluoButton(
          label: switch (s.tool) {
            EditTool.box => 'Add a box in the middle',
            EditTool.redact => 'Add a redaction in the middle',
            _ => 'Add an arrow in the middle',
          },
          icon: switch (s.tool) {
            EditTool.box => LucideIcons.square,
            EditTool.redact => LucideIcons.eyeOff,
            _ => LucideIcons.moveUpRight,
          },
          expand: true,
          onPressed: () => s.addDefaultShape(switch (s.tool) {
            EditTool.box => AnnotationKind.box,
            EditTool.redact => AnnotationKind.redact,
            _ => AnnotationKind.arrow,
          }),
        ),
      ],
      if (s.tool == EditTool.pin) ...[
        const SizedBox(height: 12),
        Row(children: [
          Text('New pin', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
          const Spacer(),
          for (final sev in Severity.values) ...[
            const SizedBox(width: 8),
            _sevButton(s, sev, s.newPinSeverity),
          ],
        ]),
        const SizedBox(height: 12),
        // The same thing without touching the image.
        FluoButton(
          label: 'Add pin in the middle',
          icon: LucideIcons.mapPin,
          expand: true,
          onPressed: () => s.addPin(const Offset(0.5, 0.5)),
        ),
      ],
    ]);
  }

  Widget _cropPanel(EditorState s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text('Crop', style: fs(15, w: FontWeight.w600))),
      const SizedBox(height: 4),
      Text(
        'Drag the corners or the frame. The original screenshot is never cut; the crop is only applied when you export.',
        style: fs(13, c: FluoColors.fgMuted, h: 1.4),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FluoButton(label: 'Apply crop', kind: BtnKind.primary, expand: true, onPressed: s.applyCrop),
        ),
        const SizedBox(width: 8),
        FluoButton(label: 'Reset', onPressed: s.shot.crop == null && s.cropIsFull ? null : s.resetCrop),
      ]),
    ]);
  }

  /// Every mark as a button: select without touching the image.
  Widget _marksList(EditorState s) {
    final items = <(String, String, String)>[
      for (final p in s.pins) (p.id, '${p.severity.letter}${p.number}', 'Pin ${p.severity.letter}${p.number}, ${p.severity.label}'),
      for (final a in s.annotations) (a.id, _kindName(a.kind), _kindName(a.kind)),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true, // controls inside stay separately focusable
      label: 'Marks on this screen',
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, text, label) in items)
          Pressable(
            radius: 22,
            selected: s.selectedId == id,
            label: label,
            onTap: () => s.select(id),
            builder: (_, _) => Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: s.selectedId == id ? FluoColors.limeTint : null,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: s.selectedId == id ? FluoColors.lime : FluoColors.borderStrong),
              ),
              // Center with a width factor keeps the chip as wide as its text.
              child: Center(
                widthFactor: 1,
                child: Text(text,
                    style: fs(14, w: FontWeight.w500, c: s.selectedId == id ? FluoColors.limeSoft : FluoColors.fg)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The picture with its marks, and the gestures that make them.
class _Canvas extends StatefulWidget {
  const _Canvas({required this.state, required this.image});
  final EditorState state;
  final ui.Image image;

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  List<Offset> _points = []; // normalised, while drawing
  String? _pinId; // being dragged
  Offset? _pinAt;
  Offset? _downAt; // widget coordinates where the finger landed
  double _travel = 0; // furthest the finger got from there

  EditorState get s => widget.state;

  EditViewport _vp(Size box) => EditViewport(
        box: box,
        imageSize: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
        crop: s.tool == EditTool.crop ? null : s.shot.crop, // crop mode shows the whole image
      );

  Annotation? _draft() {
    if (_points.length < 2) return null;
    final a = _points.first, b = _points.last;
    return switch (s.tool) {
      EditTool.pen => Annotation(
          id: 'draft', shotId: '', kind: AnnotationKind.pen, z: 1 << 20,
          data: {'points': [for (final p in _points) [p.dx, p.dy]]}),
      EditTool.arrow => Annotation(
          id: 'draft', shotId: '', kind: AnnotationKind.arrow, z: 1 << 20,
          data: {'from': [a.dx, a.dy], 'to': [b.dx, b.dy]}),
      EditTool.box || EditTool.redact => Annotation(
          id: 'draft', shotId: '', z: 1 << 20,
          kind: s.tool == EditTool.box ? AnnotationKind.box : AnnotationKind.redact,
          data: {'rect': [a.dx < b.dx ? a.dx : b.dx, a.dy < b.dy ? a.dy : b.dy, a.dx < b.dx ? b.dx : a.dx, a.dy < b.dy ? b.dy : a.dy]}),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final vp = _vp(box);
      final draft = _draft();
      final pins = [
        for (final p in s.pins)
          if (p.id == _pinId && _pinAt != null)
            Pin(id: p.id, shotId: p.shotId, number: p.number, severity: p.severity, x: _pinAt!.dx, y: _pinAt!.dy, note: p.note)
          else
            p,
      ];
      return Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: EditPainter(
              image: widget.image,
              viewport: vp,
              annotations: [...s.annotations, ?draft],
              pins: pins,
              selectedId: s.selectedId,
            ),
          ),
        ),
        if (s.tool == EditTool.crop)
          Positioned.fill(child: CropOverlay(state: s, viewport: vp))
        else
          Positioned.fill(
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (r) => r.onTapUp = (d) => _tap(vp, d.localPosition),
                ),
                // Claims drags early so the page does not scroll under a
                // stroke, and starts where the finger landed so a pin you
                // grab is the pin you touched.
                QuickPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<QuickPanGestureRecognizer>(
                  QuickPanGestureRecognizer.new,
                  (r) => r
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = ((d) => _panStart(vp, d.localPosition))
                    ..onUpdate = ((d) => _panUpdate(vp, d.localPosition))
                    ..onEnd = ((_) => _panEnd(vp))
                    ..onCancel = _reset,
                ),
              },
            ),
          ),
      ]);
    });
  }

  void _tap(EditViewport vp, Offset local) {
    final id = hitTest(vp, local, s.annotations, s.pins);
    if (id != null) {
      s.select(id);
    } else if (s.tool == EditTool.pin && vp.display.contains(local)) {
      s.addPin(vp.toNorm(local));
    } else {
      s.select(null);
    }
  }

  void _panStart(EditViewport vp, Offset local) {
    _downAt = local;
    _travel = 0;
    if (s.tool == EditTool.pin) {
      final id = hitTest(vp, local, const [], s.pins);
      if (id != null) {
        s.select(id);
        setState(() {
          _pinId = id;
          _pinAt = vp.clampToRegion(vp.toNorm(local));
        });
      }
      return;
    }
    if (!vp.display.contains(local)) return;
    setState(() => _points = [vp.toNorm(local)]);
  }

  void _panUpdate(EditViewport vp, Offset local) {
    final d0 = _downAt;
    if (d0 != null) _travel = _travel > (local - d0).distance ? _travel : (local - d0).distance;
    if (_pinId != null) {
      setState(() => _pinAt = vp.clampToRegion(vp.toNorm(local)));
    } else if (_points.isNotEmpty) {
      final n = vp.clampToRegion(vp.toNorm(local));
      setState(() {
        if (s.tool == EditTool.pen) {
          _points = [..._points, n];
        } else {
          _points = [_points.first, n];
        }
      });
    }
  }

  void _panEnd(EditViewport vp) {
    final pts = _points;
    final pin = _pinId, at = _pinAt;
    final down = _downAt;
    final wasTap = _travel < 12;
    _reset();
    if (wasTap && down != null) {
      // Barely moved: the finger meant a tap (placing or selecting), which
      // the quick pan recognizer won before the tap recognizer could.
      _tap(vp, down);
    } else if (pin != null && at != null) {
      s.movePin(pin, at);
    } else if (pts.length >= 2) {
      switch (s.tool) {
        case EditTool.pen:
          s.addStroke(pts);
        case EditTool.arrow:
          s.addArrow(pts.first, pts.last);
        case EditTool.box:
          s.addRect(AnnotationKind.box, pts.first, pts.last);
        case EditTool.redact:
          s.addRect(AnnotationKind.redact, pts.first, pts.last);
        case EditTool.pin || EditTool.crop:
          break;
      }
    }
  }

  void _reset() => setState(() {
        _points = [];
        _pinId = null;
        _pinAt = null;
        _downAt = null;
        _travel = 0;
      });
}
