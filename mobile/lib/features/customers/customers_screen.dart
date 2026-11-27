import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_sync_pip.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'customer_sheets.dart';
import 'customers_controller.dart';
import 'customers_models.dart';

/// Customers (plan 5.2): who owes the shop, oldest first. Free on every
/// plan. One main action: add a customer.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final list = context.watch<CustomersController>();
    final data = list.customers;
    final problem = list.problem;

    final Widget body;
    if (data == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: list.load);
    } else if (data == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          LampSkeletonCard(lines: 2),
          SizedBox(height: Gap.md),
          LampSkeletonCard(),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: list.load,
        child: _List(data: data, controller: list),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.tabCustomers)),
      body: body,
    );
  }
}

Widget addCustomerButton(BuildContext context) => ElevatedButton.icon(
  key: const ValueKey('customers-add'),
  onPressed: () => addCustomer(context),
  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
  icon: const Icon(Icons.person_add_alt),
  label: Text(L10n.of(context).customersAdd),
);

class _List extends StatelessWidget {
  const _List({required this.data, required this.controller});

  final CustomerList data;
  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final n = data.items.length;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        if (controller.savedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: LampSyncPip(savedAt: controller.savedAt!, problem: controller.problem),
          ),
        if (n == 0)
          LampEmpty(
            icon: Icons.people_outline,
            title: l.customersEmptyTitle,
            message: l.customersEmptyBody,
            action: addCustomerButton(context),
          )
        else ...[
          addCustomerButton(context),
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: n == 1 ? l.customersCountOne : l.customersCount(formatCount(n, bangla: bn))),
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final cu in data.items)
                  LampRow(
                    key: ValueKey('customer-${cu.code}'),
                    icon: cu.trusted ? Icons.verified_outlined : Icons.person_outline,
                    iconColor: cu.trusted ? c.verified : c.inkMuted,
                    title: cu.label,
                    subtitle: customerLine(l, cu, bn),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(cu.amount, bangla: bn),
                          style: LaMPType.figure.copyWith(color: c.ink),
                        ),
                        if (smsChip(l, cu.smsStatus) case final chip?) ...[const SizedBox(height: Gap.xs), chip],
                      ],
                    ),
                    onTap: () => context.go('/customers/${cu.code}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Since Tue 3 Nov · 24 days · 4 weekly parts".
String customerLine(L10n l, Customer cu, bool bn) => [
  l.customerSince(formatDay(cu.since, bangla: bn), formatCount(cu.daysOutstanding, bangla: bn)),
  planName(l, cu.plan, bn),
].join(' · ');

String planName(L10n l, CustomerPlan? p, bool bn) => switch (p) {
  null => l.customerNoPlan,
  CustomerPlan(parts: 1) => l.planOnePayment,
  _ => l.planWeeklyParts(formatCount(p.parts, bangla: bn)),
};

/// The SMS state as a word; none shows nothing.
Widget? smsChip(L10n l, SmsStatus s) => switch (s) {
  SmsStatus.none => null,
  SmsStatus.pending => LampChip(label: l.smsJoining, tone: LampTone.pending),
  SmsStatus.on => LampChip(label: l.smsOn, tone: LampTone.verified, icon: Icons.sms_outlined),
  SmsStatus.stopped => LampChip(label: l.smsStopped),
  SmsStatus.failed => LampChip(label: l.smsFailed, tone: LampTone.dispute),
};
