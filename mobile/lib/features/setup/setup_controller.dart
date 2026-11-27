import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/auth/auth_service.dart';
import '../../core/l10n/digits.dart';
import '../../core/state/session_controller.dart';
import 'setup_models.dart';

/// The five steps of the first day (plan 5.2), in order.
enum SetupStep { shop, suppliers, cash, expenses, stock }

/// Drives Setup: one server call per step, then `setup/complete`.
///
/// - The shop step is the only one that can't be skipped: every other call
///   needs the shop's id. The rest can be skipped and done later; Today
///   lists what is missing.
/// - Where the owner got to is kept on the phone, so closing the app halfway
///   opens Setup at the same step.
/// - A save that failed is retried with the same Idempotency-Key while its
///   body is unchanged, so a second tap after a timeout can't record the
///   opening cash twice (plan 2.1, "Safe retries").
class SetupController extends ChangeNotifier {
  SetupController(this._api, this._session, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final ApiClient _api;
  final SessionController _session;
  final DateTime Function() _now;

  SetupStep _step = SetupStep.shop;
  SetupStep get step => _step;

  bool _ready = false;
  bool get ready => _ready;

  bool _busy = false;
  bool get busy => _busy;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  final List<Supplier> _suppliers = [];
  List<Supplier> get suppliers => List.unmodifiable(_suppliers);

  /// Why the saved suppliers couldn't be read. Until they are, adding one is
  /// off: the owner would re-add what the server already has.
  ApiProblem? _suppliersProblem;
  ApiProblem? get suppliersProblem => _suppliersProblem;

  final List<StockLine> _stock = [];
  List<StockLine> get stock => List.unmodifiable(_stock);

  /// "what:body" → key, for saves that may be retried.
  final Map<String, String> _keys = {};

  bool _disposed = false;

  PharmacyInfo? get pharmacy => _session.pharmacy;
  String? get _pid => pharmacy?.id;

  static String _stepKey(String pid) => 'lamp.setupStep.$pid';

  /// Opens at the shop step for a new owner, or where they left off.
  Future<void> init() async {
    final pid = _pid;
    if (pid != null) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_stepKey(pid));
      _step = SetupStep.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => SetupStep.suppliers,
      );
      if (_step == SetupStep.shop) _step = SetupStep.suppliers;
      await loadSuppliers();
    }
    _ready = true;
    _notify();
  }

  /// Reads the suppliers already saved, for an owner coming back to Setup.
  Future<void> loadSuppliers() async {
    _suppliersProblem = null;
    _notify();
    try {
      final j = await _api.get('/pharmacies/$_pid/suppliers');
      final list = j is List ? j : const [];
      _suppliers
        ..clear()
        ..addAll(list.whereType<Map<String, dynamic>>().map(Supplier.fromJson));
    } on ApiProblem catch (p) {
      _suppliersProblem = p;
    }
    _notify();
  }

  /// Step 1. Creates the shop, or renames it when the owner came back.
  Future<bool> saveShop({required String name, required String city, String? area}) =>
      _run(() async {
        final existing = pharmacy;
        if (existing == null) {
          final body = {
            'name': name,
            'city': city,
            if (area != null && area.isNotEmpty) 'area': area,
          };
          final j = await _api.post('/pharmacies', body, idempotencyKey: _keyFor('shop', body));
          _session.updatePharmacy(PharmacyInfo.fromJson(j as Map<String, dynamic>));
          // The access token carries `pid` (plan 2.1), so ask for a new pair
          // that has it.
          try {
            await _session.refreshNow();
          } on ApiProblem {
            // The next call that needs it refreshes on its own 401.
          }
        } else {
          await _api.patch('/pharmacies/${existing.id}', {'name': name, 'city': city});
          _session.updatePharmacy(existing.copyWith(name: name));
        }
        await _moveTo(SetupStep.suppliers);
      });

  /// Step 2: one supplier at a time, saved as it is added.
  Future<bool> addSupplier(Supplier s) => _run(() async {
        final body = s.toJson();
        final j = await _api.post('/pharmacies/$_pid/suppliers', body,
            idempotencyKey: _keyFor('supplier', body));
        _suppliers.add(j is Map<String, dynamic> && j['name'] is String ? Supplier.fromJson(j) : s);
      });

  Future<bool> removeSupplier(Supplier s) => _run(() async {
        if (s.id != null) await _api.delete('/pharmacies/$_pid/suppliers/${s.id}');
        _suppliers.remove(s);
        _stock.removeWhere((line) => line.supplierId != null && line.supplierId == s.id);
      });

  /// Step 3: the cash in the drawer today.
  Future<bool> saveCash(double cashOnHand) => _run(() async {
        final body = {'cash_on_hand': cashOnHand, 'as_of': apiDate(dhakaToday(_now()))};
        await _api.post('/pharmacies/$_pid/opening', body, idempotencyKey: _keyFor('cash', body));
        await _moveTo(SetupStep.expenses);
      });

  /// Step 4: monthly rent and salaries, for the forecast.
  Future<bool> saveExpenses(List<MonthlyExpense> lines) => _run(() async {
        if (lines.isNotEmpty) {
          final body = [for (final e in lines) e.toJson()];
          await _api.post('/pharmacies/$_pid/expenses', body,
              idempotencyKey: _keyFor('expenses', body));
        }
        await _moveTo(SetupStep.stock);
      });

  /// Step 5, typed stock. Lines are kept here until [finish] sends them.
  void addStockLine(StockLine line) {
    _stock.add(line);
    _notify();
  }

  void removeStockLine(StockLine line) {
    _stock.remove(line);
    _notify();
  }

  /// Sends any typed stock, then marks setup done. Today has figures after.
  Future<bool> finish() => _run(() async {
        if (_stock.isNotEmpty) {
          final body = [for (final s in _stock) s.toJson(apiDate)];
          await _api.post('/pharmacies/$_pid/stock-batches', body,
              idempotencyKey: _keyFor('stock', body));
          _stock.clear();
        }
        await _api.post('/pharmacies/$_pid/setup/complete', null);
        final p = pharmacy!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_stepKey(p.id));
        // Last: this tells the router Setup is done.
        _session.updatePharmacy(p.copyWith(setupComplete: true));
      });

  Future<void> skip() async {
    if (_step == SetupStep.shop) return;
    final i = _step.index + 1;
    if (i < SetupStep.values.length) await _moveTo(SetupStep.values[i]);
  }

  bool back() {
    if (_step.index == 0 || _busy) return false;
    _moveTo(SetupStep.values[_step.index - 1]);
    return true;
  }

  Future<void> _moveTo(SetupStep s) async {
    _step = s;
    _problem = null;
    _notify();
    final pid = _pid;
    if (pid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stepKey(pid), s.name);
  }

  String _keyFor(String what, Object body) =>
      _keys.putIfAbsent('$what:${jsonEncode(body)}', newUuid);

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _problem = null;
    _notify();
    try {
      await action();
      return true;
    } on ApiProblem catch (p) {
      _problem = p;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
