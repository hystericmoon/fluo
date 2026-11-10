import 'dart:async';

import 'package:flutter/services.dart';

enum CapturePermission {
  granted,

  /// Android 14 "selected photos only": new screenshots are not visible.
  limited,
  denied,

  /// Denied and the system will no longer show the prompt: Settings only.
  permanentlyDenied,
  unsupported,
}

/// Words the session card uses, which depend on where capture happens
/// ("photos on this phone" versus "the Desktop folder on this Mac").
class CaptureCopy {
  const CaptureCopy({
    required this.accessLabel,
    required this.watching,
    required this.checking,
    required this.needsPermission,
    required this.needsSettings,
    required this.limited,
    required this.failed,
    required this.allowLabel,
    this.watchingIn,
  });

  /// Status line while watching, once the watched folder is known. Null where
  /// there is no folder to name (the phone).
  final String Function(String folder)? watchingIn;

  /// Status line when access is missing.
  final String accessLabel;
  final String watching;
  final String checking;
  final String needsPermission;
  final String needsSettings;
  final String limited;
  final String failed;

  /// Button that raises the system permission prompt.
  final String allowLabel;

  static const phone = CaptureCopy(
    accessLabel: 'Needs photo access',
    watching: 'New screenshots land here automatically. Missed one? Share it to Fluo from your gallery.',
    checking: 'Checking photo access…',
    needsPermission: 'Allow photo access so Fluo can see new screenshots. Your photos stay on this phone.',
    needsSettings: 'Photo access is off. Turn it on in Settings so Fluo can see new screenshots.',
    limited: 'Fluo can only see the photos you picked, so it would miss new screenshots. Allow all photos in Settings.',
    failed:
        'Fluo could not start watching for screenshots. Try again, or share a screenshot to Fluo from your gallery and pick an album.',
    allowLabel: 'Allow photo access',
  );

  static const mac = CaptureCopy(
    accessLabel: 'Needs folder access',
    watching: 'New screenshots land here automatically.',
    checking: 'Checking folder access…',
    needsPermission:
        'Allow Fluo to read the folder your screenshots are saved to, so it can see new ones. They stay on this Mac.',
    needsSettings:
        'Folder access is off. Turn it on in System Settings > Privacy & Security > Files & Folders so Fluo can see new screenshots.',
    limited: 'Fluo cannot see all of your screenshot folder. Allow access in System Settings.',
    failed: 'Fluo could not start watching for screenshots. Try again.',
    allowLabel: 'Allow folder access',
    watchingIn: _macWatchingIn,
  );

  static String _macWatchingIn(String folder) =>
      'Watching $folder. New screenshots land here automatically. One copied '
      'to the clipboard or saved somewhere else will not show up.';

  /// The detail line while watching, naming [folder] when there is one.
  String watchingText(String? folder) {
    final f = watchingIn;
    return (f != null && folder != null && folder.isNotEmpty) ? f(folder) : watching;
  }
}

/// A screenshot the platform copied into the app's private inbox.
class IncomingShot {
  const IncomingShot({
    required this.path,
    required this.capturedAt,
    this.width,
    this.height,
  });
  final String path;
  final DateTime capturedAt;
  final int? width;
  final int? height;
}

/// Platform side of screenshot capture.
///
/// The platform watches for new screenshots while a watch is started and
/// copies each one into an inbox folder the moment it appears, even when the
/// Dart side is not running. Dart then [drain]s the inbox and [ack]s what it
/// has stored, so a screenshot is never lost between the two.
abstract class CaptureSource {
  bool get supported;

  /// Wording for the session card.
  CaptureCopy get copy;

  /// Short name of the folder being watched ("Desktop"), or null when capture
  /// is not folder based (the phone) or it is not known yet.
  String? get watchedFolder;

  /// Whether the user can pick which folder is watched (macOS only).
  bool get canChooseFolder;

  /// True when the watched folder was picked by the user, not the system
  /// default.
  bool get customFolder;

  /// Shows the folder picker and remembers the choice. False if cancelled.
  /// The caller restarts the watch.
  Future<bool> chooseFolder();

  /// Goes back to the system screenshot folder.
  Future<void> useDefaultFolder();

  /// Whether images can be dropped on the window (desktop only).
  bool get canImportFiles;

  /// Copies dropped image files into the shared inbox. Returns how many were
  /// taken; they then wait for an album like shares do.
  Future<int> importFiles(List<String> paths);
  Future<CapturePermission> permission();
  Future<CapturePermission> requestPermission();
  Future<void> openSettings();

  /// Starts watching. Screenshots that already exist are ignored.
  Future<void> start();
  Future<void> stop();
  Future<List<IncomingShot>> drain();
  Future<void> ack(List<String> paths);

  /// Fires when something new landed in the inbox.
  Stream<void> get captured;

  /// Screenshots sent to Fluo from the system share sheet, waiting for the
  /// user to choose an album. Separate from the inbox: they are not session
  /// captures.
  Future<List<IncomingShot>> drainShared();
  Future<void> ackShared(List<String> paths);

  /// Fires when something was shared to Fluo while the app is running.
  Stream<void> get sharedIn;
}

/// Platforms without a capture plugin yet (iOS and desktop come later).
class NoCaptureSource implements CaptureSource {
  @override
  bool get supported => false;
  @override
  CaptureCopy get copy => CaptureCopy.phone;
  @override
  String? get watchedFolder => null;
  @override
  bool get canChooseFolder => false;
  @override
  bool get customFolder => false;
  @override
  Future<bool> chooseFolder() async => false;
  @override
  Future<void> useDefaultFolder() async {}
  @override
  bool get canImportFiles => false;
  @override
  Future<int> importFiles(List<String> paths) async => 0;
  @override
  Future<CapturePermission> permission() async => CapturePermission.unsupported;
  @override
  Future<CapturePermission> requestPermission() async => CapturePermission.unsupported;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<List<IncomingShot>> drain() async => const [];
  @override
  Future<void> ack(List<String> paths) async {}
  @override
  Stream<void> get captured => const Stream.empty();
  @override
  Future<List<IncomingShot>> drainShared() async => const [];
  @override
  Future<void> ackShared(List<String> paths) async {}
  @override
  Stream<void> get sharedIn => const Stream.empty();
}

/// Talks to `CaptureChannel.kt`.
class AndroidCaptureSource implements CaptureSource {
  AndroidCaptureSource({
    MethodChannel? method,
    EventChannel? events,
  })  : _m = method ?? const MethodChannel('app.fluo/capture'),
        _e = events ?? const EventChannel('app.fluo/capture/events');

  final MethodChannel _m;
  final EventChannel _e;

  @override
  bool get supported => true;
  @override
  CaptureCopy get copy => CaptureCopy.phone;
  @override
  String? get watchedFolder => null;
  @override
  bool get canChooseFolder => false;
  @override
  bool get customFolder => false;
  @override
  Future<bool> chooseFolder() async => false;
  @override
  Future<void> useDefaultFolder() async {}
  @override
  bool get canImportFiles => false;
  @override
  Future<int> importFiles(List<String> paths) async => 0;

  static CapturePermission _parse(String? s) => switch (s) {
        'granted' => CapturePermission.granted,
        'limited' => CapturePermission.limited,
        'permanentlyDenied' => CapturePermission.permanentlyDenied,
        _ => CapturePermission.denied,
      };

  @override
  Future<CapturePermission> permission() async =>
      _parse(await _m.invokeMethod<String>('permission'));

  @override
  Future<CapturePermission> requestPermission() async =>
      _parse(await _m.invokeMethod<String>('requestPermission'));

  @override
  Future<void> openSettings() => _m.invokeMethod<void>('openSettings');

  @override
  Future<void> start() => _m.invokeMethod<void>('start');

  @override
  Future<void> stop() => _m.invokeMethod<void>('stop');

  @override
  Future<List<IncomingShot>> drain() => _drain('drain');

  @override
  Future<List<IncomingShot>> drainShared() => _drain('drainShared');

  @override
  Future<void> ackShared(List<String> paths) => _m.invokeMethod<void>('ackShared', paths);

  Future<List<IncomingShot>> _drain(String method) async {
    final raw = await _m.invokeListMethod<Map<Object?, Object?>>(method) ?? const [];
    return [
      for (final m in raw)
        IncomingShot(
          path: m['path']! as String,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(m['capturedAtMs']! as int),
          width: (m['width'] as num?)?.toInt(),
          height: (m['height'] as num?)?.toInt(),
        ),
    ];
  }

  @override
  Future<void> ack(List<String> paths) => _m.invokeMethod<void>('ack', paths);

  // One native listener serves both streams: a `null` event is a new
  // screenshot in the inbox, "shared" is something sent from the share sheet.
  late final Stream<Object?> _events = _e.receiveBroadcastStream();

  @override
  Stream<void> get captured => _events.where((e) => e != 'shared').map((_) {});

  @override
  Stream<void> get sharedIn => _events.where((e) => e == 'shared').map((_) {});
}
