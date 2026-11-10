import '../data/models.dart';

enum ExportFormat { claude, pdf, long, share }

extension ExportFormatX on ExportFormat {
  String get title => switch (this) {
        ExportFormat.claude => 'Claude pack',
        ExportFormat.pdf => 'PDF',
        ExportFormat.long => 'Long image',
        ExportFormat.share => 'Share images',
      };

  /// Which formats can carry the untouched originals, and which can use a brief.
  bool get canIncludeOriginals => this == ExportFormat.claude || this == ExportFormat.share;
  bool get canIncludeBrief => this == ExportFormat.claude || this == ExportFormat.pdf;
}

class ExportOptions {
  const ExportOptions({
    required this.format,
    this.includeOriginals = false,
    this.includeBrief = true,
  });
  final ExportFormat format;

  /// Off by default: originals still show whatever was redacted.
  final bool includeOriginals;
  final bool includeBrief;

  bool get originalsActuallyIncluded => includeOriginals && format.canIncludeOriginals;
  bool get briefActuallyIncluded => includeBrief && format.canIncludeBrief;
}

/// One screen of the album, as exported: its place in the flow, its marks.
class ExportEntry {
  const ExportEntry({
    required this.number,
    required this.shot,
    required this.pins,
    required this.annotations,
  });

  /// 1-based place in the flow.
  final int number;
  final Shot shot;
  final List<Pin> pins;
  final List<Annotation> annotations;

  String get title => shot.name.trim().isEmpty ? 'Screen $number' : shot.name.trim();
  String get caption => shot.caption.trim();
  int get redactionCount => annotations.where((a) => a.kind == AnnotationKind.redact).length;

  /// `01-cart`: sorts in flow order and is safe in a file name.
  String get fileStem => '${number.toString().padLeft(2, '0')}-${slugify(shot.name, fallback: 'screen')}';
}

String slugify(String s, {String fallback = 'item'}) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : (slug.length > 40 ? slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '') : slug);
}

class ExportFile {
  const ExportFile({required this.path, required this.name, required this.mime});
  final String path;
  final String name;
  final String mime;
}

class ExportResult {
  const ExportResult({required this.files, required this.screens, this.text, this.subject});
  final List<ExportFile> files;
  final int screens;

  /// Optional text to send along (the share sheet's message).
  final String? text;
  final String? subject;
}

/// What the Export screen shows about the album.
class ExportSummary {
  const ExportSummary({required this.screens, required this.pins, required this.redactions});
  final int screens;
  final int pins;
  final int redactions;
}
