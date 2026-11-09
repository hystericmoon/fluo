import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repo_scope.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import '../ui/new_album_dialog.dart';
import 'album.dart';
import 'settings.dart';
import 'triage.dart';

/// Albums list, read from the local database. The session card shows when
/// some album has screenshots waiting for review.
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<AlbumSummary>? _albums;

  void _load() => setState(() => _albums = RepoScope.of(context).listAlbums());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _albums ??= RepoScope.of(context).listAlbums();
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(fluoRoute(page));
    if (mounted) _load(); // pick up changes made on the screens we visited
  }

  Future<void> _newAlbum() async {
    final name = await askAlbumName(context);
    if (name == null || !mounted) return;
    RepoScope.of(context).createAlbum(name);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums ?? const <AlbumSummary>[];
    final waiting = albums.where((a) => a.pendingCount > 0).firstOrNull;
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
                      if (waiting != null) ...[
                        _SessionCard(
                          albumName: waiting.album.name,
                          newCount: waiting.pendingCount,
                          onReview: () => _push(const TriageScreen()),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Semantics(
                        header: true,
                        child: Text('All albums',
                            style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
                      ),
                      const SizedBox(height: 10),
                      for (final a in albums) ...[
                        _AlbumRow(
                          name: a.album.name,
                          meta:
                              '${screensLabel(a.keptCount)} · ${relativeDay(a.album.updatedAt, now: now)}',
                          onTap: () => _push(AlbumScreen(title: a.album.name)),
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
  const _SessionCard({required this.albumName, required this.newCount, required this.onReview});
  final String albumName;
  final int newCount;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Active session',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluoColors.limeTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FluoColors.lime),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: FluoColors.lime, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('Session on', style: fs(13, w: FontWeight.w500, c: FluoColors.limeSoft)),
          ]),
          const SizedBox(height: 12),
          Text(albumName, style: fs(17, w: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('New screenshots land here automatically',
              style: fs(14, c: FluoColors.fgMuted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FluoButton(
                label: 'Review $newCount new',
                kind: BtnKind.primary,
                expand: true,
                onPressed: onReview,
              ),
            ),
            const SizedBox(width: 8),
            FluoButton(label: 'Pause', hPad: 18, onPressed: () {}),
          ]),
        ]),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.name, required this.meta, required this.onTap});
  final String name;
  final String meta;
  final VoidCallback onTap;

  Widget _thumb(bool lime) => Container(
        width: 34,
        height: 60,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFF202024),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: FluoColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 4, decoration: BoxDecoration(color: const Color(0xFF3F3F46), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 3),
          FractionallySizedBox(
            widthFactor: 0.6,
            child: Container(height: 4, decoration: BoxDecoration(color: const Color(0xFF3F3F46), borderRadius: BorderRadius.circular(2))),
          ),
          const Spacer(),
          Container(
              height: 8,
              decoration: BoxDecoration(
                  color: lime ? FluoColors.lime : const Color(0xFF3F3F46),
                  borderRadius: BorderRadius.circular(3))),
        ]),
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
        child: Row(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _thumb(true),
            const SizedBox(width: 4),
            _thumb(false),
            const SizedBox(width: 4),
            _thumb(false),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: fs(16, w: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(meta, style: fs(13, c: FluoColors.fgMuted)),
            ]),
          ),
          const Icon(LucideIcons.chevronRight, size: 20, color: FluoTints.chevron),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(LucideIcons.images, size: 40, color: FluoColors.fgMuted),
        const SizedBox(height: 16),
        Text('No albums yet', style: fs(17, w: FontWeight.w600)),
        const SizedBox(height: 4),
        SizedBox(
          width: 260,
          child: Text('Create an album, then take screenshots to start a review.',
              textAlign: TextAlign.center, style: fs(14, c: FluoColors.fgMuted, h: 1.4)),
        ),
      ]),
    );
  }
}
