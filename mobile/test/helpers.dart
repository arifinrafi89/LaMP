import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lamp_shop/app.dart';
import 'package:lamp_shop/core/auth/auth_service.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';
import 'package:lamp_shop/core/auth/token_store.dart';
import 'package:lamp_shop/core/state/session_controller.dart';

const testDevice = DeviceInfo(id: 'd-test', name: 'Test phone', os: 'android', appVersion: '0.1.0+1');

SessionController fakeSession(FakeAuthService auth, [TokenStore? store]) => SessionController(
      auth: auth,
      store: store ?? MemoryTokenStore(),
      device: () async => testDevice,
      cookieRefresh: false,
    );

/// A session already signed in, with a shop whose setup is done.
Future<SessionController> signedInSession({bool setupComplete = true}) async {
  final auth = FakeAuthService(
    pharmacy: PharmacyInfo(id: 'green-life', name: 'Green Life Pharmacy', setupComplete: setupComplete),
  );
  final s = fakeSession(auth);
  await s.restore();
  final c = await s.requestCode('+8801912345678', 'en');
  await s.verifyCode(c, FakeAuthService.code, agreedToTerms: true);
  return s;
}

/// Pumps the whole app at a phone's size (360 x 800).
Future<void> pumpLamp(
  WidgetTester tester, {
  required SessionController session,
  String at = '/today',
  Locale? locale = const Locale('en'),
  http.Client? http,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(LampApp(
    session: session,
    initialLocation: at,
    locale: locale,
    // No real network in tests: an unanswered call reads as the server down.
    httpClient: http ?? MockClient((_) async => _down),
  ));
  await tester.pumpAndSettle();
}

final _down = http.Response('{"detail": "no server in this test"}', 503,
    headers: {'content-type': 'application/json'});
