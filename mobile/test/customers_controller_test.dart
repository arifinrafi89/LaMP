import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/api/problem.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';
import 'package:lamp_shop/features/customers/customers_controller.dart';
import 'package:lamp_shop/features/customers/customers_models.dart';

/// Customers (plan 2.2): the list is read from the phone first, and every
/// change goes to the server once, however often the owner taps Save.
void main() {
  final customers = File('test/fixtures/customers.json').readAsStringSync();
  final card = File('test/fixtures/card.json').readAsStringSync();
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late int saved;

  http.Response json(Object body, [int status = 200]) => http.Response(
    body is String ? body : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

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

  CustomerActions actions() => CustomerActions(api(), 'green-life', onSaved: () => saved++);
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  setUp(() {
    sent = [];
    saved = 0;
    reply = (_) => json(customers);
  });

  group('the list', () {
    test('reads every customer and keeps it on the phone', () async {
      final cache = MemoryCacheStore();
      final c = CustomersController(api(), cache, 'green-life');
      await c.load();
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/customers');
      expect(c.customers!.items, hasLength(4));
      expect((await cache.read('/pharmacies/green-life/customers'))!.json, isA<List>());
    });

    test('offline, the kept list shows', () async {
      final cache = MemoryCacheStore();
      await cache.write('/pharmacies/green-life/customers', jsonDecode(customers));
      reply = (_) => throw http.ClientException('no network');
      final c = CustomersController(api(), cache, 'green-life');
      await c.load();
      expect(c.customers!.items, hasLength(4));
      expect(c.problem!.code, 'offline');
    });

    test('an answer that is not a list is a plain problem, not a crash', () async {
      reply = (_) => json({'detail': 'changed'});
      final c = CustomersController(api(), MemoryCacheStore(), 'green-life');
      await c.load();
      expect(c.customers, isNull);
      expect(c.problem!.code, 'unknown');
    });
  });

  group('changes', () {
    test('adding a customer: the amount and since when, nothing else', () async {
      reply = (_) => json({
        'code': 'GL-2WSX-3EDC',
        'label': 'Customer 006',
        'join': {'text': 'LAMP GL2WSX3EDC', 'to': '21213'},
      }, 201);
      final made = await actions().add(amount: 1200, since: DateTime(2026, 11, 27), key: 'k-1');
      final r = sent.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/api/v1/pharmacies/green-life/customers');
      expect(body(r), {'amount': 1200.0, 'since': '2026-11-27'});
      expect(r.headers['Idempotency-Key'], 'k-1');
      expect(made.label, 'Customer 006');
      expect(made.join.text, 'LAMP GL2WSX3EDC');
      expect(saved, 1);
    });

    test('a sale', () async {
      reply = (_) => json({'code': 'GL-7KQM-4XPA', 'amount': 7000.0}, 201);
      final owes = await actions().sale('GL-7KQM-4XPA', amount: 500, on: DateTime(2026, 11, 27), key: 'k-2');
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/customers/GL-7KQM-4XPA/sales');
      expect(body(sent.single), {'amount': 500.0, 'on': '2026-11-27'});
      expect(sent.single.headers['Idempotency-Key'], 'k-2');
      expect(owes, 7000);
      expect(saved, 1);
    });

    test('a payment, with how it was paid', () async {
      reply = (_) => json({'code': 'GL-7KQM-4XPA', 'amount': 4875.0}, 201);
      final owes = await actions().payment(
        'GL-7KQM-4XPA',
        amount: 1625,
        on: DateTime(2026, 11, 26),
        method: 'bkash',
        key: 'k-3',
      );
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/customers/GL-7KQM-4XPA/payments');
      expect(body(sent.single), {'amount': 1625.0, 'on': '2026-11-26', 'method': 'bkash'});
      expect(owes, 4875);
    });

    test('a failed save keeps nothing and says why', () async {
      reply = (_) => throw http.ClientException('no network');
      await expectLater(
        actions().payment('GL-7KQM-4XPA', amount: 100, on: DateTime(2026, 11, 26), method: 'cash', key: 'k'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'offline')),
      );
      expect(saved, 0);
    });

    test('plan choices come from the card', () async {
      reply = (_) => json(card);
      final c = await actions().choices('GL-3HFD-9WQT');
      expect(sent.single.url.path, '/api/v1/cards/GL-3HFD-9WQT');
      expect(c.options.map((o) => o.parts), [1, 2, 4]);
      expect(saved, 0, reason: 'reading changes nothing');
    });

    test('setting a plan', () async {
      reply = (_) => json(card);
      await actions().setPlan('GL-3HFD-9WQT', parts: 4, firstOn: DateTime(2026, 12, 1));
      expect(sent.single.method, 'PUT');
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/customers/GL-3HFD-9WQT/plan');
      expect(body(sent.single), {'parts': 4, 'first_on': '2026-12-01'});
      expect(saved, 1);
    });

    test('the family\'s number, with their consent', () async {
      reply = (_) => json({'sms_status': 'PENDING'}, 202);
      final s = await actions().addPhone('GL-8NBV-2KLM', phone: '+8801912345678', language: 'bn');
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/customers/GL-8NBV-2KLM/phone');
      expect(body(sent.single), {
        'phone': '+8801912345678',
        'language': 'bn',
        'consent': {'agreed': true, 'wording_version': familyConsentVersion},
      });
      expect(s, SmsStatus.pending);
      expect(saved, 1);
    });

    test('while masking is on the server says join by text', () async {
      reply = (_) => json({'detail': 'Counter route is off', 'code': 'join_by_text'}, 403);
      await expectLater(
        actions().addPhone('GL-8NBV-2KLM', phone: '+8801912345678', language: 'bn'),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'join_by_text')),
      );
    });

    test('stop SMS, and a reminder now', () async {
      reply = (req) =>
          json({'sms_status': req.method == 'DELETE' ? 'STOPPED' : 'ON'}, req.method == 'DELETE' ? 200 : 202);
      expect(await actions().remind('GL-7KQM-4XPA'), SmsStatus.on);
      expect(sent.last.url.path, '/api/v1/pharmacies/green-life/customers/GL-7KQM-4XPA/remind');
      expect(await actions().stopSms('GL-7KQM-4XPA'), SmsStatus.stopped);
      expect(sent.last.method, 'DELETE');
      expect(sent.last.url.path, '/api/v1/pharmacies/green-life/customers/GL-7KQM-4XPA/phone');
      expect(saved, 2);
    });
  });
}
