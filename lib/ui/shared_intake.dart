import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_controller.dart';
import '../capture/capture_scope.dart';
import '../capture/capture_source.dart';
import '../data/models.dart';
import '../data/repo_scope.dart';
import '../theme/tokens.dart';
import 'kit.dart';
import 'new_album_dialog.dart';

/// Watches for screenshots sent to Fluo from the share sheet (the fallback when
/// automatic detection misses one) and asks which album they belong in.
class SharedIntake extends StatefulWidget {
  const SharedIntake({super.key, required this.child});
  final Widget child;

  @override
  State<SharedIntake> createState() => _SharedIntakeState();
}

class _SharedIntakeState extends State<SharedIntake> with WidgetsBindingObserver {
  CaptureController? _capture;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = CaptureScope.of(context);
    if (!identical(c, _capture)) {
      _capture?.sharedArrived.removeListener(_check);
      _capture = c..sharedArrived.addListener(_check);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capture?.sharedArrived.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final capture = _capture;
    if (_asking || !mounted || capture == null) return;
    _asking = true;
    try {
      final shots = await capture.sharedWaiting();
      if (shots.isEmpty || !mounted) return;
      final repo = RepoScope.of(context);
      final choice = await showGeneralDialog<_Choice>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: const Color(0xB3000000),
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (ctx, _, _) => _AlbumPicker(
          shots: shots,
          albums: [for (final a in repo.listAlbums()) a.album],
        ),
        transitionBuilder: (ctx, anim, _, child) =>
            (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false)
                ? child
                : FadeTransition(opacity: anim, child: child),
      );
      if (!mounted) return;
      var albumId = choice?.albumId;
      if (choice != null && choice.newAlbum) {
        final name = await askAlbumName(context);
        if (!mounted) return;
        if (name != null) albumId = repo.createAlbum(name).id;
      }
      if (albumId == null) {
        // Dismissed: do not ask again on every return to the app. The
        // original is still in the app it was shared from.
        await capture.discardShared(shots);
        return;
      }
      await capture.addShared(albumId, shots);
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Choice {
  const _Choice.album(this.albumId) : newAlbum = false;
  const _Choice.create()
      : albumId = null,
        newAlbum = true;
  final String? albumId;
  final bool newAlbum;
}

class _AlbumPicker extends StatelessWidget {
  const _AlbumPicker({required this.shots, required this.albums});
  final List<IncomingShot> shots;
  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    final n = shots.length;
    final title = n == 1 ? 'Add this screenshot to…' : 'Add $n screenshots to…';
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: title,
              explicitChildNodes: true,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FluoColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: FluoColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 78,
                          child: ExcludeSemantics(
                            child: Image.file(
                              File(shots.first.path),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: FluoColors.bg),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(title, style: fs(17, w: FontWeight.w600)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('They arrive as new screens to review.',
                        style: fs(13, c: FluoColors.fgMuted)),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.35),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final a in albums) ...[
                              FluoButton(
                                label: a.name,
                                expand: true,
                                onPressed: () =>
                                    Navigator.of(context).pop(_Choice.album(a.id)),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                    FluoButton(
                      label: 'New album',
                      kind: BtnKind.primary,
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(const _Choice.create()),
                    ),
                    const SizedBox(height: 8),
                    FluoButton(
                      label: 'Cancel',
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
