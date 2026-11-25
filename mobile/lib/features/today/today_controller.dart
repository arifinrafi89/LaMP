import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import 'today_models.dart';

/// Loads `GET /pharmacies/{pid}/today`. One call, made for slow networks.
class TodayController extends ChangeNotifier {
  TodayController(this._api, this._pid);

  final ApiClient _api;
  final String _pid;

  TodaySummary? _summary;
  TodaySummary? get summary => _summary;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _loading = false;
  bool get loading => _loading;

  bool _disposed = false;

  Future<void> load() async {
    _loading = true;
    _problem = null;
    _notify();
    try {
      final j = await _api.get('/pharmacies/$_pid/today');
      _summary = TodaySummary.fromJson(j as Map<String, dynamic>);
    } on ApiProblem catch (p) {
      // Keep what was shown before; the screen says it couldn't refresh.
      _problem = p;
    } finally {
      _loading = false;
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
