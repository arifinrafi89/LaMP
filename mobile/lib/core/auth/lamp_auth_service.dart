import '../api/api_client.dart';
import '../api/problem.dart';
import 'auth_service.dart';

/// [AuthService] on the LaMP server's `/auth/*` routes (plan 2.2).
///
/// Give it an [ApiClient] whose `refresh` returns false: the refresh call
/// itself must never trigger another refresh.
class LampAuthService implements AuthService {
  LampAuthService(this._api);

  final ApiClient _api;

  Map<String, dynamic> _map(Object? o) => o as Map<String, dynamic>;

  @override
  Future<OtpChallenge> requestCode(String e164, String language) async {
    final j = _map(await _api.post('/auth/otp/request', {'phone': e164, 'language': language}));
    return OtpChallenge(
      challengeId: j['challenge_id'] as String,
      phone: e164,
      expiresIn: Duration(seconds: (j['expires_in'] as num? ?? 300).round()),
      resendAfter: Duration(seconds: (j['resend_after'] as num? ?? 30).round()),
    );
  }

  @override
  Future<SignedIn> verifyCode(OtpChallenge challenge, String code, DeviceInfo device) async {
    final j = await _api.post('/auth/otp/verify', {
      'challenge_id': challenge.challengeId,
      'code': code,
      'device': device.toJson(),
    });
    return SignedIn.fromJson(_map(j));
  }

  @override
  Future<TokenPair?> refresh(String? refreshToken) async {
    try {
      final j = await _api.post(
          '/auth/refresh', {'refresh_token': ?refreshToken});
      return TokenPair.fromJson(_map(j));
    } on ApiProblem catch (p) {
      if (p.code == 'session_expired' || p.status == 401) return null;
      rethrow;
    }
  }

  @override
  Future<void> acceptTerms() async {
    final legal = _map(await _api.get('/legal/current'));
    await _api.post('/me/consents', {
      'terms_version': legal['terms_version'],
      'privacy_version': legal['privacy_version'],
    });
  }

  @override
  Future<void> signOut() async {
    try {
      await _api.post('/auth/sign-out', null);
    } on ApiProblem {
      // Signing out locally is what matters; the server session expires anyway.
    }
  }
}
