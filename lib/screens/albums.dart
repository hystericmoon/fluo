import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/tokens.dart';

/// Empty Albums screen (session 1). Real content arrives in sessions 2 and 3.
class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluoColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        'Albums',
                        style: TextStyle(
                          fontFamily: FluoFonts.body,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.56,
                          color: FluoColors.fg,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Settings',
                    button: true,
                    excludeSemantics: true,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        // 3:1 against the background (WCAG 1.4.11).
                        border: Border.all(color: FluoColors.borderStrong),
                      ),
                      child: GhostButton(
                        onPressed: () {},
                        density: ButtonDensity.icon,
                        child: const Icon(LucideIcons.slidersHorizontal),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: PrimaryButton(
                      onPressed: () {},
                      leading: const Icon(LucideIcons.plus),
                      child: const Text('New album'),
                    ),
                  ),
                ],
              ),
              const Expanded(child: _EmptyState()),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.images, size: 40, color: FluoColors.fgMuted),
          SizedBox(height: 16),
          Text(
            'No albums yet',
            style: TextStyle(
              fontFamily: FluoFonts.body,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: FluoColors.fg,
              decoration: TextDecoration.none,
            ),
          ),
          SizedBox(height: 4),
          SizedBox(
            width: 260,
            child: Text(
              'Create an album, then take screenshots to start a review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: FluoFonts.body,
                fontSize: 14,
                height: 1.4,
                color: FluoColors.fgMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
