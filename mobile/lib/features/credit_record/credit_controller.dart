import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'credit_models.dart';

/// `GET /pharmacies/{pid}/credit-record`, from the phone first.
class CreditRecordController extends CachedRead<CreditRecord> {
  CreditRecordController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super(api, cache, '/pharmacies/$pid/credit-record', CreditRecord.fromJson);

  CreditRecord? get record => data;
}

enum PurchaseStage {
  idle,

  /// The purchase is being asked for.
  starting,

  /// Banglalink sent a code to the owner's phone.
  code,

  /// The code was sent; waiting for the server to say PAID.
  checking,

  /// Banglalink hasn't confirmed within the checks; nothing more is charged.
  waiting,
  paid,

  /// Nothing was charged (low balance, refused).
  failed,

  /// The code ran out; nothing was charged.
  expired,
}

/// One BDT 10 purchase (plan 3.7). One charge per purchase: a wrong code or
/// a slow answer never starts a second one. Only the server's PAID counts.
class PurchaseController extends ChangeNotifier {
  PurchaseController(
    this._api,
    String pid, {
    VoidCallback? onPaid,
    this.pollEvery = const Duration(seconds: 3),
    this.maxPolls = 40,
  }) : _base = '/pharmacies/$pid/credit-record/purchases',
       _onPaid = onPaid;

  final ApiClient _api;
  final String _base;
  final VoidCallback? _onPaid;

  /// Plan 2.2: every 3 s, for up to 2 minutes.
  final Duration pollEvery;
  final int maxPolls;

  PurchaseStage _stage = PurchaseStage.idle;
  PurchaseStage get stage => _stage;

  String? _chargeId;
  int? _attemptsLeft;

  /// After a wrong code.
  int? get attemptsLeft => _attemptsLeft;

  String? _reason;

  /// The server's words when the charge failed.
  String? get reason => _reason;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  void _set(PurchaseStage s) {
    _stage = s;
    if (!_disposed) notifyListeners();
  }

  /// A new purchase, with its own key: only after the last one ended with
  /// nothing charged (or none yet).
  Future<void> start() async {
    _problem = null;
    _reason = null;
    _attemptsLeft = null;
    _set(PurchaseStage.starting);
    try {
      final j = await _api.post(_base, null, idempotent: true);
      _apply(Charge.fromJson(j as Map<String, dynamic>));
    } on ApiProblem catch (p) {
      _problem = p;
      _set(PurchaseStage.failed);
    }
  }

  Future<void> submit(String otp) async {
    final id = _chargeId;
    if (id == null) return;
    _problem = null;
    _set(PurchaseStage.checking);
    try {
      final j = await _api.post('$_base/$id/otp', {'otp': otp});
      await _after(Charge.fromJson(j as Map<String, dynamic>));
    } on ApiProblem catch (p) {
      // The code can be sent again: the same charge, never a new one.
      _problem = p;
      _set(PurchaseStage.code);
    }
  }

  /// After "not confirmed yet": look again, without charging anything.
  Future<void> checkAgain() async {
    _problem = null;
    _set(PurchaseStage.checking);
    await _poll();
  }

  Future<void> _after(Charge c) async {
    _apply(c);
    if (c.status == 'VERIFYING' || c.status == 'UNKNOWN') await _poll();
  }

  Future<void> _poll() async {
    final id = _chargeId!;
    for (var i = 0; i < maxPolls; i++) {
      if (_disposed) return;
      try {
        final c = Charge.fromJson(await _api.get('$_base/$id') as Map<String, dynamic>);
        if (c.status != 'VERIFYING' && c.status != 'UNKNOWN') return _apply(c);
      } on ApiProblem catch (p) {
        _problem = p;
      }
      await Future<void>.delayed(pollEvery);
    }
    _set(PurchaseStage.waiting);
  }

  void _apply(Charge c) {
    _chargeId = c.id;
    _attemptsLeft = c.attemptsLeft;
    _reason = c.reason;
    switch (c.status) {
      case 'OTP_SENT':
        _set(PurchaseStage.code);
      case 'PAID':
        _set(PurchaseStage.paid);
        _onPaid?.call();
      case 'FAILED':
        _set(PurchaseStage.failed);
      case 'EXPIRED':
        _set(PurchaseStage.expired);
      default:
        _set(PurchaseStage.checking);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Sharing the bought record, and its PDF.
class CreditActions {
  CreditActions(this._api, String pid, {VoidCallback? onSaved})
    : _base = '/pharmacies/$pid/credit-record',
      _onSaved = onSaved;

  final ApiClient _api;
  final String _base;
  final VoidCallback? _onSaved;

  /// A link for one lender, open for 7 days.
  Future<CreditShare> share(String lenderName) async {
    final j = await _api.post('$_base/shares', {'lender_name': lenderName, 'expires_in_days': 7});
    _onSaved?.call();
    return CreditShare.fromJson(j as Map<String, dynamic>);
  }

  Future<void> revoke(String id) async {
    await _api.delete('$_base/shares/$id');
    _onSaved?.call();
  }

  Future<Uint8List> pdf() => _api.getBytes('$_base/pdf');
}
