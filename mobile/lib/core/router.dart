import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/more/more_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/welcome/loading_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../l10n/app_localizations.dart';
import 'state/session_controller.dart';

/// A screen reachable from the bar or from More: its path and its title.
class LampDestination {
  const LampDestination(this.path, this.icon, this.title);
  final String path;
  final IconData icon;
  final String Function(L10n) title;
}

/// The five tabs, in bar order (plan 5.2).
final tabs = <LampDestination>[
  LampDestination('/today', Icons.wb_sunny_outlined, (l) => l.tabToday),
  LampDestination('/scan', Icons.document_scanner_outlined, (l) => l.tabScan),
  LampDestination('/customers', Icons.people_outline, (l) => l.tabCustomers),
  LampDestination('/ask', Icons.chat_bubble_outline, (l) => l.tabAsk),
  LampDestination('/more', Icons.menu, (l) => l.tabMore),
];

/// The screens under More. Their URLs are top-level (`/stock`), and they sit
/// in the More branch so More stays selected while one is open.
final moreDestinations = <LampDestination>[
  LampDestination('/stock', Icons.inventory_2_outlined, (l) => l.navStock),
  LampDestination('/cash', Icons.payments_outlined, (l) => l.navCash),
  LampDestination('/plan', Icons.event_note_outlined, (l) => l.navPlan),
  LampDestination('/approvals', Icons.task_alt, (l) => l.navApprovals),
  LampDestination('/credit-record', Icons.verified_outlined, (l) => l.navCreditRecord),
  LampDestination('/plus', Icons.workspace_premium_outlined, (l) => l.navPlus),
  LampDestination('/history', Icons.history, (l) => l.navHistory),
  LampDestination('/settings', Icons.settings_outlined, (l) => l.navSettings),
  LampDestination('/help', Icons.help_outline, (l) => l.navHelp),
];

GoRoute _placeholder(LampDestination d) => GoRoute(
      path: d.path,
      builder: (context, state) => PlaceholderScreen(destination: d),
    );

/// Shown until the owner names their shop (Y2.1 replaces it).
final setupDestination =
    LampDestination('/setup', Icons.storefront_outlined, (l) => l.navSetup);

/// Where the session says this phone may be.
///
/// - Until the stored session is read: a holding screen, keeping the link.
/// - Signed out: Welcome, whatever the link.
/// - Signed in with no shop yet: Setup.
/// - Signed in: anywhere but Welcome; the link given at launch is kept.
String? sessionRedirect(SessionController session, Uri uri) {
  final at = uri.path;
  switch (session.status) {
    case SessionStatus.restoring:
      if (at == '/loading') return null;
      return Uri(path: '/loading', queryParameters: {'from': uri.toString()}).toString();
    case SessionStatus.signedOut:
      return at == '/welcome' ? null : '/welcome';
    case SessionStatus.signedIn:
      final pharmacy = session.pharmacy;
      if (pharmacy == null) return at == '/setup' ? null : '/setup';
      if (at == '/welcome' || at == '/loading') {
        final from = uri.queryParameters['from'];
        if (!pharmacy.setupComplete) return '/setup';
        if (from != null && from.startsWith('/') && !from.startsWith('/loading')) return from;
        return '/today';
      }
      return null;
  }
}

GoRouter buildRouter({
  required SessionController session,
  String initialLocation = '/today',
}) =>
    GoRouter(
      initialLocation: initialLocation,
      refreshListenable: session,
      redirect: (context, state) => sessionRedirect(session, state.uri),
      routes: [
        GoRoute(path: '/', redirect: (_, _) => '/today'),
        GoRoute(path: '/loading', builder: (_, _) => const LoadingScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        _placeholder(setupDestination),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            for (final t in tabs.take(4))
              StatefulShellBranch(routes: [_placeholder(t)]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
              ),
              for (final d in moreDestinations) _placeholder(d),
            ]),
          ],
        ),
      ],
    );
