import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes a stored screenshot for editing. Very large images are decoded at
/// [maxWidth] to keep memory sane; marks are stored normalised, so the
/// resolution only affects sharpness.
Future<ui.Image> loadShotImage(String path, {int maxWidth = 1600}) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final desc = await ui.ImageDescriptor.encoded(buffer);
    try {
      final codec = await desc.instantiateCodec(targetWidth: desc.width > maxWidth ? maxWidth : null);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      desc.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
