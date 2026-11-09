import 'dart:io' show Platform;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'capture/capture_controller.dart';
import 'capture/capture_scope.dart';
import 'capture/capture_source.dart';
import 'data/repo_scope.dart';
import 'data/repository.dart';
import 'data/storage.dart';
import 'screens/albums.dart';
import 'screens/splash.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await openAppRepo();
  final CaptureSource source = Platform.isAndroid ? AndroidCaptureSource() : NoCaptureSource();
  runApp(FluoApp(repo: repo, source: source));
}

class FluoApp extends StatefulWidget {
  const FluoApp({
    super.key,
    required this.repo,
    required this.source,
    this.splash = const Duration(milliseconds: 1200),
  });
  final FluoRepo repo;
  final CaptureSource source;
  final Duration splash;

  @override
  State<FluoApp> createState() => _FluoAppState();
}

class _FluoAppState extends State<FluoApp> with WidgetsBindingObserver {
  bool _showSplash = true;
  late final CaptureController _capture = CaptureController(widget.repo, widget.source);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(widget.splash, () {
      if (mounted) setState(() => _showSplash = false);
    });
    _capture.sync(); // picks a stored session back up and imports waiting shots
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      repo: widget.repo,
      child: CaptureScope(
        controller: _capture,
        child: ShadcnApp(
          title: 'Fluo',
          debugShowCheckedModeBanner: false,
          theme: fluoTheme(),
          home: _showSplash ? const SplashScreen() : const AlbumsScreen(),
        ),
      ),
    );
  }
}
