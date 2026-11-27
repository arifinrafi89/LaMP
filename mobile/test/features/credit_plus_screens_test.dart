import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Credit record (BDT 10, free plan too) and LaMP Plus (BDT 50 a month),
/// plan 3.3, 3.7 and Y3.4.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();
  const base = '/api/v1/pharmacies/green-life';

  late List<http.Request> sent;
  late bool bought;
  late List<String> chargeAnswers; // what each GET of the charge says, in turn
  late String otpAnswer;
  late String plusStatus;
  late http.Response? Function(http.Request)? override;
  late List<String> shared;
  late List<(Uint8List, String)> files;
  late List<Object?> shares;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, Object?> charge(String status, {int? left, String? reason}) => {
    'charge_id': 'ch-1',
    'status': status,
    'amount': 10.0,
    'attempts_left': left,
    'reason': reason,
  };

  MockClient server() => MockClient((req) async {
    sent.add(req);
    final o = override?.call(req);
    if (o != null) return o;
    final p = req.url.path;
    if (p == '/api/v1/me') {
      final me = jsonDecode(fixture('me')) as Map<String, dynamic>;
      final on = plusStatus == 'ACTIVE';
      return json({
        ...me,
        'plan': on ? 'plus' : 'free',
        'entitlements': {'cash': on, 'plan': on, 'approvals': on, 'ask': on, 'scans_left': on ? null : 7},
      });
    }
    if (p == '$base/forecast') {
      return http.Response(fixture('forecast'), 200, headers: {'content-type': 'application/json'});
    }
    if (p == '$base/credit-record') {
      final r = jsonDecode(fixture(bought ? 'credit_record_bought' : 'credit_record')) as Map<String, dynamic>;
      return json({...r, if (bought) 'shares': shares});
    }
    if (p == '$base/credit-record/purchases') return json(charge('OTP_SENT'), 201);
    if (p.endsWith('/purchases/ch-1/otp')) {
      final b = jsonDecode(req.body) as Map;
      if (b['otp'] == '000000') return json(charge('OTP_SENT', left: 2));
      return json(charge(otpAnswer, reason: otpAnswer == 'FAILED' ? 'Not enough balance.' : null));
    }
    if (p.endsWith('/purchases/ch-1')) {
      final s = chargeAnswers.length > 1 ? chargeAnswers.removeAt(0) : chargeAnswers.first;
      if (s == 'PAID') bought = true;
      return json(charge(s));
    }
    if (p == '$base/credit-record/pdf') {
      return http.Response.bytes([0x25, 0x50, 0x44, 0x46], 200, headers: {'content-type': 'application/pdf'});
    }
    if (p == '$base/credit-record/shares') {
      final b = jsonDecode(req.body) as Map;
      final s = {
        'id': 'sh-9',
        'lender_name': b['lender_name'],
        'url': 'https://lamp-api-k2xf.onrender.com/r/Zq81',
        'expires_at': '2026-12-04T06:00:00+06:00',
        'views': 0,
      };
      shares = [s];
      return json(s, 201);
    }
    if (p.startsWith('$base/credit-record/shares/')) {
      shares = [];
      return http.Response('', 204);
    }
    if (p == '$base/plus') {
      return json({'status': plusStatus, 'renews_on': plusStatus == 'ACTIVE' ? '2026-12-27' : null});
    }
    if (p == '$base/plus/subscribe') {
      plusStatus = 'OTP_SENT';
      return json({'status': plusStatus, 'renews_on': null}, 202);
    }
    if (p == '$base/plus/otp') {
      if ((jsonDecode(req.body) as Map)['otp'] == '000000') {
        return json({'detail': 'wrong', 'code': 'otp_wrong'}, 400);
      }
      plusStatus = 'ACTIVE';
      return json({'status': plusStatus, 'renews_on': '2026-12-27'});
    }
    if (p == '$base/plus/cancel') {
      plusStatus = 'STOPPED';
      return json({'status': plusStatus, 'renews_on': null});
    }
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    sent = [];
    bought = false;
    chargeAnswers = ['PAID'];
    otpAnswer = 'VERIFYING';
    plusStatus = 'NONE';
    override = null;
    shared = [];
    files = [];
    shares = (jsonDecode(fixture('credit_record_bought')) as Map)['shares'] as List;
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
      shareFile: (b, name, _) async => files.add((b, name)),
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

  Iterable<http.Request> to(String path) => sent.where((r) => r.url.path == path);

  group('credit record', () {
    testWidgets('free plan too: the preview and the one action, BDT 10', (tester) async {
      await open(tester, '/credit-record');
      expect(find.text('38 of 41 bills paid on time, over 12 months'), findsOneWidget);
      expect(find.text('BDT 10 from your mobile balance. Banglalink sends a code to confirm.'), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-buy')), findsOneWidget);
      expect(find.textContaining('part of LaMP Plus'), findsNothing);
    });

    testWidgets('buy, type the code, wait for PAID: the record opens', (tester) async {
      chargeAnswers = ['VERIFYING', 'PAID'];
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-buy');
      expect(to('$base/credit-record/purchases').single.headers['Idempotency-Key'], isNotNull);
      expect(find.text('Banglalink sent a code to your phone. Type it to pay BDT 10.'), findsOneWidget);
      await type(tester, 'credit-code', '123456');
      await tapKey(tester, 'credit-pay');
      expect(find.text('Your record is ready'), findsOneWidget);
      expect(to('$base/credit-record/purchases'), hasLength(1), reason: 'one charge');
    });

    testWidgets('a code typed in Bangla digits is sent in English digits', (tester) async {
      await open(tester, '/credit-record', locale: const Locale('bn'));
      await tapKey(tester, 'credit-buy');
      await type(tester, 'credit-code', '১২৩৪৫৬');
      await tapKey(tester, 'credit-pay');
      final otp = sent.firstWhere((r) => r.url.path.endsWith('/otp'));
      expect(jsonDecode(otp.body), {'otp': '123456'});
    });

    testWidgets('a short code is caught on the phone', (tester) async {
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-buy');
      await type(tester, 'credit-code', '123');
      await tapKey(tester, 'credit-pay');
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      expect(sent.where((r) => r.url.path.endsWith('/otp')), isEmpty);
    });

    testWidgets('a wrong code: how many tries are left, same charge', (tester) async {
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-buy');
      await type(tester, 'credit-code', '000000');
      await tapKey(tester, 'credit-pay');
      expect(find.text("That code isn't right. 2 tries left."), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-pay')), findsOneWidget);
    });

    testWidgets('low balance: the reason, no money taken, and Try again', (tester) async {
      otpAnswer = 'FAILED';
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-buy');
      await type(tester, 'credit-code', '123456');
      await tapKey(tester, 'credit-pay');
      expect(find.text('Not enough balance.'), findsOneWidget);
      expect(find.text('No money was taken.'), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-buy')), findsOneWidget);
    });

    testWidgets('Banglalink slow: says so, then Check again finds it paid', (tester) async {
      chargeAnswers = ['UNKNOWN'];
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-buy');
      await type(tester, 'credit-code', '123456');
      await tapKey(tester, 'credit-pay');
      expect(
        find.text("Banglalink hasn't confirmed yet. Nothing more will be charged. Check again in a minute."),
        findsOneWidget,
      );
      chargeAnswers = ['PAID'];
      await tapKey(tester, 'credit-check');
      expect(find.text('Your record is ready'), findsOneWidget);
      expect(to('$base/credit-record/purchases'), hasLength(1));
    });

    testWidgets('bought: the PDF goes to the share sheet as a file', (tester) async {
      bought = true;
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-pdf');
      expect(files.single.$1, [0x25, 0x50, 0x44, 0x46]);
      expect(files.single.$2, endsWith('.pdf'));
    });

    testWidgets('bought: the lender\'s link, its views, and taking it back', (tester) async {
      bought = true;
      await open(tester, '/credit-record');
      expect(find.text('Link for City Bank Bogura'), findsOneWidget);
      expect(find.text('Open until Fri 4 Dec · opened 2 times'), findsOneWidget);
      await tapKey(tester, 'credit-link-share');
      expect(shared.single, 'https://lamp-api-k2xf.onrender.com/r/9fK2xQ7mPa');
      await tapKey(tester, 'credit-revoke');
      expect(sent.firstWhere((r) => r.method == 'DELETE').url.path, '$base/credit-record/shares/sh-1');
      expect(find.byKey(const ValueKey('credit-lender')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('bought, no link yet: name one lender, get the link', (tester) async {
      bought = true;
      shares = [];
      await open(tester, '/credit-record');
      await tapKey(tester, 'credit-make-link');
      expect(find.text("Enter the lender's name."), findsOneWidget);
      await type(tester, 'credit-lender', 'BRAC Bank');
      await tapKey(tester, 'credit-make-link');
      final post = to('$base/credit-record/shares').single;
      expect(jsonDecode(post.body), {'lender_name': 'BRAC Bank', 'expires_in_days': 7});
      expect(find.text('Link for BRAC Bank'), findsOneWidget);
    });
  });

  group('LaMP Plus', () {
    testWidgets('what it adds, the price in words, Agree, the code, then on', (tester) async {
      await open(tester, '/plus');
      expect(find.text('LaMP Plus, BDT 50 a month + VAT from your mobile balance. Stop any time.'), findsOneWidget);
      expect(find.text('Scans with no monthly limit'), findsOneWidget);
      await tapKey(tester, 'plus-agree');
      expect(to('$base/plus/subscribe'), hasLength(1));
      expect(find.text('Banglalink sent a code to your phone. Type it to start LaMP Plus.'), findsOneWidget);
      await type(tester, 'plus-code', '123456');
      await tapKey(tester, 'plus-confirm');
      expect(jsonDecode(to('$base/plus/otp').single.body), {'otp': '123456'});
      expect(find.text('LaMP Plus is on'), findsOneWidget);
      expect(find.text('Renews on Sun 27 Dec'), findsOneWidget);
    });

    testWidgets('from a locked screen: start Plus, and that screen opens', (tester) async {
      await open(tester, '/cash');
      expect(find.text('Cash is part of LaMP Plus'), findsOneWidget);
      await tapKey(tester, 'plus-start');
      await tapKey(tester, 'plus-agree');
      await type(tester, 'plus-code', '123456');
      await tapKey(tester, 'plus-confirm');
      expect(
        sent.where((r) => r.url.path == '/api/v1/me'),
        hasLength(greaterThan(1)),
        reason: '/me reads again so the Plus screens unlock',
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/cash');
      await tester.pumpAndSettle();
      expect(find.text('Cash is part of LaMP Plus'), findsNothing);
      expect(find.text('You have ৳ 39,150 now'), findsOneWidget);
    });

    testWidgets('a wrong code: plain words, try again', (tester) async {
      await open(tester, '/plus');
      await tapKey(tester, 'plus-agree');
      await type(tester, 'plus-code', '000000');
      await tapKey(tester, 'plus-confirm');
      expect(find.text("That code isn't right."), findsOneWidget);
      expect(find.byKey(const ValueKey('plus-confirm')), findsOneWidget);
    });

    testWidgets('waiting for Banglalink, and Check again', (tester) async {
      plusStatus = 'PENDING';
      await open(tester, '/plus');
      expect(find.text('Waiting for Banglalink to confirm.'), findsOneWidget);
      plusStatus = 'ACTIVE';
      await tapKey(tester, 'plus-check');
      expect(find.text('LaMP Plus is on'), findsOneWidget);
    });

    testWidgets('on: stop it, after saying what that means', (tester) async {
      plusStatus = 'ACTIVE';
      await open(tester, '/plus');
      await tapKey(tester, 'plus-cancel');
      expect(
        find.text("Stop LaMP Plus? Cash, Plan, Approvals and Ask lock again, and you won't be charged again."),
        findsOneWidget,
      );
      expect(to('$base/plus/cancel'), isEmpty);
      await tapKey(tester, 'plus-cancel-yes');
      expect(to('$base/plus/cancel'), hasLength(1));
      expect(find.text("LaMP Plus is off. You won't be charged again."), findsOneWidget);
      expect(find.byKey(const ValueKey('plus-agree')), findsOneWidget, reason: 'can start again, with a fresh consent');
    });

    testWidgets('a balance too low to renew: top up, free things keep working', (tester) async {
      plusStatus = 'BLOCKED';
      await open(tester, '/plus');
      expect(find.textContaining('Top up your balance'), findsOneWidget);
    });

    testWidgets('not open yet on the server: coming soon, not an error', (tester) async {
      override = (r) => r.url.path == '$base/plus' ? json({'detail': 'not built', 'code': 'not_built'}, 501) : null;
      await open(tester, '/plus');
      expect(find.text('LaMP Plus is coming soon'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('Start LaMP Plus on a locked screen leads here', (tester) async {
      await open(tester, '/cash');
      await tapKey(tester, 'plus-start');
      expect(find.byKey(const ValueKey('plus-agree')), findsOneWidget);
    });
  });

  group('every state at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      for (final (name, at, setup) in <(String, String, void Function())>[
        ('record, to buy', '/credit-record', () {}),
        ('record, bought', '/credit-record', () => bought = true),
        ('plus, none', '/plus', () {}),
        ('plus, on', '/plus', () => plusStatus = 'ACTIVE'),
        ('plus, blocked', '/plus', () => plusStatus = 'BLOCKED'),
      ]) {
        testWidgets('$name · ${dark ? 'dark' : 'light'}', (tester) async {
          setup();
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
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final (name, at, key) in [
      ('record, code', '/credit-record', 'credit-buy'),
      ('plus, code', '/plus', 'plus-agree'),
    ]) {
      testWidgets('$name · light', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpLamp(tester, session: await signedInSession(), at: at, locale: const Locale('bn'), http: server());
        await tapKey(tester, key);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
