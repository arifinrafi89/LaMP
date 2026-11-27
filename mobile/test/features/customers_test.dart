import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/core/l10n/digits.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';
import 'package:lamp_shop/features/customers/customers_controller.dart';
import 'package:lamp_shop/widgets/ui/lamp_parts_bar.dart';

import '../helpers.dart';

/// Customers (plan 3.4, Y3.1): who owes the shop, amounts only. One main
/// action: add a customer. Families join SMS by texting the join text.
void main() {
  final customers = jsonDecode(File('test/fixtures/customers.json').readAsStringSync()) as List;
  final card = File('test/fixtures/card.json').readAsStringSync();
  final me = jsonDecode(File('test/fixtures/me.json').readAsStringSync()) as Map<String, dynamic>;
  const base = '/api/v1/pharmacies/green-life/customers';

  late List<http.Request> sent;
  late List<Object?> rows;
  late List<String> joinRoutes;
  late bool down;
  late http.Response? Function(http.Request)? override;
  late List<String> shared;
  late List<String> copied;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  MockClient server() => MockClient((req) async {
    sent.add(req);
    if (down) throw http.ClientException('no network');
    final o = override?.call(req);
    if (o != null) return o;
    final p = req.url.path;
    if (p == '/api/v1/me') return json({...me, 'family_join_routes': joinRoutes});
    if (p.startsWith('/api/v1/cards/')) {
      return http.Response(card, 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }
    if (p == base && req.method == 'GET') return json(rows);
    if (p == base && req.method == 'POST') {
      final made = {
        'code': 'GL-2WSX-3EDC',
        'label': 'Customer 006',
        'join': {'text': 'LAMP GL2WSX3EDC', 'to': '21213'},
      };
      rows = [
        ...rows,
        {
          ...made,
          'amount': 1200.0,
          'since': '2026-11-27',
          'days_outstanding': 0,
          'status': 'no_plan',
          'plan': null,
          'sms_status': 'NONE',
          'trusted': false,
        },
      ];
      return json(made, 201);
    }
    if (p.endsWith('/payments')) return json({'code': 'GL-7KQM-4XPA', 'amount': 4875.0}, 201);
    if (p.endsWith('/sales')) return json({'code': 'GL-7KQM-4XPA', 'amount': 7000.0}, 201);
    if (p.endsWith('/plan')) return http.Response(card, 200, headers: {'content-type': 'application/json'});
    if (p.endsWith('/remind')) return json({'sms_status': 'ON'}, 202);
    if (p.endsWith('/phone') && req.method == 'DELETE') return json({'sms_status': 'STOPPED'});
    if (p.endsWith('/phone')) return json({'sms_status': 'PENDING'}, 202);
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    sent = [];
    rows = customers;
    joinRoutes = ['text'];
    down = false;
    override = null;
    shared = [];
    copied = [];
  });

  Future<void> open(WidgetTester tester, String at, {Locale locale = const Locale('en'), CacheStore? cache}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    await pumpLamp(
      tester,
      session: await signedInSession(),
      at: at,
      locale: locale,
      http: server(),
      cache: cache,
      share: (text) async => shared.add(text),
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  Iterable<http.Request> writes() => sent.where((r) => r.method != 'GET');
  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
  final today = apiDate(dhakaToday());

  group('the list', () {
    testWidgets('every customer, what they owe and where their SMS stands', (tester) async {
      await open(tester, '/customers');
      expect(sent.where((r) => r.url.path == base), hasLength(1));
      expect(find.text('4 customers owe you'), findsOneWidget);
      expect(find.text('Customer 004'), findsOneWidget);
      expect(find.text('৳ 6,500'), findsOneWidget);
      expect(find.text('SMS on'), findsOneWidget);
      expect(find.text('Joining'), findsOneWidget);
      expect(find.text('SMS stopped'), findsOneWidget);
      expect(find.text('Since Tue 3 Nov · 24 days · 4 weekly parts'), findsOneWidget);
      expect(find.text('Since Fri 20 Nov · 7 days · No plan yet'), findsOneWidget);
      expect(find.textContaining('Updated '), findsOneWidget);
    });

    testWidgets('nobody owes: plain words and the one action', (tester) async {
      rows = [];
      await open(tester, '/customers');
      expect(find.text('No one owes you yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('customers-add')), findsOneWidget);
    });

    testWidgets('offline, the kept list shows and says how old', (tester) async {
      final cache = MemoryCacheStore();
      await cache.write('/pharmacies/green-life/customers', customers);
      down = true;
      await open(tester, '/customers', cache: cache);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Customer 004'), findsOneWidget);
      expect(find.textContaining('Offline · updated'), findsOneWidget);
    });

    testWidgets('in Bangla: Bangla digits for money, English for card codes', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA', locale: const Locale('bn'));
      expect(find.text('৳৬,৫০০'), findsWidgets);
      expect(find.text('GL-7KQM-4XPA'), findsOneWidget);
    });

    testWidgets('a row opens that customer', (tester) async {
      await open(tester, '/customers');
      await tapKey(tester, 'customer-GL-7KQM-4XPA');
      expect(find.text('Owes'), findsOneWidget);
      expect(find.text('GL-7KQM-4XPA'), findsOneWidget);
      expect(sent.where((r) => r.url.path == base), hasLength(1), reason: 'one read for list and card');
    });
  });

  group('one customer', () {
    testWidgets('with SMS on: the plan, its parts, and reminders', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      expect(find.text('৳ 6,500'), findsOneWidget);
      expect(find.text('Pays on time'), findsOneWidget);
      expect(find.text('4 weekly parts'), findsOneWidget);
      expect(find.text('Part 2 · Thu 3 Dec'), findsOneWidget);
      expect(
        find.text('The family gets a reminder two days before each part, and a receipt for each payment.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('join-share')), findsNothing, reason: 'already on');
      expect(find.byKey(const ValueKey('sms-remind')), findsOneWidget);
    });

    testWidgets('a server that marks parts paid gets the parts bar', (tester) async {
      rows = [
        for (final r in customers.cast<Map<String, dynamic>>())
          if (r['code'] == 'GL-7KQM-4XPA')
            {
              ...r,
              'plan': {
                ...(r['plan'] as Map<String, dynamic>),
                'schedule': [
                  for (final p in ((r['plan'] as Map)['schedule'] as List).cast<Map<String, dynamic>>())
                    {...p, 'paid': p['n'] == 1},
                ],
              },
            }
          else
            r,
      ];
      await open(tester, '/customers/GL-7KQM-4XPA');
      expect(find.byType(LampPartsBar), findsOneWidget);
      expect(find.text('1 of 4 parts paid'), findsOneWidget);
      expect(find.text('Next: ৳ 1,625 on Thu 3 Dec'), findsOneWidget);
      expect(find.text('৳ 1,625 · Paid'), findsOneWidget);
    });

    testWidgets('without paid marks no bar, so nothing claims a part was paid', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      expect(find.byType(LampPartsBar), findsNothing);
      expect(find.textContaining('Paid'), findsNothing);
    });

    testWidgets('not on SMS yet: the join text to read out, share or copy', (tester) async {
      await open(tester, '/customers/GL-8NBV-2KLM');
      expect(find.text('Ask the family to text this to 21213:'), findsOneWidget);
      expect(find.text('LAMP GL8NBV2KLM'), findsOneWidget);
      await tapKey(tester, 'join-share');
      expect(
        shared.single,
        'Text LAMP GL8NBV2KLM to 21213 for free reminders of what you owe. Free. Text LAMP STOP to stop.',
      );
      await tapKey(tester, 'join-copy');
      expect(copied.single, shared.single);
      expect(find.text('Copied'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('joining: says it waits for Banglalink, no join text', (tester) async {
      await open(tester, '/customers/GL-3HFD-9WQT');
      expect(find.text('The family texted. Waiting for Banglalink to confirm.'), findsOneWidget);
      expect(find.byKey(const ValueKey('join-share')), findsNothing);
    });

    testWidgets('in Bangla the join text keeps English letters and digits', (tester) async {
      await open(tester, '/customers/GL-8NBV-2KLM', locale: const Locale('bn'));
      expect(find.text('LAMP GL8NBV2KLM'), findsOneWidget);
      await tapKey(tester, 'join-share');
      expect(shared.single, contains('21213'));
      expect(shared.single, contains('LAMP GL8NBV2KLM'));
    });

    testWidgets('a card that is not in the list says so', (tester) async {
      await open(tester, '/customers/GL-0000-0000');
      expect(find.text("This card isn't in your list."), findsOneWidget);
      await tapKey(tester, 'customers-back');
      expect(find.text('4 customers owe you'), findsOneWidget);
    });
  });

  group('adding a customer', () {
    testWidgets('the amount and since when; then the card code and join text', (tester) async {
      await open(tester, '/customers');
      await tapKey(tester, 'customers-add');
      expect(find.text('No name is kept. The card has a number and a code.'), findsOneWidget);
      await type(tester, 'add-amount', '1200');
      await tapKey(tester, 'add-save');
      final post = writes().single;
      expect(post.url.path, base);
      expect(body(post), {'amount': 1200.0, 'since': today});
      expect(post.headers['Idempotency-Key'], isNotNull);
      expect(find.text('Customer 006 added'), findsOneWidget);
      expect(find.text('GL-2WSX-3EDC'), findsOneWidget);
      expect(find.text('LAMP GL2WSX3EDC'), findsOneWidget);
    });

    testWidgets('an amount that is not one, or is 0, is refused on the phone', (tester) async {
      await open(tester, '/customers');
      await tapKey(tester, 'customers-add');
      await type(tester, 'add-amount', 'abc');
      await tapKey(tester, 'add-save');
      expect(find.text("That doesn't look like an amount."), findsOneWidget);
      await type(tester, 'add-amount', '0');
      await tapKey(tester, 'add-save');
      expect(find.text('Enter an amount above 0.'), findsOneWidget);
      expect(writes(), isEmpty);
    });

    testWidgets('offline: plain words, and Save again sends the same key', (tester) async {
      await open(tester, '/customers');
      await tapKey(tester, 'customers-add');
      await type(tester, 'add-amount', '1200');
      down = true;
      await tapKey(tester, 'add-save');
      expect(find.text("You're offline. Check your connection."), findsOneWidget);
      down = false;
      await tapKey(tester, 'add-save');
      final keys = writes().map((r) => r.headers['Idempotency-Key']).toSet();
      expect(keys, hasLength(1));
      expect(find.text('Customer 006 added'), findsOneWidget);
    });
  });

  group('money', () {
    testWidgets('a payment: amount, how it was paid, and what is owed now', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      await tapKey(tester, 'customer-pay');
      await type(tester, 'money-amount', '1625');
      await tapKey(tester, 'method-bkash');
      await tapKey(tester, 'money-save');
      final post = writes().single;
      expect(post.url.path, '$base/GL-7KQM-4XPA/payments');
      expect(body(post), {'amount': 1625.0, 'on': today, 'method': 'bkash'});
      expect(post.headers['Idempotency-Key'], isNotNull);
      expect(find.text('Payment saved · now owes ৳ 4,875'), findsOneWidget);
      expect(sent.where((r) => r.url.path == base), hasLength(2), reason: 'the list reads again');
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('a sale on credit', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      await tapKey(tester, 'customer-sale');
      expect(find.byKey(const ValueKey('method-cash')), findsNothing, reason: 'only payments have a method');
      await type(tester, 'money-amount', '500');
      await tapKey(tester, 'money-save');
      expect(writes().single.url.path, '$base/GL-7KQM-4XPA/sales');
      expect(body(writes().single), {'amount': 500.0, 'on': today});
      expect(find.text('Sale saved · now owes ৳ 7,000'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('the plan', () {
    testWidgets('choices are the server\'s; the owner picks one with the family', (tester) async {
      await open(tester, '/customers/GL-3HFD-9WQT');
      await tapKey(tester, 'plan-set');
      expect(sent.last.url.path, '/api/v1/cards/GL-3HFD-9WQT');
      expect(find.text('One payment of ৳ 2,450'), findsOneWidget);
      expect(find.text('4 weekly parts of ৳ 612'), findsOneWidget);
      await tapKey(tester, 'plan-4');
      await tapKey(tester, 'plan-save');
      final put = writes().single;
      expect(put.method, 'PUT');
      expect(put.url.path, '$base/GL-3HFD-9WQT/plan');
      expect(body(put), {'parts': 4, 'first_on': '2026-11-27'});
      expect(find.text('Plan saved'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('SMS', () {
    testWidgets('a reminder now', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      await tapKey(tester, 'sms-remind');
      expect(writes().single.url.path, '$base/GL-7KQM-4XPA/remind');
      expect(find.text('Reminder sent'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('one a day: the server\'s refusal in plain words', (tester) async {
      override = (r) => r.url.path.endsWith('/remind')
          ? json({'detail': 'once a day', 'code': 'rate_limited', 'retry_after': 3600}, 429)
          : null;
      await open(tester, '/customers/GL-7KQM-4XPA');
      await tapKey(tester, 'sms-remind');
      expect(find.text('Too many tries. Wait a moment and try again.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('stop SMS, after saying what it means', (tester) async {
      await open(tester, '/customers/GL-7KQM-4XPA');
      await tapKey(tester, 'sms-stop');
      expect(
        find.text('Stop SMS for Customer 004? The family can text the join text again to restart.'),
        findsOneWidget,
      );
      expect(writes(), isEmpty);
      await tapKey(tester, 'sms-stop-yes');
      expect(writes().single.method, 'DELETE');
      expect(writes().single.url.path, '$base/GL-7KQM-4XPA/phone');
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('typing the family\'s number (counter route)', () {
    testWidgets('hidden while the server lists only texting', (tester) async {
      await open(tester, '/customers/GL-8NBV-2KLM');
      expect(find.byKey(const ValueKey('customer-number')), findsNothing);
      expect(sent.where((r) => r.url.path == '/api/v1/me'), hasLength(1));
    });

    testWidgets('when it is on: read the words aloud, then They agreed', (tester) async {
      joinRoutes = ['text', 'counter'];
      await open(tester, '/customers/GL-8NBV-2KLM');
      await tapKey(tester, 'customer-number');
      expect(
        find.text('LaMP will text you what you owe and remind you before each payment. Free. Stop any time.'),
        findsOneWidget,
      );
      await type(tester, 'phone-input', '01912 345678');
      await tapKey(tester, 'phone-lang-en');
      await tapKey(tester, 'consent-agreed');
      final post = writes().single;
      expect(post.url.path, '$base/GL-8NBV-2KLM/phone');
      expect(body(post), {
        'phone': '+8801912345678',
        'language': 'en',
        'consent': {'agreed': true, 'wording_version': familyConsentVersion},
      });
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('a number on another network is refused on the phone', (tester) async {
      joinRoutes = ['text', 'counter'];
      await open(tester, '/customers/GL-8NBV-2KLM');
      await tapKey(tester, 'customer-number');
      await type(tester, 'phone-input', '01712345678');
      await tapKey(tester, 'consent-agreed');
      expect(find.text('Use a Banglalink number.'), findsOneWidget);
      expect(writes(), isEmpty);
    });

    testWidgets('if the server turned it off meanwhile: join by text', (tester) async {
      joinRoutes = ['text', 'counter'];
      override = (r) => r.method == 'POST' && r.url.path.endsWith('/phone')
          ? json({'detail': 'off', 'code': 'join_by_text'}, 403)
          : null;
      await open(tester, '/customers/GL-8NBV-2KLM');
      await tapKey(tester, 'customer-number');
      await type(tester, 'phone-input', '01912345678');
      await tapKey(tester, 'consent-agreed');
      expect(find.text('Ask the family to text the join text instead.'), findsOneWidget);
    });
  });

  group('every sheet at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      for (final (at, key) in [
        ('/customers', 'customers-add'),
        ('/customers/GL-7KQM-4XPA', 'customer-pay'),
        ('/customers/GL-3HFD-9WQT', 'plan-set'),
        ('/customers/GL-8NBV-2KLM', 'customer-number'),
        ('/customers/GL-7KQM-4XPA', 'sms-stop'),
      ]) {
        testWidgets('$key · ${dark ? 'dark' : 'light'}', (tester) async {
          joinRoutes = ['text', 'counter'];
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
          await pumpLamp(tester,
              session: await signedInSession(),
              at: at,
              locale: const Locale('bn'),
              http: server(),
              prefs: {'lamp.themeMode': dark ? 'dark' : 'light'});
          await tapKey(tester, key);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
