import 'dart:async';

import 'package:fluo/capture/capture_source.dart';

/// In-memory stand-in for the platform side of capture.
class FakeSource implements CaptureSource {
  @override
  CaptureCopy get copy => CaptureCopy.phone;

  FakeSource({this.perm = CapturePermission.granted, this.isSupported = true});
  CapturePermission perm;
  CapturePermission afterRequest = CapturePermission.granted;
  final bool isSupported;
  bool watching = false;
  int starts = 0, stops = 0, requests = 0, settings = 0;
  final inbox = <IncomingShot>[];
  final acked = <String>[];
  final failAck = <String>{};
  final _ctl = StreamController<void>.broadcast();

  @override
  bool get supported => isSupported;
  @override
  Future<CapturePermission> permission() async => perm;
  @override
  Future<CapturePermission> requestPermission() async {
    requests++;
    return perm = afterRequest;
  }

  @override
  Future<void> openSettings() async => settings++;
  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    watching = true;
    starts++;
  }

  @override
  Future<void> stop() async {
    watching = false;
    stops++;
  }

  @override
  Future<List<IncomingShot>> drain() async => List.of(inbox);
  @override
  Future<void> ack(List<String> paths) async {
    for (final x in paths) {
      acked.add(x);
      inbox.removeWhere((s) => s.path == x);
    }
  }

  final shared = <IncomingShot>[];
  final sharedAcked = <String>[];
  final _sharedCtl = StreamController<void>.broadcast();
  @override
  Future<List<IncomingShot>> drainShared() async => List.of(shared);
  @override
  Future<void> ackShared(List<String> paths) async {
    for (final x in paths) {
      sharedAcked.add(x);
      shared.removeWhere((s) => s.path == x);
    }
  }

  @override
  Stream<void> get sharedIn => _sharedCtl.stream;
  void pingShared() => _sharedCtl.add(null);

  /// When set, [start] throws, like a native failure would.
  Object? startError;

  @override
  Stream<void> get captured => _ctl.stream;
  void ping() => _ctl.add(null);
}
