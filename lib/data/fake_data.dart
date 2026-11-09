import 'package:flutter/painting.dart';

import '../theme/tokens.dart';

enum Severity { bug, ux, a11y }

extension SeverityX on Severity {
  String get letter => switch (this) { Severity.bug => 'B', Severity.ux => 'U', Severity.a11y => 'A' };
  String get label => switch (this) { Severity.bug => 'Bug', Severity.ux => 'UX', Severity.a11y => 'A11y' };
  Color get color => switch (this) {
        Severity.bug => FluoColors.bug,
        Severity.ux => FluoColors.ux,
        Severity.a11y => FluoColors.a11y,
      };
}

class AlbumInfo {
  const AlbumInfo(this.name, this.meta);
  final String name;
  final String meta;
}

class ShotInfo {
  const ShotInfo(this.name, this.pins, this.button);
  final String name;
  final List<Severity> pins;
  final Color button;
}

const fakeAlbums = [
  AlbumInfo('Checkout flow review', '19 screens · Today'),
  AlbumInfo('Onboarding audit', '12 screens · Mon'),
  AlbumInfo('Settings and profile', '9 screens · Last week'),
  AlbumInfo('Search and filters', '5 screens · Oct 28'),
  AlbumInfo('Notifications', '14 screens · Oct 12'),
];

const _blue = Color(0xFF2563EB);
const _green = Color(0xFF16A34A);
const _violet = Color(0xFF7C3AED);

const fakeShots = [
  ShotInfo('Welcome', [], _blue),
  ShotInfo('Cart', [Severity.bug, Severity.ux], _blue),
  ShotInfo('Address', [Severity.ux], _green),
  ShotInfo('Payment', [Severity.a11y, Severity.bug], _blue),
  ShotInfo('Review order', [], _green),
  ShotInfo('Confirmation', [], _violet),
  ShotInfo('Receipt', [Severity.ux], _blue),
  ShotInfo('Order status', [], _green),
  ShotInfo('Help', [], _violet),
];
