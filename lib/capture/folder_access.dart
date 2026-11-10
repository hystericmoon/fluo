import 'package:flutter/services.dart';

/// A folder the user chose, with the bookmark that keeps access to it.
class PickedFolder {
  const PickedFolder({required this.path, required this.bookmark});
  final String path;

  /// Base64 security-scoped bookmark.
  final String bookmark;
}

/// A stored bookmark that was resolved again. [bookmark] is set when the old
/// one was stale and macOS made a fresh one to keep.
class OpenedFolder {
  const OpenedFolder({required this.path, this.bookmark});
  final String path;
  final String? bookmark;
}

/// Folder choice under the macOS app sandbox: an open panel plus
/// security-scoped bookmarks (`FolderChannel.swift`).
abstract class FolderAccess {
  /// Shows the system folder picker. Null when cancelled or refused.
  Future<PickedFolder?> pick();

  /// Resolves a stored bookmark and starts access to it. Null when the folder
  /// is gone or access is refused.
  Future<OpenedFolder?> open(String bookmark);

  /// Ends access to the current folder.
  Future<void> close();
}

class MacFolderAccess implements FolderAccess {
  MacFolderAccess({MethodChannel? channel})
    : _c = channel ?? const MethodChannel('app.fluo/folder');
  final MethodChannel _c;

  @override
  Future<PickedFolder?> pick() async {
    try {
      final m = await _c.invokeMapMethod<String, Object?>('pick');
      if (m == null) return null;
      return PickedFolder(
        path: m['path']! as String,
        bookmark: m['bookmark']! as String,
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<OpenedFolder?> open(String bookmark) async {
    try {
      final m = await _c.invokeMapMethod<String, Object?>('open', bookmark);
      if (m == null) return null;
      return OpenedFolder(
        path: m['path']! as String,
        bookmark: m['bookmark'] as String?,
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _c.invokeMethod<void>('close');
    } on PlatformException {
      // Nothing to release.
    }
  }
}
