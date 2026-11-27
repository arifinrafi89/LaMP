import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

/// What survives a restart: the refresh token (Android only; on web it is an
/// httpOnly cookie no script can read) and who is signed in, so the app opens
/// on the right screen even offline. The access token is never stored.
class StoredSession {
  const StoredSession({this.refreshToken, required this.owner, this.pharmacy});

  final String? refreshToken;
  final OwnerInfo owner;
  final PharmacyInfo? pharmacy;

  StoredSession copyWith({String? refreshToken, PharmacyInfo? pharmacy}) => StoredSession(
        refreshToken: refreshToken ?? this.refreshToken,
        owner: owner,
        pharmacy: pharmacy ?? this.pharmacy,
      );

  Map<String, Object?> toJson() => {
        'refresh_token': refreshToken,
        'owner': owner.toJson(),
        'pharmacy': pharmacy?.toJson(),
      };

  factory StoredSession.fromJson(Map<String, dynamic> j) => StoredSession(
        refreshToken: j['refresh_token'] as String?,
        owner: OwnerInfo.fromJson(j['owner'] as Map<String, dynamic>),
        pharmacy: j['pharmacy'] == null
            ? null
            : PharmacyInfo.fromJson(j['pharmacy'] as Map<String, dynamic>),
      );
}

abstract class TokenStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// For tests: nothing survives a restart.
class MemoryTokenStore implements TokenStore {
  StoredSession? _s;

  @override
  Future<StoredSession?> read() async => _s;

  @override
  Future<void> write(StoredSession session) async => _s = session;

  @override
  Future<void> clear() async => _s = null;
}

/// Android Keystore-backed storage (plan 5.3).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'lamp.session';

  @override
  Future<StoredSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // A corrupt or unreadable entry is a signed-out phone, not a crash.
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
