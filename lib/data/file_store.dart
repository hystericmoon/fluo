import 'dart:io';

import 'package:path/path.dart' as p;

/// Keeps original screenshots on disk.
///
/// Originals are write-once: this class can import and delete a file but has
/// no way to modify one. Paths are stored relative to [root], so the app's
/// data folder can move (a new iOS container, a restored backup).
class FileStore {
  FileStore(this.root);
  final Directory root;

  /// Copies [source] in under a name built from [id]. Returns the relative
  /// path to store in the database.
  Future<String> importOriginal(File source, String id) async {
    final dir = Directory(p.join(root.path, 'originals'));
    await dir.create(recursive: true);
    final ext = p.extension(source.path).toLowerCase();
    final rel = p.join('originals', '$id${ext.isEmpty ? '.png' : ext}');
    final tmp = File(p.join(root.path, '$rel.part'));
    // Copy to a temp name first so a crash never leaves a half-written original.
    await source.copy(tmp.path);
    await tmp.rename(p.join(root.path, rel));
    return rel;
  }

  String resolve(String relative) => p.join(root.path, relative);

  /// For small batches where finishing before returning matters more than
  /// keeping the UI thread free (a handful of screenshots).
  void deleteSync(String relative) {
    final f = File(resolve(relative));
    if (f.existsSync()) f.deleteSync();
  }

  Future<void> delete(String relative) async {
    final f = File(resolve(relative));
    if (await f.exists()) await f.delete();
  }
}
