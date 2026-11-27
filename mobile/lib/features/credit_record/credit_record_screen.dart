import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_toast.dart';
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
import '../customers/share_text.dart';
import 'credit_controller.dart';
import 'credit_models.dart';

/// Credit record (plan 3.7, BDT 10, on every plan): how the shop pays its
/// suppliers, for one lender. One main action: get my record.
class CreditRecordScreen extends StatelessWidget {
  const CreditRecordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pid = context.read<SessionController>().pharmacy!.id;
    final api = context.read<ApiClient>();
    final changes = context.read<ShopChanges>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => CreditRecordController(api, context.read<CacheStore>(), pid, refreshOn: changes)..load(),
        ),
        ChangeNotifierProvider(create: (_) => PurchaseController(api, pid, onPaid: changes.saved)),
        Provider(create: (_) => CreditActions(api, pid, onSaved: changes.saved)),
      ],
      child: const _CreditView(),
    );
  }
}

class _CreditView extends StatelessWidget {
  const _CreditView();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final rec = context.watch<CreditRecordController>();
    final data = rec.record;

    final Widget body;
    if (data == null && rec.problem != null) {
      body = LampFailed(problem: rec.problem!, onRetry: rec.load);
    } else if (data == null) {
      body = ListView(padding: const EdgeInsets.all(Gap.lg), children: const [LampSkeletonCard(lines: 3)]);
    } else {
      body = RefreshIndicator(
        onRefresh: rec.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rec.savedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: LampSyncPip(savedAt: rec.savedAt!, problem: rec.problem),
                ),
              LampCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.creditWhat, style: LaMPType.body.copyWith(color: c.inkMuted)),
                    const SizedBox(height: Gap.md),
                    Text(
                      data.billsTotal == 0
                          ? l.creditNoBills
                          : l.creditPreview(
                              formatCount(data.paidOnTime, bangla: bn),
                              formatCount(data.billsTotal, bangla: bn),
                              formatCount(data.months, bangla: bn),
                            ),
                      style: LaMPType.head.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              if (data.purchased) _Bought(record: data) else const _Buy(),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.navCreditRecord)),
      body: body,
    );
  }
}

/// Buying: the price, Banglalink's code, and the server's word on it.
class _Buy extends StatefulWidget {
  const _Buy();

  @override
  State<_Buy> createState() => _BuyState();
}

class _BuyState extends State<_Buy> {
  final _code = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _pay(PurchaseController p) {
    final code = readCode(_code.text);
    if (code == null) return setState(() => _codeError = L10n.of(context).otpBadCode);
    setState(() => _codeError = null);
    p.submit(code);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final p = context.watch<PurchaseController>();

    Widget buy({String? why}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (why != null) ...[Text(why, style: LaMPType.sub.copyWith(color: c.ink)), const SizedBox(height: Gap.xs)],
        // A refusal to start already says no money was taken (errChargeFailed).
        if ((p.stage == PurchaseStage.failed && p.problem == null) || p.stage == PurchaseStage.expired) ...[
          Text(
            p.stage == PurchaseStage.expired ? l.creditExpired : l.creditFailed,
            style: LaMPType.body.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: Gap.md),
        ],
        Text(l.creditBuyNote, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.md),
        ElevatedButton(
          key: const ValueKey('credit-buy'),
          onPressed: () {
            _code.clear();
            p.start();
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.creditBuy),
        ),
      ],
    );

    final Widget child = switch (p.stage) {
      PurchaseStage.idle => buy(),
      PurchaseStage.failed => buy(
        why: p.reason != null
            ? serverWords(p.reason!, bangla: bn)
            : p.problem == null
            ? null
            : problemMessage(l, p.problem!),
      ),
      PurchaseStage.expired => buy(),
      PurchaseStage.starting || PurchaseStage.checking => Row(
        children: [
          const LampBusy(),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(l.creditChecking, style: LaMPType.body.copyWith(color: c.ink)),
          ),
        ],
      ),
      PurchaseStage.code => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.codeTitle, style: LaMPType.sub.copyWith(color: c.ink)),
          Text(l.creditCodeBody, style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          LampCodeField(
            key: const ValueKey('credit-code'),
            controller: _code,
            label: l.codeTitle,
            onSubmitted: (_) => _pay(p),
          ),
          LampErrorText(
            _codeError ??
                (p.attemptsLeft != null
                    ? l.creditWrongCode(formatCount(p.attemptsLeft!, bangla: bn))
                    : p.problem == null
                    ? null
                    : problemMessage(l, p.problem!)),
          ),
          const SizedBox(height: Gap.md),
          ElevatedButton(
            key: const ValueKey('credit-pay'),
            onPressed: () => _pay(p),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.creditPay),
          ),
        ],
      ),
      PurchaseStage.waiting => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.creditWaiting, style: LaMPType.body.copyWith(color: c.ink)),
          const SizedBox(height: Gap.md),
          OutlinedButton(
            key: const ValueKey('credit-check'),
            onPressed: p.checkAgain,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(l.checkAgain),
          ),
        ],
      ),
      // The record reads again and opens as bought.
      PurchaseStage.paid => Text(l.creditPaid, style: LaMPType.head.copyWith(color: c.verified)),
    };
    return LampCard(child: child);
  }
}

/// Bought: the PDF, and one lender's link.
class _Bought extends StatefulWidget {
  const _Bought({required this.record});

  final CreditRecord record;

  @override
  State<_Bought> createState() => _BoughtState();
}

class _BoughtState extends State<_Bought> {
  final _lender = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _lender.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    final l = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _error = problemMessage(l, p));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final actions = context.read<CreditActions>();
    final link = widget.record.activeShare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_outlined, color: c.verified),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(l.creditPaid, style: LaMPType.head.copyWith(color: c.ink)),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              OutlinedButton.icon(
                key: const ValueKey('credit-pdf'),
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final share = context.read<ShareFile>();
                        final bytes = await actions.pdf();
                        await share(bytes, 'lamp-credit-record.pdf', 'application/pdf');
                      }),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(l.creditPdf),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        LampCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.creditShareTitle, style: LaMPType.sub.copyWith(color: c.ink)),
              Text(l.creditShareBody, style: LaMPType.caption.copyWith(color: c.inkMuted)),
              const SizedBox(height: Gap.md),
              if (link != null) ...[
                Text(l.creditLinkFor(link.lenderName), style: LaMPType.body.copyWith(color: c.ink)),
                SelectableText(link.url, style: LaMPType.monoCaption.copyWith(color: c.ink)),
                if (link.expiresAt != null)
                  Text(
                    l.creditLinkUntil(
                      formatDay(dhakaToday(link.expiresAt), bangla: bn),
                      formatCount(link.views, bangla: bn),
                    ),
                    style: LaMPType.caption.copyWith(color: c.inkMuted),
                  ),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('credit-link-share'),
                      onPressed: () => context.read<ShareText>()(link.url),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(l.joinShare),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link.url));
                        if (context.mounted) LumaToast.show(context, l.joinCopied, icon: Icons.check);
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(l.joinCopy),
                    ),
                    TextButton(
                      key: const ValueKey('credit-revoke'),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await actions.revoke(link.id);
                              if (context.mounted) LumaToast.show(context, l.creditRevoked, icon: Icons.check);
                            }),
                      child: Text(l.creditRevoke),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  key: const ValueKey('credit-lender'),
                  controller: _lender,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: l.creditLenderName, counterText: ''),
                ),
                const SizedBox(height: Gap.md),
                ElevatedButton(
                  key: const ValueKey('credit-make-link'),
                  onPressed: _busy
                      ? null
                      : () {
                          final name = _lender.text.trim();
                          if (name.isEmpty) return setState(() => _error = l.creditNameNeeded);
                          _run(() => actions.share(name));
                        },
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy ? const LampBusy() : Text(l.creditMakeLink),
                ),
              ],
              LampErrorText(_error),
            ],
          ),
        ),
      ],
    );
  }
}
