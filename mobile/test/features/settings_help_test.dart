import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/features/welcome/welcome_screen.dart';

import '../helpers.dart';

/// Settings and Help (plan 13.3, 15.1; Y4.1).
void main() {
  final me = File('test/fixtures/me.json').readAsStringSync();
  late List<http.Request> sent;
  late bool patchDown;
  late String exportStatus;
  late List<Uri> opened;
  late List<Map<String, Object?>> devices;

  http.Response json(Object? body, [int status = 200]) => http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  MockClient server() => MockClient((req) async {
    sent.add(req);
    final p = req.url.path;
    if (p == '/api/v1/me' && req.method == 'PATCH') {
      if (patchDown) throw http.ClientException('no network');
      return json(jsonDecode(me));
    }
    if (p == '/api/v1/me') return http.Response(me, 200, headers: {'content-type': 'application/json'});
    if (p == '/api/v1/auth/devices') return json(devices);
    if (p.startsWith('/api/v1/auth/devices/')) {
      devices = [
        for (final d in devices)
          if (!p.endsWith('/${d['id']}')) d,
      ];
      return json(null, 204);
    }
    if (p == '/api/v1/auth/sign-out') return json(null, 204);
    if (p == '/api/v1/legal/current') {
      return json({
        'terms_version': 't1',
        'privacy_version': 'p1',
        'terms_url': 'https://lamp.example/terms',
        'privacy_url': 'https://lamp.example/privacy',
      });
    }
    if (p == '/api/v1/me/export') return json({'export_id': 'ex-1'}, 202);
    if (p == '/api/v1/me/export/ex-1') {
      return json({
        'status': exportStatus,
        'download_url': exportStatus == 'ready' ? 'https://lamp.example/dl/ex-1' : null,
      });
    }
    if (p == '/api/v1/me/delete') return json({'erase_on': '2026-12-04'}, 202);
    if (p == '/api/v1/support/reports') return json({'report_id': 'r-1'}, 201);
    return json({'detail': 'not in this test', 'code': 'not_found'}, 404);
  });

  setUp(() {
    sent = [];
    patchDown = false;
    exportStatus = 'ready';
    opened = [];
    devices = [
      {
        'id': 'd-1',
        'name': 'Android phone',
        'os': 'android',
        'last_used_at': '2026-11-27T04:00:00Z',
        'this_device': true,
      },
      {'id': 'd-2', 'name': 'Web browser', 'os': 'web', 'last_used_at': '2026-11-20T09:30:00Z', 'this_device': false},
    ];
  });

  Future<void> open(WidgetTester tester, String at, {Locale? locale = const Locale('en')}) async {
    await pumpLamp(
      tester,
      session: await signedInSession(),
      at: at,
      locale: locale,
      http: server(),
      open: (u) async {
        opened.add(u);
        return true;
      },
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Iterable<http.Request> to(String path, [String? method]) =>
      sent.where((r) => r.url.path == path && (method == null || r.method == method));

  group('settings', () {
    testWidgets('the signed-in phones; another one signed out', (tester) async {
      await open(tester, '/settings');
      expect(find.text('This phone'), findsOneWidget);
      expect(find.text('Web browser'), findsOneWidget);
      expect(find.byKey(const ValueKey('device-signout-d-1')), findsNothing, reason: 'not this phone, from here');
      await tapKey(tester, 'device-signout-d-2');
      expect(to('/api/v1/auth/devices/d-2', 'DELETE'), hasLength(1));
      expect(find.text('Web browser is signed out'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.text('Web browser'), findsNothing);
    });

    testWidgets('Bangla: the app switches, and the server is told for SMS', (tester) async {
      await open(tester, '/settings', locale: null);
      await tapKey(tester, 'lang-bn');
      expect(find.text('সেটিংস'), findsWidgets);
      expect(jsonDecode(to('/api/v1/me', 'PATCH').single.body), {'language': 'bn'});
    });

    testWidgets('offline: the phone keeps the choice, and says SMS will follow', (tester) async {
      patchDown = true;
      await open(tester, '/settings', locale: null);
      await tapKey(tester, 'lang-bn');
      expect(find.text('এই ফোনে সংরক্ষিত। অনলাইনে এলে এসএমএসের ভাষাও বদলাবে।'), findsOneWidget);
      expect(find.text('সেটিংস'), findsWidgets);
    });

    testWidgets('dark', (tester) async {
      await open(tester, '/settings');
      await tapKey(tester, 'theme-dark');
      expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    });

    testWidgets('download my data: ready, then the link opens', (tester) async {
      await open(tester, '/settings');
      await tapKey(tester, 'settings-export');
      expect(to('/api/v1/me/export', 'POST'), hasLength(1));
      expect(find.text('Your data is ready. The link works for 10 minutes.'), findsOneWidget);
      await tapKey(tester, 'settings-export-open');
      expect(opened.single.toString(), 'https://lamp.example/dl/ex-1');
    });

    testWidgets('download my data: it failed, plain words', (tester) async {
      exportStatus = 'failed';
      await open(tester, '/settings');
      await tapKey(tester, 'settings-export');
      expect(find.text("Your data couldn't be prepared. Try again."), findsOneWidget);
    });

    testWidgets('terms and privacy open outside the app', (tester) async {
      await open(tester, '/settings');
      await tapKey(tester, 'settings-terms');
      await tapKey(tester, 'settings-privacy');
      expect(opened.map((u) => u.toString()), ['https://lamp.example/terms', 'https://lamp.example/privacy']);
    });

    testWidgets('the app version', (tester) async {
      await open(tester, '/settings');
      expect(find.text('LaMP 0.1.0+1'), findsOneWidget);
    });

    testWidgets('sign out of this phone: back to Welcome', (tester) async {
      await open(tester, '/settings');
      await tapKey(tester, 'settings-signout');
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('delete: only after typing DELETE; the erase day; then signed out', (tester) async {
      await open(tester, '/settings');
      await tapKey(tester, 'settings-delete');
      await tester.enterText(find.byKey(const ValueKey('delete-word')), 'delete');
      await tapKey(tester, 'delete-confirm');
      expect(find.text('Type DELETE, in capital letters.'), findsOneWidget);
      expect(to('/api/v1/me/delete'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('delete-word')), 'DELETE');
      await tapKey(tester, 'delete-confirm');
      expect(jsonDecode(to('/api/v1/me/delete').single.body), {'confirm': 'DELETE'});
      expect(find.text('Your account will be erased on Fri 4 Dec. Sign in before then to keep it.'), findsOneWidget);
      await tapKey(tester, 'delete-done');
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('help', () {
    testWidgets('plain answers to what owners ask', (tester) async {
      await open(tester, '/help');
      await tapKey(tester, 'help-q-1');
      expect(find.textContaining('When they text it to 21213'), findsOneWidget);
    });

    testWidgets('report a problem: what it is about, what happened, and where', (tester) async {
      await open(tester, '/help');
      await tapKey(tester, 'help-report');
      await tapKey(tester, 'report-send');
      expect(find.text('Write a few words about it.'), findsOneWidget);
      expect(to('/api/v1/support/reports'), isEmpty);
      await tapKey(tester, 'report-question');
      await tester.enterText(find.byKey(const ValueKey('report-message')), 'How do I add a second shop?');
      await tapKey(tester, 'report-send');
      expect(jsonDecode(to('/api/v1/support/reports').single.body), {
        'category': 'question',
        'message': 'How do I add a second shop?',
        'screen': 'help',
        'app_version': '0.1.0+1',
      });
      expect(find.text('Thank you. We got it.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('at 360 wide, Bangla, text 1.3', () {
    for (final dark in [false, true]) {
      for (final (at, key) in [
        ('/settings', null),
        ('/settings', 'settings-delete'),
        ('/help', 'help-q-0'),
        ('/help', 'help-report'),
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
