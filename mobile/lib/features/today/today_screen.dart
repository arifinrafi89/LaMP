import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'today_controller.dart';
import 'today_models.dart';

/// Today (plan 5.2): one main action, the one thing to do next, then the
/// day's figures. Free on every plan.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    return ChangeNotifierProvider(
      create: (context) => TodayController(context.read<ApiClient>(), pid)..load(),
      child: const _TodayView(),
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final today = context.watch<TodayController>();
    final summary = today.summary;
    final problem = today.problem;

    final Widget body;
    if (summary == null && problem != null) {
      body = _Failed(problem: problem, onRetry: today.load);
    } else if (summary == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [LampSkeletonCard(lines: 3), SizedBox(height: Gap.md), LampSkeletonCard()],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: today.load,
        child: _Figures(summary: summary, problem: problem),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(l.tabToday)), body: body);
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.summary, required this.problem});

  final TodaySummary summary;
  final ApiProblem? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final bn = isBangla(context);
    String money(double v) => formatMoney(v, bangla: bn);
    String day(DateTime d) => formatDay(d, bangla: bn);
    final next = summary.nextProblem;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Text(l.todayAsOf(day(summary.asOf)), style: LaMPType.caption.copyWith(color: c.inkFaint)),
        if (problem != null) ...[
          const SizedBox(height: Gap.xs),
          Text(problemMessage(l, problem!), style: LaMPType.caption.copyWith(color: c.pending)),
        ],
        const SizedBox(height: Gap.md),
        _OneThingCard(oneThing: summary.oneThing),
        if (next != null) ...[
          const SizedBox(height: Gap.md),
          LampCard(
            background: c.pendingSoft,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: c.pending),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    next.kind == 'shortfall'
                        ? l.todayShortOn(money(next.amount), day(next.date))
                        : l.todayProblemOn(day(next.date)),
                    style: LaMPType.sub.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        LampCard(
          child: LampStatRow(
            children: [
              LampStat(label: l.todayCashNow, value: money(summary.cashNow)),
              LampStat(
                label: l.todayExpiring,
                value: money(summary.expiringValue),
                caption: summary.returnEligible > 0
                    ? l.todayCanGoBack(money(summary.returnEligible))
                    : null,
              ),
              LampStat(
                label: l.todayApprovals,
                value: formatCount(summary.approvalsWaiting, bangla: bn),
              ),
            ],
          ),
        ),
        if (summary.alerts.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: l.todayAlerts),
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final a in summary.alerts)
                  LampRow(
                    icon: a.severity == 'critical'
                        ? Icons.error_outline
                        : a.severity == 'warning'
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline,
                    iconColor: a.severity == 'info' ? c.inkMuted : c.pending,
                    // The server sends these in English; only digits change.
                    title: bn ? bnNumbers(a.title) : a.title,
                    subtitle: bn ? bnNumbers(a.detail) : a.detail,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The screen's one main action.
class _OneThingCard extends StatelessWidget {
  const _OneThingCard({required this.oneThing});

  final OneThing? oneThing;

  static (String Function(L10n), String)? _target(String kind) => switch (kind) {
        'approve' => ((l) => l.oneApprove, '/approvals'),
        'return_stock' => ((l) => l.oneReturn, '/stock'),
        'scan_bill' => ((l) => l.oneScan, '/scan'),
        'finish_setup' => ((l) => l.oneSetup, '/setup'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    final target = oneThing == null ? null : _target(oneThing!.kind);
    if (target == null) {
      return LampCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: c.inkMuted),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(l.oneNothing, style: LaMPType.sub.copyWith(color: c.ink))),
          ],
        ),
      );
    }
    final (title, path) = target;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.todayOneThing, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          Text(title(l), style: LaMPType.head.copyWith(color: c.ink)),
          const SizedBox(height: Gap.md),
          ElevatedButton(
            key: const ValueKey('one-thing'),
            onPressed: () => context.go(path),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.todayOpen),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.problem, required this.onRetry});

  final ApiProblem problem;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    final l = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(problem.code == ApiProblem.offline ? Icons.cloud_off_outlined : Icons.error_outline,
                size: IconSize.xl, color: c.inkMuted),
            const SizedBox(height: Gap.md),
            Text(problemMessage(l, problem),
                textAlign: TextAlign.center, style: LaMPType.body.copyWith(color: c.ink)),
            const SizedBox(height: Gap.lg),
            OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}
