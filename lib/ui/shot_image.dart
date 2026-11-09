import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';

/// A stored screenshot. Decoded at display size so a grid of full-size
/// phone screenshots does not fill memory. A missing or unreadable file shows
/// a quiet placeholder instead of an error.
class ShotImage extends StatelessWidget {
  const ShotImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.cacheWidth = 400,
  });
  final String path;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => Container(
        color: const Color(0xFF202024),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.imageOff, size: 28, color: FluoColors.fgMuted),
      ),
    );
  }
}
