import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Cash, Plan and Approvals (plan 5.2, Y3.2): LaMP Plus screens. On the
/// free plan each shows what it does and one "Start LaMP Plus" button.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();
  final me = jsonDecode(fixture('me')) as Map<String, dynamic>;
  final plusMe = {
    ...me,
    'plan': 'plus',
    'plus_status': 'ACTIVE',
    'entitlements': {'cash': true, 'plan': true, 'approvals': true, 'ask': true, 'scans_left': null},
  };
  const base = '/api/v1/pharmacies/green-life';

  late List<http.Request> sent;
  late Map<String, dynamic> meBody;
  late String forecast;
  late List<Object?> actions;
  late bool paused;
  late http.Response? Function(http.Request)? override;
  late List<String> shared;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
  http.Response raw(String body) =>
      http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});

  Map<String, dynamic> executed(String id) {
    final a = (actions.firstWhere((x) => (x as Map)['id'] == id) as Map<String, dynamic>);
    return {
      ...a,
      'status': 'executed',
      'decided_at': '2026-11-27T06:00:00Z',
      'result': a['kind'] == 'extension_request'
          ? {
              'summary': 'Your message to Supplier A is ready.',
              'share_text_en': 'Dear Supplier A, could we have 20 more days on BDT 8,200?',
              'share_text_bn': 'প্রিয় Supplier A, ৳৮,২০০-এর জন্য আরও ২০ দিন পেতে পারি?',
              'supplier_phone': '+8801912000111',
            }
          : {'summary': 'Done.'},
    };
  }

  MockClient server() => MockClient((req) async {
    sent.add(req);
    final o = override?.call(req);
    if (o != null) return o;
    final p = req.url.path;
    if (p == '/api/v1/me') return json(meBody);
    if (p == '$base/forecast') return raw(forecast);
    if (p == '$base/funding-plan') return raw(fixture('funding_plan'));
    if (p == '$base/orders') return raw(fixture('orders'));
    if (p.endsWith('/trim')) return raw(fixture('trim'));
    if (p == '$base/pause' && req.method == 'GET') return json({'paused': paused, 'changed_at': null});
    if (p == '$base/pause') {
      paused = (jsonDecode(req.body) as Map)['paused'] as bool;
      return json({'paused': paused, 'changed_at': '2026-11-27T06:00:00Z'});
    }
    if (p == '$base/actions' && req.method == 'GET') return json(actions);
    if (p == '$base/actions') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      final made = {
        'id': 'new-${actions.length}',
        'kind': b['kind'],
        'status': 'proposed',
        'payload': b['payload'],
        'proposed_by': 'owner',
        'created_at': '2026-11-27T06:00:00Z',
        'decided_at': null,
        'result': null,
      };
      actions = [made, ...actions];
      return json(made);
    }
    final m = RegExp(r'/actions/([^/]+)/(approve|reject)$').firstMatch(p);
    if (m != null) {
      final done = m[2] == 'approve'
          ? executed(m[1]!)
          : {...(actions.firstWhere((x) => (x as Map)['id'] == m[1]) as Map<String, dynamic>), 'status': 'rejected'};
      actions = [for (final a in actions) (a as Map)['id'] == m[1] ? done : a];
      return json(done);
    }
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    sent = [];
    meBody = plusMe;
    forecast = fixture('forecast');
    actions = jsonDecode(fixture('actions')) as List;
    paused = false;
    override = null;
    shared = [];
  });

  Future<void> open(WidgetTester tester, String at, {Locale locale = const Locale('en')}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    await pumpLamp(
      tester,
      session: await signedInSession(),
      at: at,
      locale: locale,
      http: server(),
      share: (t) async => shared.add(t),
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Iterable<http.Request> writes() => sent.where((r) => r.method != 'GET' && !r.url.path.endsWith('/funding-plan'));
  Iterable<http.Request> to(String path) => sent.where((r) => r.url.path == path);

  group('on the free plan', () {
    for (final (at, title, path) in [
      ('/cash', 'Cash is part of LaMP Plus', '$base/forecast'),
      ('/plan', 'Plan is part of LaMP Plus', '$base/funding-plan'),
      ('/approvals', 'Approvals is part of LaMP Plus', '$base/actions'),
    ]) {
      testWidgets('$at says what it does, offers Plus, and reads nothing', (tester) async {
        meBody = me;
        await open(tester, at);
        expect(find.text(title), findsOneWidget);
        expect(find.text('BDT 50 a month, from your mobile balance. Stop any time.'), findsOneWidget);
        expect(to(path), isEmpty);
        await tapKey(tester, 'plus-start');
        expect(find.text('LaMP Plus'), findsWidgets);
      });
    }

    testWidgets('the server saying plus_required shows the same lock, never an error', (tester) async {
      override = (r) =>
          r.url.path == '$base/forecast' ? json({'detail': 'Plus only', 'code': 'plus_required'}, 403) : null;
      await open(tester, '/cash');
      expect(find.text('Cash is part of LaMP Plus'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('cash', () {
    testWidgets('the next short day, its cause, and the cash now', (tester) async {
      await open(tester, '/cash');
      expect(to('$base/forecast'), hasLength(1));
      expect(find.text('Short ৳ 19,000 on Mon 26 Oct'), findsOneWidget);
      expect(find.text('Supplier A order BDT 60,000'), findsOneWidget);
      expect(find.text('You have ৳ 39,150 now'), findsOneWidget);
      expect(find.text('Supplier D invoice D-20931'), findsOneWidget);
    });

    testWidgets('See why: that day, each item as the server sent it, and what is left', (tester) async {
      await open(tester, '/cash');
      await tapKey(tester, 'cash-why');
      expect(find.text('Why Mon 26 Oct runs short'), findsOneWidget);
      expect(find.text('Supplier A order'), findsWidgets);
      expect(find.text('-৳ 60,000'), findsWidgets);
      expect(find.text("Left at day's end: -৳ 17,350"), findsWidgets, reason: 'on the card and in the sheet');
      await tapKey(tester, 'cash-plan');
      expect(find.text('To cover by Mon 26 Oct'), findsOneWidget);
    });

    testWidgets('no short day: plain words', (tester) async {
      final f = jsonDecode(forecast) as Map<String, dynamic>;
      forecast = jsonEncode({...f, 'shortfalls': []});
      await open(tester, '/cash');
      expect(find.text('No short day in the next 30 days'), findsOneWidget);
      expect(find.byKey(const ValueKey('cash-why')), findsNothing);
    });

    testWidgets('in Bangla the server\'s figures get Bangla digits', (tester) async {
      await open(tester, '/cash', locale: const Locale('bn'));
      expect(find.text('Supplier A order ৳৬০,০০০'), findsOneWidget);
    });
  });

  group('plan', () {
    testWidgets('what to cover, by when, the steps and what they cost', (tester) async {
      actions = [];
      await open(tester, '/plan');
      expect(to('$base/funding-plan').single.method, 'POST');
      expect(find.text('To cover by Mon 26 Oct'), findsOneWidget);
      expect(find.text('৳ 8,200'), findsWidgets);
      expect(find.text('Cut Montelukast from 30 to 12 boxes'), findsOneWidget);
      expect(find.text('Ask Supplier A for 20 more days on BDT 8,200'), findsOneWidget);
      expect(find.text("If Supplier A hasn't agreed, take a mobile-wallet loan"), findsOneWidget);
      expect(find.text('If needed, on Thu 22 Oct'), findsOneWidget);
      expect(find.text('This plan costs ৳ 0'), findsOneWidget);
      expect(find.text('Borrowing it all would cost ৳ 422'), findsOneWidget);
    });

    testWidgets('how the figure was worked out', (tester) async {
      await open(tester, '/plan');
      await tapKey(tester, 'plan-explain');
      expect(find.text('Cash at the start of 26 Oct'), findsOneWidget);
      expect(find.text('To cover'), findsOneWidget);
    });

    testWidgets('Send to Approvals: every step but the loan, then Approvals', (tester) async {
      actions = [];
      await open(tester, '/plan');
      await tapKey(tester, 'plan-send');
      final posts = writes().toList();
      expect(posts.map((r) => (jsonDecode(r.body) as Map)['kind']), ['trim_order', 'extension_request']);
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('Cut Montelukast from 30 to 12 boxes'), findsOneWidget);
    });

    testWidgets('steps already waiting: no second send', (tester) async {
      await open(tester, '/plan');
      expect(find.byKey(const ValueKey('plan-send')), findsNothing);
      expect(find.text('Waiting in Approvals: approve each step there.'), findsOneWidget);
      await tapKey(tester, 'plan-open-approvals');
      expect(find.text('Waiting for you'), findsOneWidget);
    });

    testWidgets('other ways, with their cost, and the ones not open to this shop', (tester) async {
      await open(tester, '/plan');
      expect(find.text('Mobile-wallet loan, 3 months'), findsOneWidget);
      expect(find.text('Costs ৳ 182 · 9% a year'), findsOneWidget);
      expect(find.text('Bank small-business loan'), findsOneWidget);
      expect(find.text('Not open to you'), findsOneWidget);
    });

    testWidgets('see what to cut from the order', (tester) async {
      await open(tester, '/plan');
      await tapKey(tester, 'plan-trim');
      expect(to('$base/orders/o-1/trim'), hasLength(1));
      expect(find.text('Montelukast 10 mg, box of 30'), findsOneWidget);
      expect(find.text('Order 12 instead of 30'), findsOneWidget);
      expect(find.text('Saves ৳ 10,800'), findsOneWidget);
    });
  });

  group('approvals', () {
    testWidgets('what waits, who suggested it, and what was decided', (tester) async {
      await open(tester, '/approvals');
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('Suggested by LaMP'), findsWidgets);
      expect(find.text('Added by you'), findsOneWidget);
      expect(find.text('Order fewer'), findsOneWidget);
      expect(find.text('More days to pay'), findsOneWidget);
      expect(find.text('Return sent. Your next bills should be BDT 9,200 lower.'), findsOneWidget);
      expect(find.text('Not done'), findsOneWidget);
    });

    testWidgets('approve: sent once, said in plain words, and the list reads again', (tester) async {
      await open(tester, '/approvals');
      await tapKey(tester, 'approve-act-3');
      expect(writes().single.url.path, '$base/actions/act-3/approve');
      expect(find.text('Approved'), findsOneWidget);
      expect(to('$base/actions').where((r) => r.method == 'GET'), hasLength(2));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('approving more days: the message to send the supplier', (tester) async {
      await open(tester, '/approvals');
      await tapKey(tester, 'approve-act-4');
      expect(find.text('Send this to the supplier'), findsOneWidget);
      expect(find.text('Dear Supplier A, could we have 20 more days on BDT 8,200?'), findsOneWidget);
      expect(find.text('Their number: +880 1912 000111'), findsOneWidget);
      await tapKey(tester, 'supplier-share');
      expect(shared.single, 'Dear Supplier A, could we have 20 more days on BDT 8,200?');
    });

    testWidgets('in Bangla, the Bangla message', (tester) async {
      await open(tester, '/approvals', locale: const Locale('bn'));
      await tapKey(tester, 'approve-act-4');
      expect(find.text('প্রিয় Supplier A, ৳৮,২০০-এর জন্য আরও ২০ দিন পেতে পারি?'), findsOneWidget);
    });

    testWidgets('not now', (tester) async {
      await open(tester, '/approvals');
      await tapKey(tester, 'reject-act-3');
      expect(writes().single.url.path, '$base/actions/act-3/reject');
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('pause LaMP\'s suggestions, and resume', (tester) async {
      await open(tester, '/approvals');
      await tapKey(tester, 'pause-switch');
      expect(writes().single.url.path, '$base/pause');
      expect(jsonDecode(writes().single.body), {'paused': true});
      expect(find.text("LaMP's suggestions are paused"), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('nothing waiting: plain words', (tester) async {
      actions = [];
      await open(tester, '/approvals');
      expect(find.text('Nothing waits for you'), findsOneWidget);
    });

    testWidgets('More shows how many wait', (tester) async {
      await open(tester, '/more');
      expect(find.byKey(const ValueKey('approvals-badge')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('approvals-badge')), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('More shows no badge on the free plan', (tester) async {
      meBody = me;
      await open(tester, '/more');
      expect(find.byKey(const ValueKey('approvals-badge')), findsNothing);
      expect(to('$base/actions'), isEmpty);
    });
  });

  group('every screen and sheet at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      for (final (at, key) in [
        ('/cash', null),
        ('/cash', 'cash-why'),
        ('/plan', null),
        ('/plan', 'plan-explain'),
        ('/plan', 'plan-trim'),
        ('/approvals', null),
        ('/approvals', 'approve-act-4'),
      ]) {
        testWidgets('$at ${key ?? ''} · ${dark ? 'dark' : 'light'}', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpLamp(
            tester,
            session: await signedInSession(),
            at: at,
            locale: const Locale('bn'),
            http: server(),
            prefs: {'lamp.themeMode': dark ? 'dark' : 'light'},
          );
          if (key != null) await tapKey(tester, key);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
