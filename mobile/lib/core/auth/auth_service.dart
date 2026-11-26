/// Everything sign-in needs from a backend (adapted from lamp-flutter: the
/// interface is kept, Google and Firestore are gone).
///
/// D2: a Banglalink number and an Applink code once per device, then LaMP's
/// own session: a 15-minute access token and a 30-day rotating refresh token.
/// [LampAuthService] talks to the server; [FakeAuthService] stands in for
/// tests, where the code is always 123456.
library;

class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.phone,
    required this.expiresIn,
    required this.resendAfter,
  });

  final String challengeId;

  /// `+8801912345678`, kept only to show "We sent a code to …".
  final String phone;
  final Duration expiresIn;
  final Duration resendAfter;
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.os,
    required this.appVersion,
  });

  final String id;
  final String name;
  final String os;
  final String appVersion;

  Map<String, String> toJson() =>
      {'id': id, 'name': name, 'os': os, 'app_version': appVersion};
}

class TokenPair {
  const TokenPair({required this.accessToken, this.refreshToken});

  final String accessToken;

  /// Null on web, where the refresh token is an httpOnly cookie.
  final String? refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String?,
      );
}

class OwnerInfo {
  const OwnerInfo({required this.id, required this.phoneMasked, required this.language});

  final String id;
  final String phoneMasked;
  final String language;

  factory OwnerInfo.fromJson(Map<String, dynamic> j) => OwnerInfo(
        id: j['id'] as String,
        phoneMasked: j['phone_masked'] as String,
        language: j['language'] as String? ?? 'bn',
      );
}

class PharmacyInfo {
  const PharmacyInfo({required this.id, required this.name, required this.setupComplete});

  final String id;
  final String name;
  final bool setupComplete;

  PharmacyInfo copyWith({String? name, bool? setupComplete}) => PharmacyInfo(
        id: id,
        name: name ?? this.name,
        setupComplete: setupComplete ?? this.setupComplete,
      );

  factory PharmacyInfo.fromJson(Map<String, dynamic> j) => PharmacyInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        setupComplete: j['setup_complete'] as bool? ?? false,
      );
}

class SignedIn {
  const SignedIn({
    required this.tokens,
    required this.owner,
    required this.pharmacy,
    required this.isNew,
  });

  final TokenPair tokens;
  final OwnerInfo owner;

  /// Null until the owner names their shop (Setup, plan 5.2).
  final PharmacyInfo? pharmacy;
  final bool isNew;

  factory SignedIn.fromJson(Map<String, dynamic> j) => SignedIn(
        tokens: TokenPair.fromJson(j),
        owner: OwnerInfo.fromJson(j['owner'] as Map<String, dynamic>),
        pharmacy: j['pharmacy'] == null
            ? null
            : PharmacyInfo.fromJson(j['pharmacy'] as Map<String, dynamic>),
        isNew: j['is_new'] as bool? ?? false,
      );
}

/// Failures arrive as `ApiProblem` with the server's code (`otp_wrong`,
/// `otp_expired`, `not_banglalink`, `rate_limited`, …).
abstract class AuthService {
  Future<OtpChallenge> requestCode(String e164, String language);

  Future<SignedIn> verifyCode(OtpChallenge challenge, String code, DeviceInfo device);

  /// A new pair, or null when the server says the session is over. Being
  /// offline throws instead: that is not a reason to sign anyone out.
  Future<TokenPair?> refresh(String? refreshToken);

  /// Records that the owner agreed to the current terms and privacy policy.
  Future<void> acceptTerms();

  Future<void> signOut();
}
