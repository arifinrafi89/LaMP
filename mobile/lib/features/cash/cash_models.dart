/// The next 30 days of cash (`GET /forecast`, Plus). The server works out
/// every figure; the app only shows them (D8).
library;

DateTime _day(Object? s) => DateTime.parse(s as String);
double _money(Object? v) => (v as num).toDouble();

class ForecastItem {
  const ForecastItem(this.label, this.amount);

  final String label;

  /// Signed: + money in, - money out.
  final double amount;
}

class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.inflow,
    required this.outflow,
    required this.balance,
    required this.items,
  });

  final DateTime date;
  final double inflow;
  final double outflow;

  /// Cash left at the end of the day.
  final double balance;

  /// The bills, orders and rent that day, by name.
  final List<ForecastItem> items;

  bool get short => balance < 0;

  factory ForecastDay.fromJson(Map<String, dynamic> j) => ForecastDay(
    date: _day(j['date']),
    inflow: _money(j['inflow']),
    outflow: _money(j['outflow']),
    balance: _money(j['balance']),
    items: [
      for (final i in (j['items'] as List?) ?? const [])
        ForecastItem((i as Map)['label'] as String, _money(i['amount'])),
    ],
  );
}

class Shortfall {
  const Shortfall(this.date, this.amount, this.cause);

  final DateTime date;
  final double amount;

  /// The server's words: "Supplier A order BDT 60,000".
  final String cause;
}

class Forecast {
  const Forecast({required this.startCash, required this.days, required this.shortfalls});

  final double startCash;
  final List<ForecastDay> days;
  final List<Shortfall> shortfalls;

  /// Days with a named bill, order or payment.
  List<ForecastDay> get namedDays => days.where((d) => d.items.isNotEmpty).toList();

  ForecastDay? dayOf(DateTime date) {
    for (final d in days) {
      if (d.date == date) return d;
    }
    return null;
  }

  factory Forecast.fromJson(Map<String, dynamic> j) => Forecast(
    startCash: _money(j['start_cash']),
    days: [for (final d in j['days'] as List) ForecastDay.fromJson(d as Map<String, dynamic>)],
    shortfalls: [
      for (final s in (j['shortfalls'] as List?) ?? const [])
        Shortfall(_day((s as Map)['date']), _money(s['amount']), s['cause'] as String),
    ],
  );
}
