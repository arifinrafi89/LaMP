import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';

/// The bottom bar around every owner screen (plan 5.2).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            // Tapping the open tab again goes back to its first screen.
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.title(l)),
        ],
      ),
    );
  }
}
