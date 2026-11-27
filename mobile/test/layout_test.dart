import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lamp_shop/app.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';

import 'helpers.dart';

/// Plan 5.8 and 9.1: every screen at 360 x 800, light and dark, text at 1.0
/// and 1.3, in English and Bangla, with nothing overflowing. An overflow is
/// reported by Flutter as an exception, which fails the test.
void main() {
  String fixture(String name) => File('test/fixtures/$name.json').readAsStringSync();
  final byPath = {
    '/today': fixture('today'),
    '/expiry': fixture('expiry'),
    '/customers': fixture('customers'),
    '/me': fixture('me'),
    '/credit-record': fixture('credit_record'),
    '/plus': fixture('plus'),
    '/usage': '{"plan":"free","scans_used":7,"scans_limit":10,"ai_used_bdt":0.4,'
        '"ai_budget_bdt":1.2,"resets_on":"2026-12-01"}',
  };
  // Each screen gets its own answer; anything else reads as an empty list.
  final server = MockClient((req) async {
    final body = byPath.entries
            .where((e) => req.url.path.endsWith(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        '[]';
    return http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });

  final screens = [
    '/welcome',
    '/setup',
    '/today',
    '/scan',
    '/customers',
    // SMS on with a plan; and not on SMS yet, with the join text.
    '/customers/GL-7KQM-4XPA',
    '/customers/GL-8NBV-2KLM?added=1',
    '/more',
    '/stock',
    // On the free plan (me.json): each shows what it does and Start LaMP Plus.
    '/cash',
    '/plan',
    '/approvals',
    '/credit-record',
    '/plus',
    '/ask',
    '/settings',
    '/help',
    // Not a demo shop (me.json): says the phone is for the demo shop only.
    '/demo-phone',
  ];

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    for (final scale in [1.0, 1.3]) {
      for (final lang in ['en', 'bn']) {
        for (final at in screens) {
          testWidgets('$at · ${theme.name} · text $scale · $lang', (tester) async {
            SharedPreferences.setMockInitialValues({'lamp.themeMode': theme.name});
            tester.view.physicalSize = const Size(360, 800);
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            final session = switch (at) {
              '/welcome' => fakeSession(FakeAuthService()),
              '/setup' => await signedInSession(hasShop: false),
              _ => await signedInSession(),
            };
            await tester.pumpWidget(LampApp(
              session: session,
              initialLocation: at,
              locale: Locale(lang),
              httpClient: server,
              cache: MemoryCacheStore(),
            ));
            await tester.pumpAndSettle();

            final context = tester.element(find.byType(Scaffold).first);
            expect(Theme.of(context).brightness,
                theme == ThemeMode.dark ? Brightness.dark : Brightness.light);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
