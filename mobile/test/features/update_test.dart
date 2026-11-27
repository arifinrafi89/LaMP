import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Plan 13.5: the update gate around every screen.
void main() {
  late Map<String, Object?> config;
  late List<Uri> opened;
  late bool tooOld;

  MockClient server() => MockClient((req) async {
    if (req.url.path == '/api/v1/app/config') {
      return http.Response(jsonEncode(config), 200, headers: {'content-type': 'application/json'});
    }
    if (tooOld) return http.Response('{"detail":"too old"}', 426, headers: {'content-type': 'application/json'});
    return http.Response('{"detail":"no server in this test"}', 503, headers: {'content-type': 'application/json'});
  });

  setUp(() {
    opened = [];
    tooOld = false;
    config = {
      'min_version': '0.1.0',
      'latest_version': '0.1.0',
      'play_url': 'https://play.google.com/store/apps/details?id=bd.lamp.shop',
      'maintenance': false,
      'flags': {},
    };
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLamp(
      tester,
      session: await signedInSession(),
      at: '/more',
      locale: locale,
      http: server(),
      updates: true,
      open: (u) async {
        opened.add(u);
        return true;
      },
    );
  }

  testWidgets('up to date: nothing in the way', (tester) async {
    await open(tester);
    expect(find.text('Update LaMP'), findsNothing);
    expect(find.text('A new version of LaMP is ready.'), findsNothing);
    expect(find.text('More'), findsWidgets);
  });

  testWidgets('a newer version: a banner, put off with Later', (tester) async {
    config['latest_version'] = '0.2.0';
    await open(tester);
    expect(find.text('A new version of LaMP is ready.'), findsOneWidget);
    expect(find.text('More'), findsWidgets, reason: 'the app still works');
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
    expect(find.text('A new version of LaMP is ready.'), findsNothing);
  });

  testWidgets('below the minimum: Update LaMP, the Play page, and no way past', (tester) async {
    config['min_version'] = '0.2.0';
    await open(tester);
    expect(find.text('Update LaMP'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-later')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('update-play')));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'play.google.com');
  });

  testWidgets('maintenance: plain words and Try again', (tester) async {
    config['maintenance'] = true;
    await open(tester);
    expect(find.text('LaMP is being updated'), findsOneWidget);
    config['maintenance'] = false;
    await tester.tap(find.byKey(const ValueKey('maintenance-retry')));
    await tester.pumpAndSettle();
    expect(find.text('LaMP is being updated'), findsNothing);
  });

  testWidgets('the server answering 426 to any request: Update LaMP', (tester) async {
    tooOld = true;
    await pumpLamp(tester, session: await signedInSession(), at: '/stock', http: server(), updates: true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Update LaMP'), findsOneWidget);
  });

  testWidgets('in Bangla, 360 wide, text 1.3, both screens fit', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    config['min_version'] = '0.2.0';
    await open(tester, locale: const Locale('bn'));
    expect(find.text('LaMP আপডেট করুন'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
