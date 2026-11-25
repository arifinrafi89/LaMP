import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'problem.dart';

/// The one way the app talks to the LaMP server (plan 5.3, rules in 2.1).
///
/// - Reads time out after 15 s, uploads after 60 s.
/// - A GET is retried twice, with backoff, after a network error. Nothing
///   else is retried here: a POST that may have reached the server is only
///   safe to repeat with its Idempotency-Key, which the outbox does (Phase 2).
/// - A 401 triggers one token refresh, then the request is replayed once.
/// - Money POSTs carry an `Idempotency-Key`; every request carries
///   `X-App-Version` and `Accept-Language`.
/// - Errors arrive as [ApiProblem], with the server's `code`.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.appVersion,
    required this.language,
    required this.accessToken,
    required this.refresh,
    http.Client? http,
    Duration Function(int attempt)? backoff,
  })  : _http = http ?? _defaultClient(),
        _backoff = backoff ?? _defaultBackoff;

  /// For example `https://lamp-api.onrender.com/api/v1`, from
  /// `--dart-define=LAMP_API_URL=…`. On web it is `/api/v1`: the static site
  /// rewrites `/api/*` to the API, so the browser sees one origin.
  final String baseUrl;
  final String appVersion;

  /// `bn` or `en`, read on every request so a language change applies at once.
  final String Function() language;

  /// The current access token, or empty when signed out.
  final String Function() accessToken;

  /// Gets a new access token. Returns false when the session is over.
  final Future<bool> Function() refresh;

  final http.Client _http;
  final Duration Function(int attempt) _backoff;

  static const readTimeout = Duration(seconds: 15);
  static const uploadTimeout = Duration(seconds: 60);
  static const _getAttempts = 3;

  static http.Client _defaultClient() => http.Client();

  static Duration _defaultBackoff(int attempt) =>
      Duration(milliseconds: 400 * (1 << attempt) + Random().nextInt(250));

  Future<Object?> get(String path) => _send('GET', path, retry: true);

  Future<Object?> post(String path, Object? body, {bool idempotent = false}) =>
      _send('POST', path, body: body, idempotencyKey: idempotent ? newUuid() : null);

  Future<Object?> put(String path, Object? body) => _send('PUT', path, body: body);

  Future<Object?> patch(String path, Object? body) => _send('PATCH', path, body: body);

  Future<Object?> delete(String path) => _send('DELETE', path);

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    bool retry = false,
  }) async {
    var refreshed = false;
    while (true) {
      final response = await _withRetry(
        () => _once(method, path, body, idempotencyKey),
        attempts: retry ? _getAttempts : 1,
      );
      if (response.statusCode == 401 && !refreshed) {
        refreshed = true;
        if (await refresh()) continue;
        throw const ApiProblem('session_expired', status: 401);
      }
      return _decode(response);
    }
  }

  Future<http.Response> _withRetry(
    Future<http.Response> Function() call, {
    required int attempts,
  }) async {
    for (var i = 0;; i++) {
      try {
        return await call();
      } on Object catch (e) {
        if (!_isNetworkError(e)) rethrow;
        if (i + 1 >= attempts) {
          throw ApiProblem(ApiProblem.offline, detail: e.toString());
        }
        await Future<void>.delayed(_backoff(i));
      }
    }
  }

  static bool _isNetworkError(Object e) =>
      e is http.ClientException || e is TimeoutException;

  Future<http.Response> _once(
    String method,
    String path,
    Object? body,
    String? idempotencyKey,
  ) {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers(idempotencyKey));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    return _http.send(request).then(http.Response.fromStream).timeout(readTimeout);
  }

  Map<String, String> _headers(String? idempotencyKey) {
    final token = accessToken();
    return {
      'Accept': 'application/json',
      'X-App-Version': appVersion,
      'Accept-Language': language(),
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Idempotency-Key': ?idempotencyKey,
    };
  }

  Object? _decode(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    Object? json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return json;

    final m = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final detail = m['detail'] is String ? m['detail'] as String : null;
    final retry = m['retry_after'];
    final code = switch (r.statusCode) {
      426 => 'update_required',
      401 => 'session_expired',
      _ => m['code'] is String ? m['code'] as String : _codeFor(r.statusCode),
    };
    throw ApiProblem(
      code,
      detail: detail,
      status: r.statusCode,
      retryAfter: retry is num ? Duration(seconds: retry.round()) : null,
    );
  }

  static String _codeFor(int status) => switch (status) {
        404 => 'not_found',
        422 => 'invalid',
        429 => 'rate_limited',
        503 => 'applink_down',
        _ => 'unknown',
      };

  void close() => _http.close();
}

final _random = Random.secure();

/// A random (version 4) UUID, for Idempotency-Key and device ids.
String newUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
