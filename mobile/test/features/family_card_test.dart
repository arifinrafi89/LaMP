import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';
import 'package:lamp_shop/features/family/family_card.dart';

import '../helpers.dart';

/// The family's card (`/me/<code>`, plan 0.6 and 3.5): what they owe and a
/// plan they choose, on any smartphone, without signing in. Amounts only.
void main() {
  final cardJson = jsonDecode(File('test/fixtures/card.json').readAsStringSync()) as Map<String, dynamic>;
  late List<http.Request> sent;
  late Map<String, dynamic> card;
  late http.Response? Function(http.Request)? override;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  MockClient server() => MockClient((req) async {
    sent.add(req);
    final o = override?.call(req);
    if (o != null) return o;
    final p = req.url.path;
    if (p == '/api/v1/cards/GL-3HFD-9WQT' && req.method == 'GET') return json(card);
    if (p == '/api/v1/cards/GL-3HFD-9WQT/plan') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      card = {
        ...card,
        'plan': {
          'parts': b['parts'],
          'first_on': b['first_on'],
          'schedule': [
            {'n': 1, 'due_on': '2026-11-30', 'amount': 1225.0},
            {'n': 2, 'due_on': '2026-12-07', 'amount': 1225.0},
          ],
        },
      };
      return json(card);
    }
    if (p.startsWith('/api/v1/cards/')) return json({'detail': 'No card', 'code': 'not_found'}, 404);
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    sent = [];
    card = Map.of(cardJson);
    override = null;
  });

  /// Signed out, as a family is.
  Future<void> open(WidgetTester tester, String at, {Locale? locale = const Locale('en')}) async {
    final s = fakeSession(FakeAuthService());
    await s.restore();
    await pumpLamp(tester, session: s, at: at, locale: locale, http: server());
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('the code', () {
    test('typed any way, read the way the server reads it', () {
      expect(normaliseCode('gl7kqm4xpa'), 'GL-7KQM-4XPA');
      expect(normaliseCode(' GL 7KQM 4XPA '), 'GL-7KQM-4XPA');
      expect(normaliseCode('GL-7KQM-4XPA'), 'GL-7KQM-4XPA');
      expect(normaliseCode('abc'), 'ABC');
    });

    testWidgets('signed out, the code page opens (not Welcome), and Open goes to the card', (tester) async {
      await open(tester, '/me');
      expect(find.text('Enter the code on your slip from the pharmacy.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('me-code')), 'gl 3hfd 9wqt');
      await tapKey(tester, 'me-open');
      expect(sent.single.url.path, '/api/v1/cards/GL-3HFD-9WQT');
      expect(find.text('You owe'), findsOneWidget);
    });
  });

  group('the card', () {
    testWidgets('signed out: the pharmacy, the label, what is owed, no name', (tester) async {
      await open(tester, '/me/GL-3HFD-9WQT');
      expect(find.text('Green Life Pharmacy, Bogura · Customer 003'), findsOneWidget);
      expect(find.text('৳ 2,450'), findsOneWidget);
      expect(find.text('Since Tue 20 Oct, 38 days ago'), findsOneWidget);
      expect(sent.single.headers['Authorization'], isNull, reason: 'no session on a family\'s phone');
    });

    testWidgets('no plan yet: the server\'s ways to pay; pick one and promise it', (tester) async {
      await open(tester, '/me/GL-3HFD-9WQT');
      expect(find.text('All at once: ৳ 2,450'), findsOneWidget);
      expect(find.text('2 weekly parts of ৳ 1,225'), findsOneWidget);
      await tapKey(tester, 'me-plan-2');
      await tapKey(tester, 'me-promise');
      final post = sent.firstWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/v1/cards/GL-3HFD-9WQT/plan');
      expect(jsonDecode(post.body), {'parts': 2, 'first_on': '2026-11-27'});
      expect(find.text('Your plan'), findsOneWidget);
      expect(find.text('Promised'), findsOneWidget);
      expect(find.text('Mon 30 Nov'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('with a plan: the parts, and Change my plan', (tester) async {
      card['plan'] = {
        'parts': 2,
        'first_on': '2026-11-30',
        'schedule': [
          {'n': 1, 'due_on': '2026-11-30', 'amount': 1225.0},
          {'n': 2, 'due_on': '2026-12-07', 'amount': 1225.0},
        ],
      };
      await open(tester, '/me/GL-3HFD-9WQT');
      expect(find.text('Mon 7 Dec'), findsOneWidget);
      expect(find.byKey(const ValueKey('me-promise')), findsNothing);
      await tapKey(tester, 'me-change');
      expect(find.byKey(const ValueKey('me-promise')), findsOneWidget);
    });

    testWidgets('free SMS reminders: the join text for this card', (tester) async {
      await open(tester, '/me/GL-3HFD-9WQT');
      expect(find.text('LAMP GL3HFD9WQT'), findsOneWidget);
    });

    testWidgets('a code that does not exist: plain words, and the way back', (tester) async {
      await open(tester, '/me/GL-0000-0000');
      expect(find.text("We couldn't find that card"), findsOneWidget);
      await tapKey(tester, 'me-enter-code');
      expect(find.byKey(const ValueKey('me-code')), findsOneWidget);
    });

    testWidgets('too many wrong codes: the server\'s refusal, in plain words', (tester) async {
      override = (_) => json({'detail': 'slow down', 'code': 'rate_limited', 'retry_after': 60}, 429);
      await open(tester, '/me/GL-3HFD-9WQT');
      expect(find.text('Too many tries. Wait a moment and try again.'), findsOneWidget);
    });

    testWidgets('a family can switch to Bangla on the card', (tester) async {
      await open(tester, '/me/GL-3HFD-9WQT', locale: null);
      await tapKey(tester, 'me-lang');
      expect(find.text('আপনার বাকি'), findsOneWidget);
      expect(find.text('৳২,৪৫০'), findsOneWidget);
      expect(find.text('LAMP GL3HFD9WQT'), findsOneWidget, reason: 'codes keep English letters and digits');
    });

    testWidgets('an owner who is signed in sees it too, without the bottom bar', (tester) async {
      await pumpLamp(tester, session: await signedInSession(), at: '/me/GL-3HFD-9WQT', http: server());
      expect(find.text('You owe'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      for (final at in ['/me', '/me/GL-3HFD-9WQT']) {
        testWidgets('$at · ${dark ? 'dark' : 'light'}', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final s = fakeSession(FakeAuthService());
          await s.restore();
          await pumpLamp(
            tester,
            session: s,
            at: at,
            locale: const Locale('bn'),
            http: server(),
            prefs: {'lamp.themeMode': dark ? 'dark' : 'light'},
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
