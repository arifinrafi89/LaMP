import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/constants/palette.dart';
import '../../core/constants/typography.dart';
import '../../core/design/luma_toast.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/locale_controller.dart';
import '../../core/state/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_skeleton.dart';
import '../../widgets/ui/lamp_ui.dart';
import '../customers/customers_models.dart';

/// "gl 7kqm 4xpa" and "GL-7KQM-4XPA" are the same code, read the way the
/// server's `normalize_code` reads it.
String normaliseCode(String typed) {
  final s = typed.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  return s.length == 10 ? '${s.substring(0, 2)}-${s.substring(2, 6)}-${s.substring(6)}' : s;
}

/// One family's card (`GET /cards/{code}`). Amounts only: no names, no
/// medicines.
class FamilyCard {
  const FamilyCard({
    required this.pharmacy,
    required this.city,
    required this.label,
    required this.since,
    required this.daysOutstanding,
    required this.choices,
  });

  final String pharmacy;
  final String city;
  final String label;
  final DateTime since;
  final int daysOutstanding;

  /// What is owed, the ways to pay and the plan, as the server splits them.
  final PlanChoices choices;

  factory FamilyCard.fromJson(Map<String, dynamic> j) => FamilyCard(
    pharmacy: j['pharmacy_name'] as String,
    city: (j['city'] as String?) ?? '',
    label: j['label'] as String,
    since: DateTime.parse(j['since'] as String),
    daysOutstanding: j['days_outstanding'] as int,
    choices: PlanChoices.fromJson(j),
  );
}

/// Read fresh each time and never kept on the phone: a family may use a
/// shared phone or a borrowed browser.
class FamilyCardController extends ChangeNotifier {
  FamilyCardController(this._api, this.code);

  final ApiClient _api;
  final String code;

  FamilyCard? _card;
  FamilyCard? get card => _card;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _problem = null;
    _notify();
    try {
      _card = FamilyCard.fromJson(await _api.get('/cards/$code') as Map<String, dynamic>);
    } on ApiProblem catch (p) {
      _problem = p;
    } on Object catch (e) {
      debugPrint('LaMP card: $e');
      _problem = const ApiProblem('unknown');
    }
    _notify();
  }

  /// A plan is a promise, not a payment. The server sends the plan SMS if
  /// this card's family has SMS on.
  Future<void> promise(int parts, DateTime firstOn) async {
    final j = await _api.post('/cards/$code/plan', {'parts': parts, 'first_on': apiDate(firstOn)});
    _card = FamilyCard.fromJson(j as Map<String, dynamic>);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The family's pages have no bottom bar: LaMP's name, and a way to switch
/// language, since a family may read either.
class _FamilyFrame extends StatelessWidget {
  const _FamilyFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final locale = context.read<LocaleController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          TextButton(
            key: const ValueKey('me-lang'),
            onPressed: () => locale.set(Locale(isBangla(context) ? 'en' : 'bn')),
            child: Text(l.meLanguageOther),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  const SizedBox(height: Gap.xl),
                  Text(
                    l.meRunPharmacy,
                    textAlign: TextAlign.center,
                    style: LaMPType.caption.copyWith(color: c.inkMuted),
                  ),
                  TextButton(
                    key: const ValueKey('me-owner-app'),
                    onPressed: () => context.go(
                      context.read<SessionController>().status == SessionStatus.signedIn ? '/today' : '/welcome',
                    ),
                    child: Text(l.meOwnerApp),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `/me`: type the code from the slip.
class FamilyCodeScreen extends StatefulWidget {
  const FamilyCodeScreen({super.key});

  @override
  State<FamilyCodeScreen> createState() => _FamilyCodeScreenState();
}

class _FamilyCodeScreenState extends State<FamilyCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _open() {
    final code = normaliseCode(_code.text);
    if (code.isNotEmpty) context.go('/me/$code');
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    return _FamilyFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.meTitle, style: LaMPType.head.copyWith(color: c.ink)),
          const SizedBox(height: Gap.sm),
          Text(l.meEnter, style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.lg),
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('me-code'),
                  controller: _code,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  style: LaMPType.monoBody,
                  decoration: InputDecoration(labelText: l.meCode, hintText: 'GL-XXXX-XXXX'),
                  onSubmitted: (_) => _open(),
                ),
                const SizedBox(height: Gap.md),
                ElevatedButton(
                  key: const ValueKey('me-open'),
                  onPressed: _open,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(l.meOpen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `/me/<code>`: what is owed, and a plan the family picks. One main action:
/// pick how to pay (plan 5.2).
class FamilyCardScreen extends StatelessWidget {
  const FamilyCardScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Keyed by the code: another code is another card.
      key: ValueKey(code),
      create: (context) => FamilyCardController(context.read<ApiClient>(), normaliseCode(code))..load(),
      child: const _FamilyFrame(child: _CardView()),
    );
  }
}

class _CardView extends StatefulWidget {
  const _CardView();

  @override
  State<_CardView> createState() => _CardViewState();
}

class _CardViewState extends State<_CardView> {
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = context.lamp;
    final bn = isBangla(context);
    final ctrl = context.watch<FamilyCardController>();
    final card = ctrl.card;
    final problem = ctrl.problem;

    if (card == null && problem != null) {
      final missing = problem.code == 'not_found';
      return LampEmpty(
        icon: missing ? Icons.search_off : Icons.wifi_off,
        title: missing ? l.meNotFound : l.meLoadError,
        message: missing ? l.meCheckCode : problemMessage(l, problem),
        action: Wrap(
          alignment: WrapAlignment.center,
          spacing: Gap.sm,
          children: [
            OutlinedButton(
              key: const ValueKey('me-enter-code'),
              onPressed: () => context.go('/me'),
              child: Text(l.meEnterCode),
            ),
            if (!missing) TextButton(onPressed: ctrl.load, child: Text(l.retry)),
          ],
        ),
      );
    }
    if (card == null) return const LampSkeletonCard(lines: 4);

    final plan = card.choices.plan;
    final join = JoinText.forCode(ctrl.code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.meWhere(card.pharmacy, card.city, card.label), style: LaMPType.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: Gap.sm),
        LampStat(
          label: l.meYouOwe,
          value: formatMoney(card.choices.amount, bangla: bn),
          caption: l.meSince(formatDay(card.since, bangla: bn), formatCount(card.daysOutstanding, bangla: bn)),
        ),
        const SizedBox(height: Gap.lg),
        if (plan != null && !_changing)
          LampCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l.meYourPlan, style: LaMPType.sub.copyWith(color: c.ink)),
                    ),
                    LampChip(label: l.mePromised, tone: LampTone.verified),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                for (final p in plan.schedule)
                  LampKeyValue(
                    label: formatDay(p.dueOn, bangla: bn),
                    value: formatMoney(p.amount, bangla: bn),
                    mono: true,
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('me-change'),
                    onPressed: () => setState(() => _changing = true),
                    child: Text(l.meChange),
                  ),
                ),
              ],
            ),
          )
        else
          _Picker(card: card, onDone: () => setState(() => _changing = false)),
        const SizedBox(height: Gap.lg),
        LampCard(
          background: c.surfaceAlt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.meSmsTitle, style: LaMPType.sub.copyWith(color: c.ink)),
              const SizedBox(height: Gap.xs),
              Text(l.meSmsHow(join.to), style: LaMPType.body.copyWith(color: c.inkMuted)),
              const SizedBox(height: Gap.sm),
              // Codes keep English letters and digits (plan 5.4).
              SelectableText(join.text, style: LaMPType.displayFigure.copyWith(color: c.ink)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Picker extends StatefulWidget {
  const _Picker({required this.card, required this.onDone});

  final FamilyCard card;
  final VoidCallback onDone;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late int _parts;
  late DateTime _firstOn;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ch = widget.card.choices;
    _parts = ch.plan?.parts ?? ch.options.last.parts;
    final kept = ch.plan?.firstOn;
    _firstOn = kept != null && !kept.isBefore(ch.asOf) && !kept.isAfter(ch.latestFirstOn) ? kept : ch.asOf;
  }

  Future<void> _promise() async {
    final l = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<FamilyCardController>().promise(_parts, _firstOn);
      if (!mounted) return;
      LumaToast.show(context, l.meSaved, icon: Icons.check, tone: LumaToastTone.verified);
      widget.onDone();
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
    final ch = widget.card.choices;
    return LampCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.meYourWay, style: LaMPType.sub.copyWith(color: c.ink)),
          const SizedBox(height: Gap.xs),
          Text(l.meHow, style: LaMPType.body.copyWith(color: c.inkMuted)),
          const SizedBox(height: Gap.md),
          for (final o in ch.options) ...[
            Material(
              color: _parts == o.parts ? c.brandSoft : c.surfaceAlt,
              borderRadius: BorderRadius.circular(LaMPRadius.control),
              child: InkWell(
                key: ValueKey('me-plan-${o.parts}'),
                borderRadius: BorderRadius.circular(LaMPRadius.control),
                onTap: () => setState(() => _parts = o.parts),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
                  child: Row(
                    children: [
                      Icon(
                        _parts == o.parts ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: _parts == o.parts ? c.brand : c.inkMuted,
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          o.parts == 1
                              ? l.meAll(formatMoney(ch.amount, bangla: bn))
                              : l.meParts(formatCount(o.parts, bangla: bn), formatMoney(o.partAmount, bangla: bn)),
                          style: LaMPType.body.copyWith(color: c.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
          ],
          const SizedBox(height: Gap.sm),
          Text(l.meFirst, style: LaMPType.caption.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.xs),
          OutlinedButton.icon(
            key: const ValueKey('me-first-on'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft),
            icon: const Icon(Icons.event_outlined),
            label: Text(formatDay(_firstOn, bangla: bn)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _firstOn,
                firstDate: ch.asOf,
                lastDate: ch.latestFirstOn,
              );
              if (picked != null) setState(() => _firstOn = picked);
            },
          ),
          Text(
            l.meAnyDay(formatDay(ch.asOf, bangla: bn), formatDay(ch.latestFirstOn, bangla: bn)),
            style: LaMPType.caption.copyWith(color: c.inkMuted),
          ),
          LampErrorText(_error),
          const SizedBox(height: Gap.md),
          ElevatedButton.icon(
            key: const ValueKey('me-promise'),
            onPressed: _busy ? null : _promise,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.event_available),
            label: _busy ? const LampBusy() : Text(l.mePromise),
          ),
          const SizedBox(height: Gap.xs),
          Text(l.mePromiseNote, style: LaMPType.caption.copyWith(color: c.inkMuted)),
        ],
      ),
    );
  }
}
