import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/models.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Asks which album to move screens to. Returns its id, or null if cancelled.
Future<String?> pickAlbum(BuildContext context, List<AlbumSummary> albums, {required int count}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0xB3000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: 'Move to album',
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
                    Semantics(
                      header: true,
                      child: Text(count == 1 ? 'Move 1 screen to…' : 'Move $count screens to…',
                          style: fs(17, w: FontWeight.w600)),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final a in albums) ...[
                            FluoButton(
                              label: a.album.name,
                              expand: true,
                              onPressed: () => Navigator.of(ctx).pop(a.album.id),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    FluoButton(label: 'Cancel', expand: true, onPressed: () => Navigator.of(ctx).pop()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) =>
        (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false) ? child : FadeTransition(opacity: anim, child: child),
  );
}
