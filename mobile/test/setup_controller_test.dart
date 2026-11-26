import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/state/session_controller.dart';
import 'package:lamp_shop/features/setup/setup_controller.dart';
import 'package:lamp_shop/features/setup/setup_models.dart';

import 'helpers.dart';

/// Setup (plan 5.2 and 2.2): the five steps, what each one sends, and what
/// happens when a save fails.
void main() {
  late List<http.Request> sent;
  late bool down;

  http.Response ok(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json; charset=utf-8'});

  final pharmacy = File('test/fixtures/pharmacy_new.json').readAsStringSync();

  MockClient server() => MockClient((req) async {
        sent.add(req);
        if (down) throw http.ClientException('no network');
        final route = '${req.method} ${req.url.path.replaceFirst('/api/v1', '')}';
        return switch (route) {
          'POST /pharmacies' => http.Response(pharmacy, 201,
              headers: {'content-type': 'application/json; charset=utf-8'}),
          'GET /pharmacies/green-life/suppliers' => ok([
              {'id': 's1', 'name': 'Square', 'payment_days': 30, 'return_cutoff_days': 60},
            ]),
          'POST /pharmacies/rahman-pharma/suppliers' =>
            ok({'id': 's9', ...jsonDecode(req.body) as Map<String, dynamic>}, 201),
          _ => ok({}, 201),
        };
      });

  late SessionController session;
  late SetupController setup;

  Future<void> start({bool hasShop = false, Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    session = await signedInSession(hasShop: hasShop, setupComplete: false);
    final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      appVersion: '0.1.0+1',
      language: () => 'en',
      accessToken: () => session.accessToken,
      refresh: session.refreshNow,
      http: server(),
      backoff: (_) => Duration.zero,
    );
    setup = SetupController(api, session, now: () => DateTime.utc(2026, 11, 26, 19));
    await setup.init();
  }

  http.Request last(String method, String path) =>
      sent.lastWhere((r) => r.method == method && r.url.path == '/api/v1$path');

  setUp(() {
    sent = [];
    down = false;
  });

  test('a new owner starts by naming the shop, which can\'t be skipped', () async {
    await start();
    expect(setup.step, SetupStep.shop);
    await setup.skip();
    expect(setup.step, SetupStep.shop);
  });

  test('naming the shop creates it, and the session now has it', () async {
    await start();
    final ok = await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura', area: 'Satmatha');
    expect(ok, isTrue);
    expect(jsonDecode(last('POST', '/pharmacies').body),
        {'name': 'Rahman Pharma', 'city': 'Bogura', 'area': 'Satmatha'});
    expect(session.pharmacy!.id, 'rahman-pharma');
    expect(session.pharmacy!.setupComplete, isFalse);
    expect(setup.step, SetupStep.suppliers);
  });

  test('a supplier is saved as it is added', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    await setup.addSupplier(const Supplier(name: 'Square', phone: '01711000000', paymentDays: 45, returnCutoffDays: 90));
    expect(jsonDecode(last('POST', '/pharmacies/rahman-pharma/suppliers').body), {
      'name': 'Square',
      'phone': '01711000000',
      'payment_days': 45,
      'return_cutoff_days': 90,
    });
    expect(setup.suppliers.single.id, 's9');
  });

  test('opening cash is sent with today\'s Dhaka date and a key', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    await setup.skip();
    expect(setup.step, SetupStep.cash);
    await setup.saveCash(25000);
    final r = last('POST', '/pharmacies/rahman-pharma/opening');
    // 19:00 UTC on the 26th is 01:00 on the 27th in Dhaka.
    expect(jsonDecode(r.body), {'cash_on_hand': 25000.0, 'as_of': '2026-11-27'});
    expect(r.headers['Idempotency-Key'], isNotEmpty);
    expect(setup.step, SetupStep.expenses);
  });

  test('a failed save keeps its key for the retry, and says why', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    down = true;
    expect(await setup.saveCash(25000), isFalse);
    expect(setup.problem!.code, 'offline');
    expect(setup.step, SetupStep.suppliers);
    down = false;
    await setup.saveCash(25000);
    final keys = sent
        .where((r) => r.url.path.endsWith('/opening'))
        .map((r) => r.headers['Idempotency-Key'])
        .toSet();
    expect(keys, hasLength(1));
    // A different amount is a different save.
    await setup.saveCash(30000);
    expect(
        sent.where((r) => r.url.path.endsWith('/opening')).map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(2));
  });

  test('rent and salaries go in one call', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    await setup.saveExpenses(const [
      MonthlyExpense(category: 'rent', amount: 12000, dayOfMonth: 1),
      MonthlyExpense(category: 'salaries', amount: 18000, dayOfMonth: 5),
    ]);
    expect(jsonDecode(last('POST', '/pharmacies/rahman-pharma/expenses').body), [
      {'category': 'rent', 'amount': 12000.0, 'day_of_month': 1},
      {'category': 'salaries', 'amount': 18000.0, 'day_of_month': 5},
    ]);
    expect(setup.step, SetupStep.stock);
  });

  test('finishing sends typed stock, then marks setup done', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    setup.addStockLine(StockLine(
      product: 'Napa',
      strength: '500 mg',
      batchNo: 'B123',
      expiryDate: DateTime(2027, 6, 30),
      qty: 200,
      unitCost: 1.2,
      supplierId: 's9',
    ));
    expect(await setup.finish(), isTrue);
    final paths = sent.map((r) => '${r.method} ${r.url.path}').toList();
    expect(
        paths.indexOf('POST /api/v1/pharmacies/rahman-pharma/stock-batches'),
        lessThan(paths.indexOf('POST /api/v1/pharmacies/rahman-pharma/setup/complete')));
    expect(jsonDecode(last('POST', '/pharmacies/rahman-pharma/stock-batches').body), [
      {
        'product': 'Napa',
        'strength': '500 mg',
        'batch_no': 'B123',
        'expiry_date': '2027-06-30',
        'qty': 200,
        'unit_cost': 1.2,
        'supplier_id': 's9',
      }
    ]);
    expect(session.pharmacy!.setupComplete, isTrue);
  });

  test('finishing with no stock typed sends no stock call', () async {
    await start();
    await setup.saveShop(name: 'Rahman Pharma', city: 'Bogura');
    await setup.finish();
    expect(sent.where((r) => r.url.path.endsWith('/stock-batches')), isEmpty);
    expect(session.pharmacy!.setupComplete, isTrue);
  });

  test('coming back opens at the step the owner left, with their suppliers', () async {
    await start(hasShop: true, prefs: {'lamp.setupStep.green-life': 'expenses'});
    expect(setup.step, SetupStep.expenses);
    expect(setup.suppliers.single.name, 'Square');
  });

  test('coming back with no step saved opens at suppliers, not the shop', () async {
    await start(hasShop: true);
    expect(setup.step, SetupStep.suppliers);
  });

  test('back goes one step back, and renaming the shop patches it', () async {
    await start(hasShop: true);
    expect(setup.back(), isTrue);
    expect(setup.step, SetupStep.shop);
    expect(setup.back(), isFalse);
    await setup.saveShop(name: 'Green Life', city: 'Bogura');
    expect(jsonDecode(last('PATCH', '/pharmacies/green-life').body), {'name': 'Green Life', 'city': 'Bogura'});
    expect(session.pharmacy!.name, 'Green Life');
    expect(setup.step, SetupStep.suppliers);
  });
}
