import 'dart:async';

import 'package:fluo/update/update_source.dart';

/// A scripted update source.
class FakeUpdateSource implements UpdateSource {
  bool available = false;
  bool unsupported = false;
  Object? checkError;
  bool startAccepted = true;
  int checks = 0, downloads = 0, installs = 0;
  final _phases = StreamController<UpdatePhase>.broadcast();

  void emit(UpdatePhase p) => _phases.add(p);

  @override
  Future<bool> checkAvailable() async {
    checks++;
    if (unsupported) throw const UpdateUnsupported('test');
    if (checkError != null) throw checkError!;
    return available;
  }

  @override
  Future<bool> startDownload() async {
    downloads++;
    return startAccepted;
  }

  @override
  Stream<UpdatePhase> get phases => _phases.stream;

  @override
  Future<void> installDownloaded() async => installs++;
}

class FakeNetwork implements NetworkInfo {
  FakeNetwork({this.unmetered = true});
  bool unmetered;
  int asked = 0;

  @override
  Future<bool> isUnmetered() async {
    asked++;
    return unmetered;
  }
}

class FakeAppInfo implements AppInfoSource {
  const FakeAppInfo([this.info = const AppInfo('0.1.0', '1')]);
  final AppInfo info;
  @override
  Future<AppInfo> load() async => info;
}
