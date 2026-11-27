import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/digits.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import '../plan/plan_models.dart';
import 'approvals_models.dart';

/// `GET /pharmacies/{pid}/actions`, from the phone first.
class ApprovalsController extends CachedRead<ActionList> {
  ApprovalsController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super.list(api, cache, '/pharmacies/$pid/actions', ActionList.fromJson);

  ActionList? get actions => data;
}

/// `GET /pharmacies/{pid}/pause`.
class PauseController extends CachedRead<PauseState> {
  PauseController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super(api, cache, '/pharmacies/$pid/pause', PauseState.fromJson);

  PauseState? get pause => data;
}

/// The owner's changes on Plan and Approvals, and the reads only a sheet
/// needs. Each change rings [onSaved], so Today, the plan and the list read
/// again.
class MoneyActions {
  MoneyActions(this._api, String pid, {VoidCallback? onSaved}) : _base = '/pharmacies/$pid', _onSaved = onSaved;

  final ApiClient _api;
  final String _base;
  final VoidCallback? _onSaved;

  T _saved<T>(T value) {
    _onSaved?.call();
    return value;
  }

  static Map<String, dynamic> _map(Object? j) => j as Map<String, dynamic>;

  /// Puts a plan step in Approvals, as the owner's own proposal.
  Future<LampAction> propose(PlanStep s) async => _saved(await _propose(s));

  /// Every step, in order; the screens read again once, after the last.
  Future<void> proposeAll(List<PlanStep> steps) async {
    try {
      for (final s in steps) {
        await _propose(s);
      }
    } finally {
      // Some may have landed before a failure: show what the server has.
      _onSaved?.call();
    }
  }

  Future<LampAction> _propose(PlanStep s) async {
    final j = await _api.post('$_base/actions', {
      'kind': s.kind,
      'payload': {'summary': s.label, 'amount': s.amount, 'when': apiDate(s.when)},
    }, idempotent: true);
    return LampAction.fromJson(_map(j));
  }

  Future<LampAction> approve(String id) async =>
      _saved(LampAction.fromJson(_map(await _api.post('$_base/actions/$id/approve', null, idempotent: true))));

  Future<LampAction> reject(String id) async =>
      _saved(LampAction.fromJson(_map(await _api.post('$_base/actions/$id/reject', null, idempotent: true))));

  Future<PauseState> setPause(bool paused) async =>
      _saved(PauseState.fromJson(_map(await _api.post('$_base/pause', {'paused': paused}))));

  Future<List<Order>> orders() async => [
    for (final o in await _api.get('$_base/orders') as List) Order.fromJson(o as Map<String, dynamic>),
  ];

  Future<Trim> trim(String orderId) async => Trim.fromJson(_map(await _api.get('$_base/orders/$orderId/trim')));
}
