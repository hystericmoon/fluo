import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'data/repo_scope.dart';
import 'data/repository.dart';
import 'data/storage.dart';
import 'screens/albums.dart';
import 'screens/splash.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await openAppRepo();
  runApp(FluoApp(repo: repo));
}

class FluoApp extends StatefulWidget {
  const FluoApp({super.key, required this.repo, this.splash = const Duration(milliseconds: 1200)});
  final FluoRepo repo;
  final Duration splash;

  @override
  State<FluoApp> createState() => _FluoAppState();
}

class _FluoAppState extends State<FluoApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.splash, () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      repo: widget.repo,
      child: ShadcnApp(
        title: 'Fluo',
        debugShowCheckedModeBanner: false,
        theme: fluoTheme(),
        home: _showSplash ? const SplashScreen() : const AlbumsScreen(),
      ),
    );
  }
}
