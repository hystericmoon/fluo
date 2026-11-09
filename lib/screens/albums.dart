import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/fake_data.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';
import 'album.dart';
import 'settings.dart';
import 'triage.dart';

/// Albums list with the active session card.
class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key, this.albums = fakeAlbums, this.sessionNew = 7});

  final List<AlbumInfo> albums;
  final int sessionNew;

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => Navigator.of(context).push(fluoRoute(const SettingsScreen())),
              ),
              FluoButton(
                label: 'New album',
                icon: LucideIcons.plus,
                kind: BtnKind.primary,
                onPressed: () {},
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
                      _SessionCard(newCount: sessionNew),
                      const SizedBox(height: 20),
                      Semantics(
                        header: true,
                        child: Text('All albums',
                            style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
                      ),
                      const SizedBox(height: 10),
                      for (final a in albums) ...[
                        _AlbumRow(a),
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
  const _SessionCard({required this.newCount});
  final int newCount;

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
          Text('Checkout flow review', style: fs(17, w: FontWeight.w600)),
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
                onPressed: () => Navigator.of(context).push(fluoRoute(const TriageScreen())),
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
  const _AlbumRow(this.album);
  final AlbumInfo album;

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
      onTap: () => Navigator.of(context).push(fluoRoute(AlbumScreen(title: album.name))),
      label: '${album.name}, ${album.meta}',
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
              Text(album.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: fs(16, w: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(album.meta, style: fs(13, c: FluoColors.fgMuted)),
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
