import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/auth/phone_number.dart';
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
import '../customers/share_text.dart';
import '../plus/plus_gate.dart';
import 'approvals_controller.dart';
import 'approvals_models.dart';

/// Approvals (plan 5.2, Plus): nothing LaMP suggests happens until the owner
/// says yes. One main action: approve a step.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return PlusGate(
      title: l.navApprovals,
      what: l.approvalsWhat,
      icon: Icons.task_alt,
      allowed: (e) => e.approvals,
      child: ChangeNotifierProvider(
        create: (context) => PauseController(
          context.read<ApiClient>(),
          context.read<CacheStore>(),
          context.read<SessionController>().pharmacy!.id,
          refreshOn: context.read<ShopChanges>(),
        )..load(),
        child: const _ApprovalsView(),
      ),
    );
  }
}

class _ApprovalsView extends StatelessWidget {
  const _ApprovalsView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final list = context.watch<ApprovalsController>();
    final data = list.actions;
    final problem = list.problem;

    final Widget body;
    if (data == null && problem?.code == 'plus_required') {
      body = PlusLocked(title: l.navApprovals, what: l.approvalsWhat, icon: Icons.task_alt);
    } else if (data == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: list.load);
    } else if (data == null) {
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: const [
          LampSkeletonCard(lines: 2),
          SizedBox(height: Gap.md),
          LampSkeletonCard(lines: 3),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: list.load,
        child: _List(data: data, controller: list),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navApprovals)),
      body: body,
    );
  }
}

String kindName(L10n l, String kind) => switch (kind) {
  'trim_order' => l.kindTrimOrder,
  'extension_request' => l.kindExtension,
  'return_claim' => l.kindReturn,
  'set_aside' => l.kindSetAside,
  'loan_application' => l.kindLoan,
  _ => l.kindOther,
};

Widget _statusChip(L10n l, String status) => switch (status) {
  'executed' => LampChip(label: l.statusExecuted, tone: LampTone.verified),
  'approved' => LampChip(label: l.statusApproved, tone: LampTone.verified),
  'failed' => LampChip(label: l.statusFailed, tone: LampTone.dispute),
  _ => LampChip(label: l.statusRejected),
};

class _List extends StatelessWidget {
  const _List({required this.data, required this.controller});

  final ActionList data;
  final ApprovalsController controller;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final waiting = data.waiting;
    final done = data.done;
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
          if (waiting.isEmpty)
            LampEmpty(icon: Icons.task_alt, title: l.approvalsNone, message: l.approvalsNoneBody)
          else ...[
            LampSectionHeader(title: l.approvalsWaiting),
            for (final a in waiting) ...[_Waiting(key: ValueKey(a.id), action: a), const SizedBox(height: Gap.sm)],
          ],
          const SizedBox(height: Gap.md),
          const _PauseCard(),
          if (done.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            LampSectionHeader(title: l.approvalsDone),
            LampCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in done)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kindName(l, a.kind), style: LaMPType.sub.copyWith(color: c.ink)),
                                if ((a.resultSummary ?? a.summary) case final words?)
                                  Text(
                                    serverWords(words, bangla: bn),
                                    style: LaMPType.caption.copyWith(color: c.inkMuted),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Gap.sm),
                          _statusChip(l, a.status),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One step waiting for the owner: what it is, who suggested it, Approve or
/// Not now.
class _Waiting extends StatefulWidget {
  const _Waiting({super.key, required this.action});

  final LampAction action;

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _busy = false;

  Future<void> _decide({required bool yes}) async {
    final l = L10n.of(context);
    final actions = context.read<MoneyActions>();
    setState(() => _busy = true);
    try {
      final a = widget.action;
      if (!yes) {
        await actions.reject(a.id);
        if (mounted) LumaToast.show(context, l.rejectedToast);
        return;
      }
      final done = await actions.approve(a.id);
      if (!mounted) return;
      final message = done.shareText(bangla: isBangla(context));
      if (message != null) {
        await showSupplierMessage(context, message, done.supplierPhone);
      } else {
        LumaToast.show(context, l.approvedToast, icon: Icons.check, tone: LumaToastTone.verified);
      }
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
    final bn = isBangla(context);
    final a = widget.action;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kindName(l, a.kind), style: LaMPType.sub.copyWith(color: c.ink)),
              ),
              LampChip(label: a.byLamp ? l.byLamp : l.byYou, tone: a.byLamp ? LampTone.brand : LampTone.neutral),
            ],
          ),
          if (a.summary != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              serverWords(a.summary!, bangla: bn),
              style: LaMPType.body.copyWith(color: c.ink),
            ),
          ],
          if (a.amount != null)
            Text(
              formatMoney(a.amount!, bangla: bn),
              style: LaMPType.monoBody.copyWith(color: c.inkMuted),
            ),
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  key: ValueKey('approve-${a.id}'),
                  onPressed: _busy ? null : () => _decide(yes: true),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy ? const LampBusy() : Text(l.approve),
                ),
              ),
              const SizedBox(width: Gap.sm),
              TextButton(
                key: ValueKey('reject-${a.id}'),
                onPressed: _busy ? null : () => _decide(yes: false),
                child: Text(l.notNow),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final paused = context.watch<PauseController>().pause?.paused ?? false;
    return LampCard(
      padding: EdgeInsets.zero,
      // Its own Material, so the tile's ink shows on the card.
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          key: const ValueKey('pause-switch'),
          value: paused,
          title: Text(l.pauseTitle, style: LaMPType.sub.copyWith(color: c.ink)),
          subtitle: Text(l.pauseBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
          onChanged: (v) async {
            try {
              await context.read<MoneyActions>().setPause(v);
              if (context.mounted) LumaToast.show(context, v ? l.pausedToast : l.resumedToast, icon: Icons.check);
            } on ApiProblem catch (p) {
              if (context.mounted) LumaToast.show(context, problemMessage(l, p), tone: LumaToastTone.pending);
            }
          },
        ),
      ),
    );
  }
}

/// The message for the supplier after "more days" is approved. LaMP never
/// sends it itself: the owner shares it or reads it out (plan 2.2).
Future<void> showSupplierMessage(BuildContext context, String message, String? phone) {
  final l = L10n.of(context);
  final c = context.lamp;
  // Read now: the card that opened this goes once the list reads again.
  final share = context.read<ShareText>();
  return LumaSheet.show<void>(
    context: context,
    title: l.shareToSupplier,
    fitContent: true,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.shareToSupplierBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.md),
        LampCard(
          background: c.surfaceAlt,
          child: SelectableText(message, style: LaMPType.body.copyWith(color: c.ink)),
        ),
        if (phone != null) ...[
          const SizedBox(height: Gap.sm),
          Text(l.supplierNumber(formatPhone(phone)), style: LaMPType.monoCaption.copyWith(color: c.inkMuted)),
        ],
        const SizedBox(height: Gap.lg),
        ElevatedButton.icon(
          key: const ValueKey('supplier-share'),
          onPressed: () => share(message),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.share_outlined),
          label: Text(l.joinShare),
        ),
        TextButton(onPressed: () => Navigator.of(sheet).pop(), child: Text(l.back)),
      ],
    ),
  );
}
