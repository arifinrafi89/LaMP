import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/locale_controller.dart';
import '../../core/state/shop_changes.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../plus/plus_gate.dart';
import 'ask_controller.dart';

/// Ask (plan 5.2, Plus): questions about the shop's money in the owner's own
/// words. One main action: ask a question.
class AskScreen extends StatelessWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return PlusGate(
      title: l.tabAsk,
      what: l.askWhat,
      icon: Icons.chat_bubble_outline,
      allowed: (e) => e.ask,
      child: ChangeNotifierProvider(
        create: (context) {
          final locale = context.read<LocaleController>();
          return AskController(
            context.read<ApiClient>(),
            language: () => locale.languageFor(null),
            onProposed: context.read<ShopChanges>().saved,
          );
        },
        child: const _AskView(),
      ),
    );
  }
}

/// What LaMP is looking up, in the owner's words.
String toolWords(L10n l, String name) => switch (name) {
  'get_accounts' => l.toolAccounts,
  'get_dues' => l.toolDues,
  'get_forecast' => l.toolForecast,
  'get_alerts' => l.toolAlerts,
  'get_expiry' => l.toolExpiry,
  'get_orders' => l.toolOrders,
  'get_trim' => l.toolTrim,
  'get_funding_plan' => l.toolPlan,
  'get_passport' => l.toolRecord,
  'share_plan' => l.toolMessage,
  'propose_action' => l.toolPropose,
  _ => l.askBusy,
};

class _AskView extends StatefulWidget {
  const _AskView();

  @override
  State<_AskView> createState() => _AskViewState();
}

class _AskViewState extends State<_AskView> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(AskController ask, String text) {
    if (text.trim().isEmpty || ask.busy) return;
    _input.clear();
    ask.ask(text);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final ask = context.watch<AskController>();
    final turns = ask.turns;
    final suggestions = [l.askSuggest1, l.askSuggest2, l.askSuggest3];
    return Scaffold(
      appBar: AppBar(title: Text(l.tabAsk)),
      body: Column(
        children: [
          Expanded(
            child: turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(Gap.lg),
                    children: [
                      LampEmpty(icon: Icons.chat_bubble_outline, title: l.askEmpty, message: l.askEmptyBody),
                      const SizedBox(height: Gap.md),
                      for (final (i, s) in suggestions.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.sm),
                          child: OutlinedButton(
                            key: ValueKey('ask-suggest-$i'),
                            onPressed: () => _send(ask, s),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Text(s),
                          ),
                        ),
                    ],
                  )
                // Newest at the bottom, and the list stays there as it grows.
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(Gap.lg),
                    children: [
                      for (final t in turns.reversed) ...[
                        t.mine ? _Question(turn: t) : _Answer(turn: t, onAgain: ask.askAgain),
                        const SizedBox(height: Gap.md),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.line)),
              ),
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ask-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(hintText: l.askPlaceholder),
                      onSubmitted: (v) => _send(ask, v),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  IconButton.filled(
                    key: const ValueKey('ask-send'),
                    tooltip: l.askSend,
                    onPressed: ask.busy ? null : () => _send(ask, _input.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.turn});

  final AskTurn turn;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: LampCard(
          background: c.brandSoft,
          child: Text(turn.text, style: LaMPType.body.copyWith(color: c.ink)),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.turn, required this.onAgain});

  final AskTurn turn;
  final Future<void> Function() onAgain;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final t = turn;

    Widget note(IconData icon, Color color, String words) => Padding(
      padding: const EdgeInsets.only(top: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(words, style: LaMPType.caption.copyWith(color: color)),
          ),
        ],
      ),
    );

    final failed = t.end == AskEnd.failed || t.end == AskEnd.lost;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Answers come back as "BDT 8,100"; in Bangla only the figures change.
          if (t.text.isNotEmpty)
            Text(
              serverWords(t.text, bangla: bn),
              style: LaMPType.body.copyWith(color: c.ink),
            ),
          if (t.end == AskEnd.streaming)
            Padding(
              padding: EdgeInsets.only(top: t.text.isEmpty ? 0 : Gap.sm),
              child: Row(
                children: [
                  const LampBusy(),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      t.tools.isEmpty ? l.askBusy : toolWords(l, t.tools.last),
                      style: LaMPType.caption.copyWith(color: c.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
          if (t.checked) note(Icons.verified_outlined, c.verified, l.askChecked),
          if (t.held) note(Icons.shield_outlined, c.pending, l.askHeld),
          if (t.proposed && t.end == AskEnd.done) ...[
            note(Icons.task_alt, c.ink, l.askProposed),
            const SizedBox(height: Gap.sm),
            OutlinedButton(
              key: const ValueKey('ask-approvals'),
              onPressed: () => context.go('/approvals'),
              child: Text(l.planOpenApprovals),
            ),
          ],
          if (failed) ...[
            note(
              t.end == AskEnd.lost ? Icons.wifi_off : Icons.error_outline,
              c.dispute,
              t.end == AskEnd.lost
                  ? l.askLost
                  : t.problem == null
                  ? l.askFailed
                  : problemMessage(l, t.problem!),
            ),
            const SizedBox(height: Gap.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(key: const ValueKey('ask-again'), onPressed: onAgain, child: Text(l.askAgain)),
            ),
          ],
        ],
      ),
    );
  }
}
