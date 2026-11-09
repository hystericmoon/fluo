import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'screens/albums.dart';
import 'screens/splash.dart';
import 'theme/app_theme.dart';

void main() => runApp(const FluoApp());

class FluoApp extends StatefulWidget {
  const FluoApp({super.key});

  @override
  State<FluoApp> createState() => _FluoAppState();
}

class _FluoAppState extends State<FluoApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'Fluo',
      debugShowCheckedModeBanner: false,
      theme: fluoTheme(),
      home: _showSplash ? const SplashScreen() : const AlbumsScreen(),
    );
  }
}
