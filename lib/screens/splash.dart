import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';
import '../ui/wordmark.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluoColors.bg,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FluoWordmark(),
          SizedBox(height: 18),
          SizedBox(
            width: 240,
            child: Text(
              'Screenshots in, review out.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FluoFonts.body,
                fontSize: 15,
                height: 1.4,
                color: FluoColors.fgMuted,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
