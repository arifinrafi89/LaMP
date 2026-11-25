import '../api/problem.dart';
import 'auth_service.dart';
import 'phone_number.dart';

/// An [AuthService] with no server, for tests and offline development.
/// The code is always [code]. Mirrors the server's rules closely enough that
/// a screen tested against it behaves the same against the real one.
class FakeAuthService implements AuthService {
  FakeAuthService({this.pharmacy});

  static const code = '123456';

  /// The shop a returning owner already has; null for a new owner.
  PharmacyInfo? pharmacy;

  /// When true every call fails as if there were no network.
  bool offline = false;

  int codeRequests = 0;
  int refreshCalls = 0;
  int termsAccepted = 0;
  int signOuts = 0;

  int _n = 0;
  final _liveRefresh = <String>{};

  void _checkOnline() {
    if (offline) throw const ApiProblem(ApiProblem.offline);
  }

  /// Ends every session, as a sign-out from another device would.
  void revokeAll() => _liveRefresh.clear();

  TokenPair _newPair() {
    _n++;
    final pair = TokenPair(accessToken: 'fake-access-$_n', refreshToken: 'fake-refresh-$_n');
    _liveRefresh.add(pair.refreshToken!);
    return pair;
  }

  @override
  Future<OtpChallenge> requestCode(String e164, String language) async {
    _checkOnline();
    codeRequests++;
    if (checkBanglalink(e164).result != PhoneResult.ok) {
      throw const ApiProblem('not_banglalink', status: 422);
    }
    return OtpChallenge(
      challengeId: 'fake-challenge-$codeRequests',
      phone: e164,
      expiresIn: const Duration(minutes: 5),
      resendAfter: const Duration(seconds: 30),
    );
  }

  @override
  Future<SignedIn> verifyCode(OtpChallenge challenge, String code, DeviceInfo device) async {
    _checkOnline();
    if (code != FakeAuthService.code) {
      throw const ApiProblem('otp_wrong', status: 422);
    }
    final p = challenge.phone;
    return SignedIn(
      tokens: _newPair(),
      owner: OwnerInfo(
        id: 'owner-${p.substring(p.length - 4)}',
        phoneMasked: '+880 ${p.substring(4, 6)}•• ••${p.substring(p.length - 4)}',
        language: 'bn',
      ),
      pharmacy: pharmacy,
      isNew: pharmacy == null,
    );
  }

  @override
  Future<TokenPair?> refresh(String? refreshToken) async {
    _checkOnline();
    refreshCalls++;
    if (refreshToken == null || !_liveRefresh.remove(refreshToken)) return null;
    return _newPair();
  }

  @override
  Future<void> acceptTerms() async {
    _checkOnline();
    termsAccepted++;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _liveRefresh.clear();
  }
}
