import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/me.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_parts_bar.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_sync_pip.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'customer_sheets.dart';
import 'customers_controller.dart';
import 'customers_models.dart';
import 'customers_screen.dart';

/// One customer's card (`/customers/<code>`): what they owe, their plan and
/// their SMS. One main action: record a payment.
class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key, required this.code, this.added = false});

  final String code;

  /// Just added: say so, and lead with the join text.
  final bool added;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final list = context.watch<CustomersController>();
    final data = list.customers;
    final cu = data?.byCode(code);

    final Widget body;
    if (data == null && list.problem != null) {
      body = LampFailed(problem: list.problem!, onRetry: list.load);
    } else if (data == null || (cu == null && list.loading)) {
      // Also while a just-added card is on its way.
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          LampSkeletonCard(lines: 2),
          SizedBox(height: Gap.md),
          LampSkeletonCard(),
        ],
      );
    } else if (cu == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampEmpty(
            icon: Icons.search_off,
            title: l.customerNotFound,
            message: l.errNotFound,
            action: OutlinedButton(
              key: const ValueKey('customers-back'),
              onPressed: () => context.go('/customers'),
              child: Text(l.customersBack),
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: list.load,
        child: _Card(customer: cu, added: added, savedAt: list.savedAt, controller: list),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(cu?.label ?? l.tabCustomers)),
      body: body,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.customer, required this.added, required this.savedAt, required this.controller});

  final Customer customer;
  final bool added;
  final DateTime? savedAt;
  final CustomersController controller;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final cu = customer;
    final sms = _Sms(customer: cu);
    // Not lazy: one card is short, and every part of it is there to find.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (savedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: LampSyncPip(savedAt: savedAt!, problem: controller.problem),
            ),
          if (added) ...[
            LampCard(
              background: c.verifiedSoft,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: c.verified),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(l.addedTitle(cu.label), style: LaMPType.sub.copyWith(color: c.ink)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            sms,
            const SizedBox(height: Gap.md),
          ],
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LampStat(
                  label: l.customerOwes,
                  value: formatMoney(cu.amount, bangla: bn),
                  caption: l.customerSince(
                    formatDay(cu.since, bangla: bn),
                    formatCount(cu.daysOutstanding, bangla: bn),
                  ),
                ),
                if (cu.trusted) ...[
                  const SizedBox(height: Gap.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: LampChip(label: l.customerTrusted, tone: LampTone.verified, icon: Icons.verified_outlined),
                  ),
                ],
                const SizedBox(height: Gap.sm),
                // Card codes keep English letters and digits (plan 5.4).
                LampKeyValue(label: l.addedCode, value: cu.code, mono: true),
                const SizedBox(height: Gap.md),
                ElevatedButton.icon(
                  key: const ValueKey('customer-pay'),
                  onPressed: () => recordMoney(context, cu, payment: true),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(l.customerRecordPayment),
                ),
                const SizedBox(height: Gap.sm),
                OutlinedButton.icon(
                  key: const ValueKey('customer-sale'),
                  onPressed: () => recordMoney(context, cu, payment: false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(l.customerRecordSale),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          _Plan(customer: cu),
          if (!added) ...[const SizedBox(height: Gap.md), sms],
        ],
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final p = customer.plan;
    final next = p?.nextUnpaid;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.planTitle, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          Text(planName(l, p, bn), style: LaMPType.head.copyWith(color: c.ink)),
          if (p != null && p.paidKnown) ...[
            const SizedBox(height: Gap.md),
            LampPartsBar(parts: p.schedule.length, paid: p.paidCount),
            const SizedBox(height: Gap.xs),
            Text(
              l.planPaidOf(formatCount(p.paidCount, bangla: bn), formatCount(p.schedule.length, bangla: bn)),
              style: LaMPType.caption.copyWith(color: c.inkMuted),
            ),
            if (next != null)
              Text(
                l.planNext(formatMoney(next.amount, bangla: bn), formatDay(next.dueOn, bangla: bn)),
                style: LaMPType.caption.copyWith(color: c.inkMuted),
              ),
          ],
          if (p != null) ...[
            const SizedBox(height: Gap.sm),
            for (final part in p.schedule)
              LampKeyValue(
                label: l.planPartLine(formatCount(part.n, bangla: bn), formatDay(part.dueOn, bangla: bn)),
                value: part.paid == true
                    ? '${formatMoney(part.amount, bangla: bn)} · ${l.planPaid}'
                    : formatMoney(part.amount, bangla: bn),
                valueColor: part.paid == true ? c.verified : null,
                mono: true,
              ),
          ],
          const SizedBox(height: Gap.md),
          OutlinedButton(
            key: const ValueKey('plan-set'),
            onPressed: () => setPlan(context, customer),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(p == null ? l.planSet : l.planChange),
          ),
        ],
      ),
    );
  }
}

/// Where the family's SMS stands, and what the owner can do about it.
class _Sms extends StatelessWidget {
  const _Sms({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final cu = customer;
    final counter = context.watch<MeController>().me?.counterRoute ?? false;
    final words = switch (cu.smsStatus) {
      SmsStatus.none => l.smsNoneBody,
      SmsStatus.pending => l.smsPendingBody,
      SmsStatus.on => l.smsOnBody,
      SmsStatus.stopped => l.smsStoppedBody,
      SmsStatus.failed => l.smsFailedBody,
    };
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.joinTitle, style: LaMPType.sub.copyWith(color: c.ink)),
              ),
              ?smsChip(l, cu.smsStatus),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(words, style: LaMPType.body.copyWith(color: c.inkMuted)),
          if (cu.canJoin) ...[
            const SizedBox(height: Gap.md),
            JoinBox(join: cu.join),
            if (counter) ...[
              const SizedBox(height: Gap.sm),
              TextButton(
                key: const ValueKey('customer-number'),
                onPressed: () => addFamilyNumber(context, cu),
                child: Text(l.customerAddNumber),
              ),
            ],
          ],
          if (cu.smsStatus == SmsStatus.on) ...[
            const SizedBox(height: Gap.md),
            OutlinedButton.icon(
              key: const ValueKey('sms-remind'),
              onPressed: () => remindNow(context, cu),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(l.smsRemind),
            ),
            TextButton(key: const ValueKey('sms-stop'), onPressed: () => stopSms(context, cu), child: Text(l.smsStop)),
          ],
        ],
      ),
    );
  }
}
