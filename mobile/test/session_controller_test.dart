import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/api/problem.dart';
import 'package:lamp_shop/core/auth/auth_service.dart';
import 'package:lamp_shop/core/auth/fake_auth_service.dart';
import 'package:lamp_shop/core/auth/token_store.dart';
import 'package:lamp_shop/core/state/session_controller.dart';

/// D2 and 3.2: OTP once per device, then LaMP's own session. A returning
/// owner makes no Applink call; being offline never signs anyone out.
void main() {
  late FakeAuthService auth;
  late MemoryTokenStore store;

  SessionController session({bool cookieRefresh = false}) => SessionController(
        auth: auth,
        store: store,
        device: () async => const DeviceInfo(
            id: 'd-1', name: 'Android phone', os: 'android', appVersion: '0.1.0+1'),
        cookieRefresh: cookieRefresh,
      );

  Future<SessionController> signedIn() async {
    final s = session();
    await s.restore();
    final c = await s.requestCode('+8801912345678', 'en');
    await s.verifyCode(c, FakeAuthService.code, agreedToTerms: true);
    return s;
  }

  setUp(() {
    auth = FakeAuthService();
    store = MemoryTokenStore();
  });

  test('a first launch with nothing stored is signed out, with no server call', () async {
    final s = session();
    expect(s.status, SessionStatus.restoring);
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
    expect(auth.refreshCalls, 0);
  });

  test('the right code signs in, stores the session and records the terms', () async {
    final s = await signedIn();
    expect(s.status, SessionStatus.signedIn);
    expect(s.accessToken, isNotEmpty);
    expect(s.owner!.id, isNotEmpty);
    expect(s.pharmacy, isNull);
    expect(auth.termsAccepted, 1);
    final saved = await store.read();
    expect(saved!.refreshToken, isNotNull);
    expect(saved.owner.id, s.owner!.id);
  });

  test('the wrong code is an otp_wrong problem and leaves the owner signed out', () async {
    final s = session();
    await s.restore();
    final c = await s.requestCode('+8801912345678', 'en');
    await expectLater(s.verifyCode(c, '000000', agreedToTerms: true),
        throwsA(isA<ApiProblem>().having((p) => p.code, 'code', 'otp_wrong')));
    expect(s.status, SessionStatus.signedOut);
  });

  test('a returning owner is signed in from the stored session, without a code', () async {
    await signedIn();
    final codesBefore = auth.codeRequests;
    final again = session();
    await again.restore();
    expect(again.status, SessionStatus.signedIn);
    expect(again.accessToken, isNotEmpty);
    expect(auth.codeRequests, codesBefore);
    expect(auth.refreshCalls, 1);
  });

  test('the refresh token rotates on every use', () async {
    await signedIn();
    final first = (await store.read())!.refreshToken;
    final again = session();
    await again.restore();
    expect((await store.read())!.refreshToken, isNot(first));
  });

  test('a refused refresh signs out and forgets the session', () async {
    await signedIn();
    auth.revokeAll();
    final again = session();
    await again.restore();
    expect(again.status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
  });

  test('offline at launch keeps the owner signed in with what was stored', () async {
    final s = await signedIn();
    final ownerId = s.owner!.id;
    auth.offline = true;
    final again = session();
    await again.restore();
    expect(again.status, SessionStatus.signedIn);
    expect(again.owner!.id, ownerId);
    expect(await store.read(), isNotNull);
  });

  test('refreshNow gets a new access token, once, however many ask at once', () async {
    final s = await signedIn();
    final before = s.accessToken;
    final calls = auth.refreshCalls;
    final results = await Future.wait([s.refreshNow(), s.refreshNow(), s.refreshNow()]);
    expect(results, everyElement(isTrue));
    expect(auth.refreshCalls, calls + 1);
    expect(s.accessToken, isNot(before));
  });

  test('on web the cookie is the refresh token, so launch always tries it', () async {
    final s = session(cookieRefresh: true);
    await s.restore();
    expect(auth.refreshCalls, 1);
    expect(s.status, SessionStatus.signedOut);
  });

  test('signing out ends the session here and on the server', () async {
    final s = await signedIn();
    await s.signOut();
    expect(s.status, SessionStatus.signedOut);
    expect(s.accessToken, isEmpty);
    expect(await store.read(), isNull);
    expect(auth.signOuts, 1);
  });

  test('a shop that finished setup is remembered', () async {
    final s = await signedIn();
    s.updatePharmacy(const PharmacyInfo(id: 'p-1', name: 'Green Life', setupComplete: true));
    expect(s.pharmacy!.setupComplete, isTrue);
    expect((await store.read())!.pharmacy!.name, 'Green Life');
  });
}
