import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_failed.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import 'customers_controller.dart';
import 'customers_models.dart';
import 'share_text.dart';

/// The join text, big enough to read out across a counter, with Share and
/// Copy. Its letters and digits stay English in both languages (plan 5.4).
class JoinBox extends StatelessWidget {
  const JoinBox({super.key, required this.join});

  final JoinText join;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final message = l.joinShareText(join.text, join.to);
    return LampCard(
      background: c.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.joinHow(join.to), style: LaMPType.body.copyWith(color: c.ink)),
          const SizedBox(height: Gap.sm),
          SelectableText(
            join.text,
            key: const ValueKey('join-text'),
            style: LaMPType.displayFigure.copyWith(color: c.ink),
          ),
          const SizedBox(height: Gap.xs),
          Text(l.joinWriteOnBill, style: LaMPType.caption.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('join-share'),
                onPressed: () => context.read<ShareText>()(message),
                icon: const Icon(Icons.share_outlined),
                label: Text(l.joinShare),
              ),
              TextButton.icon(
                key: const ValueKey('join-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (context.mounted) LumaToast.show(context, l.joinCopied, icon: Icons.check);
                },
                icon: const Icon(Icons.copy),
                label: Text(l.joinCopy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sheet's Save: busy while it runs, its problem in plain words below.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saveKey, required this.label, required this.busy, required this.onSave, this.error});

  final String saveKey;
  final String label;
  final bool busy;
  final VoidCallback? onSave;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LampErrorText(error),
        const SizedBox(height: Gap.md),
        ElevatedButton(
          key: ValueKey(saveKey),
          onPressed: busy ? null : onSave,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: busy ? const LampBusy() : Text(label),
        ),
      ],
    );
  }
}

/// An amount typed in either language, above 0; null with the reason.
(double?, String?) _readAmount(L10n l, String typed) {
  final a = parseAmount(typed);
  if (a == null) return (null, l.fieldBadAmount);
  if (a <= 0) return (null, l.moneyAboveZero);
  return (a, null);
}

class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.dayKey,
    required this.label,
    required this.day,
    required this.first,
    required this.last,
    required this.onPicked,
  });

  final String dayKey;
  final String label;
  final DateTime day;
  final DateTime first;
  final DateTime last;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: LaMPType.caption.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.xs),
        OutlinedButton.icon(
          key: ValueKey(dayKey),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
          icon: const Icon(Icons.event_outlined),
          label: Text(formatDay(day, bangla: isBangla(context))),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: day, firstDate: first, lastDate: last);
            if (picked != null) onPicked(picked);
          },
        ),
      ],
    );
  }
}

/* ---------------------------------------------------------------------------- */
/* Add a customer                                                               */
/* ---------------------------------------------------------------------------- */

/// The amount owed and since when; then the new card opens with its join text.
Future<void> addCustomer(BuildContext context) async {
  final actions = context.read<CustomerActions>();
  final made = await LumaSheet.show<CustomerCreated>(
    context: context,
    title: L10n.of(context).customersAdd,
    fitContent: true,
    builder: (_) => _AddSheet(actions: actions),
  );
  if (made != null && context.mounted) context.go('/customers/${made.code}?added=1');
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.actions});

  final CustomerActions actions;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _amount = TextEditingController();
  late DateTime _since = dhakaToday();

  /// One key for this sheet: Add again after a failure can't make two cards.
  final _key = newUuid();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    final (amount, why) = _readAmount(l, _amount.text);
    if (amount == null) return setState(() => _error = why);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final made = await widget.actions.add(amount: amount, since: _since, key: _key);
      if (mounted) Navigator.of(context).pop(made);
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
    final today = dhakaToday();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.addNoNames, style: LaMPType.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.md),
        TextField(
          key: const ValueKey('add-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l.addOwes, prefixText: '৳ '),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: Gap.md),
        _DayButton(
          dayKey: 'add-since',
          label: l.addSince,
          day: _since,
          first: DateTime(today.year - 2),
          last: today,
          onPicked: (d) => setState(() => _since = d),
        ),
        _SaveBar(saveKey: 'add-save', label: l.addSave, busy: _busy, onSave: _save, error: _error),
      ],
    );
  }
}

/* ---------------------------------------------------------------------------- */
/* A payment, or a sale on credit                                               */
/* ---------------------------------------------------------------------------- */

const _methods = ['cash', 'bkash', 'nagad', 'other'];

Future<void> recordMoney(BuildContext context, Customer cu, {required bool payment}) async {
  final l = L10n.of(context);
  final bn = isBangla(context);
  final actions = context.read<CustomerActions>();
  final owes = await LumaSheet.show<double>(
    context: context,
    title: payment ? l.customerRecordPayment : l.customerRecordSale,
    subtitle: cu.label,
    fitContent: true,
    builder: (_) => _MoneySheet(actions: actions, customer: cu, payment: payment),
  );
  if (owes != null && context.mounted) {
    final money = formatMoney(owes, bangla: bn);
    LumaToast.show(
      context,
      payment ? l.paymentSaved(money) : l.saleSaved(money),
      icon: Icons.check,
      tone: LumaToastTone.verified,
    );
  }
}

class _MoneySheet extends StatefulWidget {
  const _MoneySheet({required this.actions, required this.customer, required this.payment});

  final CustomerActions actions;
  final Customer customer;
  final bool payment;

  @override
  State<_MoneySheet> createState() => _MoneySheetState();
}

class _MoneySheetState extends State<_MoneySheet> {
  final _amount = TextEditingController();
  late DateTime _on = dhakaToday();
  String _method = 'cash';
  final _key = newUuid();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    final (amount, why) = _readAmount(l, _amount.text);
    if (amount == null) return setState(() => _error = why);
    setState(() {
      _busy = true;
      _error = null;
    });
    final code = widget.customer.code;
    try {
      final owes = widget.payment
          ? await widget.actions.payment(code, amount: amount, on: _on, method: _method, key: _key)
          : await widget.actions.sale(code, amount: amount, on: _on, key: _key);
      if (mounted) Navigator.of(context).pop(owes);
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _error = problemMessage(l, p));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _methodName(L10n l, String m) => switch (m) {
    'cash' => l.methodCash,
    'bkash' => l.methodBkash,
    'nagad' => l.methodNagad,
    _ => l.methodOther,
  };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final today = dhakaToday();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('money-amount'),
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l.moneyAmount, prefixText: '৳ '),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: Gap.md),
        _DayButton(
          dayKey: 'money-on',
          label: l.fieldDate,
          day: _on,
          first: widget.customer.since.isBefore(today) ? widget.customer.since : today,
          last: today,
          onPicked: (d) => setState(() => _on = d),
        ),
        if (widget.payment) ...[
          const SizedBox(height: Gap.md),
          Text(l.moneyMethod, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final m in _methods)
                ChoiceChip(
                  key: ValueKey('method-$m'),
                  label: Text(_methodName(l, m)),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
        ],
        _SaveBar(saveKey: 'money-save', label: l.fieldSave, busy: _busy, onSave: _save, error: _error),
      ],
    );
  }
}

/* ---------------------------------------------------------------------------- */
/* The plan                                                                     */
/* ---------------------------------------------------------------------------- */

/// The owner sets the plan with the family at the counter. The choices and
/// their amounts are the server's (D8).
Future<void> setPlan(BuildContext context, Customer cu) async {
  final l = L10n.of(context);
  final actions = context.read<CustomerActions>();
  final saved = await LumaSheet.show<bool>(
    context: context,
    title: l.planChoose,
    subtitle: cu.label,
    builder: (_) => _PlanSheet(actions: actions, customer: cu),
  );
  if (saved == true && context.mounted) {
    LumaToast.show(context, l.planSaved, icon: Icons.check, tone: LumaToastTone.verified);
  }
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.actions, required this.customer});

  final CustomerActions actions;
  final Customer customer;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  PlanChoices? _choices;
  ApiProblem? _readProblem;
  int? _parts;
  DateTime? _firstOn;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parts = widget.customer.plan?.parts;
    _read();
  }

  Future<void> _read() async {
    setState(() => _readProblem = null);
    try {
      final ch = await widget.actions.choices(widget.customer.code);
      if (!mounted) return;
      final kept = ch.plan?.firstOn ?? widget.customer.plan?.firstOn;
      setState(() {
        _choices = ch;
        _firstOn = kept != null && !kept.isBefore(ch.asOf) && !kept.isAfter(ch.latestFirstOn) ? kept : ch.asOf;
      });
    } on ApiProblem catch (p) {
      if (mounted) setState(() => _readProblem = p);
    }
  }

  Future<void> _save() async {
    final l = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.actions.setPlan(widget.customer.code, parts: _parts!, firstOn: _firstOn!);
      if (mounted) Navigator.of(context).pop(true);
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
    final ch = _choices;
    if (_readProblem != null) return LampFailed(problem: _readProblem!, onRetry: _read);
    if (ch == null) {
      return const Padding(
        padding: EdgeInsets.all(Gap.xl),
        child: Center(child: LampBusy(size: 28)),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in ch.options) ...[
          _Choice(
            key: ValueKey('plan-${o.parts}'),
            label: o.parts == 1
                ? l.planOneOf(formatMoney(o.partAmount, bangla: bn))
                : l.planPartsOf(formatCount(o.parts, bangla: bn), formatMoney(o.partAmount, bangla: bn)),
            selected: _parts == o.parts,
            onTap: () => setState(() => _parts = o.parts),
          ),
          const SizedBox(height: Gap.sm),
        ],
        Text(l.planLastPart, style: LaMPType.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.md),
        _DayButton(
          dayKey: 'plan-first-on',
          label: l.planFirstOn,
          day: _firstOn!,
          first: ch.asOf,
          last: ch.latestFirstOn,
          onPicked: (d) => setState(() => _firstOn = d),
        ),
        _SaveBar(
          saveKey: 'plan-save',
          label: l.planSave,
          busy: _busy,
          onSave: _parts == null ? null : _save,
          error: _error,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lamp;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.brandSoft : c.surfaceAlt,
        borderRadius: BorderRadius.circular(LaMPRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LaMPRadius.control),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? c.brand : c.inkMuted,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(label, style: LaMPType.body.copyWith(color: c.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------------------------------------------------------------------- */
/* SMS                                                                          */
/* ---------------------------------------------------------------------------- */

Future<void> remindNow(BuildContext context, Customer cu) async {
  final l = L10n.of(context);
  try {
    await context.read<CustomerActions>().remind(cu.code);
    if (context.mounted) LumaToast.show(context, l.smsReminded, icon: Icons.check, tone: LumaToastTone.verified);
  } on ApiProblem catch (p) {
    if (context.mounted) LumaToast.show(context, problemMessage(l, p), tone: LumaToastTone.pending);
  }
}

Future<void> stopSms(BuildContext context, Customer cu) async {
  final l = L10n.of(context);
  final actions = context.read<CustomerActions>();
  final yes = await LumaSheet.show<bool>(
    context: context,
    title: l.smsStop,
    fitContent: true,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.smsStopConfirm(cu.label), style: LaMPType.body.copyWith(color: sheet.lamp.ink)),
        const SizedBox(height: Gap.lg),
        ElevatedButton(
          key: const ValueKey('sms-stop-yes'),
          onPressed: () => Navigator.of(sheet).pop(true),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l.smsStop),
        ),
        TextButton(onPressed: () => Navigator.of(sheet).pop(false), child: Text(l.back)),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await actions.stopSms(cu.code);
    if (context.mounted) LumaToast.show(context, l.smsStopped, icon: Icons.check);
  } on ApiProblem catch (p) {
    if (context.mounted) LumaToast.show(context, problemMessage(l, p), tone: LumaToastTone.pending);
  }
}

/// Counter route only (plan 3.4 route 2): the owner reads the words aloud,
/// the family agrees, and the owner types their number.
Future<void> addFamilyNumber(BuildContext context, Customer cu) async {
  final l = L10n.of(context);
  final actions = context.read<CustomerActions>();
  await LumaSheet.show<void>(
    context: context,
    title: l.familyPhoneTitle,
    subtitle: cu.label,
    builder: (_) => _NumberSheet(actions: actions, customer: cu),
  );
}

class _NumberSheet extends StatefulWidget {
  const _NumberSheet({required this.actions, required this.customer});

  final CustomerActions actions;
  final Customer customer;

  @override
  State<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends State<_NumberSheet> {
  final _phone = TextEditingController();
  late String _language = isBangla(context) ? 'bn' : 'en';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _agreed() async {
    final l = L10n.of(context);
    final check = checkBanglalink(_phone.text);
    if (check.result != PhoneResult.ok) {
      return setState(() => _error = check.result == PhoneResult.notBanglalink ? l.errNotBanglalink : l.phoneInvalid);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.actions.addPhone(widget.customer.code, phone: check.e164!, language: _language);
      if (mounted) Navigator.of(context).pop();
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.consentReadAloud, style: LaMPType.caption.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.xs),
        LampCard(
          background: c.surfaceAlt,
          child: Text(l.consentWording, style: LaMPType.sub.copyWith(color: c.ink)),
        ),
        const SizedBox(height: Gap.md),
        TextField(
          key: const ValueKey('phone-input'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l.phoneLabel, hintText: '019…'),
        ),
        const SizedBox(height: Gap.md),
        Text(l.smsLanguage, style: LaMPType.caption.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.xs),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'bn',
              label: Text(l.languageBangla, key: const ValueKey('phone-lang-bn')),
            ),
            ButtonSegment(
              value: 'en',
              label: Text(l.languageEnglish, key: const ValueKey('phone-lang-en')),
            ),
          ],
          selected: {_language},
          onSelectionChanged: (s) => setState(() => _language = s.first),
        ),
        _SaveBar(saveKey: 'consent-agreed', label: l.consentAgreed, busy: _busy, onSave: _agreed, error: _error),
      ],
    );
  }
}
