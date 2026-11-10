import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'capture_source.dart';
import 'folder_access.dart';

/// Screenshot capture for macOS, in plain Dart.
///
/// macOS saves a screenshot as a file in one folder (the Desktop unless the
/// user changed it), so there is no gallery to query. While a watch is on we
/// watch that folder, and copy each new screenshot into a private inbox. The
/// inbox contract is the same as Android's: [drain] lists it, [ack] deletes.
///
/// Unlike Android there is no background service: screenshots taken while
/// Fluo is closed are picked up at the next launch, as long as the session
/// stayed on (the cursor file below survives a restart).
class MacCaptureSource implements CaptureSource {
  MacCaptureSource({
    Future<Directory> Function()? screenshotDir,
    Future<Directory> Function()? inboxDir,
    Future<Directory> Function()? sharedDir,
    Future<void> Function()? openSystemSettings,
    FolderAccess? folderAccess,
    this.pollInterval = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _screenshotDir = screenshotDir ?? _systemScreenshotDir,
       _inboxDir = inboxDir ?? _defaultInboxDir,
       _sharedDir = sharedDir ?? _defaultSharedDir,
       _openSystemSettings = openSystemSettings ?? _openPrivacySettings,
       _access = folderAccess ?? MacFolderAccess(),
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _screenshotDir;
  final Future<Directory> Function() _inboxDir;
  final Future<Directory> Function() _sharedDir;
  final Future<void> Function() _openSystemSettings;
  final FolderAccess _access;
  final Duration pollInterval;
  final DateTime Function() _now;

  final _captured = StreamController<void>.broadcast();
  final _shared = StreamController<void>.broadcast();
  StreamSubscription<FileSystemEvent>? _fsSub;
  Timer? _poll;
  bool _scanning = false;
  bool _rescan = false;

  /// Files already copied, by `path|modifiedMs`, so a poll never copies twice.
  final _seen = <String>{};

  @override
  bool get supported => true;
  @override
  CaptureCopy get copy => CaptureCopy.mac;

  String? _folderName;
  @override
  String? get watchedFolder => _folderName;

  // ---- folder choice ----------------------------------------------------
  //
  // Under the sandbox only ~/Desktop is readable. A folder the user picks in
  // the open panel is readable too, and a security-scoped bookmark, saved in
  // `capture_folder.json` beside the inbox, brings that access back after a
  // restart.

  @override
  bool get canChooseFolder => true;
  @override
  bool get customFolder => _custom != null;

  /// The folder the user picked, once its access is open this run.
  Directory? _custom;
  bool _customLoaded = false;

  Future<File> _choiceFile() async =>
      File(p.join((await _inboxDir()).parent.path, 'capture_folder.json'));

  Future<void> _saveChoice(String path, String bookmark) async {
    final f = await _choiceFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({'path': path, 'bookmark': bookmark}));
  }

  /// Opens the stored choice, if any. Null means no choice or it cannot be
  /// opened; [_choiceBroken] tells the two apart.
  bool _choiceBroken = false;
  Future<void> _loadChoice() async {
    if (_customLoaded) return;
    final f = await _choiceFile();
    if (!await f.exists()) {
      _customLoaded = true;
      return;
    }
    try {
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final opened = await _access.open(m['bookmark'] as String);
      if (opened == null) {
        _choiceBroken = true;
      } else {
        if (opened.bookmark != null) await _saveChoice(opened.path, opened.bookmark!);
        _custom = Directory(opened.path);
        _folderName = p.basename(opened.path);
      }
    } on FormatException {
      _choiceBroken = true;
    } on TypeError {
      _choiceBroken = true;
    }
    _customLoaded = true;
  }

  @override
  Future<bool> chooseFolder() async {
    final picked = await _access.pick();
    if (picked == null) return false;
    await _saveChoice(picked.path, picked.bookmark);
    _custom = Directory(picked.path);
    _customLoaded = true;
    _choiceBroken = false;
    _folderName = p.basename(picked.path);
    _seen.clear();
    return true;
  }

  @override
  Future<void> useDefaultFolder() async {
    final f = await _choiceFile();
    if (await f.exists()) await f.delete();
    await _access.close();
    _custom = null;
    _customLoaded = true;
    _choiceBroken = false;
    _folderName = null;
    _seen.clear();
  }

  /// The folder to watch, or null when a chosen folder cannot be opened any
  /// more (moved, deleted, or the bookmark was revoked).
  Future<Directory?> _resolveDir() async {
    await _loadChoice();
    if (_choiceBroken) return null;
    if (_custom != null) return _custom;
    final dir = await _screenshotDir();
    _folderName = p.basename(dir.path);
    return dir;
  }

  // ---- permission -------------------------------------------------------

  /// Reading the Desktop, Documents or Downloads folder needs the user's
  /// consent (a one-time system prompt). The only way to find out is to try,
  /// so this lists the folder; that is also what raises the prompt.
  @override
  Future<CapturePermission> permission() async {
    try {
      final dir = await _resolveDir();
      if (dir == null) return CapturePermission.denied; // chosen folder lost
      if (!await dir.exists()) return CapturePermission.granted;
      await dir.list().isEmpty;
      return CapturePermission.granted;
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      // 1 = EPERM, 13 = EACCES: macOS refused. Only the user's own pick can
      // fix a default folder outside ~/Desktop, so that case asks for a pick
      // (denied); a picked folder that is refused needs System Settings.
      if (code == 1 || code == 13) {
        return customFolder
            ? CapturePermission.permanentlyDenied
            : CapturePermission.denied;
      }
      return CapturePermission.denied;
    }
  }

  /// "Allow folder access": when the folder cannot be read, ask the user to
  /// pick it (the sandbox then grants it).
  @override
  Future<CapturePermission> requestPermission() async {
    final p0 = await permission();
    if (p0 != CapturePermission.denied) return p0;
    if (!await chooseFolder()) return p0;
    return permission();
  }

  @override
  Future<void> openSettings() => _openSystemSettings();

  // ---- watching ---------------------------------------------------------

  @override
  Future<void> start() async {
    if (_poll != null) return;
    final inbox = await _inboxDir();
    await inbox.create(recursive: true);
    final cursor = File(p.join(inbox.parent.path, 'capture_cursor'));
    if (!await cursor.exists()) {
      await cursor.writeAsString('${_now().millisecondsSinceEpoch}');
    }
    final dir = await _resolveDir();
    if (dir == null) {
      throw const FileSystemException('The chosen screenshot folder is gone');
    }
    try {
      _fsSub = dir.watch().listen((_) => _scan(), onError: (_) {});
    } on FileSystemException {
      // Polling below still covers it.
    }
    _poll = Timer.periodic(pollInterval, (_) => _scan());
    unawaited(_scan());
  }

  @override
  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    await _fsSub?.cancel();
    _fsSub = null;
    _seen.clear();
    // A paused or ended session must not import what happens meanwhile.
    final inbox = await _inboxDir();
    final cursor = File(p.join(inbox.parent.path, 'capture_cursor'));
    if (await cursor.exists()) await cursor.delete();
  }

  Future<void> _scan() async {
    if (_scanning) {
      _rescan = true;
      return;
    }
    _scanning = true;
    try {
      do {
        _rescan = false;
        if (await _scanOnce()) _captured.add(null);
      } while (_rescan && _poll != null);
    } catch (_) {
      // A folder that vanished or lost access is reported by [permission].
    } finally {
      _scanning = false;
    }
  }

  Future<bool> _scanOnce() async {
    final dir = await _resolveDir();
    if (dir == null || !await dir.exists()) return false;
    final inbox = await _inboxDir();
    final cursorFile = File(p.join(inbox.parent.path, 'capture_cursor'));
    if (!await cursorFile.exists()) return false;
    var cursor =
        int.tryParse(await cursorFile.readAsString()) ??
        _now().millisecondsSinceEpoch;

    final found = <({File file, int modifiedMs})>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!MacScreenshotFilter.isScreenshot(name)) continue;
      final ms = (await e.stat()).modified.millisecondsSinceEpoch;
      if (ms < cursor) continue;
      found.add((file: e, modifiedMs: ms));
    }
    found.sort((a, b) => a.modifiedMs.compareTo(b.modifiedMs));

    var any = false;
    for (final f in found) {
      final key = '${f.file.path}|${f.modifiedMs}';
      if (_seen.contains(key)) continue;
      if (await _copyToInbox(f.file, inbox, f.modifiedMs)) {
        _seen.add(key);
        any = true;
        if (f.modifiedMs >= cursor) cursor = f.modifiedMs;
      }
    }
    if (any) await cursorFile.writeAsString('$cursor');
    return any;
  }

  /// Copies via a `.part` file so [drain] never sees a half-written image.
  /// A screenshot still being written is retried on the next scan.
  Future<bool> _copyToInbox(
    File src,
    Directory inbox,
    int modifiedMs, {
    String? idSeed,
  }) async {
    final ext = p.extension(src.path).replaceFirst('.', '').toLowerCase();
    final base = '${modifiedMs}_${_stableId(idSeed ?? p.basename(src.path))}';
    final target = File(
      p.join(inbox.path, '$base.${ext.isEmpty ? 'png' : ext}'),
    );
    if (await target.exists()) return true;
    final tmp = File('${target.path}.part');
    try {
      final before = await src.length();
      if (before == 0) return false;
      await src.copy(tmp.path);
      // Size changed under us: macOS was still writing. Try again later.
      if (await tmp.length() != await src.length()) {
        await tmp.delete();
        return false;
      }
      await tmp.rename(target.path);
      return true;
    } on FileSystemException {
      if (await tmp.exists()) await tmp.delete();
      return false;
    }
  }

  // ---- inbox ------------------------------------------------------------

  @override
  Future<List<IncomingShot>> drain() async {
    final inbox = await _inboxDir();
    if (!await inbox.exists()) return const [];
    return _listShots(inbox);
  }

  Future<List<IncomingShot>> _listShots(Directory inbox) async {
    final out = <IncomingShot>[];
    await for (final e in inbox.list()) {
      if (e is! File) continue;
      final parsed = parseInboxName(p.basename(e.path));
      if (parsed == null) continue;
      final size = await _pngSize(e);
      out.add(
        IncomingShot(
          path: e.path,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(parsed),
          width: size?.$1,
          height: size?.$2,
        ),
      );
    }
    out.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return out;
  }

  @override
  Future<void> ack(List<String> paths) async {
    for (final path in paths) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Stream<void> get captured => _captured.stream;

  // ---- dropped files ----------------------------------------------------
  //
  // Images dropped on the window are copied to a separate folder and handled
  // like shares on Android: the user picks an album for them.

  static const importExts = {'.png', '.jpg', '.jpeg', '.webp'};

  @override
  bool get canImportFiles => true;

  @override
  Future<int> importFiles(List<String> paths) async {
    final dir = await _sharedDir();
    await dir.create(recursive: true);
    var n = 0;
    for (final path in paths) {
      if (!importExts.contains(p.extension(path).toLowerCase())) continue;
      final f = File(path);
      try {
        if (!await f.exists()) continue;
        final ms = (await f.stat()).modified.millisecondsSinceEpoch;
        if (await _copyToInbox(f, dir, ms, idSeed: path)) n++;
      } on FileSystemException {
        // Unreadable (access refused or vanished): skip it.
      }
    }
    if (n > 0) _shared.add(null);
    return n;
  }

  @override
  Future<List<IncomingShot>> drainShared() async {
    final dir = await _sharedDir();
    if (!await dir.exists()) return const [];
    return _listShots(dir);
  }

  @override
  Future<void> ackShared(List<String> paths) => ack(paths);
  @override
  Stream<void> get sharedIn => _shared.stream;

  Future<void> dispose() async {
    await stop();
    await _captured.close();
    await _shared.close();
  }

  // ---- helpers ----------------------------------------------------------

  /// Parses `modifiedMs_id.ext` to modifiedMs. Null for anything else (`.part`).
  static int? parseInboxName(String name) {
    final m = RegExp(r'^(\d+)_([0-9a-f]+)\.([a-z0-9]{1,5})$').firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static String _stableId(String s) {
    // FNV-1a: only needs to tell two shots in the same millisecond apart.
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  static Future<(int, int)?> _pngSize(File f) async {
    try {
      final raf = await f.open();
      try {
        final head = await raf.read(24);
        if (head.length < 24) return null;
        const sig = [0x89, 0x50, 0x4e, 0x47];
        for (var i = 0; i < 4; i++) {
          if (head[i] != sig[i]) return null;
        }
        final b = ByteData.sublistView(Uint8List.fromList(head));
        return (b.getUint32(16), b.getUint32(20));
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return null;
    }
  }
}

/// Which files in the screenshot folder count as screenshots.
///
/// macOS names them `Screenshot DATE at TIME.png` ("Screen Shot ..." before
/// Big Sur, and localised on non-English systems). Hidden `.` files are the
/// temporary file macOS uses while it is still writing.
class MacScreenshotFilter {
  static const _tokens = [
    'screenshot',
    'screen shot',
    'screen_shot',
    'screen-shot',
    'captura de pantalla',
    'bildschirmfoto',
    'capture d’écran',
    "capture d'écran",
    'schermafbeelding',
    'skärmbild',
    'schermata',
    'tangkapan layar',
    '截屏',
    '截图',
    'スクリーンショット',
    '스크린샷',
  ];
  static const _exts = {'.png', '.jpg', '.jpeg', '.heic', '.webp', '.tiff'};

  static bool isScreenshot(String fileName) {
    if (fileName.startsWith('.')) return false;
    final lower = fileName.toLowerCase();
    if (!_exts.contains(p.extension(lower))) return false;
    return _tokens.any(lower.contains);
  }
}

/// `defaults read com.apple.screencapture location`, else the Desktop.
Future<Directory> _systemScreenshotDir() async {
  final home = _realHome();
  try {
    final r = await Process.run('defaults', [
      'read',
      'com.apple.screencapture',
      'location',
    ]);
    if (r.exitCode == 0) {
      var path = (r.stdout as String).trim();
      if (path.startsWith('~')) path = home + path.substring(1);
      if (path.isNotEmpty) return Directory(path);
    }
  } on ProcessException {
    // Fall through to the default.
  }
  return Directory(p.join(home, 'Desktop'));
}

Future<Directory> _defaultSharedDir() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'fluo', 'shared'),
);

Future<Directory> _defaultInboxDir() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'fluo', 'inbox'),
);

Future<void> _openPrivacySettings() async {
  await Process.run('open', [
    'x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders',
  ]);
}

/// Inside the app sandbox `HOME` is the app's container, not the user's home.
String _realHome() {
  final home = Platform.environment['HOME'] ?? '';
  final user = Platform.environment['USER'];
  if (home.contains('/Library/Containers/') &&
      user != null &&
      user.isNotEmpty) {
    return '/Users/$user';
  }
  return home;
}
