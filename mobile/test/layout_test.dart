import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lamp_shop/app.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';

import 'helpers.dart';

/// Plan 5.8 and 9.1: every screen at 360 x 800, light and dark, text at 1.0
/// and 1.3, in English and Bangla, with nothing overflowing. An overflow is
/// reported by Flutter as an exception, which fails the test.
void main() {
  final today = File('test/fixtures/today.json').readAsStringSync();
  final server = MockClient((req) async => http.Response(today, 200,
      headers: {'content-type': 'application/json; charset=utf-8'}));

  final screens = ['/welcome', '/today', '/customers', '/more', '/stock'];

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

            final session = at == '/welcome'
                ? fakeSession(FakeAuthService())
                : await signedInSession();
            await tester.pumpWidget(LampApp(
              session: session,
              initialLocation: at,
              locale: Locale(lang),
              httpClient: server,
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
