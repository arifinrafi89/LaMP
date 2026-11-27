import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

/// One kept read: the server's JSON and when it arrived.
class CachedJson {
  const CachedJson(this.json, this.savedAt);

  final Object? json;
  final DateTime savedAt;
}

/// The last good answer to each read, so the app opens with the last data
/// when offline (plan 5.6, Phase 1). Keys are API paths, which carry the
/// shop's id, so each shop's data is kept apart. Cleared on sign-out.
abstract class CacheStore {
  Future<CachedJson?> read(String key);
  Future<void> write(String key, Object? json, {DateTime? at});
  Future<void> clear();
}

/// For tests, and for when the phone's storage can't be opened.
class MemoryCacheStore implements CacheStore {
  final Map<String, CachedJson> _items = {};

  @override
  Future<CachedJson?> read(String key) async => _items[key];

  @override
  Future<void> write(String key, Object? json, {DateTime? at}) async =>
      _items[key] = CachedJson(json, at ?? DateTime.now().toUtc());

  @override
  Future<void> clear() async => _items.clear();
}

/// The cache on the phone: a `hive_ce` box encrypted with AES-256, its key
/// kept in secure storage (Android Keystore; on web, the browser's).
///
/// The cache is a convenience. If it can't be opened (a private window, a
/// key that no longer matches), the app works without it and never crashes.
class HiveCacheStore implements CacheStore {
  HiveCacheStore({Future<void> Function()? init, Future<List<int>> Function()? key})
      : _init = init ?? _defaultInit,
        _key = key ?? _secureKey;

  static const boxName = 'lamp_cache';
  static const _keyName = 'lamp.cacheKey';

  final Future<void> Function() _init;
  final Future<List<int>> Function() _key;
  Future<Box<String>?>? _box;

  static Future<void> _defaultInit() async {
    // On web hive_ce keeps boxes in IndexedDB and needs no folder.
    if (!kIsWeb) Hive.init((await getApplicationSupportDirectory()).path);
  }

  static Future<List<int>> _secureKey() async {
    const storage = FlutterSecureStorage();
    final saved = await storage.read(key: _keyName);
    if (saved != null) return base64Decode(saved);
    final key = Hive.generateSecureKey();
    await storage.write(key: _keyName, value: base64Encode(key));
    return key;
  }

  Future<Box<String>?> _open() => _box ??= _openBox();

  Future<Box<String>?> _openBox() async {
    try {
      await _init();
      final cipher = HiveAesCipher(await _key());
      try {
        return await Hive.openBox<String>(boxName, encryptionCipher: cipher);
      } on Object {
        // Unreadable (corrupt, or a different key): start it again.
        await Hive.deleteBoxFromDisk(boxName);
        return await Hive.openBox<String>(boxName, encryptionCipher: cipher);
      }
    } on Object catch (e) {
      debugPrint('LaMP cache off: $e');
      return null;
    }
  }

  @override
  Future<CachedJson?> read(String key) async {
    final box = await _open();
    final raw = box?.get(key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return CachedJson(m['j'], DateTime.parse(m['t'] as String));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json, {DateTime? at}) async {
    final box = await _open();
    if (box == null) return;
    final t = (at ?? DateTime.now()).toUtc().toIso8601String();
    try {
      await box.put(key, jsonEncode({'t': t, 'j': json}));
    } on Object catch (e) {
      debugPrint('LaMP cache write failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    final box = await _open();
    await box?.clear();
  }
}
