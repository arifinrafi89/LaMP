import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/problem.dart';
import 'cache_store.dart';

/// One screen's read, from the phone first, then from the server
/// (plan 5.6, Phase 1).
///
/// - The kept copy shows at once, so a shop with no signal still opens.
/// - A fresh answer replaces it and is kept for next time.
/// - A failed refresh keeps what is shown and says why; with nothing kept,
///   the screen shows the problem and a way to try again.
class CachedRead<T> extends ChangeNotifier {
  CachedRead(this._api, this._cache, this.path, this._parse,
      {Listenable? refreshOn, DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _refreshOn = refreshOn {
    _refreshOn?.addListener(load);
  }

  final ApiClient _api;
  final CacheStore _cache;

  /// The API path, which is also the cache key: it carries the shop's id.
  final String path;
  final T Function(Map<String, dynamic>) _parse;
  final DateTime Function() _now;

  /// Reads again whenever this rings (see ShopChanges).
  final Listenable? _refreshOn;

  T? _data;
  T? get data => _data;

  DateTime? _savedAt;

  /// When the data on screen came from the server.
  DateTime? get savedAt => _savedAt;

  ApiProblem? _problem;

  /// Why the last refresh failed; null after a good one.
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  Future<void> load() async {
    _problem = null;
    _notify();
    if (_data == null) {
      final kept = await _cache.read(path);
      final parsed = kept == null ? null : _tryParse(kept.json);
      if (parsed != null && _data == null) {
        _data = parsed;
        _savedAt = kept!.savedAt;
        _notify();
      }
    }
    try {
      final j = await _api.get(path);
      final parsed = _tryParse(j);
      // No detail: the owner reads the plain-words line, not ours.
      if (parsed == null) throw const ApiProblem('unknown');
      _data = parsed;
      _savedAt = _now().toUtc();
      await _cache.write(path, j, at: _savedAt);
    } on ApiProblem catch (p) {
      _problem = p;
    } finally {
      _notify();
    }
  }

  /// Null for an answer the app can't read, so a changed shape shows as a
  /// plain problem rather than a screen stuck loading.
  T? _tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return _parse(json);
    } on Object catch (e) {
      debugPrint('LaMP: could not read $path: $e');
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _refreshOn?.removeListener(load);
    _disposed = true;
    super.dispose();
  }
}
