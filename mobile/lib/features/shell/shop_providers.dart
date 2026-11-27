import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/state/me.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/shop_changes.dart';
import '../approvals/approvals_controller.dart';
import '../customers/customers_controller.dart';

/// Reads that more than one screen shares, for the signed-in shop.
///
/// - Each is made, and read, only when a screen first asks for it.
/// - They live as long as the bottom bar: signing out leaves the shell, so
///   they go with it and the next owner starts fresh.
class ShopProviders extends StatelessWidget {
  const ShopProviders({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => MeController(
            context.read<ApiClient>(),
            context.read<CacheStore>(),
            refreshOn: context.read<ShopChanges>(),
          )..load(),
        ),
        ChangeNotifierProvider(
          create: (context) => CustomersController(
            context.read<ApiClient>(),
            context.read<CacheStore>(),
            pid,
            refreshOn: context.read<ShopChanges>(),
          )..load(),
        ),
        Provider(
          create: (context) =>
              CustomerActions(context.read<ApiClient>(), pid, onSaved: context.read<ShopChanges>().saved),
        ),
        // Shared by Approvals, the Plan (is a step waiting?) and More's badge.
        ChangeNotifierProvider(
          create: (context) => ApprovalsController(
            context.read<ApiClient>(),
            context.read<CacheStore>(),
            pid,
            refreshOn: context.read<ShopChanges>(),
          )..load(),
        ),
        Provider(
          create: (context) => MoneyActions(context.read<ApiClient>(), pid, onSaved: context.read<ShopChanges>().saved),
        ),
      ],
      child: child,
    );
  }
}
