import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/approvals/approvals_screen.dart';
import '../features/ask/ask_screen.dart';
import '../features/cash/cash_screen.dart';
import '../features/credit_record/credit_record_screen.dart';
import '../features/customers/customer_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/more/more_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/plus/plus_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/help_screen.dart';
import '../features/sms_phone_mock/sms_phone_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/stock/stock_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/shop_providers.dart';
import '../features/today/today_screen.dart';
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

/// More's screens that have landed; the rest are placeholders until theirs do.
const _built = {'/stock', '/cash', '/plan', '/approvals', '/credit-record', '/plus', '/settings', '/help'};

GoRoute _placeholder(LampDestination d) => GoRoute(
      path: d.path,
      builder: (context, state) => PlaceholderScreen(destination: d),
    );

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
        GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => ShopProviders(child: AppShell(shell: shell)),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/customers',
                builder: (_, _) => const CustomersScreen(),
                routes: [
                  GoRoute(
                    path: ':code',
                    builder: (_, state) => CustomerScreen(
                      code: state.pathParameters['code']!,
                      added: state.uri.queryParameters['added'] == '1',
                    ),
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/ask', builder: (_, _) => const AskScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
              ),
              GoRoute(path: '/stock', builder: (_, _) => const StockScreen()),
              GoRoute(path: '/cash', builder: (_, _) => const CashScreen()),
              GoRoute(path: '/plan', builder: (_, _) => const PlanScreen()),
              GoRoute(path: '/approvals', builder: (_, _) => const ApprovalsScreen()),
              GoRoute(path: '/credit-record', builder: (_, _) => const CreditRecordScreen()),
              GoRoute(path: '/plus', builder: (_, _) => const PlusScreen()),
              GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
              GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
              GoRoute(path: '/demo-phone', builder: (_, _) => const SmsPhoneScreen()),
              for (final d in moreDestinations.where((d) => !_built.contains(d.path))) _placeholder(d),
            ]),
          ],
        ),
      ],
    );
