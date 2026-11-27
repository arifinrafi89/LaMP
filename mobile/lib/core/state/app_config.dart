import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/problem.dart';

/// Compares `1.2.3+45` versions part by part, as numbers; the build number
/// counts only when both have one. A version that can't be read compares
/// equal, so a typo on the server never locks an owner out.
int compareVersions(String a, String b) {
  List<int>? parts(String v) {
    final m = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+(\d+))?$').firstMatch(v.trim());
    if (m == null) return null;
    return [for (var i = 1; i <= 4; i++) int.tryParse(m[i] ?? '') ?? (i == 4 ? -1 : 0)];
  }

  final x = parts(a), y = parts(b);
  if (x == null || y == null) return 0;
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  if (x[3] < 0 || y[3] < 0) return 0;
  return x[3].compareTo(y[3]);
}

enum UpdateState {
  ok,

  /// A newer version exists: a banner the owner can put off.
  available,

  /// This version is below the minimum: a full screen with the Play link.
  required,

  /// The server is being updated.
  maintenance,
}

/// `GET /app/config` at launch (plan 13.5). Any failure to read it leaves
/// the app open as usual.
class AppConfigController extends ChangeNotifier {
  AppConfigController(this._api, {required this.appVersion});

  final ApiClient _api;
  final String appVersion;

  UpdateState _state = UpdateState.ok;
  UpdateState get state => _later && _state == UpdateState.available ? UpdateState.ok : _state;

  bool _later = false;

  String? _playUrl;
  String? get playUrl => _playUrl;

  Future<void> load() async {
    try {
      final j = await _api.get('/app/config') as Map<String, dynamic>;
      _playUrl = j['play_url'] as String?;
      if (j['maintenance'] == true) {
        _state = UpdateState.maintenance;
      } else if (compareVersions(appVersion, (j['min_version'] as String?) ?? '') < 0) {
        _state = UpdateState.required;
      } else if (compareVersions(appVersion, (j['latest_version'] as String?) ?? '') < 0) {
        _state = UpdateState.available;
      } else {
        _state = UpdateState.ok;
      }
    } on ApiProblem {
      // Offline or the server asleep: open as usual.
    } on Object catch (e) {
      debugPrint('LaMP: could not read /app/config: $e');
    }
    notifyListeners();
  }

  /// The banner, put off for this session.
  void later() {
    _later = true;
    notifyListeners();
  }

  /// The server answered 426 to a request: this version may not write.
  void serverSaysUpdate() {
    if (_state == UpdateState.required) return;
    _state = UpdateState.required;
    notifyListeners();
  }
}
