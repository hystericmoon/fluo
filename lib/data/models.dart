import 'dart:convert';
import 'dart:ui' show Color;

import '../theme/tokens.dart';

enum Severity { bug, ux, a11y }

extension SeverityX on Severity {
  String get letter => switch (this) { Severity.bug => 'B', Severity.ux => 'U', Severity.a11y => 'A' };
  String get label => switch (this) { Severity.bug => 'Bug', Severity.ux => 'UX', Severity.a11y => 'A11y' };
  Color get color => switch (this) {
        Severity.bug => FluoColors.bug,
        Severity.ux => FluoColors.ux,
        Severity.a11y => FluoColors.a11y,
      };
}

/// Where a screenshot sits in the review flow.
enum ShotStatus { pending, kept, discarded }

enum AnnotationKind { pen, arrow, box, redact }

/// Crop rectangle in normalised image coordinates (0..1). Vector data: the
/// original file is never cropped on disk.
class CropRect {
  const CropRect(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;

  String toJson() => jsonEncode([left, top, right, bottom]);

  static CropRect fromJson(String s) {
    final l = (jsonDecode(s) as List).cast<num>();
    return CropRect(l[0].toDouble(), l[1].toDouble(), l[2].toDouble(), l[3].toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is CropRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
  @override
  String toString() => 'CropRect($left, $top, $right, $bottom)';
}

class Album {
  const Album({required this.id, required this.name, required this.createdAt, required this.updatedAt});
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Album plus the numbers the Albums list needs.
class AlbumSummary {
  const AlbumSummary({
    required this.album,
    required this.keptCount,
    required this.pendingCount,
    required this.thumbnailPaths,
  });
  final Album album;
  final int keptCount;
  final int pendingCount;

  /// Absolute paths of up to three kept shots, in album order.
  final List<String> thumbnailPaths;
}

class Shot {
  const Shot({
    required this.id,
    required this.albumId,
    required this.name,
    required this.caption,
    required this.position,
    required this.status,
    required this.originalPath,
    required this.width,
    required this.height,
    required this.crop,
    required this.capturedAt,
    required this.createdAt,
  });
  final String id;
  final String albumId;
  final String name;
  final String caption;

  /// Flow order within the album, 0-based.
  final int position;
  final ShotStatus status;

  /// Absolute path of the untouched original.
  final String originalPath;
  final int? width;
  final int? height;
  final CropRect? crop;
  final DateTime capturedAt;
  final DateTime createdAt;
}

class Pin {
  const Pin({
    required this.id,
    required this.shotId,
    required this.number,
    required this.severity,
    required this.x,
    required this.y,
    required this.note,
  });
  final String id;
  final String shotId;

  /// 1-based, contiguous within a shot.
  final int number;
  final Severity severity;

  /// Position in normalised image coordinates (0..1).
  final double x, y;
  final String note;
}

/// A pen stroke, arrow, box or redaction. [data] is kind-specific vector data
/// in normalised coordinates, for example `{"points": [[x, y], ...]}`.
class Annotation {
  const Annotation({
    required this.id,
    required this.shotId,
    required this.kind,
    required this.data,
    required this.z,
  });
  final String id;
  final String shotId;
  final AnnotationKind kind;
  final Map<String, Object?> data;
  final int z;
}

/// Everything the Editor reads for one screenshot.
class ShotEdit {
  const ShotEdit({required this.shot, required this.pins, required this.annotations});
  final Shot shot;
  final List<Pin> pins;
  final List<Annotation> annotations;
}
