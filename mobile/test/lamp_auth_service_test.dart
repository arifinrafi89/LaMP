import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/api/problem.dart';
import 'package:lamp_shop/core/auth/auth_service.dart';
import 'package:lamp_shop/core/auth/lamp_auth_service.dart';

/// The /auth/* shapes from plan 2.2 (owner [A]), as the app sends and reads
/// them.
void main() {
  late List<http.Request> sent;

  LampAuthService service(MockClientHandler handler, {String token = ''}) {
    final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      appVersion: '0.1.0+1',
      language: () => 'en',
      accessToken: () => token,
      refresh: () async => false,
      http: MockClient((r) {
        sent.add(r);
        return handler(r);
      }),
      backoff: (_) => Duration.zero,
    );
    return LampAuthService(api);
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  setUp(() => sent = []);

  const device = DeviceInfo(id: 'd-1', name: 'Android phone', os: 'android', appVersion: '0.1.0+1');

  test('requesting a code sends the number and language', () async {
    final s = service((_) async =>
        json({'challenge_id': 'c-9', 'expires_in': 300, 'resend_after': 30}, 202));
    final c = await s.requestCode('+8801912345678', 'bn');
    expect(sent.single.url.path, '/api/v1/auth/otp/request');
    expect(bodyOf(sent.single), {'phone': '+8801912345678', 'language': 'bn'});
    expect(c.challengeId, 'c-9');
    expect(c.phone, '+8801912345678');
    expect(c.expiresIn, const Duration(minutes: 5));
    expect(c.resendAfter, const Duration(seconds: 30));
  });

  test('verifying sends the code and this device, and reads the session', () async {
    final s = service((_) async => json({
          'access_token': 'acc',
          'expires_at': '2026-11-26T10:15:00+06:00',
          'refresh_token': 'ref',
          'owner': {'id': 'o-1', 'phone_masked': '+880 19•• ••5678', 'language': 'bn'},
          'pharmacy': null,
          'is_new': true,
        }));
    final challenge = OtpChallenge(
        challengeId: 'c-9', phone: '+8801912345678',
        expiresIn: const Duration(minutes: 5), resendAfter: const Duration(seconds: 30));
    final signedIn = await s.verifyCode(challenge, '123456', device);

    expect(sent.single.url.path, '/api/v1/auth/otp/verify');
    expect(bodyOf(sent.single), {
      'challenge_id': 'c-9',
      'code': '123456',
      'device': {'id': 'd-1', 'name': 'Android phone', 'os': 'android', 'app_version': '0.1.0+1'},
    });
    expect(signedIn.tokens.accessToken, 'acc');
    expect(signedIn.tokens.refreshToken, 'ref');
    expect(signedIn.owner.phoneMasked, '+880 19•• ••5678');
    expect(signedIn.owner.language, 'bn');
    expect(signedIn.pharmacy, isNull);
    expect(signedIn.isNew, isTrue);
  });

  test('a returning owner gets their shop back', () async {
    final s = service((_) async => json({
          'access_token': 'acc',
          'expires_at': '2026-11-26T10:15:00+06:00',
          'owner': {'id': 'o-1', 'phone_masked': 'x', 'language': 'en'},
          'pharmacy': {'id': 'green-life', 'name': 'Green Life Pharmacy', 'setup_complete': true},
          'is_new': false,
        }));
    final r = await s.verifyCode(
        OtpChallenge(challengeId: 'c', phone: 'p', expiresIn: Duration.zero, resendAfter: Duration.zero),
        '123456', device);
    expect(r.pharmacy!.name, 'Green Life Pharmacy');
    expect(r.pharmacy!.setupComplete, isTrue);
    // Web: the refresh token is an httpOnly cookie, so the body has none.
    expect(r.tokens.refreshToken, isNull);
  });

  test('refresh rotates the pair', () async {
    final s = service((_) async => json({'access_token': 'a2', 'refresh_token': 'r2'}));
    final pair = await s.refresh('r1');
    expect(sent.single.url.path, '/api/v1/auth/refresh');
    expect(bodyOf(sent.single), {'refresh_token': 'r1'});
    expect(pair!.accessToken, 'a2');
    expect(pair.refreshToken, 'r2');
  });

  test('on web, refresh relies on the cookie and sends no token', () async {
    final s = service((_) async => json({'access_token': 'a2'}));
    await s.refresh(null);
    expect(bodyOf(sent.single), isEmpty);
  });

  test('a refused refresh means the session is over', () async {
    final s = service((_) async => json({'code': 'session_expired'}, 401));
    expect(await s.refresh('r1'), isNull);
  });

  test('being offline is not the end of the session', () async {
    final s = service((_) async => throw http.ClientException('down'));
    await expectLater(s.refresh('r1'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'offline')));
  });

  test('accepting the terms records the current versions', () async {
    final s = service((r) async => r.method == 'GET'
        ? json({'terms_version': 't-3', 'privacy_version': 'p-2', 'terms_url': 'u', 'privacy_url': 'v'})
        : json({}, 201), token: 'acc');
    await s.acceptTerms();
    expect(sent.map((r) => '${r.method} ${r.url.path}'),
        ['GET /api/v1/legal/current', 'POST /api/v1/me/consents']);
    expect(bodyOf(sent.last), {'terms_version': 't-3', 'privacy_version': 'p-2'});
    expect(sent.last.headers['Authorization'], 'Bearer acc');
  });

  test('signing out tells the server, and a failure there is ignored', () async {
    final s = service((_) async => json({'detail': 'gone'}, 500), token: 'acc');
    await s.signOut();
    expect(sent.single.url.path, '/api/v1/auth/sign-out');
  });
}
