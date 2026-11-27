/// The credit record (plan 3.7): a BDT 10 summary of how the shop pays its
/// suppliers, shared with one lender at a time through an expiring link.
library;

/// One lender's link to the record.
class CreditShare {
  const CreditShare({
    required this.id,
    required this.lenderName,
    required this.url,
    required this.expiresAt,
    required this.views,
  });

  final String id;
  final String lenderName;
  final String url;
  final DateTime? expiresAt;

  /// How often the lender opened it; every view is in History too.
  final int views;

  factory CreditShare.fromJson(Map<String, dynamic> j) => CreditShare(
    id: j['id'] as String,
    lenderName: j['lender_name'] as String,
    url: j['url'] as String,
    expiresAt: DateTime.tryParse((j['expires_at'] as String?) ?? ''),
    views: (j['views'] as int?) ?? 0,
  );
}

class CreditRecord {
  const CreditRecord({
    required this.billsTotal,
    required this.paidOnTime,
    required this.months,
    required this.purchased,
    required this.shares,
  });

  final int billsTotal;
  final int paidOnTime;
  final int months;

  /// Bought (PAID): the PDF and sharing are open.
  final bool purchased;
  final List<CreditShare> shares;

  /// One active share at a time (plan 2.2).
  CreditShare? get activeShare => shares.isEmpty ? null : shares.first;

  factory CreditRecord.fromJson(Map<String, dynamic> j) => CreditRecord(
    billsTotal: j['bills_total'] as int,
    paidOnTime: j['paid_on_time'] as int,
    months: j['months'] as int,
    purchased: j['purchased'] == true,
    shares: [for (final s in (j['shares'] as List?) ?? const []) CreditShare.fromJson(s as Map<String, dynamic>)],
  );
}

/// One purchase's charge, as the server reports it.
class Charge {
  const Charge(this.id, this.status, this.attemptsLeft, this.reason);

  final String id;

  /// OTP_SENT, VERIFYING, PAID, FAILED, EXPIRED or UNKNOWN.
  final String status;
  final int? attemptsLeft;

  /// The server's words when FAILED.
  final String? reason;

  factory Charge.fromJson(Map<String, dynamic> j) =>
      Charge(j['charge_id'] as String, j['status'] as String, j['attempts_left'] as int?, j['reason'] as String?);
}
