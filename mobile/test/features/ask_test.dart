import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Ask (plan 5.2, 5.3; Y3.3): a Plus tab. One main action: ask a question.
void main() {
  String fixture(String name, [String ext = 'json']) => File('test/fixtures/$name.$ext').readAsStringSync();
  final freeMe = jsonDecode(fixture('me')) as Map<String, dynamic>;
  final plusMe = {
    ...freeMe,
    'plan': 'plus',
    'entitlements': {'cash': true, 'plan': true, 'approvals': true, 'ask': true, 'scans_left': null},
  };

  late Map<String, dynamic> me;
  late List<Map<String, dynamic>> chats;
  late Stream<List<int>> Function() answer;
  late http.StreamedResponse? Function()? refuse;

  http.StreamedResponse jsonResponse(String body, [int status = 200]) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  MockClient server() => MockClient.streaming((req, body) async {
    final bytes = await body.toBytes();
    final p = req.url.path;
    if (p == '/api/v1/me') return jsonResponse(jsonEncode(me));
    if (p == '/api/v1/chat') {
      chats.add(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      final r = refuse?.call();
      if (r != null) return r;
      return http.StreamedResponse(answer(), 200, headers: {'content-type': 'text/event-stream'});
    }
    if (p.endsWith('/actions')) return jsonResponse(fixture('actions'));
    if (p.endsWith('/pause')) return jsonResponse(fixture('pause'));
    return jsonResponse('{"detail":"not in this test","code":"not_found"}', 404);
  });

  setUp(() {
    me = plusMe;
    chats = [];
    refuse = null;
    answer = () => Stream.value(utf8.encode(fixture('chat_answer', 'txt')));
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester, session: await signedInSession(), at: '/ask', locale: locale, http: server());
  }

  /// The mocked streaming response is piped on the real event loop, which a
  /// widget test's fake clock never runs; give it a moment of real time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> askThis(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('ask-input')), q);
    await tapKey(tester, 'ask-send');
  }

  String asked(int i) =>
      ((((chats[i]['messages'] as List).last as Map)['parts'] as List).single as Map)['text'] as String;

  testWidgets('on the free plan: what it does, Start LaMP Plus, and nothing sent', (tester) async {
    me = freeMe;
    await open(tester);
    expect(find.text('Ask is part of LaMP Plus'), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-input')), findsNothing);
    expect(chats, isEmpty);
  });

  testWidgets('empty: a few questions to start from; tapping one asks it', (tester) async {
    await open(tester);
    expect(find.text('Ask about your money.'), findsOneWidget);
    await tapKey(tester, 'ask-suggest-1');
    expect(asked(0), "Can I pay Supplier A's order next week?");
    expect(find.text("You will be short BDT 19,000 on 26 Oct, when Supplier A's order is due."), findsOneWidget);
    expect(find.text('Every figure checked against your books'), findsOneWidget);
  });

  testWidgets('a typed question, sent with the app\'s language', (tester) async {
    await open(tester);
    await askThis(tester, 'Can I pay Supplier A next week?');
    expect(asked(0), 'Can I pay Supplier A next week?');
    expect(chats.single['lang'], 'en');
    expect(find.text('Can I pay Supplier A next week?'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('ask-input'))).controller!.text, isEmpty);
  });

  testWidgets('while LaMP works: the step it is on, in plain words', (tester) async {
    final c = StreamController<List<int>>();
    answer = () => c.stream;
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('ask-input')), 'Q');
    await tester.tap(find.byKey(const ValueKey('ask-send')));
    await tester.pump();
    c.add(utf8.encode('data: {"type":"tool-input-start","toolCallId":"t1","toolName":"get_forecast"}\n\n'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('Looking at your cash…'), findsOneWidget);
    c.add(utf8.encode('data: {"type":"text-delta","id":"a","delta":"Done."}\n\ndata: {"type":"finish"}\n\n'));
    await c.close();
    await settle(tester);
    expect(find.text('Looking at your cash…'), findsNothing);
    expect(find.text('Done.'), findsOneWidget);
  });

  testWidgets('in Bangla, the answer\'s figures get Bangla digits', (tester) async {
    await open(tester, locale: const Locale('bn'));
    await askThis(tester, 'প্রশ্ন');
    expect(chats.single['lang'], 'bn');
    expect(find.textContaining('৳১৯,০০০'), findsOneWidget);
  });

  testWidgets('held back by the guard: the safe reply, and why', (tester) async {
    answer = () => Stream.value(utf8.encode(fixture('chat_held', 'txt')));
    await open(tester);
    await askThis(tester, 'Q');
    expect(find.textContaining('I held that answer back'), findsOneWidget);
    expect(find.text("Held back: an amount didn't match your books"), findsOneWidget);
    expect(find.text('Every figure checked against your books'), findsNothing);
  });

  testWidgets('cut off: Lost connection, and Ask again sends the same question', (tester) async {
    answer = () => Stream.value(utf8.encode(fixture('chat_dropped', 'txt')));
    await open(tester);
    await askThis(tester, 'Can I pay?');
    expect(find.text('Lost connection. Ask again.'), findsOneWidget);
    answer = () => Stream.value(utf8.encode(fixture('chat_answer', 'txt')));
    await tapKey(tester, 'ask-again');
    expect(asked(1), 'Can I pay?');
    expect(find.text('Lost connection. Ask again.'), findsNothing);
    expect(find.text('Can I pay?'), findsOneWidget, reason: 'asked once on screen');
  });

  testWidgets('the month\'s budget used up: the plain words for it', (tester) async {
    refuse = () => jsonResponse('{"detail":"Budget","code":"ai_budget_reached"}', 402);
    await open(tester);
    await askThis(tester, 'Q');
    expect(find.text(lookupMessage('errAiBudgetReached')), findsOneWidget);
  });

  testWidgets('a step proposed: said, and the way to Approvals', (tester) async {
    answer = () => Stream.value(utf8.encode(fixture('chat_propose', 'txt')));
    await open(tester);
    await askThis(tester, 'Ask Supplier A for more days');
    expect(find.text('A step is waiting in Approvals.'), findsOneWidget);
    await tapKey(tester, 'ask-approvals');
    expect(find.text('Waiting for you'), findsOneWidget);
  });

  testWidgets('one question at a time: Send is off while LaMP answers', (tester) async {
    final c = StreamController<List<int>>();
    answer = () => c.stream;
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('ask-input')), 'Q');
    await tester.tap(find.byKey(const ValueKey('ask-send')));
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('ask-send'))).onPressed, isNull);
    await c.close();
    await settle(tester);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('ask-send'))).onPressed, isNotNull);
  });

  group('at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      testWidgets('empty and answered · ${dark ? 'dark' : 'light'}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpLamp(
          tester,
          session: await signedInSession(),
          at: '/ask',
          locale: const Locale('bn'),
          http: server(),
          prefs: {'lamp.themeMode': dark ? 'dark' : 'light'},
        );
        expect(tester.takeException(), isNull);
        answer = () => Stream.value(utf8.encode(fixture('chat_propose', 'txt')));
        await askThis(tester, 'অনেক লম্বা একটি প্রশ্ন যাতে লাইন ভেঙে যায় এবং বোতামগুলো ঠিক থাকে কিনা দেখা যায়');
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// The English text of an ARB key, read from the file the app is built from.
String lookupMessage(String key) =>
    (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>)[key] as String;
