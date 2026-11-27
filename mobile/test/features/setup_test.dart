import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/core/state/session_controller.dart';

import '../helpers.dart';

/// Setup on screen (plan 5.2): a new owner goes from naming the shop to
/// Today, every step after the first can be skipped, and nothing overflows
/// at 360 x 800 with Bangla text at 1.3.
void main() {
  late List<http.Request> sent;
  late bool down;

  final pharmacy = File('test/fixtures/pharmacy_new.json').readAsStringSync();
  final today = File('test/fixtures/today.json').readAsStringSync();
  const headers = {'content-type': 'application/json; charset=utf-8'};

  MockClient server() => MockClient((req) async {
        sent.add(req);
        if (down) throw http.ClientException('no network');
        final path = req.url.path.replaceFirst('/api/v1', '');
        if (req.method == 'POST' && path == '/pharmacies') {
          return http.Response(pharmacy, 201, headers: headers);
        }
        if (path.endsWith('/today')) return http.Response(today, 200, headers: headers);
        if (req.method == 'POST' && path.endsWith('/suppliers')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'id': 's1', ...body}), 201, headers: headers);
        }
        if (req.method == 'GET' && path.endsWith('/suppliers')) {
          return http.Response('[]', 200, headers: headers);
        }
        return http.Response('{}', 201, headers: headers);
      });

  setUp(() {
    sent = [];
    down = false;
  });

  Iterable<String> posts() =>
      sent.where((r) => r.method == 'POST').map((r) => r.url.path.replaceFirst('/api/v1', ''));

  Future<SessionController> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    final session = await signedInSession(hasShop: false);
    await pumpLamp(tester, session: session, at: '/today', locale: locale, http: server());
    return session;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) =>
      tester.enterText(find.byKey(ValueKey(key)), text);

  testWidgets('a new owner walks all five steps to Today', (tester) async {
    final session = await open(tester);
    expect(find.text('Name your shop'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-skip')), findsNothing);

    await tapKey(tester, 'setup-next');
    expect(find.text("Enter the shop's name and town."), findsOneWidget);
    expect(posts(), isEmpty);

    await type(tester, 'shop-name', 'Rahman Pharma');
    await type(tester, 'shop-city', 'Bogura');
    await tapKey(tester, 'setup-next');
    expect(posts(), contains('/pharmacies'));
    expect(find.text('Your main suppliers'), findsOneWidget);

    await tapKey(tester, 'add-supplier');
    await type(tester, 'supplier-name', 'Square');
    await type(tester, 'supplier-pay', '45');
    await tapKey(tester, 'supplier-save');
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('45 days to pay · 60 days to send back'), findsOneWidget);
    await tapKey(tester, 'setup-next');

    expect(find.text('Cash in the drawer today'), findsOneWidget);
    await type(tester, 'cash', 'lots');
    await tapKey(tester, 'setup-next');
    expect(find.text('Enter an amount in taka, like 25000.'), findsOneWidget);
    await type(tester, 'cash', '25,000');
    await tapKey(tester, 'setup-next');
    expect(posts(), contains('/pharmacies/rahman-pharma/opening'));

    expect(find.text('Rent and salaries'), findsOneWidget);
    await type(tester, 'rent-amount', '12000');
    await tapKey(tester, 'setup-next');
    final expenses = sent.lastWhere((r) => r.url.path.endsWith('/expenses'));
    expect(jsonDecode(expenses.body), [
      {'category': 'rent', 'amount': 12000.0, 'day_of_month': 1},
    ]);

    expect(find.text('Your stock'), findsOneWidget);
    await tapKey(tester, 'setup-finish');
    expect(posts(), contains('/pharmacies/rahman-pharma/setup/complete'));
    expect(session.pharmacy!.setupComplete, isTrue);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Today')), findsOneWidget);
    // Let the confirmation toast time out.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('every step after the shop can be skipped, and back goes back', (tester) async {
    await open(tester);
    await type(tester, 'shop-name', 'Rahman Pharma');
    await type(tester, 'shop-city', 'Bogura');
    await tapKey(tester, 'setup-next');
    await tapKey(tester, 'setup-skip');
    expect(find.text('Cash in the drawer today'), findsOneWidget);
    await tapKey(tester, 'setup-back');
    expect(find.text('Your main suppliers'), findsOneWidget);
    await tapKey(tester, 'setup-skip');
    await tapKey(tester, 'setup-skip');
    await tapKey(tester, 'setup-skip');
    expect(find.text('Your stock'), findsOneWidget);
    expect(find.text('Step 5 of 5'), findsOneWidget);
    expect(posts(), ['/pharmacies']);
  });

  testWidgets('typed stock is listed, then sent when finishing', (tester) async {
    await open(tester);
    await type(tester, 'shop-name', 'Rahman Pharma');
    await type(tester, 'shop-city', 'Bogura');
    await tapKey(tester, 'setup-next');
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'setup-skip');
    }
    await tapKey(tester, 'add-stock');
    await type(tester, 'stock-product', 'Napa');
    await type(tester, 'stock-strength', '500 mg');
    await type(tester, 'stock-batch', 'B123');
    await type(tester, 'stock-qty', '200');
    await type(tester, 'stock-cost', '1.20');
    await tapKey(tester, 'stock-save');
    expect(find.text('Fill in the medicine, batch, expiry, quantity and cost.'), findsOneWidget);
    await tapKey(tester, 'stock-expiry');
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'stock-save');
    expect(find.text('Napa 500 mg'), findsOneWidget);

    await tapKey(tester, 'setup-finish');
    final stock = sent.singleWhere((r) => r.url.path.endsWith('/stock-batches'));
    final line = (jsonDecode(stock.body) as List).single as Map<String, dynamic>;
    expect(line['product'], 'Napa');
    expect(line['qty'], 200);
    expect(line['unit_cost'], 1.2);
    expect(line['expiry_date'], matches(RegExp(r'^\d{4}-\d{2}-15$')));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('offline: the step stays, with plain words', (tester) async {
    await open(tester);
    down = true;
    await type(tester, 'shop-name', 'Rahman Pharma');
    await type(tester, 'shop-city', 'Bogura');
    await tapKey(tester, 'setup-next');
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    expect(find.text('Name your shop'), findsOneWidget);
    down = false;
    await tapKey(tester, 'setup-next');
    expect(find.text('Your main suppliers'), findsOneWidget);
  });

  testWidgets('coming back offline: suppliers say why, adding waits', (tester) async {
    down = true;
    final session = await signedInSession(hasShop: true, setupComplete: false);
    await pumpLamp(tester, session: session, at: '/setup', http: server());
    // A GET is retried twice with backoff before the app says it's offline.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    expect(find.text('No suppliers yet.'), findsNothing);
    final add = tester.widget<OutlinedButton>(find.byKey(const ValueKey('add-supplier')));
    expect(add.onPressed, isNull);
    down = false;
    await tapKey(tester, 'suppliers-retry');
    expect(find.text('No suppliers yet.'), findsOneWidget);
  });

  testWidgets('in Bangla at 1.3, every step fits and digits are Bangla', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, locale: const Locale('bn'));
    expect(find.text('ধাপ ১ / ৫'), findsOneWidget);
    // A Bangla keyboard types Bangla digits; they are sent as numbers.
    await type(tester, 'shop-name', 'রহমান ফার্মা');
    await type(tester, 'shop-city', 'বগুড়া');
    await tapKey(tester, 'setup-next');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'add-supplier');
    expect(tester.takeException(), isNull);
    await type(tester, 'supplier-name', 'স্কয়ার');
    await tapKey(tester, 'supplier-save');
    expect(find.text('টাকা দিতে ৩০ দিন · ফেরত ৬০ দিন'), findsOneWidget);
    await tapKey(tester, 'setup-next');
    await type(tester, 'cash', '২৫,০০০');
    await tapKey(tester, 'setup-next');
    final cash = sent.lastWhere((r) => r.url.path.endsWith('/opening'));
    expect((jsonDecode(cash.body) as Map)['cash_on_hand'], 25000.0);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'setup-skip');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'add-stock');
    expect(tester.takeException(), isNull);
  });
}
