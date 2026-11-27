import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';
import 'package:lamp_shop/features/approvals/approvals_controller.dart';
import 'package:lamp_shop/features/cash/cash_controller.dart';
import 'package:lamp_shop/features/plan/plan_controller.dart';
import 'package:lamp_shop/features/plan/plan_models.dart';

/// Cash, Plan and Approvals read from the phone first; every change goes to
/// the server once.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late int saved;

  http.Response ok(String body, [int status = 200]) =>
      http.Response(body, status, headers: {'content-type': 'application/json; charset=utf-8'});

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

  MoneyActions actions() => MoneyActions(api(), 'green-life', onSaved: () => saved++);
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  setUp(() {
    sent = [];
    saved = 0;
  });

  test('cash: the forecast', () async {
    reply = (_) => ok(fixture('forecast'));
    final c = CashController(api(), MemoryCacheStore(), 'green-life');
    await c.load();
    expect(sent.single.method, 'GET');
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/forecast');
    expect(c.forecast!.shortfalls, hasLength(5));
  });

  test('plan: asked with no body, kept, and shown offline next time', () async {
    reply = (_) => ok(fixture('funding_plan'));
    final cache = MemoryCacheStore();
    final p = PlanController(api(), cache, 'green-life');
    await p.load();
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/funding-plan');
    expect(sent.single.body, isEmpty);
    expect(p.plan!.need.amount, 8200);

    reply = (_) => throw http.ClientException('no network');
    final again = PlanController(api(), cache, 'green-life');
    await again.load();
    expect(again.plan!.need.amount, 8200);
    expect(again.problem!.code, 'offline');
  });

  test('approvals: the list, and pause', () async {
    reply = (req) => ok(fixture(req.url.path.endsWith('/pause') ? 'pause' : 'actions'));
    final a = ApprovalsController(api(), MemoryCacheStore(), 'green-life');
    await a.load();
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/actions');
    expect(a.actions!.waiting, hasLength(2));
    final pause = PauseController(api(), MemoryCacheStore(), 'green-life');
    await pause.load();
    expect(pause.pause!.paused, isFalse);
  });

  test('a plan step goes to Approvals as the owner\'s proposal', () async {
    reply = (_) => ok(jsonEncode((jsonDecode(fixture('actions')) as List).first));
    final step = PlanStep(
      kind: 'extension_request',
      label: 'Ask Supplier A for 20 more days on BDT 8,200',
      amount: 8200,
      when: DateTime(2026, 10, 16),
    );
    await actions().propose(step);
    final r = sent.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/api/v1/pharmacies/green-life/actions');
    expect(body(r), {
      'kind': 'extension_request',
      'payload': {'summary': 'Ask Supplier A for 20 more days on BDT 8,200', 'amount': 8200.0, 'when': '2026-10-16'},
    });
    expect(r.headers['Idempotency-Key'], isNotNull);
    expect(saved, 1);
  });

  test('approve and not now', () async {
    final executed = (jsonDecode(fixture('actions')) as List)[2] as Map<String, dynamic>;
    reply = (_) => ok(jsonEncode(executed));
    final done = await actions().approve('act-4');
    expect(sent.last.url.path, '/api/v1/pharmacies/green-life/actions/act-4/approve');
    expect(sent.last.headers['Idempotency-Key'], isNotNull);
    expect(done.status, 'executed');
    await actions().reject('act-3');
    expect(sent.last.url.path, '/api/v1/pharmacies/green-life/actions/act-3/reject');
    expect(saved, 2);
  });

  test('pause and resume', () async {
    reply = (req) => ok(jsonEncode({'paused': body(req)['paused'], 'changed_at': '2026-11-27T05:00:00Z'}));
    expect((await actions().setPause(true)).paused, isTrue);
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/pause');
    expect(body(sent.single), {'paused': true});
    expect(saved, 1);
  });

  test('orders and what to cut from each, read only', () async {
    reply = (req) => ok(fixture(req.url.path.endsWith('/trim') ? 'trim' : 'orders'));
    final orders = await actions().orders();
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/orders');
    final t = await actions().trim(orders.single.id);
    expect(sent.last.url.path, '/api/v1/pharmacies/green-life/orders/o-1/trim');
    expect(t.saving, 10800);
    expect(saved, 0);
  });
}
