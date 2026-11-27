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
  /// For a read that answers a JSON object.
  ///
  /// [fetch] replaces the GET, for a read the server answers to a POST
  /// (`/funding-plan`).
  CachedRead(ApiClient api, CacheStore cache, String path, T Function(Map<String, dynamic>) parse,
      {Listenable? refreshOn, DateTime Function()? now, Future<Object?> Function()? fetch})
      : this._(api, cache, path, (j) => j is Map<String, dynamic> ? parse(j) : null,
            refreshOn: refreshOn, now: now, fetch: fetch);

  /// For a read that answers a JSON list, like `GET /customers`.
  CachedRead.list(ApiClient api, CacheStore cache, String path, T Function(List<dynamic>) parse,
      {Listenable? refreshOn, DateTime Function()? now})
      : this._(api, cache, path, (j) => j is List ? parse(j) : null, refreshOn: refreshOn, now: now);

  CachedRead._(this._api, this._cache, this.path, this._parse,
      {Listenable? refreshOn, DateTime Function()? now, Future<Object?> Function()? fetch})
      : _now = now ?? DateTime.now,
        _fetch = fetch,
        _refreshOn = refreshOn {
    _refreshOn?.addListener(load);
  }

  final ApiClient _api;
  final CacheStore _cache;

  /// The API path, which is also the cache key: it carries the shop's id.
  final String path;
  /// Null when the answer has the wrong shape (an object for a list).
  final T? Function(Object?) _parse;
  final DateTime Function() _now;
  final Future<Object?> Function()? _fetch;

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

  bool _loading = false;

  /// A read is on its way.
  bool get loading => _loading;

  bool _disposed = false;

  Future<void> load() async {
    _problem = null;
    _loading = true;
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
      final j = await (_fetch?.call() ?? _api.get(path));
      final parsed = _tryParse(j);
      // No detail: the owner reads the plain-words line, not ours.
      if (parsed == null) throw const ApiProblem('unknown');
      _data = parsed;
      _savedAt = _now().toUtc();
      await _cache.write(path, j, at: _savedAt);
    } on ApiProblem catch (p) {
      _problem = p;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Null for an answer the app can't read, so a changed shape shows as a
  /// plain problem rather than a screen stuck loading.
  T? _tryParse(Object? json) {
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
