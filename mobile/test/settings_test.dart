import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';
import 'package:lamp_shop/features/settings/settings_controller.dart';

/// Settings (plan 13.3, Y4.1): signed-in phones, the owner's data out, and
/// the account deleted with a 7-day undo.
void main() {
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;

  http.Response json(Object? body, [int status = 200]) =>
      http.Response(body == null ? '' : jsonEncode(body), status, headers: {'content-type': 'application/json'});

  ApiClient api() => ApiClient(
    baseUrl: 'https://api.test/api/v1',
    appVersion: '0.1.0+1',
    language: () => 'en',
    accessToken: () => 'tok',
    refresh: () async => false,
    http: MockClient((req) async {
      sent.add(req);
      return reply(req);
    }),
    backoff: (_) => Duration.zero,
  );

  setUp(() => sent = []);

  test('the signed-in phones and browsers, this one marked', () async {
    reply = (_) => json([
      {
        'id': 'd-1',
        'name': 'Android phone',
        'os': 'android',
        'last_used_at': '2026-11-27T04:00:00Z',
        'this_device': true,
      },
      {'id': 'd-2', 'name': 'Web browser', 'os': 'web', 'last_used_at': '2026-11-20T09:30:00Z', 'this_device': false},
    ]);
    final d = DevicesController(api(), MemoryCacheStore());
    await d.load();
    expect(sent.single.url.path, '/api/v1/auth/devices');
    expect(d.devices!.map((x) => x.name), ['Android phone', 'Web browser']);
    expect(d.devices!.first.thisDevice, isTrue);
    expect(d.devices!.last.lastUsedAt, DateTime.utc(2026, 11, 20, 9, 30));
  });

  test('terms and privacy, with their links', () async {
    reply = (_) => json({
      'terms_version': 't-2026-11',
      'privacy_version': 'p-2026-11',
      'terms_url': 'https://lamp.example/terms',
      'privacy_url': 'https://lamp.example/privacy',
    });
    final l = LegalController(api(), MemoryCacheStore());
    await l.load();
    expect(sent.single.url.path, '/api/v1/legal/current');
    expect(l.legal!.termsUrl, 'https://lamp.example/terms');
  });

  test('the language, for the SMS the server sends', () async {
    reply = (_) => json({});
    await SettingsActions(api()).setLanguage('bn');
    expect(sent.single.method, 'PATCH');
    expect(sent.single.url.path, '/api/v1/me');
    expect(jsonDecode(sent.single.body), {'language': 'bn'});
  });

  test('another phone signed out', () async {
    reply = (_) => json(null, 204);
    await SettingsActions(api()).signOutDevice('d-2');
    expect(sent.single.method, 'DELETE');
    expect(sent.single.url.path, '/api/v1/auth/devices/d-2');
  });

  test('delete: the server\'s own check word, and the day it is erased', () async {
    reply = (_) => json({'erase_on': '2026-12-04'}, 202);
    final eraseOn = await SettingsActions(api()).deleteAccount();
    expect(sent.single.url.path, '/api/v1/me/delete');
    expect(jsonDecode(sent.single.body), {'confirm': 'DELETE'});
    expect(eraseOn, DateTime(2026, 12, 4));
  });

  group('export', () {
    ExportController export({int maxPolls = 40}) =>
        ExportController(api(), pollEvery: Duration.zero, maxPolls: maxPolls);

    test('started, then checked until ready, with its link', () async {
      var polls = 0;
      reply = (req) {
        if (req.method == 'POST') return json({'export_id': 'ex-1'}, 202);
        polls++;
        return json(
          polls < 3 ? {'status': 'building'} : {'status': 'ready', 'download_url': 'https://lamp.example/dl/ex-1'},
        );
      };
      final e = export();
      await e.start();
      expect(sent.first.url.path, '/api/v1/me/export');
      expect(sent.skip(1).every((r) => r.url.path == '/api/v1/me/export/ex-1'), isTrue);
      expect(e.stage, ExportStage.ready);
      expect(e.url, 'https://lamp.example/dl/ex-1');
    });

    test('failed on the server', () async {
      reply = (req) => req.method == 'POST' ? json({'export_id': 'ex-1'}, 202) : json({'status': 'failed'});
      final e = export();
      await e.start();
      expect(e.stage, ExportStage.failed);
    });

    test('still building after the checks: say so, check again', () async {
      var ready = false;
      reply = (req) {
        if (req.method == 'POST') return json({'export_id': 'ex-1'}, 202);
        return json(ready ? {'status': 'ready', 'download_url': 'https://x/y'} : {'status': 'building'});
      };
      final e = export(maxPolls: 3);
      await e.start();
      expect(e.stage, ExportStage.waiting);
      ready = true;
      await e.checkAgain();
      expect(e.stage, ExportStage.ready);
      expect(sent.where((r) => r.method == 'POST'), hasLength(1));
    });

    test('offline: plain words, and Export again', () async {
      reply = (_) => throw http.ClientException('no network');
      final e = export();
      await e.start();
      expect(e.stage, ExportStage.failed);
      expect(e.problem!.code, 'offline');
    });
  });
}
