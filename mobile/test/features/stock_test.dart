import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/features/stock/stock_models.dart';

import '../helpers.dart';

/// Stock (plan 5.2): batches expiring in the next 60 days, and what can still
/// go back to its supplier. One main action: open a batch that can go back.
void main() {
  final expiry = File('test/fixtures/expiry.json').readAsStringSync();
  late List<http.Request> sent;
  late String body;
  late bool down;

  MockClient server() => MockClient((req) async {
        sent.add(req);
        if (down) throw http.ClientException('no network');
        return http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });

  setUp(() {
    sent = [];
    body = expiry;
    down = false;
  });

  group('model', () {
    final s = StockExpiry.fromJson(jsonDecode(expiry) as Map<String, dynamic>);

    test('reads the totals and every batch', () {
      expect(s.horizonDays, 60);
      expect(s.atRiskValue, 18400);
      expect(s.returnValue, 9200);
      expect(s.batches, hasLength(6));
      expect(s.batches.first.expiryDate, DateTime(2026, 12, 10));
    });

    test('what can go back comes first, soonest first', () {
      expect(s.canGoBack.map((b) => b.batchNo), ['CT2411', 'OM2409']);
      expect(s.cannotGoBack.map((b) => b.batchNo),
          ['VB2385', 'OR2390', 'MF2398', 'AX2402']);
    });
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester, session: await signedInSession(), at: '/stock', locale: locale, http: server());
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('shows what is at risk and what can still go back', (tester) async {
    await open(tester);
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/expiry');
    expect(find.text('৳ 18,400'), findsOneWidget);
    expect(find.text('৳ 9,200 can go back to suppliers'), findsOneWidget);
    expect(find.text('Cetirizine 10 mg, box of 100'), findsOneWidget);
    expect(find.text('48 days left'), findsOneWidget);
  });

  testWidgets('the main action opens the batch that can go back soonest', (tester) async {
    await open(tester);
    await tapKey(tester, 'stock-first-return');
    expect(find.text('Supplier C can take this back.'), findsOneWidget);
    expect(find.text('CT2411'), findsWidgets);
    expect(find.text('Thu 3 Dec'), findsOneWidget);
  });

  testWidgets('a batch past going back says so', (tester) async {
    await open(tester);
    await tapKey(tester, 'batch-AX2402');
    expect(find.text("Supplier E won't take this back now."), findsOneWidget);
  });

  testWidgets('nothing expiring: says so, and offers a scan', (tester) async {
    body = jsonEncode({'horizon_days': 60, 'batches': [], 'at_risk_value': 0, 'return_eligible_value': 0});
    await open(tester);
    expect(find.text('Nothing expires in the next 60 days'), findsOneWidget);
    await tapKey(tester, 'stock-scan');
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Scan')), findsOneWidget);
  });

  testWidgets('a batch already expired says Expired, not a count', (tester) async {
    final j = jsonDecode(expiry) as Map<String, dynamic>;
    (j['batches'] as List).last['days_left'] = 0;
    body = jsonEncode(j);
    await open(tester);
    expect(find.text('Expired'), findsOneWidget);
  });

  testWidgets('offline: plain words and a way to try again', (tester) async {
    down = true;
    await open(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    down = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('৳ 18,400'), findsOneWidget);
  });

  testWidgets('in Bangla, amounts, days and dates use Bangla digits', (tester) async {
    await open(tester, locale: const Locale('bn'));
    expect(find.text('৳১৮,৪০০'), findsOneWidget);
    // The product's strength keeps its English digits (plan 5.4).
    expect(find.text('Cetirizine 10 mg, box of 100'), findsOneWidget);
    expect(find.text('আর ৪৮ দিন'), findsOneWidget);
  });
}
