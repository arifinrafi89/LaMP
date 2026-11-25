import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/core/auth/auth_service.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';
import 'package:lamp_shop/core/auth/token_store.dart';

import '../helpers.dart';

/// Plan 5.2 step 1 and 3.2: welcome, number and code, adapted from
/// lamp-flutter's sign-in (Google, seat picker and registration gone; a
/// language choice and terms consent added).
void main() {
  Future<void> toPhoneStep(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('agree-terms')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('continue-phone')));
    await tester.pumpAndSettle();
  }

  Future<void> sendCode(WidgetTester tester, String number) async {
    await tester.enterText(find.byKey(const ValueKey('phone-field')), number);
    await tester.tap(find.byKey(const ValueKey('send-code')));
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-out phone opens on Welcome, whatever the link', (tester) async {
    await pumpLamp(tester, session: fakeSession(FakeAuthService()), at: '/customers');
    expect(find.text('Welcome to LaMP'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the owner must agree to the terms before going on', (tester) async {
    await pumpLamp(tester, session: fakeSession(FakeAuthService()));
    final button = find.byKey(const ValueKey('continue-phone'));
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('agree-terms')));
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
  });

  testWidgets('another operator\'s number is turned away before any code is sent',
      (tester) async {
    final auth = FakeAuthService();
    await pumpLamp(tester, session: fakeSession(auth));
    await toPhoneStep(tester);
    await sendCode(tester, '01712345678');
    expect(find.text('Use a Banglalink number.'), findsOneWidget);
    expect(auth.codeRequests, 0);
  });

  testWidgets('a wrong code says so, and the right one opens Setup for a new owner',
      (tester) async {
    await pumpLamp(tester, session: fakeSession(FakeAuthService()));
    await toPhoneStep(tester);
    await sendCode(tester, '01912 345678');
    expect(find.text('We sent a 6-digit code to +880 1912 345678.'), findsOneWidget);
    // The resend button waits for the server's 30 seconds.
    expect(find.textContaining('Send again in'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('code-field')), '000000');
    await tester.pumpAndSettle();
    expect(find.text("That code isn't right."), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('code-field')), FakeAuthService.code);
    await tester.pumpAndSettle();
    expect(find.text('Set up your shop'), findsWidgets);
  });

  testWidgets('a returning owner with a set-up shop lands on Today', (tester) async {
    final auth = FakeAuthService(
        pharmacy: const PharmacyInfo(id: 'g', name: 'Green Life', setupComplete: true));
    await pumpLamp(tester, session: fakeSession(auth));
    await toPhoneStep(tester);
    await sendCode(tester, '01912345678');
    await tester.enterText(find.byKey(const ValueKey('code-field')), FakeAuthService.code);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Today')), findsOneWidget);
  });

  testWidgets('a stored session opens straight on the link it was given', (tester) async {
    final auth = FakeAuthService(
        pharmacy: const PharmacyInfo(id: 'g', name: 'Green Life', setupComplete: true));
    final store = MemoryTokenStore();
    final first = fakeSession(auth, store);
    await first.restore();
    await first.verifyCode(await first.requestCode('+8801912345678', 'en'), FakeAuthService.code,
        agreedToTerms: true);

    await pumpLamp(tester, session: fakeSession(auth, store), at: '/customers');
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Customers')),
        findsOneWidget);
  });

  testWidgets('choosing Bangla switches the welcome screen at once', (tester) async {
    await pumpLamp(tester, session: fakeSession(FakeAuthService()), locale: null);
    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();
    expect(find.text('LaMP-এ স্বাগতম'), findsOneWidget);
  });

  testWidgets('back from the code step returns to the number', (tester) async {
    await pumpLamp(tester, session: fakeSession(FakeAuthService()));
    await toPhoneStep(tester);
    await sendCode(tester, '01912345678');
    await tester.tap(find.byKey(const ValueKey('back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('phone-field')), findsOneWidget);
  });
}
