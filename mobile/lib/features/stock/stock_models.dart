/// The Stock screen's one call (plan 2.2, `GET /pharmacies/{pid}/expiry`):
/// batches expiring within the horizon, and what can still go back to its
/// supplier. Money is BDT from the server; the app does no money math (D8).
library;

double _money(Object? v) => (v as num? ?? 0).toDouble();

DateTime _day(Object? v) {
  final p = (v as String).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class ExpiringBatch {
  const ExpiringBatch({
    required this.product,
    required this.batchNo,
    required this.expiryDate,
    required this.daysLeft,
    required this.qty,
    required this.costValue,
    required this.returnEligible,
    required this.supplier,
  });

  /// As the bill named it, strength and pack included: "Cetirizine 10 mg,
  /// box of 100".
  final String product;
  final String batchNo;
  final DateTime expiryDate;
  final int daysLeft;
  final int qty;
  final double costValue;

  /// The supplier still takes it back (inside their return window).
  final bool returnEligible;
  final String supplier;

  factory ExpiringBatch.fromJson(Map<String, dynamic> j) => ExpiringBatch(
        product: j['product'] as String? ?? '',
        batchNo: j['batch_no'] as String? ?? '',
        expiryDate: _day(j['expiry_date']),
        daysLeft: (j['days_left'] as num? ?? 0).toInt(),
        qty: (j['qty'] as num? ?? 0).toInt(),
        costValue: _money(j['cost_value']),
        returnEligible: j['return_eligible'] == true,
        supplier: j['supplier'] as String? ?? '',
      );
}

class StockExpiry {
  const StockExpiry({
    required this.horizonDays,
    required this.batches,
    required this.atRiskValue,
    required this.returnValue,
  });

  final int horizonDays;
  final List<ExpiringBatch> batches;
  final double atRiskValue;

  /// The part of [atRiskValue] that can still go back.
  final double returnValue;

  /// What can go back, the one closest to its expiry first.
  List<ExpiringBatch> get canGoBack => _soonest(batches.where((b) => b.returnEligible));

  List<ExpiringBatch> get cannotGoBack => _soonest(batches.where((b) => !b.returnEligible));

  static List<ExpiringBatch> _soonest(Iterable<ExpiringBatch> b) =>
      b.toList()..sort((x, y) => x.daysLeft.compareTo(y.daysLeft));

  factory StockExpiry.fromJson(Map<String, dynamic> j) => StockExpiry(
        horizonDays: (j['horizon_days'] as num? ?? 60).toInt(),
        batches: [
          for (final b in j['batches'] as List? ?? const [])
            ExpiringBatch.fromJson(b as Map<String, dynamic>),
        ],
        atRiskValue: _money(j['at_risk_value']),
        returnValue: _money(j['return_eligible_value']),
      );
}
