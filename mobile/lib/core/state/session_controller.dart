import 'package:material_ui/material_ui.dart';

import '../api/problem.dart';
import '../auth/auth_service.dart';
import '../auth/token_store.dart';

enum SessionStatus { restoring, signedOut, signedIn }

/// Who is signed in on this phone (adapted from lamp-flutter's
/// `auth_controller.dart`; no Google, no Firestore).
///
/// - The Applink code is asked for once per device (D2). After that the
///   refresh token keeps the owner signed in for 30 days of use, and a
///   returning owner makes no Applink call.
/// - The access token lives only in memory.
/// - Being offline never signs anyone out; only the server refusing the
///   refresh token does.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService auth,
    required TokenStore store,
    required Future<DeviceInfo> Function() device,
    required bool cookieRefresh,
  })  : _auth = auth,
        _store = store,
        _device = device,
        _cookieRefresh = cookieRefresh;

  final AuthService _auth;
  final TokenStore _store;
  final Future<DeviceInfo> Function() _device;

  /// Web: the refresh token is an httpOnly cookie, so launch always tries it.
  final bool _cookieRefresh;

  SessionStatus _status = SessionStatus.restoring;
  SessionStatus get status => _status;

  String _access = '';
  String get accessToken => _access;

  StoredSession? _session;
  OwnerInfo? get owner => _session?.owner;
  PharmacyInfo? get pharmacy => _session?.pharmacy;

  Future<bool>? _refreshing;

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }

  /// Called once at launch.
  Future<void> restore() async {
    final saved = await _store.read();
    if (saved == null && !_cookieRefresh) return _set(SessionStatus.signedOut);
    if (saved == null) {
      // Web with no profile stored: the cookie alone can't say who this is.
      // Ask anyway, so a stale cookie is cleared, then sign in again.
      try {
        await _auth.refresh(null);
      } on ApiProblem {
        // Offline or refused: either way, the welcome screen.
      }
      return _set(SessionStatus.signedOut);
    }
    _session = saved;
    try {
      final ok = await _rotate();
      _set(ok ? SessionStatus.signedIn : SessionStatus.signedOut);
    } on ApiProblem {
      // Offline, or the server in trouble (a free Render service waking up
      // answers 502/503). Only a refused refresh token ends a session, so
      // open with what was stored; the first request refreshes again.
      _set(SessionStatus.signedIn);
    }
  }

  Future<OtpChallenge> requestCode(String e164, String language) =>
      _auth.requestCode(e164, language);

  Future<void> verifyCode(OtpChallenge challenge, String code, {required bool agreedToTerms}) async {
    final r = await _auth.verifyCode(challenge, code, await _device());
    _access = r.tokens.accessToken;
    _session = StoredSession(
      refreshToken: r.tokens.refreshToken,
      owner: r.owner,
      pharmacy: r.pharmacy,
    );
    await _store.write(_session!);
    if (agreedToTerms) {
      try {
        await _auth.acceptTerms();
      } on ApiProblem {
        // /me lists consents_needed, so a missed record is asked for again.
      }
    }
    _set(SessionStatus.signedIn);
  }

  /// For [ApiClient]'s 401 handling: one refresh however many requests ask.
  ///
  /// False only when the server refused the refresh token (signed out).
  /// A refresh that could not be made at all (offline, server error) throws
  /// its [ApiProblem], so the screen says what really happened.
  Future<bool> refreshNow() => _refreshing ??= _refreshOnce();

  Future<bool> _refreshOnce() async {
    try {
      final ok = await _rotate();
      if (!ok) _set(SessionStatus.signedOut);
      return ok;
    } finally {
      _refreshing = null;
    }
  }

  /// Swaps the refresh token for a new pair. False when the session is over,
  /// in which case everything stored is forgotten.
  Future<bool> _rotate() async {
    final pair = await _auth.refresh(_session?.refreshToken);
    if (pair == null) {
      await _forget();
      return false;
    }
    _access = pair.accessToken;
    _session = _session!.copyWith(refreshToken: pair.refreshToken);
    await _store.write(_session!);
    return true;
  }

  void updatePharmacy(PharmacyInfo pharmacy) {
    final s = _session;
    if (s == null) return;
    _session = s.copyWith(pharmacy: pharmacy);
    _store.write(_session!);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _forget();
    _set(SessionStatus.signedOut);
  }

  Future<void> _forget() async {
    _access = '';
    _session = null;
    await _store.clear();
  }
}
