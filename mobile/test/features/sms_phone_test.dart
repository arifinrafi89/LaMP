import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// The drawn basic phone (plan 5.7, Y4.1): demo and team-test shops only.
void main() {
  final meJson = jsonDecode(File('test/fixtures/me.json').readAsStringSync()) as Map<String, dynamic>;
  final customers = File('test/fixtures/customers.json').readAsStringSync();
  late bool demo;
  late List<http.Request> sent;
  late List<Map<String, Object?>> thread;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  MockClient server() => MockClient((req) async {
    sent.add(req);
    final p = req.url.path;
    if (p == '/api/v1/me') return json({...meJson, 'demo_tools': demo});
    if (p == '/api/v1/demo/sms/thread') return json({'messages': thread});
    if (p == '/api/v1/demo/sms') {
      final text = (jsonDecode(req.body) as Map)['text'] as String;
      thread = [
        ...thread,
        {'from': 'phone', 'text': text, 'at': '2026-11-27T05:00:00Z'},
        {'from': 'lamp', 'text': 'Green Life Pharmacy: you owe BDT 6,500.', 'at': '2026-11-27T05:00:01Z'},
      ];
      return json({
        'replies': ['Green Life Pharmacy: you owe BDT 6,500.'],
      });
    }
    if (p.endsWith('/customers')) {
      return http.Response(customers, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    demo = true;
    sent = [];
    thread = [
      {
        'from': 'lamp',
        'text': 'LaMP: text LAMP and the card code from your bill to 21213.',
        'at': '2026-11-27T04:00:00Z',
      },
    ];
  });

  Future<void> open(WidgetTester tester, String at, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester, session: await signedInSession(), at: at, locale: locale, http: server());
  }

  Future<void> key(WidgetTester tester, String k, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byKey(ValueKey('phone-key-$k')));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Iterable<http.Request> to(String path) => sent.where((r) => r.url.path == path);

  testWidgets('not a demo shop: says so, and reads nothing', (tester) async {
    demo = false;
    await open(tester, '/demo-phone');
    expect(find.text('The SMS phone is only on the demo shop'), findsOneWidget);
    expect(to('/api/v1/demo/sms/thread'), isEmpty);
  });

  testWidgets('More lists the phone only on a demo shop', (tester) async {
    await open(tester, '/more');
    expect(find.text('SMS phone (demo)'), findsOneWidget);
  });

  testWidgets('More hides it elsewhere', (tester) async {
    demo = false;
    await open(tester, '/more');
    expect(find.text('SMS phone (demo)'), findsNothing);
  });

  testWidgets('the thread with 21213', (tester) async {
    await open(tester, '/demo-phone');
    expect(find.text('21213'), findsOneWidget);
    expect(find.text('LaMP: text LAMP and the card code from your bill to 21213.'), findsOneWidget);
  });

  testWidgets('multi-tap on the keys; * deletes', (tester) async {
    await open(tester, '/demo-phone');
    await key(tester, '5', times: 3);
    await tester.pump(const Duration(seconds: 2));
    await key(tester, '2');
    await tester.pump(const Duration(seconds: 2));
    String typed() => tester.widget<Text>(find.byKey(const ValueKey('phone-typed'))).data!;
    expect(typed(), 'LA');
    await key(tester, '*');
    expect(typed(), 'L');
  });

  testWidgets('a join text from the list, Send: the reply in the thread, Customers reads again', (tester) async {
    await open(tester, '/demo-phone');
    Text typed() => tester.widget<Text>(find.byKey(const ValueKey('phone-typed')));
    await tester.ensureVisible(find.byKey(const ValueKey('phone-fill-GL-8NBV-2KLM')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-fill-GL-8NBV-2KLM')));
    await tester.pump();
    expect(typed().data, 'LAMP GL8NBV2KLM');
    final listsBefore = to('/api/v1/pharmacies/green-life/customers').length;
    await tester.ensureVisible(find.byKey(const ValueKey('phone-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone-send')));
    await tester.pumpAndSettle();
    expect(jsonDecode(to('/api/v1/demo/sms').single.body), {'text': 'LAMP GL8NBV2KLM'});
    expect(find.text('Green Life Pharmacy: you owe BDT 6,500.'), findsOneWidget);
    expect(to('/api/v1/pharmacies/green-life/customers').length, greaterThan(listsBefore));
    expect(typed().data, isEmpty, reason: 'sent: the line is cleared');
  });

  for (final dark in [false, true]) {
    testWidgets('at 360 wide, Bangla, text 1.3 · ${dark ? 'dark' : 'light'}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpLamp(
        tester,
        session: await signedInSession(),
        at: '/demo-phone',
        locale: const Locale('bn'),
        http: server(),
        prefs: {'lamp.themeMode': dark ? 'dark' : 'light'},
      );
      expect(tester.takeException(), isNull);
    });
  }
}
