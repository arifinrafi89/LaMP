/// Steps waiting for the owner's yes (`GET /actions`, Plus).
library;

DateTime? _at(Object? s) => s is String ? DateTime.tryParse(s) : null;

class LampAction {
  const LampAction({
    required this.id,
    required this.kind,
    required this.status,
    required this.payload,
    required this.proposedBy,
    required this.createdAt,
    required this.decidedAt,
    required this.result,
  });

  final String id;
  final String kind;
  final String status;
  final Map<String, dynamic> payload;
  final String proposedBy;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final Map<String, dynamic>? result;

  bool get waiting => status == 'proposed';

  /// LaMP suggested it (the chat or the scheduler), not the owner.
  bool get byLamp => proposedBy != 'owner';

  /// The server's words for what it does.
  String? get summary => payload['summary'] as String?;
  double? get amount => (payload['amount'] as num?)?.toDouble();

  /// The server's words for what happened.
  String? get resultSummary => result?['summary'] as String?;

  /// An approved request for more days: the message for the supplier.
  String? shareText({required bool bangla}) =>
      (result?[bangla ? 'share_text_bn' : 'share_text_en'] ?? result?['share_text_en']) as String?;

  String? get supplierPhone => result?['supplier_phone'] as String?;

  factory LampAction.fromJson(Map<String, dynamic> j) => LampAction(
    id: j['id'] as String,
    kind: j['kind'] as String,
    status: j['status'] as String,
    payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    proposedBy: (j['proposed_by'] as String?) ?? 'owner',
    createdAt: _at(j['created_at']),
    decidedAt: _at(j['decided_at']),
    result: (j['result'] as Map?)?.cast<String, dynamic>(),
  );
}

class ActionList {
  const ActionList(this.items);

  final List<LampAction> items;

  List<LampAction> get waiting => items.where((a) => a.waiting).toList();

  /// Decided, newest first.
  List<LampAction> get done {
    final d = items.where((a) => !a.waiting).toList();
    DateTime when(LampAction a) => a.decidedAt ?? a.createdAt ?? DateTime(2000);
    d.sort((a, b) => when(b).compareTo(when(a)));
    return d;
  }

  LampAction? byId(String id) {
    for (final a in items) {
      if (a.id == id) return a;
    }
    return null;
  }

  factory ActionList.fromJson(List<dynamic> j) =>
      ActionList([for (final a in j) LampAction.fromJson(a as Map<String, dynamic>)]);
}

/// Pause: LaMP's own suggestions stop until the owner resumes it.
class PauseState {
  const PauseState(this.paused);

  final bool paused;

  factory PauseState.fromJson(Map<String, dynamic> j) => PauseState(j['paused'] == true);
}
