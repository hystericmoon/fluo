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
