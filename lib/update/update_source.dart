import 'dart:async';

import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// This copy of the app cannot be updated from inside the app: it was not
/// installed from Google Play (a sideloaded APK, a debug build), or Play
/// services are missing.
class UpdateUnsupported implements Exception {
  const UpdateUnsupported([this.reason = '']);
  final String reason;
  @override
  String toString() => 'UpdateUnsupported($reason)';
}

enum UpdatePhase { downloading, downloaded, failed }

/// Where updates come from. On Android it is Google Play's in-app updates:
/// Play does the downloading, so Fluo itself needs no internet permission and
/// the "local only" promise holds.
abstract class UpdateSource {
  /// True if a newer version exists. Throws [UpdateUnsupported] if this copy
  /// cannot be updated from inside the app.
  Future<bool> checkAvailable();

  /// Starts a background download (Play asks for consent). False if the
  /// person declined or it could not start.
  Future<bool> startDownload();

  Stream<UpdatePhase> get phases;

  /// Applies a downloaded update. The app restarts.
  Future<void> installDownloaded();
}

class NoUpdateSource implements UpdateSource {
  const NoUpdateSource();
  @override
  Future<bool> checkAvailable() async => throw const UpdateUnsupported('not on Android');
  @override
  Future<bool> startDownload() async => false;
  @override
  Stream<UpdatePhase> get phases => const Stream.empty();
  @override
  Future<void> installDownloaded() async {}
}

class PlayUpdateSource implements UpdateSource {
  const PlayUpdateSource();

  @override
  Future<bool> checkAvailable() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable && info.flexibleUpdateAllowed;
    } on PlatformException catch (e) {
      // Play reports "not installed from Play" and "no Play services" as errors.
      throw UpdateUnsupported('${e.code}: ${e.message}');
    }
  }

  @override
  Future<bool> startDownload() async {
    try {
      return await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<UpdatePhase> get phases => InAppUpdate.installUpdateListener.map((s) => switch (s) {
        InstallStatus.downloaded => UpdatePhase.downloaded,
        InstallStatus.failed || InstallStatus.canceled => UpdatePhase.failed,
        _ => UpdatePhase.downloading,
      });

  @override
  Future<void> installDownloaded() => InAppUpdate.completeFlexibleUpdate();
}

/// Whether the current connection is unmetered (Wi-Fi, Ethernet), which is
/// what "Wi-Fi only" means.
abstract class NetworkInfo {
  Future<bool> isUnmetered();
}

class AndroidNetworkInfo implements NetworkInfo {
  const AndroidNetworkInfo();
  static const _channel = MethodChannel('app.fluo/network');

  @override
  Future<bool> isUnmetered() async {
    try {
      return await _channel.invokeMethod<bool>('unmetered') ?? false;
    } on PlatformException {
      return false; // when unsure, do not use mobile data
    }
  }
}

class NoNetworkInfo implements NetworkInfo {
  const NoNetworkInfo();
  @override
  Future<bool> isUnmetered() async => true;
}

class AppInfo {
  const AppInfo(this.version, this.build);
  final String version;
  final String build;
  @override
  String toString() => build.isEmpty ? version : '$version ($build)';
}

abstract class AppInfoSource {
  Future<AppInfo> load();
}

class PackageAppInfoSource implements AppInfoSource {
  const PackageAppInfoSource();
  @override
  Future<AppInfo> load() async {
    final p = await PackageInfo.fromPlatform();
    return AppInfo(p.version, p.buildNumber);
  }
}
