import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Today (plan 5.2): the one thing to do next, then the day's figures.
void main() {
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
    body = File('test/fixtures/today.json').readAsStringSync();
    down = false;
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester,
        session: await signedInSession(), at: '/today', locale: locale, http: server());
  }

  testWidgets('shows the day\'s figures from /today', (tester) async {
    await open(tester);
    expect(sent.single.url.path, '/api/v1/pharmacies/green-life/today');
    expect(sent.single.headers['Authorization'], startsWith('Bearer '));

    expect(find.text('Approve the plan for the short day'), findsOneWidget);
    expect(find.text('Short ৳ 19,000 on Mon 26 Oct'), findsOneWidget);
    expect(find.text('৳ 39,150'), findsOneWidget);
    expect(find.text('৳ 18,400'), findsOneWidget);
    expect(find.text('৳ 9,200 can go back'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('As of Fri 16 Oct'), findsOneWidget);
  });

  testWidgets('the one thing to do opens its screen', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('one-thing')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Approvals')),
        findsOneWidget);
  });

  for (final (kind, words) in [
    ('setup', 'Finish setting up your shop'),
    ('remind', 'Remind a customer whose payment is due'),
    ('scan', 'Scan a supplier bill'),
    ('none', 'Nothing urgent today.'),
  ]) {
    testWidgets('the one thing "$kind", as contract v1 names it', (tester) async {
      body = body.replaceFirst(RegExp(r'"one_thing": \{[^}]*\}'),
          '"one_thing": {"kind": "$kind", "action_id": null, "title_key": "today.one_thing.$kind"}');
      await open(tester);
      expect(find.text(words), findsOneWidget);
      expect(find.byKey(const ValueKey('one-thing')), kind == 'none' ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('in Bangla, amounts and dates use Bangla digits', (tester) async {
    await open(tester, locale: const Locale('bn'));
    expect(find.text('৳৩৯,১৫০'), findsOneWidget);
    expect(find.text('সোম ২৬ অক্টো তারিখে ৳১৯,০০০ কম পড়বে'), findsOneWidget);
    // The server's English alert keeps its words; its amount turns Bangla.
    expect(find.text('Send back stock worth ৳৯,২০০'), findsOneWidget);
  });

  testWidgets('a quiet day says so', (tester) async {
    body = body
        .replaceFirst(RegExp(r'"next_problem": \{[^}]*\}'), '"next_problem": null')
        .replaceFirst(RegExp(r'"one_thing": \{[^}]*\}'), '"one_thing": null');
    await open(tester);
    expect(find.text('Nothing urgent today.'), findsOneWidget);
    expect(find.textContaining('Short'), findsNothing);
  });

  testWidgets('offline: plain words and a way to try again', (tester) async {
    down = true;
    await open(tester);
    // A GET is retried twice with backoff before the app says it's offline.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    down = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('৳ 39,150'), findsOneWidget);
  });

  testWidgets('pulling down reloads', (tester) async {
    await open(tester);
    final before = sent.length;
    await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(sent.length, before + 1);
  });
}
