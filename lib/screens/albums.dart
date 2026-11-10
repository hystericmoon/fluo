import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_controller.dart';
import '../capture/capture_scope.dart';
import '../capture/capture_source.dart';
import '../data/format.dart';
import '../data/models.dart' show AlbumSummary;
import '../motion/fuse.dart';
import '../motion/star_border.dart';
import '../motion/swipe_row.dart';
import '../data/repo_scope.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/new_album_dialog.dart';
import '../ui/shot_image.dart';
import 'album.dart';
import 'settings.dart';
import 'triage.dart';
import '../theme/accent.dart';

/// Albums list, read from the local database, with the session card.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  /// Deleted from the list but not yet from the phone: waits out the undo fuse.
  /// If the app is closed meanwhile the album simply stays, which is the safe way to fail.
  AlbumSummary? _pendingDelete;

  Future<void> _push(Widget page) async {
    final result = await Navigator.of(context)
        .push<Object?>(fluoRoute<Object?>(page));
    if (!mounted) return;
    if (result is DeleteAlbumRequest) _scheduleDelete(result.albumId);
    setState(() {}); // pick up changes made on the screens we visited
  }

  void _scheduleDelete(String albumId) {
    _commitPendingDelete(); // one undo bar at a time: finish the earlier delete
    final a = RepoScope.of(context)
        .listAlbums()
        .where((x) => x.album.id == albumId)
        .firstOrNull;
    if (a != null) setState(() => _pendingDelete = a);
  }

  void _commitPendingDelete() {
    final p = _pendingDelete;
    if (p == null) return;
    _pendingDelete = null;
    final capture = CaptureScope.of(context);
    RepoScope.of(context)
        .deleteAlbum(p.album.id); // rows go now, files right after
    capture.sync(); // a session in that album ended with it
  }

  Future<void> _newAlbum() async {
    final name = await askAlbumName(context);
    if (name == null || !mounted) return;
    final album = RepoScope.of(context).createAlbum(name);
    // A new album starts a session: screenshots taken now land in it.
    await CaptureScope.of(context).begin(album.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context);
    final capture = CaptureScope.of(context); // rebuilds on status and imports
    final albums = [
      for (final a in repo.listAlbums())
        if (a.album.id != _pendingDelete?.album.id) a,
    ];
    final session = repo.activeSession();
    final sessionAlbum = session == null
        ? null
        : albums.where((a) => a.album.id == session.albumId).firstOrNull;
    final now = widget.now ?? DateTime.now();
    final pending = _pendingDelete;
    return ScreenFrame(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: _content(context, albums, sessionAlbum, capture, now),
          ),
          if (pending != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: UndoFuse(
                key: ValueKey('fuse-${pending.album.id}'),
                message: 'Deleted ${pending.album.name}',
                onUndo: () => setState(() => _pendingDelete = null),
                onBurnt: () {
                  _commitPendingDelete();
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<AlbumSummary> albums,
    AlbumSummary? sessionAlbum,
    CaptureController capture,
    DateTime now,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenHeader(
          title: 'Albums',
          big: true,
          trailing: [
            FluoIconButton(
              icon: LucideIcons.slidersHorizontal,
              label: 'Settings',
              onPressed: () => _push(const SettingsScreen()),
            ),
            FluoButton(
              label: 'New album',
              icon: LucideIcons.plus,
              kind: BtnKind.primary,
              onPressed: _newAlbum,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: albums.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (sessionAlbum != null) ...[
                      _SessionCard(
                        albumName: sessionAlbum.album.name,
                        newCount: sessionAlbum.pendingCount,
                        status: capture.status,
                        copy: capture.copy,
                        folder: capture.watchedFolder,
                        canChooseFolder: capture.canChooseFolder,
                        customFolder: capture.customFolder,
                        onChooseFolder: capture.chooseFolder,
                        onUseDefaultFolder: capture.useDefaultFolder,
                        onReview: () =>
                            _push(TriageScreen(albumId: sessionAlbum.album.id)),
                        onPause: capture.pause,
                        onResume: capture.resume,
                        onFixAccess: capture.fixAccess,
                      ),
                      const SizedBox(height: 20),
                    ],
                    Semantics(
                      header: true,
                      child: Text(
                        'All albums',
                        style: fs(
                          13,
                          w: FontWeight.w500,
                          c: FluoColors.fgMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final a in albums) ...[
                      SwipeRow(
                    key: ValueKey('row-${a.album.id}'), // state must follow the album, not the position
                    actionLabel: 'Delete album',
                        onDelete: () => _scheduleDelete(a.album.id),
                        child: _AlbumRow(
                          name: a.album.name,
                          meta:
                              '${screensLabel(a.keptCount)} · ${relativeDay(a.album.updatedAt, now: now)}',
                          thumbs: a.thumbnailPaths,
                          onTap: () => _push(AlbumScreen(albumId: a.album.id)),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.albumName,
    required this.newCount,
    required this.status,
    required this.copy,
    required this.folder,
    required this.canChooseFolder,
    required this.customFolder,
    required this.onChooseFolder,
    required this.onUseDefaultFolder,
    required this.onReview,
    required this.onPause,
    required this.onResume,
    required this.onFixAccess,
  });
  final String albumName;
  final int newCount;
  final CaptureStatus status;
  final CaptureCopy copy;
  final String? folder;
  final bool canChooseFolder;
  final bool customFolder;
  final VoidCallback onChooseFolder;
  final VoidCallback onUseDefaultFolder;
  final VoidCallback onReview;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFixAccess;

  bool get _problem =>
      status == CaptureStatus.needsPermission ||
      status == CaptureStatus.needsSettings ||
      status == CaptureStatus.limitedAccess ||
      status == CaptureStatus.failed;

  @override
  Widget build(BuildContext context) {
    final on = status == CaptureStatus.watching;
    final (dot, label) = switch (status) {
      CaptureStatus.watching => (context.accent.color, 'Session on'),
      CaptureStatus.paused => (FluoColors.fgMuted, 'Session paused'),
      CaptureStatus.unsupported => (FluoColors.fgMuted, 'Not available'),
      CaptureStatus.failed => (FluoColors.ux, 'Could not start'),
      // Before the first check has finished: neutral, not a false warning.
      CaptureStatus.off => (FluoColors.fgMuted, 'Session'),
      _ => (FluoColors.ux, copy.accessLabel),
    };
    final detail = switch (status) {
      CaptureStatus.watching => copy.watchingText(folder),
      CaptureStatus.off => copy.checking,
      CaptureStatus.paused => 'Screenshots are not being picked up',
      CaptureStatus.needsPermission => copy.needsPermission,
      CaptureStatus.needsSettings => copy.needsSettings,
      CaptureStatus.limitedAccess => copy.limited,
      CaptureStatus.failed => copy.failed,
      CaptureStatus.unsupported =>
        'Screenshot detection is not available on this device yet',
    };
    final fixLabel = switch (status) {
      CaptureStatus.needsPermission => copy.allowLabel,
      CaptureStatus.failed => 'Try again',
      _ => 'Open Settings',
    };

    return Semantics(
      container: true,
      explicitChildNodes: true, // controls inside stay separately focusable
      label: 'Active session',
      // While capturing, a bright spot circles the border. Still when it is
      // not live or when motion is reduced; the words say the same thing.
      child: FluoStarBorder(
        active: on,
        color: context.accent.color,
        radius: 16,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: on ? context.accent.soft : FluoColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: on ? null : Border.all(color: FluoColors.borderStrong),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: fs(
                      13,
                      w: FontWeight.w500,
                      c: on ? context.accent.text : FluoColors.fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(albumName, style: fs(17, w: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, style: fs(14, c: FluoColors.fgMuted, h: 1.4)),
              const SizedBox(height: 12),
              if (_problem)
                FluoButton(
                  label: fixLabel,
                  kind: BtnKind.primary,
                  expand: true,
                  onPressed: onFixAccess,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: FluoButton(
                        label: newCount > 0
                            ? 'Review $newCount new'
                            : 'Nothing new yet',
                        kind: newCount > 0 ? BtnKind.primary : BtnKind.outline,
                        expand: true,
                        onPressed: newCount > 0 ? onReview : null,
                      ),
                    ),
                    if (status != CaptureStatus.unsupported) ...[
                      const SizedBox(width: 8),
                      status == CaptureStatus.paused
                          ? FluoButton(
                              label: 'Resume',
                              hPad: 18,
                              onPressed: onResume,
                            )
                          : FluoButton(
                              label: 'Pause',
                              hPad: 18,
                              onPressed: onPause,
                            ),
                    ],
                  ],
                ),
              if (canChooseFolder && status != CaptureStatus.off) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FluoButton(
                        label: customFolder ? 'Change folder' : 'Choose folder',
                        expand: true,
                        onPressed: onChooseFolder,
                      ),
                    ),
                    if (customFolder) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FluoButton(
                          label: 'Use default',
                          expand: true,
                          onPressed: onUseDefaultFolder,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.name,
    required this.meta,
    required this.thumbs,
    required this.onTap,
  });
  final String name;
  final String meta;

  /// Up to three kept screens. Empty slots show a placeholder.
  final List<String> thumbs;
  final VoidCallback onTap;

  Widget _real(String path) => Container(
    width: 34,
    height: 60,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: FluoColors.border),
    ),
    child: ExcludeSemantics(child: ShotImage(path: path, cacheWidth: 80)),
  );

  Widget _thumb(bool lime, Color accent) => Container(
    width: 34,
    height: 60,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFF202024),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: FluoColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF3F3F46),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 3),
        FractionallySizedBox(
          widthFactor: 0.6,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: lime ? accent : const Color(0xFF3F3F46),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      label: '$name, $meta',
      radius: 14,
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FluoColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FluoColors.border),
        ),
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  i < thumbs.length
                      ? _real(thumbs[i])
                      : _thumb(i == 0 && thumbs.isEmpty, context.accent.color),
                ],
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fs(16, w: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(meta, style: fs(13, c: FluoColors.fgMuted)),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: FluoTints.chevron,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.images, size: 40, color: FluoColors.fgMuted),
          const SizedBox(height: 16),
          Text('No albums yet', style: fs(17, w: FontWeight.w600)),
          const SizedBox(height: 4),
          SizedBox(
            width: 260,
            child: Text(
              'Create an album, then take screenshots to start a review.',
              textAlign: TextAlign.center,
              style: fs(14, c: FluoColors.fgMuted, h: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
