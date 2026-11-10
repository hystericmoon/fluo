import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'capture_source.dart';

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
    Future<void> Function()? openSystemSettings,
    this.pollInterval = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _screenshotDir = screenshotDir ?? _systemScreenshotDir,
       _inboxDir = inboxDir ?? _defaultInboxDir,
       _openSystemSettings = openSystemSettings ?? _openPrivacySettings,
       _now = now ?? DateTime.now;

  final Future<Directory> Function() _screenshotDir;
  final Future<Directory> Function() _inboxDir;
  final Future<void> Function() _openSystemSettings;
  final Duration pollInterval;
  final DateTime Function() _now;

  final _captured = StreamController<void>.broadcast();
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

  // ---- permission -------------------------------------------------------

  /// Reading the Desktop, Documents or Downloads folder needs the user's
  /// consent (a one-time system prompt). The only way to find out is to try,
  /// so this lists the folder; that is also what raises the prompt.
  @override
  Future<CapturePermission> permission() async {
    try {
      final dir = await _screenshotDir();
      if (!await dir.exists()) return CapturePermission.granted;
      await dir.list().isEmpty;
      return CapturePermission.granted;
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      // 1 = EPERM, 13 = EACCES: macOS refused. It never asks twice.
      if (code == 1 || code == 13) return CapturePermission.permanentlyDenied;
      return CapturePermission.denied;
    }
  }

  @override
  Future<CapturePermission> requestPermission() => permission();

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
    final dir = await _screenshotDir();
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
    final dir = await _screenshotDir();
    if (!await dir.exists()) return false;
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
  Future<bool> _copyToInbox(File src, Directory inbox, int modifiedMs) async {
    final ext = p.extension(src.path).replaceFirst('.', '').toLowerCase();
    final base = '${modifiedMs}_${_stableId(p.basename(src.path))}';
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

  // Nothing to share *to* on desktop yet.
  @override
  Future<List<IncomingShot>> drainShared() async => const [];
  @override
  Future<void> ackShared(List<String> paths) async {}
  @override
  Stream<void> get sharedIn => const Stream.empty();

  Future<void> dispose() async {
    await stop();
    await _captured.close();
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
