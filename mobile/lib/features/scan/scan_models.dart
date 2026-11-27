/// A scanned bill or sales-book page, as the owner checks it before saving
/// (plan 2.2 `CaptureOut`, `CaptureConfirm`; plan 5.5 "Review").
///
/// The server's draft is kept as JSON and edited in place, so what goes back
/// on confirm is exactly what the owner saw, with their edits. The app does
/// no money math (D8): a line total stays as read unless the owner types it.
library;

import 'dart:convert';

import '../../core/l10n/digits.dart';

/// What was photographed: a supplier's bill, or a page of the sales book.
enum ScanKind {
  invoice('invoice'),
  salesPage('sales_page');

  const ScanKind(this.api);

  /// The `kind` the server takes and sends.
  final String api;

  static ScanKind fromApi(Object? v) =>
      values.firstWhere((k) => k.api == v, orElse: () => ScanKind.invoice);
}

enum FieldType { text, optionalText, date, integer, money }

/// Under this, a field read from the photo waits for the owner (plan 5.5).
const confidentAbove = 0.8;

const _invoiceHeader = ['supplier_name', 'invoice_no', 'invoice_date', 'due_date', 'total'];
const _lineFields = [
  'product', 'strength', 'pack', 'batch_no', 'expiry_date', 'qty', 'unit_cost', 'line_total',
];
const _dayFields = ['date', 'cash_sales', 'credit_sales', 'dues_collected', 'expenses'];

FieldType _typeOf(String name) => switch (name) {
      'strength' || 'pack' => FieldType.optionalText,
      'invoice_date' || 'due_date' || 'expiry_date' || 'date' => FieldType.date,
      'qty' => FieldType.integer,
      'total' || 'unit_cost' || 'line_total' || 'cash_sales' || 'credit_sales' ||
      'dues_collected' || 'expenses' =>
        FieldType.money,
      _ => FieldType.text,
    };

/// One value read from the photo.
class ReviewField {
  ReviewField._(this.path, this.name, this._parent, this.confidence)
      : type = _typeOf(name),
        _waiting = confidence != null && confidence < confidentAbove;

  /// Where it sits in the draft, as `field_confidence` names it:
  /// `invoice.lines[2].qty`.
  final String path;

  /// The draft's own key, which also picks the label: `qty`.
  final String name;
  final FieldType type;

  /// How sure the reading was, when the server said; null when it was sure.
  final double? confidence;

  final Map<String, dynamic> _parent;
  bool _waiting;

  Object? get value => _parent[name];

  /// Read with low confidence and not yet confirmed or corrected.
  bool get waiting => _waiting;

  /// Whether the owner had to look at it, confirmed now or not.
  bool get wasDoubtful => confidence != null && confidence! < confidentAbove;
}

/// One of the server's plain-code checks on the reading.
class ReviewCheck {
  ReviewCheck._(this.name, this.passed, this.detail);

  final String name;
  final bool passed;

  /// English from the server, for example "Lines add up to BDT 7,350 but…".
  final String detail;

  bool _acknowledged = false;

  /// The owner has read a failed check and confirmed the bill anyway.
  bool get acknowledged => passed || _acknowledged;
}

class ScanReview {
  ScanReview._({
    required this.captureId,
    required this.kind,
    required this.confirmed,
    required Map<String, dynamic> draft,
    required this.header,
    required this.items,
    required this.checks,
    required this.suspiciousText,
  }) : _draft = draft;

  final String captureId;
  final ScanKind kind;

  /// The server already has it saved (`status: confirmed`).
  final bool confirmed;

  /// The bill's own fields (supplier, number, dates, total). Empty for a
  /// sales-book page.
  final List<ReviewField> header;

  /// One group per bill line, or per day of the sales book.
  final List<List<ReviewField>> items;

  final List<ReviewCheck> checks;

  /// Text on the photo that read like instructions; the server ignored it.
  final List<String> suspiciousText;

  /// `{"invoice": {...}}` or `{"sales_page": {...}}`, edited in place.
  final Map<String, dynamic> _draft;

  factory ScanReview.fromCapture(Map<String, dynamic> capture) {
    final ex = capture['extraction'] as Map<String, dynamic>? ?? const {};
    final kind = ScanKind.fromApi(capture['kind'] ?? ex['kind']);
    final conf = <String, double>{
      for (final e in (ex['field_confidence'] as Map? ?? const {}).entries)
        if (e.value is num) e.key as String: (e.value as num).toDouble(),
    };
    // A deep copy: edits never touch the map the caller holds.
    final body = jsonDecode(jsonEncode(ex[kind.api] ?? const <String, dynamic>{}))
        as Map<String, dynamic>;

    List<ReviewField> fields(String prefix, Map<String, dynamic> parent, List<String> names) => [
          for (final n in names)
            if (parent.containsKey(n)) ReviewField._('$prefix.$n', n, parent, conf['$prefix.$n']),
        ];

    final header = <ReviewField>[];
    final items = <List<ReviewField>>[];
    if (kind == ScanKind.invoice) {
      header.addAll(fields('invoice', body, _invoiceHeader));
      final lines = body['lines'] as List? ?? const [];
      for (var i = 0; i < lines.length; i++) {
        items.add(fields('invoice.lines[$i]', lines[i] as Map<String, dynamic>, _lineFields));
      }
    } else {
      final days = body['days'] as List? ?? const [];
      for (var i = 0; i < days.length; i++) {
        items.add(fields('sales_page.days[$i]', days[i] as Map<String, dynamic>, _dayFields));
      }
    }

    return ScanReview._(
      captureId: capture['id'] as String,
      kind: kind,
      confirmed: capture['status'] == 'confirmed',
      draft: {kind.api: body},
      header: header,
      items: items,
      checks: [
        for (final c in ex['checks'] as List? ?? const [])
          if (c is Map<String, dynamic>)
            ReviewCheck._(c['name'] as String? ?? '', c['passed'] == true, c['detail'] as String? ?? ''),
      ],
      suspiciousText: [
        for (final t in ex['suspicious_text'] as List? ?? const [])
          if (t is String) t,
      ],
    );
  }

  Iterable<ReviewField> get _all sync* {
    yield* header;
    for (final g in items) {
      yield* g;
    }
  }

  ReviewField field(String path) => _all.firstWhere((f) => f.path == path);

  /// Fields still waiting for the owner, in screen order.
  List<ReviewField> get waiting => [for (final f in _all) if (f.waiting) f];

  List<ReviewCheck> get failedChecks => [for (final c in checks) if (!c.passed) c];

  /// Every doubtful field confirmed or corrected, every failed check read.
  bool get canSave => waiting.isEmpty && checks.every((c) => c.acknowledged);

  /// The owner says the value read is right.
  void confirm(String path) => field(path)._waiting = false;

  void acknowledge(ReviewCheck check) => check._acknowledged = true;

  /// The owner's correction, typed in either language. Returns false, and
  /// changes nothing, when [typed] doesn't fit the field.
  bool edit(String path, String typed) {
    final f = field(path);
    final Object? v;
    switch (f.type) {
      case FieldType.text:
        final t = typed.trim();
        if (t.isEmpty) return false;
        v = t;
      case FieldType.optionalText:
        final t = typed.trim();
        v = t.isEmpty ? null : t;
      case FieldType.date:
        final d = _parseDate(enDigits(typed.trim()));
        if (d == null) return false;
        v = apiDate(d);
      case FieldType.integer:
        final n = parseWhole(typed);
        if (n == null || n <= 0) return false;
        v = n;
      case FieldType.money:
        final a = parseAmount(typed);
        if (a == null) return false;
        v = a;
    }
    f._parent[f.name] = v;
    f._waiting = false;
    return true;
  }

  /// The body of `POST …/captures/{cid}/confirm`.
  Map<String, dynamic> toConfirmJson() => jsonDecode(jsonEncode(_draft)) as Map<String, dynamic>;

  static DateTime? _parseDate(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    // DateTime rolls 31 Feb over into March; a real date comes back the same.
    return apiDate(d) == s ? d : null;
  }
}
