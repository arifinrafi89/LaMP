import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import 'stock_models.dart';

/// Loads `GET /pharmacies/{pid}/expiry` for the Stock screen.
class StockController extends ChangeNotifier {
  StockController(this._api, this._pid);

  final ApiClient _api;
  final String _pid;

  StockExpiry? _expiry;
  StockExpiry? get expiry => _expiry;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  Future<void> load() async {
    _problem = null;
    _notify();
    try {
      final j = await _api.get('/pharmacies/$_pid/expiry');
      _expiry = StockExpiry.fromJson(j as Map<String, dynamic>);
    } on ApiProblem catch (p) {
      // Keep what was shown before; the screen says it couldn't refresh.
      _problem = p;
    } finally {
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
