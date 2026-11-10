import 'dart:io' show Directory, Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'capture/capture_controller.dart';
import 'capture/capture_scope.dart';
import 'capture/capture_source.dart';
import 'data/repo_scope.dart';
import 'data/repository.dart';
import 'data/storage.dart';
import 'export/export_scope.dart';
import 'export/export_service.dart';
import 'capture/mac_capture_source.dart';
import 'motion/motion.dart';
import 'screens/albums.dart';
import 'screens/splash.dart';
import 'settings/app_settings.dart';
import 'settings/settings_scope.dart';
import 'theme/accent.dart';
import 'theme/app_theme.dart';
import 'ui/shared_intake.dart';
import 'update/update_controller.dart';
import 'update/update_scope.dart';
import 'update/update_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await openAppRepo();
  final android = Platform.isAndroid;
  runApp(FluoApp(
    repo: repo,
    source: android
        ? AndroidCaptureSource()
        : Platform.isMacOS
            ? MacCaptureSource()
            : NoCaptureSource(),
    exports: appExportServices(),
    updateSource: android ? const PlayUpdateSource() : const NoUpdateSource(),
    network: android ? const AndroidNetworkInfo() : const NoNetworkInfo(),
  ));
}

/// Exports are written under the system temp folder and cleared before each
/// new export and at launch.
ExportServices appExportServices() => ExportServices(
      workDir: () async => Directory(p.join((await getTemporaryDirectory()).path, 'fluo_export')),
    );

class FluoApp extends StatefulWidget {
  const FluoApp({
    super.key,
    required this.repo,
    required this.source,
    required this.exports,
    this.splash = const Duration(milliseconds: 1200),
    this.reduceMotion,
    this.updateSource = const NoUpdateSource(),
    this.network = const NoNetworkInfo(),
    this.appInfo = const PackageAppInfoSource(),
  });
  final FluoRepo repo;
  final CaptureSource source;
  final ExportServices exports;
  final Duration splash;

  /// Forces the motion setting (tests). Normally null: the Settings switch
  /// decides, and the system "remove animations" setting always applies too.
  final bool? reduceMotion;
  final UpdateSource updateSource;
  final NetworkInfo network;
  final AppInfoSource appInfo;

  @override
  State<FluoApp> createState() => _FluoAppState();
}

class _FluoAppState extends State<FluoApp> with WidgetsBindingObserver {
  bool _showSplash = true;
  late final CaptureController _capture = CaptureController(widget.repo, widget.source);
  late final AppSettings _settings = AppSettings(widget.repo);
  late final UpdateController _updates = UpdateController(
    settings: _settings,
    source: widget.updateSource,
    network: widget.network,
    appInfo: widget.appInfo,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(widget.splash, () {
      if (mounted) setState(() => _showSplash = false);
    });
    widget.repo.purgeDiscarded(); // leftovers from a visit that was cut short
    // Earlier exports hold copies of screenshots: do not keep them around.
    ExportService(widget.repo, widget.exports).clearWorkDir().catchError((Object _) {});
    _capture.sync(); // picks a stored session back up and imports waiting shots
    _updates.autoCheck(); // if auto-update is on and it has been a while
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from another app or from Settings: access may have changed, and
    // screenshots may have arrived while we were away.
    if (state == AppLifecycleState.resumed) _capture.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capture.dispose();
    _updates.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      repo: widget.repo,
      child: SettingsScope(
        settings: _settings,
        child: UpdateScope(
          controller: _updates,
          // A theme or motion change in Settings rebuilds everything below.
          child: ListenableBuilder(
            listenable: _settings,
            builder: (context, _) => AccentScope(
              accent: _settings.accent,
              child: MotionScope(
                reduce: widget.reduceMotion ?? _settings.reduceMotion,
                child: ExportScope(
                  services: widget.exports,
                  child: CaptureScope(
                    controller: _capture,
                    child: ShadcnApp(
                      title: 'Fluo',
                      debugShowCheckedModeBanner: false,
                      theme: fluoTheme(accent: _settings.accent),
                      home: _showSplash
                          ? const SplashScreen()
                          : const SharedIntake(child: AlbumsScreen()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
