import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';
import 'package:lamp_shop/features/credit_record/credit_controller.dart';
import 'package:lamp_shop/features/credit_record/credit_models.dart';
import 'package:lamp_shop/features/plus/plus_controller.dart';

/// The credit record (plan 3.7, BDT 10 by CaaS) and LaMP Plus (plan 3.3):
/// one charge per purchase, the code from Banglalink, and nothing claimed
/// paid until the server says PAID.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late int saved;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, Object?> charge(String status, {int? attemptsLeft, String? reason}) => {
    'charge_id': 'ch-1',
    'status': status,
    'amount': 10.0,
    'attempts_left': attemptsLeft,
    'reason': reason,
  };

  ApiClient api() => ApiClient(
    baseUrl: 'https://api.test/api/v1',
    appVersion: '0.1.0+1',
    language: () => 'en',
    accessToken: () => 'tok',
    refresh: () async => false,
    http: MockClient((req) async {
      sent.add(req);
      return reply(req);
    }),
    backoff: (_) => Duration.zero,
  );

  const base = '/api/v1/pharmacies/green-life/credit-record';
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  PurchaseController purchase({int maxPolls = 40}) =>
      PurchaseController(api(), 'green-life', onPaid: () => saved++, pollEvery: Duration.zero, maxPolls: maxPolls);

  setUp(() {
    sent = [];
    saved = 0;
  });

  group('the record', () {
    test('a preview in plain numbers, and whether it was bought', () async {
      reply = (_) => http.Response(fixture('credit_record'), 200, headers: {'content-type': 'application/json'});
      final c = CreditRecordController(api(), MemoryCacheStore(), 'green-life');
      await c.load();
      expect(sent.single.url.path, base);
      expect(c.record!.billsTotal, 41);
      expect(c.record!.paidOnTime, 38);
      expect(c.record!.months, 12);
      expect(c.record!.purchased, isFalse);
    });

    test('bought: its share link', () {
      final r = CreditRecord.fromJson(jsonDecode(fixture('credit_record_bought')) as Map<String, dynamic>);
      expect(r.purchased, isTrue);
      expect(r.activeShare!.lenderName, 'City Bank Bogura');
      expect(r.activeShare!.views, 2);
      expect(r.activeShare!.url, startsWith('https://'));
    });
  });

  group('buying it', () {
    test('Buy asks once, with its own key; Banglalink sends a code', () async {
      reply = (_) => json(charge('OTP_SENT'), 201);
      final p = purchase();
      await p.start();
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '$base/purchases');
      expect(sent.single.headers['Idempotency-Key'], isNotNull);
      expect(p.stage, PurchaseStage.code);
    });

    test('the right code, then checking until the server says PAID', () async {
      var polls = 0;
      reply = (req) {
        if (req.url.path.endsWith('/purchases')) return json(charge('OTP_SENT'), 201);
        if (req.url.path.endsWith('/otp')) return json(charge('VERIFYING'));
        polls++;
        return json(charge(polls < 3 ? 'VERIFYING' : 'PAID'));
      };
      final p = purchase();
      await p.start();
      await p.submit('123456');
      expect(sent.firstWhere((r) => r.url.path.endsWith('/otp')).url.path, '$base/purchases/ch-1/otp');
      expect(body(sent.firstWhere((r) => r.url.path.endsWith('/otp'))), {'otp': '123456'});
      expect(sent.where((r) => r.method == 'GET').every((r) => r.url.path == '$base/purchases/ch-1'), isTrue);
      expect(polls, 3);
      expect(p.stage, PurchaseStage.paid);
      expect(saved, 1, reason: 'the record reads again, now bought');
    });

    test('a wrong code: same charge, how many tries are left', () async {
      reply = (req) => req.url.path.endsWith('/purchases')
          ? json(charge('OTP_SENT'), 201)
          : json(charge('OTP_SENT', attemptsLeft: 2));
      final p = purchase();
      await p.start();
      await p.submit('000000');
      expect(p.stage, PurchaseStage.code);
      expect(p.attemptsLeft, 2);
      expect(sent.where((r) => r.url.path.endsWith('/purchases')), hasLength(1), reason: 'no new debit, ever');
    });

    test('not enough balance: the reason, and nothing was charged', () async {
      reply = (req) => req.url.path.endsWith('/purchases')
          ? json(charge('OTP_SENT'), 201)
          : json(charge('FAILED', reason: 'Not enough balance.'));
      final p = purchase();
      await p.start();
      await p.submit('123456');
      expect(p.stage, PurchaseStage.failed);
      expect(p.reason, 'Not enough balance.');
      expect(saved, 0);
    });

    test('the server refusing to start: charge_failed with its words', () async {
      reply = (_) => json({'detail': 'Not enough balance.', 'code': 'charge_failed'}, 402);
      final p = purchase();
      await p.start();
      expect(p.stage, PurchaseStage.failed);
      expect(p.problem!.code, 'charge_failed');
    });

    test('the code expired: nothing charged; buying again is a new key', () async {
      reply = (req) => req.url.path.endsWith('/purchases') ? json(charge('OTP_SENT'), 201) : json(charge('EXPIRED'));
      final p = purchase();
      await p.start();
      await p.submit('123456');
      expect(p.stage, PurchaseStage.expired);
      await p.start();
      final keys = sent.where((r) => r.url.path.endsWith('/purchases')).map((r) => r.headers['Idempotency-Key']);
      expect(keys.toSet(), hasLength(2));
    });

    test('Banglalink slow to confirm: stop checking, say so, check again on request', () async {
      var paid = false;
      reply = (req) {
        if (req.url.path.endsWith('/purchases')) return json(charge('OTP_SENT'), 201);
        if (req.url.path.endsWith('/otp')) return json(charge('VERIFYING'));
        return json(charge(paid ? 'PAID' : 'UNKNOWN'));
      };
      final p = purchase(maxPolls: 4);
      await p.start();
      await p.submit('123456');
      expect(p.stage, PurchaseStage.waiting);
      expect(sent.where((r) => r.method == 'GET'), hasLength(4));
      paid = true;
      await p.checkAgain();
      expect(p.stage, PurchaseStage.paid);
      expect(sent.where((r) => r.url.path.endsWith('/purchases')), hasLength(1));
    });

    test('offline while sending the code: plain words, the code can be sent again', () async {
      var down = false;
      reply = (req) {
        if (down) throw http.ClientException('no network');
        return json(charge('OTP_SENT'), 201);
      };
      final p = purchase();
      await p.start();
      down = true;
      await p.submit('123456');
      expect(p.stage, PurchaseStage.code);
      expect(p.problem!.code, 'offline');
    });
  });

  group('sharing it', () {
    test('a link for one lender, for 7 days; and taking it back', () async {
      reply = (req) => req.method == 'DELETE'
          ? http.Response('', 204)
          : json({
              'id': 'sh-2',
              'lender_name': 'BRAC Bank',
              'url': 'https://lamp-api-k2xf.onrender.com/r/x',
              'expires_at': '2026-12-04T06:00:00+06:00',
              'views': 0,
            }, 201);
      final a = CreditActions(api(), 'green-life', onSaved: () => saved++);
      final s = await a.share('BRAC Bank');
      expect(sent.single.url.path, '$base/shares');
      expect(body(sent.single), {'lender_name': 'BRAC Bank', 'expires_in_days': 7});
      expect(s.url, 'https://lamp-api-k2xf.onrender.com/r/x');
      await a.revoke('sh-2');
      expect(sent.last.method, 'DELETE');
      expect(sent.last.url.path, '$base/shares/sh-2');
      expect(saved, 2);
    });

    test('the PDF, as bytes', () async {
      reply = (_) => http.Response.bytes([0x25, 0x50, 0x44, 0x46], 200, headers: {'content-type': 'application/pdf'});
      final bytes = await CreditActions(api(), 'green-life').pdf();
      expect(sent.single.url.path, '$base/pdf');
      expect(bytes, [0x25, 0x50, 0x44, 0x46]);
    });
  });

  group('LaMP Plus', () {
    const plus = '/api/v1/pharmacies/green-life/plus';

    test('where it stands', () async {
      reply = (_) => http.Response(fixture('plus'), 200, headers: {'content-type': 'application/json'});
      final c = PlusController(api(), MemoryCacheStore(), 'green-life');
      await c.load();
      expect(sent.single.url.path, plus);
      expect(c.plus!.status, PlusStatus.none);
    });

    test('Agree sends the consent; the code finishes it', () async {
      reply = (req) => json({
        'status': req.url.path.endsWith('/subscribe') ? 'OTP_SENT' : 'ACTIVE',
        'renews_on': req.url.path.endsWith('/subscribe') ? null : '2026-12-27',
      }, req.url.path.endsWith('/subscribe') ? 202 : 200);
      final a = PlusActions(api(), 'green-life', onSaved: () => saved++);
      expect((await a.subscribe()).status, PlusStatus.otpSent);
      expect(sent.single.url.path, '$plus/subscribe');
      expect(body(sent.single), {
        'consent': {'price_text': plusPriceText, 'wording_version': plusConsentVersion},
      });
      final on = await a.confirm('123456');
      expect(sent.last.url.path, '$plus/otp');
      expect(body(sent.last), {'otp': '123456'});
      expect(on.status, PlusStatus.active);
      expect(on.renewsOn, DateTime(2026, 12, 27));
      expect(saved, 2, reason: '/me reads again, so the Plus screens unlock');
    });

    test('cancel', () async {
      reply = (_) => json({'status': 'STOPPED', 'renews_on': null});
      final s = await PlusActions(api(), 'green-life').cancel();
      expect(sent.single.url.path, '$plus/cancel');
      expect(s.status, PlusStatus.stopped);
    });

    test('every state, and an unknown one reads as none', () {
      PlusStatus p(String s) => PlusState.fromJson({'status': s}).status;
      expect(
        [p('NONE'), p('OTP_SENT'), p('PENDING'), p('ACTIVE'), p('BLOCKED'), p('STOPPED'), p('X')],
        [
          PlusStatus.none,
          PlusStatus.otpSent,
          PlusStatus.pending,
          PlusStatus.active,
          PlusStatus.blocked,
          PlusStatus.stopped,
          PlusStatus.none,
        ],
      );
    });
  });
}
