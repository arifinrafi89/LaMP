/// How to cover a short day (`POST /funding-plan`, `GET /orders`,
/// `GET /orders/{oid}/trim`; Plus). Every figure is the server's (D8).
library;

DateTime _day(Object? s) => DateTime.parse(s as String);
double _money(Object? v) => (v as num).toDouble();
double? _maybe(Object? v) => v == null ? null : (v as num).toDouble();

/// One line of "how this figure was worked out": start, then - or +, then =.
class ExplainRow {
  const ExplainRow(this.label, this.amount, this.op);

  final String label;
  final double amount;
  final String op;

  factory ExplainRow.fromJson(Map<String, dynamic> j) =>
      ExplainRow(j['label'] as String, _money(j['amount']), j['op'] as String);
}

class Need {
  const Need(this.amount, this.neededBy, this.explain);

  final double amount;
  final DateTime neededBy;
  final List<ExplainRow> explain;
}

class CoverOption {
  const CoverOption({
    required this.key,
    required this.label,
    required this.provider,
    required this.amount,
    required this.costBdt,
    required this.aprPct,
    required this.eligible,
    required this.reason,
    required this.speed,
    required this.certain,
  });

  final String key;
  final String label;
  final String provider;
  final double amount;
  final double? costBdt;
  final double? aprPct;
  final bool eligible;
  final String reason;
  final String speed;

  /// The server is sure it would work (a supplier's answer isn't).
  final bool certain;

  factory CoverOption.fromJson(Map<String, dynamic> j) => CoverOption(
    key: j['key'] as String,
    label: j['label'] as String,
    provider: j['provider'] as String,
    amount: _money(j['amount']),
    costBdt: _maybe(j['cost_bdt']),
    aprPct: _maybe(j['apr_pct']),
    eligible: j['eligible'] == true,
    reason: (j['reason'] as String?) ?? '',
    speed: (j['speed'] as String?) ?? '',
    certain: j['certainty'] == 'certain',
  );
}

class PlanStep {
  const PlanStep({required this.kind, required this.label, required this.amount, required this.when, this.fallbackFor});

  final String kind;
  final String label;
  final double amount;
  final DateTime when;

  /// The step this one stands in for if that doesn't work out.
  final String? fallbackFor;

  factory PlanStep.fromJson(Map<String, dynamic> j) => PlanStep(
    kind: j['action_kind'] as String,
    label: j['label'] as String,
    amount: _money(j['amount']),
    when: _day(j['when']),
    fallbackFor: j['fallback_for'] as String?,
  );
}

/// Loans are shown with their cost, never applied for from the app (plan 2.2).
const retiredKinds = {'loan_application'};

class MoneyPlan {
  const MoneyPlan({
    required this.need,
    required this.options,
    required this.steps,
    required this.totalCost,
    required this.naiveCost,
  });

  final Need need;
  final List<CoverOption> options;
  final List<PlanStep> steps;

  /// What the plan costs.
  final double totalCost;

  /// What borrowing the whole short amount would cost.
  final double naiveCost;

  /// The steps the owner can send to Approvals.
  List<PlanStep> get toPropose => steps.where((s) => !retiredKinds.contains(s.kind)).toList();

  /// Shown as "if that doesn't work", with its cost.
  List<PlanStep> get fallbacks => steps.where((s) => retiredKinds.contains(s.kind)).toList();

  factory MoneyPlan.fromJson(Map<String, dynamic> j) {
    final need = j['need'] as Map<String, dynamic>;
    final plan = j['plan'] as Map<String, dynamic>;
    return MoneyPlan(
      need: Need(_money(need['amount']), _day(need['needed_by']), [
        for (final r in (need['explain'] as List?) ?? const []) ExplainRow.fromJson(r as Map<String, dynamic>),
      ]),
      options: [for (final o in j['options'] as List) CoverOption.fromJson(o as Map<String, dynamic>)],
      steps: [for (final s in plan['steps'] as List) PlanStep.fromJson(s as Map<String, dynamic>)],
      totalCost: _money(plan['total_cost_bdt']),
      naiveCost: _money(j['naive_cost_bdt']),
    );
  }
}

class Order {
  const Order(this.id, this.supplier, this.dueDate, this.total);

  final String id;
  final String supplier;
  final DateTime dueDate;
  final double total;

  factory Order.fromJson(Map<String, dynamic> j) =>
      Order(j['id'] as String, j['supplier'] as String, _day(j['due_date']), _money(j['total']));
}

class TrimLine {
  const TrimLine({
    required this.product,
    required this.qty,
    required this.suggestedQty,
    required this.atRiskValue,
    required this.sellableDays,
  });

  final String product;
  final int qty;
  final int suggestedQty;
  final double atRiskValue;
  final int sellableDays;

  factory TrimLine.fromJson(Map<String, dynamic> j) => TrimLine(
    product: j['product'] as String,
    qty: j['qty'] as int,
    suggestedQty: j['suggested_qty'] as int,
    atRiskValue: _money(j['at_risk_value']),
    sellableDays: j['sellable_days'] as int,
  );
}

class Trim {
  const Trim({
    required this.orderId,
    required this.lines,
    required this.originalTotal,
    required this.suggestedTotal,
    required this.saving,
  });

  final String orderId;
  final List<TrimLine> lines;
  final double originalTotal;
  final double suggestedTotal;
  final double saving;

  /// Lines the server suggests ordering fewer of.
  List<TrimLine> get cuts => lines.where((l) => l.suggestedQty < l.qty).toList();

  factory Trim.fromJson(Map<String, dynamic> j) => Trim(
    orderId: j['order_id'] as String,
    lines: [for (final l in j['lines'] as List) TrimLine.fromJson(l as Map<String, dynamic>)],
    originalTotal: _money(j['original_total']),
    suggestedTotal: _money(j['suggested_total']),
    saving: _money(j['saving']),
  );
}
