import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/api/problem.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';

/// A phone or browser signed in to this owner (`GET /auth/devices`).
class Device {
  const Device(this.id, this.name, this.os, this.lastUsedAt, this.thisDevice);

  final String id;
  final String name;
  final String os;
  final DateTime? lastUsedAt;
  final bool thisDevice;

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    j['id'] as String,
    j['name'] as String,
    (j['os'] as String?) ?? '',
    DateTime.tryParse((j['last_used_at'] as String?) ?? ''),
    j['this_device'] == true,
  );
}

class DevicesController extends CachedRead<List<Device>> {
  DevicesController(ApiClient api, CacheStore cache, {super.refreshOn})
    : super.list(api, cache, '/auth/devices', (j) => [for (final d in j) Device.fromJson(d as Map<String, dynamic>)]);

  List<Device>? get devices => data;
}

/// The current terms and privacy notice (`GET /legal/current`).
class LegalInfo {
  const LegalInfo(this.termsUrl, this.privacyUrl);

  final String termsUrl;
  final String privacyUrl;

  factory LegalInfo.fromJson(Map<String, dynamic> j) => LegalInfo(j['terms_url'] as String, j['privacy_url'] as String);
}

class LegalController extends CachedRead<LegalInfo> {
  LegalController(ApiClient api, CacheStore cache) : super(api, cache, '/legal/current', LegalInfo.fromJson);

  LegalInfo? get legal => data;
}

class SettingsActions {
  SettingsActions(this._api);

  final ApiClient _api;

  /// The language the server writes the owner's SMS in.
  Future<void> setLanguage(String code) => _api.patch('/me', {'language': code});

  Future<void> signOutDevice(String id) => _api.delete('/auth/devices/$id');

  /// The server ends every session at once and erases the data after a
  /// 7-day undo window (plan 13.3). Returns the day it is erased.
  Future<DateTime> deleteAccount() async {
    final j = await _api.post('/me/delete', {'confirm': 'DELETE'});
    return DateTime.parse((j as Map<String, dynamic>)['erase_on'] as String);
  }
}

enum ExportStage { idle, building, ready, waiting, failed }

/// The owner's data as a zip of CSV and PDF (`POST /me/export`, then its
/// status). Family phone numbers are left out by the server.
class ExportController extends ChangeNotifier {
  ExportController(this._api, {this.pollEvery = const Duration(seconds: 3), this.maxPolls = 40});

  final ApiClient _api;
  final Duration pollEvery;
  final int maxPolls;

  ExportStage _stage = ExportStage.idle;
  ExportStage get stage => _stage;

  String? _id;
  String? _url;

  /// Open for 10 minutes once ready.
  String? get url => _url;

  ApiProblem? _problem;
  ApiProblem? get problem => _problem;

  bool _disposed = false;

  void _set(ExportStage s) {
    _stage = s;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    _problem = null;
    _url = null;
    _set(ExportStage.building);
    try {
      final j = await _api.post('/me/export', null, idempotent: true);
      _id = (j as Map<String, dynamic>)['export_id'] as String;
      await _poll();
    } on ApiProblem catch (p) {
      _problem = p;
      _set(ExportStage.failed);
    }
  }

  Future<void> checkAgain() async {
    if (_id == null) return start();
    _problem = null;
    _set(ExportStage.building);
    await _poll();
  }

  Future<void> _poll() async {
    for (var i = 0; i < maxPolls; i++) {
      if (_disposed) return;
      try {
        final j = await _api.get('/me/export/$_id') as Map<String, dynamic>;
        switch (j['status']) {
          case 'ready':
            _url = j['download_url'] as String?;
            return _set(_url == null ? ExportStage.failed : ExportStage.ready);
          case 'failed':
            return _set(ExportStage.failed);
        }
      } on ApiProblem catch (p) {
        _problem = p;
      }
      await Future<void>.delayed(pollEvery);
    }
    _set(ExportStage.waiting);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
