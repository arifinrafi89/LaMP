import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/palette.dart';
import '../../core/l10n/digits.dart';
import '../../core/router.dart';
import '../../core/state/me.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../approvals/approvals_controller.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // How many steps wait, on Plus only: a free shop's More reads nothing.
    final plus = context.watch<MeController>().me?.entitlements.approvals ?? false;
    final waiting = plus ? context.watch<ApprovalsController>().actions?.waiting.length ?? 0 : 0;
    return Scaffold(
      appBar: AppBar(title: Text(l.tabMore)),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final d in moreDestinations)
                  LampRow(
                    icon: d.icon,
                    title: d.title(l),
                    trailing: d.path == '/approvals' && waiting > 0
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LampChip(
                                key: const ValueKey('approvals-badge'),
                                label: formatCount(waiting, bangla: isBangla(context)),
                                tone: LampTone.brand,
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => context.go(d.path),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
