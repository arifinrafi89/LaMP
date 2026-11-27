import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/l10n/digits.dart';
import '../../core/offline/cache_store.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_sync_pip.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../plus/plus_gate.dart';
import 'cash_controller.dart';
import 'cash_models.dart';

/// Cash (plan 5.2, Plus): the next 30 days. One main action: see why the
/// short day happens.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return PlusGate(
      title: l.navCash,
      what: l.cashWhat,
      icon: Icons.payments_outlined,
      allowed: (e) => e.cash,
      child: ChangeNotifierProvider(
        create: (context) => CashController(
          context.read<ApiClient>(),
          context.read<CacheStore>(),
          context.read<SessionController>().pharmacy!.id,
          refreshOn: context.read<ShopChanges>(),
        )..load(),
        child: const _CashView(),
      ),
    );
  }
}

class _CashView extends StatelessWidget {
  const _CashView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final cash = context.watch<CashController>();
    final data = cash.forecast;
    final problem = cash.problem;

    final Widget body;
    if (data == null && problem?.code == 'plus_required') {
      body = PlusLocked(title: l.navCash, what: l.cashWhat, icon: Icons.payments_outlined);
    } else if (data == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: cash.load);
    } else if (data == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          LampSkeletonCard(lines: 2),
          SizedBox(height: Gap.md),
          LampSkeletonCard(lines: 4),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: cash.load,
        child: _Days(data: data, controller: cash),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navCash)),
      body: body,
    );
  }
}

class _Days extends StatelessWidget {
  const _Days({required this.data, required this.controller});

  final Forecast data;
  final CashController controller;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final first = data.shortfalls.isEmpty ? null : data.shortfalls.first;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.savedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: LampSyncPip(savedAt: controller.savedAt!, problem: controller.problem),
            ),
          if (first == null)
            LampCard(
              background: c.verifiedSoft,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: c.verified),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.cashNoShort, style: LaMPType.sub.copyWith(color: c.ink)),
                        Text(l.cashNoShortBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            LampCard(
              background: c.pendingSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.todayShortOn(formatMoney(first.amount, bangla: bn), formatDay(first.date, bangla: bn)),
                    style: LaMPType.head.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    serverWords(first.cause, bangla: bn),
                    style: LaMPType.body.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: Gap.md),
                  ElevatedButton(
                    key: const ValueKey('cash-why'),
                    onPressed: () => showWhy(context, data, first),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(l.cashSeeWhy),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.md),
          LampCard(
            child: Text(
              l.cashYouHave(formatMoney(data.startCash, bangla: bn)),
              style: LaMPType.head.copyWith(color: c.ink),
            ),
          ),
          if (data.shortfalls.length > 1) ...[
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.cashOtherShort),
            LampCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in data.shortfalls.skip(1))
                    LampRow(
                      icon: Icons.warning_amber_outlined,
                      iconColor: c.pending,
                      title: l.todayShortOn(formatMoney(s.amount, bangla: bn), formatDay(s.date, bangla: bn)),
                      subtitle: serverWords(s.cause, bangla: bn),
                      onTap: () => showWhy(context, data, s),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: l.cashNext30),
          for (final d in data.namedDays) ...[_DayCard(day: d), const SizedBox(height: Gap.sm)],
        ],
      ),
    );
  }
}

/// One day: its named moves, each as the server sent it, and what is left.
/// The app adds nothing up (D8).
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final ForecastDay day;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatDay(day.date, bangla: bn),
            style: LaMPType.sub.copyWith(color: c.ink),
          ),
          for (final i in day.items)
            LampKeyValue(
              label: serverWords(i.label, bangla: bn),
              value: formatMoney(i.amount, bangla: bn),
              mono: true,
            ),
          Text(
            l.cashLeftShort(formatMoney(day.balance, bangla: bn)),
            style: LaMPType.caption.copyWith(color: day.short ? c.dispute : c.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Why that day runs short, and the way to the plan.
Future<void> showWhy(BuildContext context, Forecast data, Shortfall s) {
  final l = L10n.of(context);
  final c = context.lamp;
  final bn = isBangla(context);
  final d = data.dayOf(s.date);
  return LumaSheet.show<void>(
    context: context,
    title: l.cashWhyTitle(formatDay(s.date, bangla: bn)),
    fitContent: true,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          serverWords(s.cause, bangla: bn),
          style: LaMPType.body.copyWith(color: c.ink),
        ),
        if (d != null) ...[
          const SizedBox(height: Gap.md),
          LampKeyValue(
            label: l.cashDayIn,
            value: formatMoney(d.inflow, bangla: bn),
            mono: true,
          ),
          LampKeyValue(
            label: l.cashDayOut,
            value: formatMoney(d.outflow, bangla: bn),
            mono: true,
          ),
          for (final i in d.items)
            LampKeyValue(
              label: serverWords(i.label, bangla: bn),
              value: formatMoney(i.amount, bangla: bn),
              mono: true,
            ),
          const SizedBox(height: Gap.sm),
          Text(
            l.cashLeftShort(formatMoney(d.balance, bangla: bn)),
            style: LaMPType.sub.copyWith(color: d.short ? c.dispute : c.ink),
          ),
        ],
        const SizedBox(height: Gap.lg),
        ElevatedButton(
          key: const ValueKey('cash-plan'),
          onPressed: () {
            Navigator.of(sheet).pop();
            context.go('/plan');
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.cashSeePlan),
        ),
      ],
    ),
  );
}
