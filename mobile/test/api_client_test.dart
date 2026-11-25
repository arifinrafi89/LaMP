import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/api/problem.dart';
import 'package:lamp_shop/l10n/app_localizations_en.dart';

/// Plan 5.3 and 2.1: timeouts, GET retry, one refresh on 401 then replay,
/// Idempotency-Key on money POSTs, X-App-Version and Accept-Language on every
/// request, and the server's error `code` carried to the screen.
void main() {
  late List<http.Request> sent;
  late String token;
  late int refreshes;

  ApiClient client(MockClientHandler handler, {Future<bool> Function()? refresh}) {
    return ApiClient(
      baseUrl: 'https://api.test/api/v1',
      appVersion: '1.0.3+12',
      language: () => 'bn',
      accessToken: () => token,
      refresh: refresh ??
          () async {
            refreshes++;
            token = 'fresh';
            return true;
          },
      http: MockClient((req) {
        sent.add(req);
        return handler(req);
      }),
      backoff: (_) => Duration.zero,
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body), status,
      headers: {'content-type': 'application/json'});

  setUp(() {
    sent = [];
    token = 'old';
    refreshes = 0;
  });

  test('a GET carries the session, app version and language', () async {
    final api = client((_) async => json({'ok': true}));
    final body = await api.get('/me');
    expect(body, {'ok': true});
    final h = sent.single.headers;
    expect(sent.single.url.toString(), 'https://api.test/api/v1/me');
    expect(h['Authorization'], 'Bearer old');
    expect(h['X-App-Version'], '1.0.3+12');
    expect(h['Accept-Language'], 'bn');
  });

  test('a GET is retried twice after a network error', () async {
    var calls = 0;
    final api = client((_) async {
      calls++;
      if (calls < 3) throw http.ClientException('no network');
      return json({'ok': true});
    });
    expect(await api.get('/today'), {'ok': true});
    expect(calls, 3);
  });

  test('after three network failures a GET reports offline', () async {
    final api = client((_) async => throw http.ClientException('no network'));
    await expectLater(
      api.get('/today'),
      throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'offline')),
    );
    expect(sent.length, 3);
  });

  test('a POST is never retried on a network error', () async {
    final api = client((_) async => throw http.ClientException('no network'));
    await expectLater(api.post('/customers', {'amount': 500}),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'offline')));
    expect(sent.length, 1);
  });

  test('a 401 refreshes once and replays with the new token', () async {
    final api = client((req) async => req.headers['Authorization'] == 'Bearer fresh'
        ? json({'ok': true})
        : json({'detail': 'expired', 'code': 'session_expired'}, 401));
    expect(await api.get('/me'), {'ok': true});
    expect(refreshes, 1);
    expect(sent.map((r) => r.headers['Authorization']), ['Bearer old', 'Bearer fresh']);
  });

  test('a second 401 ends the session without a second refresh', () async {
    final api = client((_) async => json({'detail': 'no', 'code': 'session_expired'}, 401));
    await expectLater(api.get('/me'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'session_expired')));
    expect(refreshes, 1);
  });

  test('a failed refresh ends the session', () async {
    final api = client((_) async => json({'detail': 'no'}, 401),
        refresh: () async => false);
    await expectLater(api.get('/me'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'session_expired')));
    expect(sent.length, 1);
  });

  test('the error body becomes a problem with its code and retry time', () async {
    final api = client((_) async =>
        json({'detail': 'Slow down', 'code': 'rate_limited', 'retry_after': 30}, 429));
    await expectLater(
      api.post('/auth/otp/request', {'phone': '01912345678'}),
      throwsA(isA<ApiProblem>()
          .having((p) => p.code, 'code', 'rate_limited')
          .having((p) => p.detail, 'detail', 'Slow down')
          .having((p) => p.retryAfter, 'retryAfter', const Duration(seconds: 30))
          .having((p) => p.status, 'status', 429)),
    );
  });

  test('426 means the app must be updated', () async {
    final api = client((_) async => json({'detail': 'old app'}, 426));
    await expectLater(api.get('/me'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'update_required')));
  });

  test('a money POST carries an Idempotency-Key, kept across the replay', () async {
    final api = client((req) async => req.headers['Authorization'] == 'Bearer fresh'
        ? json({'ok': true}, 201)
        : json({'code': 'session_expired'}, 401));
    await api.post('/pharmacies/p1/payments', {'amount': 1625}, idempotent: true);
    final keys = sent.map((r) => r.headers['Idempotency-Key']).toList();
    expect(keys[0], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(keys[1], keys[0]);
    expect(jsonDecode(sent.first.body), {'amount': 1625});
    expect(sent.first.headers['Content-Type'], startsWith('application/json'));
  });

  test('an ordinary POST has no Idempotency-Key', () async {
    final api = client((_) async => json({}, 202));
    await api.post('/auth/otp/request', {'phone': 'x'});
    expect(sent.single.headers.containsKey('Idempotency-Key'), isFalse);
  });

  test('no token means no Authorization header', () async {
    token = '';
    final api = client((_) async => json({}));
    await api.get('/app/config');
    expect(sent.single.headers.containsKey('Authorization'), isFalse);
  });

  group('problemMessage', () {
    final l = L10nEn();
    test('a known code gets the app\'s own words', () {
      expect(problemMessage(l, const ApiProblem('otp_wrong', detail: 'x')),
          "That code isn't right.");
      expect(problemMessage(l, const ApiProblem('plus_required')),
          'This is part of LaMP Plus.');
    });
    test('an unknown code falls back to the server\'s detail', () {
      expect(problemMessage(l, const ApiProblem('brand_new', detail: 'Plain words')),
          'Plain words');
    });
    test('with no detail either, a generic line', () {
      expect(problemMessage(l, const ApiProblem('brand_new')), 'Something went wrong. Try again.');
    });
  });
}
