import 'dart:async';

import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_scope.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../data/repo_scope.dart';
import '../motion/fuse.dart';
import '../screens/album.dart';
import '../screens/albums.dart';
import '../screens/editor.dart';
import '../screens/export.dart';
import '../screens/settings.dart';
import '../screens/triage.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/new_album_dialog.dart';
import '../ui/shot_image.dart';
import '../ui/wordmark.dart';
import 'album_picker.dart';
import 'desktop_scope.dart';

/// The home screen: the desktop shell in a wide macOS window, the phone's
/// Albums screen everywhere else.
class AdaptiveHome extends StatelessWidget {
  const AdaptiveHome({super.key});

  @override
  Widget build(BuildContext context) =>
      DesktopScope.isWide(context) ? const DesktopShell() : const AlbumsScreen();
}

const double _sidebarWidth = 280;
const double _inspectorWidth = 320;
const double _tileExtent = 190;
const double _tileGap = 12;

/// Three panes: albums on the left, the selected album's screens in the
/// middle, and an inspector for the selection on the right. Triage, the
/// editor, export and settings open over it.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  String? _albumId;
  final Set<String> _sel = {};
  String? _focus; // the shot keyboard commands act on
  String? _anchor; // start of a Shift range
  bool _selectMode = false;
  bool _flow = true;
  bool _reorder = false;
  Severity? _filter;
  int _cols = 3;
  String? _lastTapId;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Deleted from view, committed when the undo fuse burns.
  AlbumSummary? _pendingAlbum;
  Set<String> _pendingShots = {};
  String _pendingShotsLabel = '';

  StreamSubscription<String>? _cmdSub;
  final FocusNode _node = FocusNode(debugLabel: 'desktop-shell');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cmdSub ??= DesktopScope.maybeOf(context)?.commands.stream.listen(_command);
  }

  @override
  void dispose() {
    _cmdSub?.cancel();
    _node.dispose();
    super.dispose();
  }

  // ---- commands (menu bar and keys share these) ----

  void _command(String c) {
    if (!mounted) return;
    switch (c) {
      case 'newAlbum':
        _newAlbum();
      case 'export':
        _export();
      case 'review':
        _review();
      case 'grid':
        setState(() => _flow = false);
      case 'flow':
        setState(() => _flow = true);
      case 'settings':
        _push(const SettingsScreen(), maxWidth: 860);
    }
  }

  Future<void> _push(Widget page, {double? maxWidth = 560}) async {
    await Navigator.of(context).push(fluoRoute(page, maxWidth: maxWidth));
    if (mounted) setState(() {});
  }

  Future<void> _newAlbum() async {
    final name = await askAlbumName(context);
    if (name == null || !mounted) return;
    final album = RepoScope.of(context).createAlbum(name);
    await CaptureScope.of(context).begin(album.id); // a new album starts a session
    if (mounted) _selectAlbum(album.id);
  }

  void _selectAlbum(String id) {
    _commitShots(); // finish an earlier discard before moving away
    setState(() {
      _albumId = id;
      _sel.clear();
      _focus = _anchor = null;
      _filter = null;
      _reorder = false;
    });
  }

  void _export() {
    final id = _albumId;
    if (id == null) return;
    final kept = RepoScope.of(context).shotsIn(id, status: ShotStatus.kept);
    if (kept.isNotEmpty) _push(ExportScreen(albumId: id), maxWidth: 960);
  }

  /// Export only the selected screens.
  void _exportSelection() {
    final id = _albumId;
    if (id == null || _sel.isEmpty) return;
    _push(ExportScreen(albumId: id, only: {..._sel}), maxWidth: 960);
  }

  /// Move the selected screens to another album (pins and marks go with them).
  Future<void> _moveSelected() async {
    final repo = RepoScope.of(context);
    final from = _albumId;
    if (from == null || _sel.isEmpty) return;
    final others = [for (final a in repo.listAlbums()) if (a.album.id != from) a];
    if (others.isEmpty) return;
    final ids = [for (final s in repo.shotsIn(from, status: ShotStatus.kept)) if (_sel.contains(s.id)) s.id];
    final to = await pickAlbum(context, others, count: ids.length);
    if (to == null || !mounted) return;
    repo.moveShots(ids, to);
    setState(() {
      _sel.clear();
      _focus = _anchor = null;
    });
  }

  void _review() {
    final id = _albumId;
    if (id != null) _push(TriageScreen(albumId: id));
  }

  void _openEditor(String shotId) => _push(EditorScreen(shotId: shotId), maxWidth: null);

  Future<void> _albumOptions() async {
    final id = _albumId;
    if (id == null) return;
    if (await showAlbumOptions(context) && mounted) _scheduleAlbumDelete(id);
  }

  void _scheduleAlbumDelete(String id) {
    _commitAlbum();
    final a = RepoScope.of(context).listAlbums().where((x) => x.album.id == id).firstOrNull;
    if (a == null) return;
    setState(() {
      _pendingAlbum = a;
      if (_albumId == id) {
        _albumId = null;
        _sel.clear();
        _focus = _anchor = null;
      }
    });
  }

  void _commitAlbum() {
    final p = _pendingAlbum;
    if (p == null) return;
    _pendingAlbum = null;
    final capture = CaptureScope.of(context);
    RepoScope.of(context).deleteAlbum(p.album.id);
    capture.sync(); // a session in that album ended with it
  }

  // Discard: the screens leave the grid at once; they are deleted when the
  // undo fuse burns (or when another discard or album change settles them).
  void _discard(Set<String> ids) {
    if (ids.isEmpty) return;
    _commitShots();
    setState(() {
      _pendingShots = {...ids};
      _pendingShotsLabel =
          ids.length == 1 ? 'Discarded 1 screen' : 'Discarded ${ids.length} screens';
      _sel.removeAll(ids);
      if (ids.contains(_focus)) _focus = null;
    });
  }

  void _commitShots() {
    if (_pendingShots.isEmpty) return;
    final repo = RepoScope.of(context);
    final ids = _pendingShots;
    _pendingShots = {};
    final albumId = _albumId;
    for (final id in ids) {
      repo.setStatus(id, ShotStatus.discarded);
    }
    repo.purgeDiscarded(albumId: albumId);
  }

  // ---- selection ----

  void _click(Shot shot, List<Shot> order) {
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final now = DateTime.now();
    final again = _lastTapId == shot.id && now.difference(_lastTapAt) < const Duration(milliseconds: 350);
    _lastTapId = shot.id;
    _lastTapAt = now;
    if (again && !meta && !shift && !_selectMode) {
      _openEditor(shot.id); // double click
      return;
    }
    setState(() {
      if (shift && _anchor != null) {
        final a = order.indexWhere((s) => s.id == _anchor);
        final b = order.indexWhere((s) => s.id == shot.id);
        if (a >= 0 && b >= 0) {
          _sel
            ..clear()
            ..addAll(order.sublist(a < b ? a : b, (a < b ? b : a) + 1).map((s) => s.id));
        }
      } else if (meta || _selectMode) {
        _toggle(shot.id);
        _anchor = shot.id;
      } else {
        _sel
          ..clear()
          ..add(shot.id);
        _anchor = shot.id;
      }
      _focus = shot.id;
    });
  }

  void _toggle(String id) => _sel.contains(id) ? _sel.remove(id) : _sel.add(id);

  void _move(List<Shot> order, int delta) {
    if (order.isEmpty) return;
    final i = order.indexWhere((s) => s.id == _focus);
    final next = order[(i < 0 ? (delta > 0 ? 0 : order.length - 1) : (i + delta).clamp(0, order.length - 1))];
    setState(() {
      _focus = next.id;
      _anchor = next.id;
      _sel
        ..clear()
        ..add(next.id);
    });
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final capture = CaptureScope.of(context);
    final albums = [
      for (final a in repo.listAlbums())
        if (a.album.id != _pendingAlbum?.album.id) a,
    ];
    if (_albumId != null && !albums.any((a) => a.album.id == _albumId)) _albumId = null;
    _albumId ??= albums.firstOrNull?.album.id;
    final albumId = _albumId;

    final kept = albumId == null
        ? <Shot>[]
        : [
            for (final s in repo.shotsIn(albumId, status: ShotStatus.kept))
              if (!_pendingShots.contains(s.id)) s,
          ];
    _sel.removeWhere((id) => !kept.any((s) => s.id == id));
    final pins = albumId == null ? <String, List<Pin>>{} : repo.pinsInAlbum(albumId);
    final anyPins = Severity.values.any((s) => kept.any((k) => (pins[k.id] ?? const []).any((p) => p.severity == s)));
    final filter = anyPins ? _filter : null;
    final numbered = [for (var i = 0; i < kept.length; i++) (i + 1, kept[i])];
    final shown = filter == null
        ? numbered
        : [for (final e in numbered) if ((pins[e.$2.id] ?? const []).any((p) => p.severity == filter)) e];
    final order = [for (final e in shown) e.$2];

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newAlbum,
      const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _export,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => _command('settings'),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
        if (typingInTextField()) return;
        setState(() {
          _sel
            ..clear()
            ..addAll(order.map((s) => s.id));
        });
      },
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_sel.isNotEmpty) setState(_sel.clear);
      },
    };
    void bare(LogicalKeyboardKey k, VoidCallback f) =>
        shortcuts[SingleActivator(k)] = () {
          if (!typingInTextField()) f();
        };
    bare(LogicalKeyboardKey.arrowLeft, () => _move(order, -1));
    bare(LogicalKeyboardKey.arrowRight, () => _move(order, 1));
    bare(LogicalKeyboardKey.arrowUp, () => _move(order, -_cols));
    bare(LogicalKeyboardKey.arrowDown, () => _move(order, _cols));
    bare(LogicalKeyboardKey.space, () {
      final f = _focus;
      if (f != null) setState(() => _toggle(f));
    });
    bare(LogicalKeyboardKey.enter, () {
      final f = _focus ?? (_sel.length == 1 ? _sel.first : null);
      if (f != null) _openEditor(f);
    });
    void del() {
      final ids = _sel.isNotEmpty ? {..._sel} : (_focus == null ? <String>{} : {_focus!});
      _discard(ids);
    }

    bare(LogicalKeyboardKey.delete, del);
    bare(LogicalKeyboardKey.backspace, del);
    bare(LogicalKeyboardKey.keyG, () => setState(() => _flow = false));
    bare(LogicalKeyboardKey.keyF, () => setState(() => _flow = true));
    bare(LogicalKeyboardKey.keyR, _review);

    final session = repo.activeSession();
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        focusNode: _node,
        autofocus: true,
        child: Container(
          color: FluoColors.bg,
          child: Row(
            children: [
              SizedBox(
                width: _sidebarWidth,
                child: _Sidebar(
                  albums: albums,
                  selectedId: albumId,
                  session: session,
                  capture: capture,
                  onSelect: _selectAlbum,
                  onNew: _newAlbum,
                  onSettings: () => _command('settings'),
                  onReview: (id) {
                    _selectAlbum(id);
                    _push(TriageScreen(albumId: id));
                  },
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: FluoColors.border),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: albumId == null
                          ? _NoAlbum(onNew: _newAlbum)
                          : _AlbumPane(
                              album: repo.getAlbum(albumId),
                              kept: kept,
                              pending: repo.shotsIn(albumId, status: ShotStatus.pending).length,
                              pins: pins,
                              shown: shown,
                              filter: filter,
                              anyPins: anyPins,
                              flow: _flow,
                              reorder: _reorder,
                              selectMode: _selectMode,
                              selected: _sel,
                              focus: _focus,
                              onCols: (c) => _cols = c,
                              onFlow: (f) => setState(() => _flow = f),
                              onFilter: (f) => setState(() => _filter = f),
                              onReorder: () => setState(() => _reorder = !_reorder),
                              onSelectMode: () => setState(() => _selectMode = !_selectMode),
                              onSelectAll: () => setState(() {
                                _sel
                                  ..clear()
                                  ..addAll(order.map((s) => s.id));
                              }),
                              onClick: (s) => _click(s, order),
                              onMove: (id, d) => setState(() => repo.moveKept(albumId, id, d)),
                              onReview: _review,
                              onExport: _export,
                              onOptions: _albumOptions,
                            ),
                    ),
                    if (_pendingAlbum != null)
                      _fuse('album-${_pendingAlbum!.album.id}', 'Deleted ${_pendingAlbum!.album.name}',
                          () => setState(() => _pendingAlbum = null), () {
                        _commitAlbum();
                        if (mounted) setState(() {});
                      })
                    else if (_pendingShots.isNotEmpty)
                      _fuse('shots-${_pendingShots.join()}', _pendingShotsLabel,
                          () => setState(() => _pendingShots = {}), () {
                        _commitShots();
                        if (mounted) setState(() {});
                      }),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: FluoColors.border),
              SizedBox(
                width: _inspectorWidth,
                child: _Inspector(
                  album: albumId == null ? null : repo.getAlbum(albumId),
                  kept: kept,
                  pending: albumId == null ? 0 : repo.shotsIn(albumId, status: ShotStatus.pending).length,
                  pins: pins,
                  selected: [for (final s in kept) if (_sel.contains(s.id)) s],
                  onEdit: _openEditor,
                  onDiscard: () => _discard({..._sel}),
                  onClear: () => setState(_sel.clear),
                  onChanged: () => setState(() {}),
                  onExport: _export,
                  onReview: _review,
                  onExportSelection: _exportSelection,
                  onMove: albums.length > 1 ? _moveSelected : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fuse(String key, String message, VoidCallback undo, VoidCallback burnt) => Positioned(
        left: 24,
        right: 24,
        bottom: 20,
        child: UndoFuse(
          key: ValueKey('fuse-$key'),
          message: message,
          onUndo: undo,
          onBurnt: burnt,
        ),
      );
}

// ---------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.albums,
    required this.selectedId,
    required this.session,
    required this.capture,
    required this.onSelect,
    required this.onNew,
    required this.onSettings,
    required this.onReview,
  });
  final List<AlbumSummary> albums;
  final String? selectedId;
  final ReviewSession? session;
  final dynamic capture; // CaptureController
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;
  final VoidCallback onSettings;
  final ValueChanged<String> onReview;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sessionAlbum =
        session == null ? null : albums.where((a) => a.album.id == session!.albumId).firstOrNull;
    return Container(
      color: FluoColors.surface.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 16),
            child: Align(alignment: Alignment.centerLeft, child: FluoWordmark(size: 22)),
          ),
          FluoButton(
            label: 'New album',
            icon: LucideIcons.plus,
            kind: BtnKind.primary,
            expand: true,
            onPressed: onNew,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (sessionAlbum != null) ...[
                  SessionCard(
                    stacked: true,
                    albumName: sessionAlbum.album.name,
                    newCount: sessionAlbum.pendingCount,
                    status: capture.status,
                    copy: capture.copy,
                    folder: capture.watchedFolder,
                    canChooseFolder: capture.canChooseFolder,
                    customFolder: capture.customFolder,
                    onChooseFolder: capture.chooseFolder,
                    onUseDefaultFolder: capture.useDefaultFolder,
                    onReview: () => onReview(sessionAlbum.album.id),
                    onPause: capture.pause,
                    onResume: capture.resume,
                    onFixAccess: capture.fixAccess,
                  ),
                  const SizedBox(height: 16),
                ],
                Semantics(
                  header: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text('Albums', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
                  ),
                ),
                if (albums.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('No albums yet', style: fs(14, c: FluoColors.fgMuted)),
                  ),
                for (final a in albums)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _AlbumItem(
                      summary: a,
                      selected: a.album.id == selectedId,
                      meta: '${screensLabel(a.keptCount)} · ${relativeDay(a.album.updatedAt, now: now)}',
                      onTap: () => onSelect(a.album.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FluoButton(
            label: 'Settings',
            icon: LucideIcons.slidersHorizontal,
            expand: true,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _AlbumItem extends StatelessWidget {
  const _AlbumItem({
    required this.summary,
    required this.selected,
    required this.meta,
    required this.onTap,
  });
  final AlbumSummary summary;
  final bool selected;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = summary.album.name;
    return Pressable(
      onTap: onTap,
      selected: selected,
      label: '$name, $meta${summary.pendingCount > 0 ? ', ${summary.pendingCount} to review' : ''}',
      radius: 10,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.accent.soft : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? context.accent.color : const Color(0x00000000)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(15, w: FontWeight.w500, c: selected ? context.accent.text : FluoColors.fg)),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: fs(12, c: FluoColors.fgMuted)),
                ],
              ),
            ),
            if (summary.pendingCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.accent.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${summary.pendingCount}',
                    style: fs(12, w: FontWeight.w600, c: context.accent.onColor)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- centre

class _NoAlbum extends StatelessWidget {
  const _NoAlbum({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.images, size: 40, color: FluoColors.fgMuted),
            const SizedBox(height: 16),
            Text('No albums yet', style: fs(17, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Create an album to start a review session.',
                style: fs(14, c: FluoColors.fgMuted)),
            const SizedBox(height: 16),
            FluoButton(label: 'New album', icon: LucideIcons.plus, kind: BtnKind.primary, onPressed: onNew),
          ],
        ),
      );
}

class _AlbumPane extends StatelessWidget {
  const _AlbumPane({
    required this.album,
    required this.kept,
    required this.pending,
    required this.pins,
    required this.shown,
    required this.filter,
    required this.anyPins,
    required this.flow,
    required this.reorder,
    required this.selectMode,
    required this.selected,
    required this.focus,
    required this.onCols,
    required this.onFlow,
    required this.onFilter,
    required this.onReorder,
    required this.onSelectMode,
    required this.onSelectAll,
    required this.onClick,
    required this.onMove,
    required this.onReview,
    required this.onExport,
    required this.onOptions,
  });
  final Album? album;
  final List<Shot> kept;
  final int pending;
  final Map<String, List<Pin>> pins;
  final List<(int, Shot)> shown;
  final Severity? filter;
  final bool anyPins;
  final bool flow;
  final bool reorder;
  final bool selectMode;
  final Set<String> selected;
  final String? focus;
  final ValueChanged<int> onCols;
  final ValueChanged<bool> onFlow;
  final ValueChanged<Severity?> onFilter;
  final VoidCallback onReorder;
  final VoidCallback onSelectMode;
  final VoidCallback onSelectAll;
  final ValueChanged<Shot> onClick;
  final void Function(String id, int delta) onMove;
  final VoidCallback onReview;
  final VoidCallback onExport;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    int screensWith(Severity s) =>
        kept.where((k) => (pins[k.id] ?? const []).any((p) => p.severity == s)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: album?.name ?? 'Album',
            subtitle: kept.length == 1 ? '1 screen' : '${kept.length} screens',
            trailing: [
              if (kept.isNotEmpty)
                FluoButton(
                  label: selectMode ? 'Done selecting' : 'Select',
                  kind: selectMode ? BtnKind.primary : BtnKind.outline,
                  onPressed: onSelectMode,
                ),
              if (kept.length > 1) FluoButton(label: 'Select all', onPressed: onSelectAll),
              FluoIconButton(icon: LucideIcons.ellipsis, label: 'Album options', onPressed: onOptions),
              FluoButton(
                label: 'Export',
                icon: LucideIcons.upload,
                kind: BtnKind.primary,
                onPressed: kept.isEmpty ? null : onExport,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pending > 0) ...[
            PendingBanner(count: pending, onReview: onReview),
            const SizedBox(height: 14),
          ],
          if (kept.isNotEmpty) ...[
            Row(
              children: [
                SizedBox(width: 220, child: GridFlowSegmented(flow: flow, onChanged: onFlow)),
                const SizedBox(width: 16),
                if (anyPins)
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FluoChip(label: 'All ${kept.length}', selected: filter == null, onTap: () => onFilter(null)),
                        for (final s in Severity.values)
                          FluoChip(
                            label: '${s.label} ${screensWith(s)}',
                            leading: SeverityDot(s),
                            selected: filter == s,
                            onTap: () => onFilter(filter == s ? null : s),
                          ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (flow && filter == null && kept.length > 1)
                  FluoButton(
                    label: reorder ? 'Done reordering' : 'Reorder screens',
                    kind: reorder ? BtnKind.primary : BtnKind.outline,
                    onPressed: onReorder,
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: kept.isEmpty
                ? EmptyAlbum(hasPending: pending > 0)
                : shown.isEmpty
                    ? Center(
                        child: Text('No screens with ${filter?.label ?? ''} pins',
                            style: fs(14, c: FluoColors.fgMuted)),
                      )
                    : LayoutBuilder(builder: (context, box) {
                        onCols((box.maxWidth / (_tileExtent + _tileGap)).ceil());
                        final canMove = flow && filter == null && kept.length > 1;
                        return GridView.builder(
                          padding: const EdgeInsets.only(bottom: 80, top: 4),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: _tileExtent,
                            mainAxisSpacing: _tileGap,
                            crossAxisSpacing: _tileGap,
                            mainAxisExtent: 190 + 6 + 18,
                          ),
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final (n, shot) = shown[i];
                            final k = n - 1;
                            return ShotTile(
                              key: ValueKey('tile-${shot.id}'),
                              shot: shot,
                              number: flow ? n : null,
                              pins: pins[shot.id] ?? const [],
                              selected: selected.contains(shot.id),
                              reorder: reorder && canMove,
                              onEarlier: canMove && k > 0 ? () => onMove(shot.id, -1) : null,
                              onLater: canMove && k < kept.length - 1 ? () => onMove(shot.id, 1) : null,
                              onTap: () => onClick(shot),
                            );
                          },
                        );
                      }),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- inspector

class _Inspector extends StatelessWidget {
  const _Inspector({
    required this.album,
    required this.kept,
    required this.pending,
    required this.pins,
    required this.selected,
    required this.onEdit,
    required this.onDiscard,
    required this.onClear,
    required this.onChanged,
    required this.onExport,
    required this.onReview,
    required this.onExportSelection,
    required this.onMove,
  });
  final VoidCallback onExportSelection;

  /// Null when there is no other album to move to.
  final VoidCallback? onMove;
  final Album? album;
  final List<Shot> kept;
  final int pending;
  final Map<String, List<Pin>> pins;
  final List<Shot> selected;
  final ValueChanged<String> onEdit;
  final VoidCallback onDiscard;
  final VoidCallback onClear;
  final VoidCallback onChanged;
  final VoidCallback onExport;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Inspector',
      child: Container(
        color: FluoColors.surface.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(20),
        child: switch (selected.length) {
          0 => _summary(context),
          1 => _single(context, selected.first),
          _ => _multi(context),
        },
      ),
    );
  }

  Widget _title(String t) => Semantics(
        header: true,
        child: Text(t, style: fs(17, w: FontWeight.w600)),
      );

  Widget _summary(BuildContext context) {
    final total = pins.values.fold<int>(0, (n, l) => n + l.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(album?.name ?? 'No album'),
        const SizedBox(height: 12),
        Text(
          album == null
              ? 'Create or choose an album.'
              : '${screensLabel(kept.length)}, ${total == 1 ? '1 pin' : '$total pins'}'
                  '${pending > 0 ? ', $pending to review' : ''}',
          style: fs(14, c: FluoColors.fgMuted, h: 1.4),
        ),
        const SizedBox(height: 12),
        if (kept.isNotEmpty)
          Text('Click a screen to inspect it. Double-click, or press Enter, to edit it.',
              style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
        const Spacer(),
        if (pending > 0) ...[
          FluoButton(label: 'Review $pending new', expand: true, onPressed: onReview),
          const SizedBox(height: 8),
        ],
        FluoButton(
          label: 'Export album',
          icon: LucideIcons.upload,
          kind: BtnKind.primary,
          expand: true,
          onPressed: kept.isEmpty ? null : onExport,
        ),
      ],
    );
  }

  Widget _multi(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('${selected.length} screens selected'),
          const SizedBox(height: 12),
          Text('Discard removes them from this album. You can undo for a few seconds.',
              style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
          const Spacer(),
          FluoButton(
            label: 'Export ${selected.length} screens',
            icon: LucideIcons.upload,
            kind: BtnKind.primary,
            expand: true,
            onPressed: onExportSelection,
          ),
          const SizedBox(height: 8),
          FluoButton(label: 'Move to album…', icon: LucideIcons.folderInput, expand: true, onPressed: onMove),
          const SizedBox(height: 8),
          FluoButton(
            label: 'Discard ${selected.length} screens',
            icon: LucideIcons.trash2,
            kind: BtnKind.danger,
            expand: true,
            onPressed: onDiscard,
          ),
          const SizedBox(height: 8),
          FluoButton(label: 'Clear selection', expand: true, onPressed: onClear),
        ],
      );

  Widget _single(BuildContext context, Shot shot) {
    final repo = RepoScope.of(context);
    final shotPins = pins[shot.id] ?? const <Pin>[];
    final n = kept.indexWhere((k) => k.id == shot.id) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Screen $n of ${kept.length}'),
        const SizedBox(height: 12),
        Container(
          height: 200,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: FluoColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: FluoColors.border),
          ),
          child: ExcludeSemantics(child: ShotImage(path: shot.originalPath, cacheWidth: 600, fit: BoxFit.contain)),
        ),
        const SizedBox(height: 14),
        FluoField(
          key: ValueKey('name-${shot.id}'),
          label: 'Screen name',
          initial: shot.name,
          placeholder: 'For example, Cart',
          fill: FluoColors.surface,
          autocorrect: false,
          onChanged: (v) {
            repo.renameShot(shot.id, v);
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        FluoField(
          key: ValueKey('caption-${shot.id}'),
          label: 'Caption',
          initial: shot.caption,
          placeholder: 'What to notice',
          fill: FluoColors.surface,
          onChanged: (v) => repo.setCaption(shot.id, v),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text('Pins', style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: shotPins.isEmpty
              ? Text('No pins yet', style: fs(13, c: FluoColors.fgMuted))
              : ListView(
                  children: [
                    for (final p in shotPins)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PinBadge(p.severity.letter, p.severity.color, size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${p.severity.label} ${p.number}${p.note.isEmpty ? '' : ': ${p.note}'}',
                                style: fs(13, h: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        FluoButton(
          label: 'Edit marks',
          icon: LucideIcons.pencil,
          kind: BtnKind.primary,
          expand: true,
          onPressed: () => onEdit(shot.id),
        ),
        const SizedBox(height: 8),
        FluoButton(label: 'Move to album…', icon: LucideIcons.folderInput, expand: true, onPressed: onMove),
        const SizedBox(height: 8),
        FluoButton(
          label: 'Discard',
          icon: LucideIcons.trash2,
          kind: BtnKind.danger,
          expand: true,
          onPressed: onDiscard,
        ),
      ],
    );
  }
}
