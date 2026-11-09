import 'package:flutter/services.dart' show TextInputAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import 'kit.dart';

/// Asks for an album name. Returns the trimmed name, or null if cancelled.
Future<String?> askAlbumName(BuildContext context) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: const Color(0xB3000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, _) => const _NewAlbumDialog(),
    transitionBuilder: (ctx, anim, _, child) =>
        (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false)
            ? child
            : FadeTransition(opacity: anim, child: child),
  );
}

class _NewAlbumDialog extends StatefulWidget {
  const _NewAlbumDialog();

  @override
  State<_NewAlbumDialog> createState() => _NewAlbumDialogState();
}

class _NewAlbumDialogState extends State<_NewAlbumDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _c.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                label: 'New album',
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
                        child: Text('New album', style: fs(17, w: FontWeight.w600)),
                      ),
                      const SizedBox(height: 16),
                      Text('Album name',
                          style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 44,
                        child: Semantics(
                          label: 'Album name',
                          textField: true,
                          child: TextField(
                            controller: _c,
                            autofocus: true,
                            placeholder: const Text('For example, Checkout flow'),
                            style: fs(15),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textAlignVertical: TextAlignVertical.center,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: FluoColors.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: FluoColors.borderStrong),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        FluoButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                        const SizedBox(width: 8),
                        FluoButton(label: 'Create', kind: BtnKind.primary, onPressed: _submit),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
