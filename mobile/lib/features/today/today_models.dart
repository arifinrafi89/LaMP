/// The Today screen's one call (plan 2.2, `GET /pharmacies/{pid}/today`),
/// made for slow networks. Money is BDT from the server; the app does no
/// money math (D8).
library;

double _money(Object? v) => (v as num? ?? 0).toDouble();

DateTime _day(Object? v) {
  final p = (v as String).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class NextProblem {
  const NextProblem({required this.kind, required this.date, required this.amount});

  /// `shortfall` for a day the cash runs short; other kinds show generically.
  final String kind;
  final DateTime date;
  final double amount;

  factory NextProblem.fromJson(Map<String, dynamic> j) =>
      NextProblem(kind: j['kind'] as String, date: _day(j['date']), amount: _money(j['amount']));
}

class OneThing {
  const OneThing({required this.kind, this.actionId});

  /// `approve`, `return_stock`, `scan_bill`, `finish_setup`, …
  final String kind;
  final String? actionId;

  factory OneThing.fromJson(Map<String, dynamic> j) =>
      OneThing(kind: j['kind'] as String, actionId: j['action_id'] as String?);
}

class TodayAlert {
  const TodayAlert({required this.id, required this.kind, required this.severity,
      required this.title, required this.detail});

  final String id;
  final String kind;

  /// `critical`, `warning` or `info`.
  final String severity;

  /// English from the server (as LaMP.ai's /alerts sends it).
  final String title;
  final String detail;

  factory TodayAlert.fromJson(Map<String, dynamic> j) => TodayAlert(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
        title: j['title'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
      );
}

class TodaySummary {
  const TodaySummary({
    required this.asOf,
    required this.cashNow,
    required this.nextProblem,
    required this.expiringValue,
    required this.returnEligible,
    required this.approvalsWaiting,
    required this.oneThing,
    required this.alerts,
  });

  final DateTime asOf;
  final double cashNow;
  final NextProblem? nextProblem;
  final double expiringValue;
  final double returnEligible;
  final int approvalsWaiting;
  final OneThing? oneThing;
  final List<TodayAlert> alerts;

  factory TodaySummary.fromJson(Map<String, dynamic> j) {
    final exp = j['expiring_60d'] as Map<String, dynamic>? ?? const {};
    return TodaySummary(
      asOf: _day(j['as_of']),
      cashNow: _money(j['cash_now']),
      nextProblem: j['next_problem'] == null
          ? null
          : NextProblem.fromJson(j['next_problem'] as Map<String, dynamic>),
      expiringValue: _money(exp['value']),
      returnEligible: _money(exp['return_eligible']),
      approvalsWaiting: (j['approvals_waiting'] as num? ?? 0).toInt(),
      oneThing: j['one_thing'] == null
          ? null
          : OneThing.fromJson(j['one_thing'] as Map<String, dynamic>),
      alerts: [
        for (final a in j['alerts'] as List? ?? const [])
          TodayAlert.fromJson(a as Map<String, dynamic>),
      ],
    );
  }
}
