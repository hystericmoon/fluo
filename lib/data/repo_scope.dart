import 'package:flutter/widgets.dart';

import 'repository.dart';

/// Hands the repository to screens without a global.
class RepoScope extends InheritedWidget {
  const RepoScope({super.key, required this.repo, required super.child});
  final FluoRepo repo;

  static FluoRepo of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<RepoScope>();
    assert(s != null, 'No RepoScope above this context');
    return s!.repo;
  }

  @override
  bool updateShouldNotify(RepoScope old) => repo != old.repo;
}
