import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_controller.dart';
import '../capture/capture_scope.dart';
import '../data/format.dart';
import '../data/repo_scope.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/new_album_dialog.dart';
import '../ui/shot_image.dart';
import 'album.dart';
import 'settings.dart';
import 'triage.dart';

/// Albums list, read from the local database, with the session card.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(fluoRoute(page));
    if (mounted) {
      setState(() {}); // pick up changes made on the screens we visited
    }
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
    final albums = repo.listAlbums();
    final session = repo.activeSession();
    final sessionAlbum = session == null
        ? null
        : albums.where((a) => a.album.id == session.albumId).firstOrNull;
    final now = widget.now ?? DateTime.now();
    return ScreenFrame(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
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
                          onReview: () => _push(TriageScreen(albumId: sessionAlbum.album.id)),
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
                        _AlbumRow(
                          name: a.album.name,
                          meta:
                              '${screensLabel(a.keptCount)} · ${relativeDay(a.album.updatedAt, now: now)}',
                          thumbs: a.thumbnailPaths,
                          onTap: () => _push(AlbumScreen(albumId: a.album.id)),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.albumName,
    required this.newCount,
    required this.status,
    required this.onReview,
    required this.onPause,
    required this.onResume,
    required this.onFixAccess,
  });
  final String albumName;
  final int newCount;
  final CaptureStatus status;
  final VoidCallback onReview;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFixAccess;

  bool get _problem =>
      status == CaptureStatus.needsPermission ||
      status == CaptureStatus.needsSettings ||
      status == CaptureStatus.limitedAccess;

  @override
  Widget build(BuildContext context) {
    final on = status == CaptureStatus.watching;
    final (dot, label) = switch (status) {
      CaptureStatus.watching => (FluoColors.lime, 'Session on'),
      CaptureStatus.paused => (FluoColors.fgMuted, 'Session paused'),
      CaptureStatus.unsupported => (FluoColors.fgMuted, 'Not available'),
      // Before the first check has finished: neutral, not a false warning.
      CaptureStatus.off => (FluoColors.fgMuted, 'Session'),
      _ => (FluoColors.ux, 'Needs photo access'),
    };
    final detail = switch (status) {
      CaptureStatus.watching => 'New screenshots land here automatically',
      CaptureStatus.off => 'Checking photo access…',
      CaptureStatus.paused => 'Screenshots are not being picked up',
      CaptureStatus.needsPermission => 'Allow photo access so Fluo can see new screenshots. Your photos stay on this phone.',
      CaptureStatus.needsSettings => 'Photo access is off. Turn it on in Settings so Fluo can see new screenshots.',
      CaptureStatus.limitedAccess => 'Fluo can only see the photos you picked, so it would miss new screenshots. Allow all photos in Settings.',
      CaptureStatus.unsupported =>
        'Screenshot detection is not available on this device yet',
    };
    final fixLabel = status == CaptureStatus.needsPermission
        ? 'Allow photo access'
        : 'Open Settings';

    return Semantics(
      container: true,
      label: 'Active session',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: on ? FluoColors.limeTint : FluoColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: on ? FluoColors.lime : FluoColors.borderStrong,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: fs(
                    13,
                    w: FontWeight.w500,
                    c: on ? FluoColors.limeSoft : FluoColors.fg,
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
          ],
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

  Widget _thumb(bool lime) => Container(
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
            color: lime ? FluoColors.lime : const Color(0xFF3F3F46),
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
                  i < thumbs.length ? _real(thumbs[i]) : _thumb(i == 0 && thumbs.isEmpty),
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
