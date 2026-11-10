import 'package:desktop_drop/desktop_drop.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../capture/capture_scope.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';

/// Lets images be dropped on the window (desktop). They wait for an album the
/// same way a screenshot shared on Android does. Does nothing where the
/// capture source cannot import files.
class FileDropZone extends StatefulWidget {
  const FileDropZone({super.key, required this.child});
  final Widget child;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final capture = CaptureScope.of(context);
    if (!capture.canImportFiles) return widget.child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        capture.importFiles([for (final f in d.files) f.path]);
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Semantics(
                  liveRegion: true,
                  label: 'Drop screenshots to add them to an album',
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FluoColors.bg.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.accent.color, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Drop screenshots to add them to an album',
                      style: TextStyle(
                        color: context.accent.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
