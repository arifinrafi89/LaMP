import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_sheet.dart';
import '../../core/l10n/digits.dart';
import '../../core/offline/cache_store.dart';
import '../../core/state/session_controller.dart';
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_code_field.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_sync_pip.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'plus_controller.dart';

/// LaMP Plus (plan 3.3, BDT 50 a month): the price in words, Agree, then
/// the code Banglalink sends. Cancel is always one tap and a confirmation.
class PlusScreen extends StatelessWidget {
  const PlusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    final api = context.read<ApiClient>();
    final changes = context.read<ShopChanges>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => PlusController(api, context.read<CacheStore>(), pid, refreshOn: changes)..load(),
        ),
        Provider(create: (_) => PlusActions(api, pid, onSaved: changes.saved)),
      ],
      child: const _PlusView(),
    );
  }
}

class _PlusView extends StatefulWidget {
  const _PlusView();

  @override
  State<_PlusView> createState() => _PlusViewState();
}

class _PlusViewState extends State<_PlusView> {
  final _code = TextEditingController();

  /// The answer to the owner's last tap, shown until they look again.
  PlusState? _latest;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<PlusState> Function() work) async {
    final l = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await work();
      if (mounted) setState(() => _latest = s);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _error = problemMessage(l, p));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAgain(PlusController c) async {
    setState(() => _latest = null);
    await c.load();
  }

  Future<void> _cancel(PlusActions actions) async {
    final l = L10n.of(context);
    final yes = await LumaSheet.show<bool>(
      context: context,
      title: l.plusCancel,
      fitContent: true,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.plusCancelConfirm, style: LaMPType.body.copyWith(color: sheet.lamp.ink)),
          const SizedBox(height: Gap.lg),
          ElevatedButton(
            key: const ValueKey('plus-cancel-yes'),
            onPressed: () => Navigator.of(sheet).pop(true),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.plusCancel),
          ),
          TextButton(onPressed: () => Navigator.of(sheet).pop(false), child: Text(l.back)),
        ],
      ),
    );
    if (yes == true && mounted) await _run(actions.cancel);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final ctrl = context.watch<PlusController>();
    final shown = _latest ?? ctrl.plus;
    final problem = ctrl.problem;

    final Widget body;
    if (shown == null && problem?.code == 'not_built') {
      // The Plus app isn't approved yet (plan 15.1): coming soon, not an error.
      body = ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampEmpty(icon: Icons.workspace_premium_outlined, title: l.plusComingSoon, message: l.plusComingSoonBody),
        ],
      );
    } else if (shown == null && problem != null) {
      body = LampFailed(problem: problem, onRetry: ctrl.load);
    } else if (shown == null) {
      body = ListView(padding: const EdgeInsets.all(Gap.lg), children: const [LampSkeletonCard(lines: 4)]);
    } else {
      body = RefreshIndicator(
        onRefresh: () => _checkAgain(ctrl),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ctrl.savedAt != null && _latest == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: LampSyncPip(savedAt: ctrl.savedAt!, problem: ctrl.problem),
                ),
              _state(context, shown, ctrl),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navPlus)),
      body: body,
    );
  }

  Widget _state(BuildContext context, PlusState s, PlusController ctrl) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final actions = context.read<PlusActions>();

    Widget button(String key, String label, VoidCallback onTap, {bool outlined = false}) {
      final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)));
      final child = _busy ? const LampBusy() : Text(label);
      return outlined
          ? OutlinedButton(key: ValueKey(key), onPressed: _busy ? null : onTap, style: style, child: child)
          : ElevatedButton(key: ValueKey(key), onPressed: _busy ? null : onTap, style: style, child: child);
    }

    final List<Widget> rows;
    switch (s.status) {
      case PlusStatus.none || PlusStatus.stopped:
        rows = [
          if (s.status == PlusStatus.stopped) ...[
            Text(l.plusStopped, style: LaMPType.sub.copyWith(color: c.ink)),
            const SizedBox(height: Gap.md),
          ],
          Text(l.plusIntro, style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.sm),
          for (final (icon, what) in [
            (Icons.payments_outlined, l.navCash),
            (Icons.event_note_outlined, l.navPlan),
            (Icons.task_alt, l.navApprovals),
            (Icons.chat_bubble_outline, l.tabAsk),
            (Icons.document_scanner_outlined, l.plusScans),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Row(
                children: [
                  Icon(icon, color: c.brand),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(what, style: LaMPType.body.copyWith(color: c.ink)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.md),
          LampCard(
            background: c.surfaceAlt,
            child: Text(l.plusConsent, style: LaMPType.sub.copyWith(color: c.ink)),
          ),
          const SizedBox(height: Gap.md),
          button('plus-agree', l.plusAgree, () => _run(actions.subscribe)),
        ];
      case PlusStatus.otpSent:
        rows = [
          Text(l.codeTitle, style: LaMPType.sub.copyWith(color: c.ink)),
          Text(l.plusCodeBody, style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          LampCodeField(key: const ValueKey('plus-code'), controller: _code, label: l.codeTitle),
          const SizedBox(height: Gap.md),
          button('plus-confirm', l.plusStart, () {
            final code = readCode(_code.text);
            if (code == null) return setState(() => _error = l.otpBadCode);
            _run(() => actions.confirm(code));
          }),
        ];
      case PlusStatus.pending:
        rows = [
          Text(l.plusPending, style: LaMPType.sub.copyWith(color: c.ink)),
          const SizedBox(height: Gap.md),
          button('plus-check', l.checkAgain, () => _checkAgain(ctrl), outlined: true),
        ];
      case PlusStatus.active || PlusStatus.blocked:
        rows = [
          Row(
            children: [
              Icon(
                s.status == PlusStatus.active ? Icons.workspace_premium : Icons.warning_amber_outlined,
                color: s.status == PlusStatus.active ? c.verified : c.pending,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(l.plusActive, style: LaMPType.head.copyWith(color: c.ink)),
              ),
            ],
          ),
          if (s.renewsOn != null && s.status == PlusStatus.active)
            Text(
              l.plusRenews(formatDay(s.renewsOn!, bangla: bn)),
              style: LaMPType.body.copyWith(color: c.inkMuted),
            ),
          if (s.status == PlusStatus.blocked) ...[
            const SizedBox(height: Gap.sm),
            Text(l.plusBlocked, style: LaMPType.body.copyWith(color: c.ink)),
          ],
          const SizedBox(height: Gap.lg),
          button('plus-cancel', l.plusCancel, () => _cancel(actions), outlined: true),
        ];
    }
    return LampCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...rows, LampErrorText(_error)]),
    );
  }
}
