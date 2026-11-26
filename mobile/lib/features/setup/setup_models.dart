/// What the Setup screen sends (plan 2.2, "Shop setup"). Shapes follow the
/// plan's table until contract v1 is in `contracts/openapi.json`.
library;

/// `GET|POST /pharmacies/{pid}/suppliers`.
class Supplier {
  const Supplier({
    this.id,
    required this.name,
    this.phone,
    required this.paymentDays,
    required this.returnCutoffDays,
  });

  /// Null until the server has saved it.
  final String? id;
  final String name;

  /// A business contact, used only for the share-to-supplier draft.
  final String? phone;
  final int paymentDays;
  final int returnCutoffDays;

  /// Most distributors give 30 days to pay; 60 days to send stock back is a
  /// common cut-off. The owner can change both.
  static const defaultPaymentDays = 30;
  static const defaultReturnCutoffDays = 60;

  Map<String, Object?> toJson() => {
        'name': name,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        'payment_days': paymentDays,
        'return_cutoff_days': returnCutoffDays,
      };

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id']?.toString(),
        name: j['name'] as String,
        phone: j['phone'] as String?,
        paymentDays: (j['payment_days'] as num?)?.toInt() ?? defaultPaymentDays,
        returnCutoffDays:
            (j['return_cutoff_days'] as num?)?.toInt() ?? defaultReturnCutoffDays,
      );
}

/// One line of `POST /pharmacies/{pid}/expenses`.
class MonthlyExpense {
  const MonthlyExpense({required this.category, required this.amount, required this.dayOfMonth});

  /// `rent` or `salaries`.
  final String category;
  final double amount;
  final int dayOfMonth;

  Map<String, Object?> toJson() =>
      {'category': category, 'amount': amount, 'day_of_month': dayOfMonth};
}

/// One line of typed opening stock, `POST /pharmacies/{pid}/stock-batches`.
class StockLine {
  const StockLine({
    required this.product,
    this.strength,
    required this.batchNo,
    required this.expiryDate,
    required this.qty,
    required this.unitCost,
    this.supplierId,
  });

  final String product;

  /// As printed on the box (`500 mg`); keeps English digits.
  final String? strength;
  final String batchNo;
  final DateTime expiryDate;
  final int qty;
  final double unitCost;
  final String? supplierId;

  Map<String, Object?> toJson(String Function(DateTime) date) => {
        'product': product,
        if (strength != null && strength!.isNotEmpty) 'strength': strength,
        'batch_no': batchNo,
        'expiry_date': date(expiryDate),
        'qty': qty,
        'unit_cost': unitCost,
        'supplier_id': ?supplierId,
      };
}
