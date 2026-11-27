import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/design/luma_toast.dart';
import '../../core/l10n/digits.dart';
import '../../core/offline/cache_store.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_sync_pip.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../approvals/approvals_controller.dart';
import '../plus/plus_gate.dart';
import 'plan_controller.dart';
import 'plan_models.dart';

/// Plan (plan 5.2, Plus): how to cover the next short day. One main action:
/// send the steps to Approvals, where the owner approves each one.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return PlusGate(
      title: l.navPlan,
      what: l.planWhat,
      icon: Icons.event_note_outlined,
      allowed: (e) => e.plan,
      child: ChangeNotifierProvider(
        create: (context) => PlanController(
          context.read<ApiClient>(),
          context.read<CacheStore>(),
          context.read<SessionController>().pharmacy!.id,
          refreshOn: context.read<ShopChanges>(),
        )..load(),
        child: const _PlanView(),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final plan = context.watch<PlanController>();
    final data = plan.plan;
    final problem = plan.problem;

    final Widget body;
    if (data == null && problem?.code == 'plus_required') {
      body = PlusLocked(title: l.navPlan, what: l.planWhat, icon: Icons.event_note_outlined);
    } else if (data == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: plan.load);
    } else if (data == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          LampSkeletonCard(lines: 2),
          SizedBox(height: Gap.md),
          LampSkeletonCard(lines: 4),
        ],
      );
    } else if (data.need.amount <= 0 && data.steps.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [LampEmpty(icon: Icons.check_circle_outline, title: l.planNothingTitle, message: l.planNothingBody)],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: plan.load,
        child: _Plan(data: data, controller: plan),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navPlan)),
      body: body,
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.data, required this.controller});

  final MoneyPlan data;
  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final need = data.need;
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
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LampStat(
                  label: l.planNeedTitle(formatDay(need.neededBy, bangla: bn)),
                  value: formatMoney(need.amount, bangla: bn),
                ),
                if (need.explain.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('plan-explain'),
                      onPressed: () => _explain(context, need),
                      child: Text(l.planHowWorked),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          LampSectionHeader(title: l.planSteps),
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in data.steps.indexed) _StepRow(n: i + 1, step: s),
                const SizedBox(height: Gap.sm),
                Text(
                  l.planCosts(formatMoney(data.totalCost, bangla: bn)),
                  style: LaMPType.sub.copyWith(color: c.ink),
                ),
                if (data.naiveCost > data.totalCost)
                  Text(
                    l.planBorrowAll(formatMoney(data.naiveCost, bangla: bn)),
                    style: LaMPType.caption.copyWith(color: c.inkMuted),
                  ),
                if (data.fallbacks.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Text(l.planLoanNote, style: LaMPType.caption.copyWith(color: c.inkMuted)),
                ],
                const SizedBox(height: Gap.md),
                _Send(plan: data),
              ],
            ),
          ),
          if (data.options.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.planOtherWays),
            for (final o in data.options) ...[_OptionCard(option: o), const SizedBox(height: Gap.sm)],
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.n, required this.step});

  final int n;
  final PlanStep step;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final s = step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: c.surfaceAlt,
            child: Text(
              formatCount(n, bangla: bn),
              style: LaMPType.caption.copyWith(color: c.ink),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serverWords(s.label, bangla: bn),
                  style: LaMPType.body.copyWith(color: c.ink),
                ),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LampChip(
                      label: s.fallbackFor == null ? l.planStepNow : l.planStepIf(formatDay(s.when, bangla: bn)),
                      tone: s.fallbackFor == null ? LampTone.brand : LampTone.neutral,
                    ),
                    Text(
                      formatMoney(s.amount, bangla: bn),
                      style: LaMPType.monoCaption.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
                if (s.kind == 'trim_order')
                  TextButton(
                    key: const ValueKey('plan-trim'),
                    onPressed: () => showTrim(context),
                    child: Text(l.planSeeOrder),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Send the plan to Approvals, or say it is already waiting there.
class _Send extends StatefulWidget {
  const _Send({required this.plan});

  final MoneyPlan plan;

  @override
  State<_Send> createState() => _SendState();
}

class _SendState extends State<_Send> {
  bool _busy = false;

  Future<void> _send() async {
    final l = L10n.of(context);
    setState(() => _busy = true);
    try {
      await context.read<MoneyActions>().proposeAll(widget.plan.toPropose);
      if (mounted) context.go('/approvals');
    } on ApiProblem catch (p) {
      if (mounted) LumaToast.show(context, problemMessage(l, p), tone: LumaToastTone.pending);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final kinds = {for (final s in widget.plan.toPropose) s.kind};
    final list = context.watch<ApprovalsController>().actions;
    final waiting =
        list?.items.any((a) => kinds.contains(a.kind) && (a.status == 'proposed' || a.status == 'approved')) ?? false;
    if (kinds.isEmpty) return const SizedBox.shrink();
    if (waiting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.planSent, style: LaMPType.body.copyWith(color: c.ink)),
          const SizedBox(height: Gap.sm),
          OutlinedButton(
            key: const ValueKey('plan-open-approvals'),
            onPressed: () => context.go('/approvals'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.planOpenApprovals),
          ),
        ],
      );
    }
    return ElevatedButton(
      key: const ValueKey('plan-send'),
      onPressed: _busy ? null : _send,
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: _busy ? const LampBusy() : Text(l.planSend),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option});

  final CoverOption option;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final o = option;
    final cost = switch (o.costBdt) {
      null => null,
      0.0 => l.planFree,
      final double v => [
        l.planCost(formatMoney(v, bangla: bn)),
        if (o.aprPct != null) l.planApr(formatPct(o.aprPct!, bangla: bn)),
      ].join(' · '),
    };
    final faint = o.eligible ? c.ink : c.inkFaint;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            serverWords(o.label, bangla: bn),
            style: LaMPType.sub.copyWith(color: faint),
          ),
          Text(
            [serverWords(o.provider, bangla: bn), if (o.speed.isNotEmpty) serverWords(o.speed, bangla: bn)].join(' · '),
            style: LaMPType.caption.copyWith(color: c.inkMuted),
          ),
          if (o.reason.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              serverWords(o.reason, bangla: bn),
              style: LaMPType.body.copyWith(color: c.inkMuted),
            ),
          ],
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!o.eligible)
                LampChip(label: l.planNotOpen)
              else
                LampChip(
                  label: o.certain ? l.planSure : l.planNotSure,
                  tone: o.certain ? LampTone.verified : LampTone.pending,
                ),
              if (cost != null) Text(cost, style: LaMPType.monoCaption.copyWith(color: faint)),
            ],
          ),
        ],
      ),
    );
  }
}

/// How the figure to cover was worked out, row by row, as the server sent it.
Future<void> _explain(BuildContext context, Need need) {
  final l = L10n.of(context);
  final c = context.lamp;
  final bn = isBangla(context);
  return LumaSheet.show<void>(
    context: context,
    title: l.planHowWorked,
    fitContent: true,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in need.explain)
          LampKeyValue(
            label: serverWords(r.label, bangla: bn),
            value: switch (r.op) {
              '-' => '− ${formatMoney(r.amount, bangla: bn)}',
              '+' => '+ ${formatMoney(r.amount, bangla: bn)}',
              _ => formatMoney(r.amount, bangla: bn),
            },
            valueColor: r.op == '=' ? c.ink : null,
            mono: true,
          ),
      ],
    ),
  );
}

/// What to order fewer of, from each open order.
Future<void> showTrim(BuildContext context) {
  final l = L10n.of(context);
  final actions = context.read<MoneyActions>();
  return LumaSheet.show<void>(
    context: context,
    title: l.kindTrimOrder,
    builder: (_) => _TrimSheet(actions: actions),
  );
}

class _TrimSheet extends StatefulWidget {
  const _TrimSheet({required this.actions});

  final MoneyActions actions;

  @override
  State<_TrimSheet> createState() => _TrimSheetState();
}

class _TrimSheetState extends State<_TrimSheet> {
  List<(Order, Trim)>? _trims;
  ApiProblem? _problem;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() => _problem = null);
    try {
      final orders = await widget.actions.orders();
      final trims = [for (final o in orders) (o, await widget.actions.trim(o.id))];
      if (mounted) setState(() => _trims = trims);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _problem = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    if (_problem != null) return LampFailed(problem: _problem!, onRetry: _read);
    final trims = _trims;
    if (trims == null) {
      return const Padding(
        padding: EdgeInsets.all(Gap.xl),
        child: Center(child: LampBusy(size: 28)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (o, t) in trims) ...[
          Text(
            '${serverWords(o.supplier, bangla: bn)} · ${formatDay(o.dueDate, bangla: bn)}',
            style: LaMPType.sub.copyWith(color: c.ink),
          ),
          if (t.cuts.isEmpty)
            Text(l.trimNone, style: LaMPType.body.copyWith(color: c.inkMuted))
          else ...[
            for (final cut in t.cuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Product names keep their own digits: "10 mg" (plan 5.4).
                    Text(cut.product, style: LaMPType.body.copyWith(color: c.ink)),
                    Text(
                      l.trimInstead(formatCount(cut.suggestedQty, bangla: bn), formatCount(cut.qty, bangla: bn)),
                      style: LaMPType.caption.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
              ),
            Text(
              l.trimSaving(formatMoney(t.saving, bangla: bn)),
              style: LaMPType.sub.copyWith(color: c.verified),
            ),
          ],
          const SizedBox(height: Gap.md),
        ],
      ],
    );
  }
}
