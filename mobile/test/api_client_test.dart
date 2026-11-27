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

  test('a caller retrying the same save passes its own key', () async {
    final api = client((_) async => json({'ok': true}, 201));
    await api.post('/pharmacies/p1/opening', {'cash_on_hand': 5}, idempotencyKey: 'k-1');
    await api.post('/pharmacies/p1/opening', {'cash_on_hand': 5}, idempotencyKey: 'k-1');
    expect(sent.map((r) => r.headers['Idempotency-Key']), ['k-1', 'k-1']);
  });

  test('a success that is not JSON is a problem, not a silent null', () async {
    final api = client((_) async => http.Response('<html>waking up</html>', 200));
    await expectLater(api.get('/pharmacies/p1/today'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'unknown')));
  });

  test('an empty success body is fine', () async {
    final api = client((_) async => http.Response('', 204));
    expect(await api.post('/pharmacies/p1/setup/complete', null), isNull);
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

  group('upload', () {
    final photo = List<int>.generate(64, (i) => i);

    Future<Object?> send(ApiClient api, {String key = 'k-1'}) => api.upload(
          '/pharmacies/green-life/captures',
          fields: {'kind': 'invoice'},
          bytes: photo,
          filename: 'bill.jpg',
          contentType: 'image/jpeg',
          idempotencyKey: key,
        );

    test('sends the file and kind as multipart, with the key and session', () async {
      final api = client((_) async => json({'id': 'cap-1'}));
      expect(await send(api), {'id': 'cap-1'});
      final req = sent.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/pharmacies/green-life/captures');
      expect(req.headers['content-type'], startsWith('multipart/form-data; boundary='));
      expect(req.headers['Idempotency-Key'], 'k-1');
      expect(req.headers['Authorization'], 'Bearer old');
      expect(req.headers['X-App-Version'], '1.0.3+12');
      final body = latin1.decode(req.bodyBytes);
      expect(body, contains('name="kind"\r\n\r\ninvoice'));
      expect(body, contains('name="file"; filename="bill.jpg"'));
      expect(body, contains('content-type: image/jpeg'));
      expect(req.bodyBytes.length, greaterThan(photo.length));
    });

    test('a 401 refreshes once and sends the same file and key again', () async {
      var calls = 0;
      final api = client((_) async => ++calls == 1 ? json({'detail': 'expired'}, 401) : json({'id': 'cap-1'}));
      await send(api);
      expect(refreshes, 1);
      expect(sent, hasLength(2));
      expect(sent[1].headers['Authorization'], 'Bearer fresh');
      expect(sent[1].headers['Idempotency-Key'], 'k-1');
      // A multipart body is a stream that can be read once: the replay must
      // build it again, or it goes out empty.
      expect(latin1.decode(sent[1].bodyBytes), contains('name="file"; filename="bill.jpg"'));
      expect(sent[1].bodyBytes.length, sent[0].bodyBytes.length);
    });

    test('a network error is not retried here: the owner sends it again', () async {
      final api = client((_) async => throw http.ClientException('no network'));
      await expectLater(send(api), throwsA(isA<ApiProblem>().having((p) => p.code, 'code', ApiProblem.offline)));
      expect(sent, hasLength(1));
    });

    test('a file over the server limit reads as too_large', () async {
      final api = client((_) async => json({'detail': 'Request Entity Too Large'}, 413));
      await expectLater(send(api), throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'too_large')));
      expect(problemMessage(L10nEn(), const ApiProblem('too_large')),
          'This file is too big to send. Take the photo again, or pick a smaller file.');
    });

    test('the scan limit keeps the day it resets on', () async {
      final api = client((_) async => json(
          {'detail': 'limit', 'code': 'scan_limit_reached', 'resets_on': '2026-12-01'}, 402));
      await expectLater(
          send(api),
          throwsA(isA<ApiProblem>()
              .having((p) => p.code, 'code', 'scan_limit_reached')
              .having((p) => p.resetsOn, 'resetsOn', DateTime(2026, 12, 1))));
    });
  });

  group('getBytes (a PDF behind the session)', () {
    test('returns the bytes as sent, with the session', () async {
      final pdf = [0x25, 0x50, 0x44, 0x46, 0x2D];
      final api = client((_) async => http.Response.bytes(pdf, 200, headers: {'content-type': 'application/pdf'}));
      expect(await api.getBytes('/pharmacies/green-life/credit-record/pdf'), pdf);
      expect(sent.single.method, 'GET');
      expect(sent.single.headers['Authorization'], 'Bearer old');
    });

    test('an expired token is refreshed once, then the bytes', () async {
      final api = client((req) async => req.headers['Authorization'] == 'Bearer old'
          ? json({'detail': 'expired'}, 401)
          : http.Response.bytes([1, 2, 3], 200));
      expect(await api.getBytes('/x'), [1, 2, 3]);
      expect(refreshes, 1);
    });

    test('a refusal is the server code, not bytes', () async {
      final api = client((_) async => json({'detail': 'Not bought yet', 'code': 'not_found'}, 404));
      await expectLater(api.getBytes('/x'), throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'not_found')));
    });
  });
}
