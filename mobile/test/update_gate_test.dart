import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/state/app_config.dart';

/// Plan 13.5: below the minimum, a full-screen "Update LaMP"; below the
/// latest, a banner; maintenance, a plain screen. Versions are `1.2.3+45`.
void main() {
  group('versions', () {
    test('compared part by part, as numbers', () {
      expect(compareVersions('0.1.0+1', '0.1.0'), 0);
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('1.2.3+45', '1.2.3+46'), lessThan(0), reason: 'the build counts when both have one');
      expect(compareVersions('1.2.3', '1.2'), greaterThan(0));
    });

    test('a version that isn\'t one never locks the owner out', () {
      expect(compareVersions('0.1.0', 'soon'), 0);
    });
  });

  group('the gate', () {
    late http.Response Function(http.Request) reply;
    late List<http.Request> sent;

    AppConfigController gate(String version) => AppConfigController(
      ApiClient(
        baseUrl: 'https://api.test/api/v1',
        appVersion: version,
        language: () => 'en',
        accessToken: () => '',
        refresh: () async => false,
        http: MockClient((req) async {
          sent.add(req);
          return reply(req);
        }),
        backoff: (_) => Duration.zero,
      ),
      appVersion: version,
    );

    http.Response config({String min = '0.1.0', String latest = '0.1.0', bool maintenance = false}) => http.Response(
      jsonEncode({
        'min_version': min,
        'latest_version': latest,
        'play_url': 'https://play.google.com/store/apps/details?id=bd.lamp.shop',
        'maintenance': maintenance,
        'flags': {},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

    setUp(() => sent = []);

    test('up to date: open', () async {
      reply = (_) => config();
      final g = gate('0.1.0+1');
      await g.load();
      expect(sent.single.url.path, '/api/v1/app/config');
      expect(g.state, UpdateState.ok);
    });

    test('below the latest: a banner', () async {
      reply = (_) => config(latest: '0.2.0');
      final g = gate('0.1.0+1');
      await g.load();
      expect(g.state, UpdateState.available);
      g.later();
      expect(g.state, UpdateState.ok, reason: 'dismissed for this session');
    });

    test('below the minimum: must update, with the Play link', () async {
      reply = (_) => config(min: '0.2.0', latest: '0.2.0');
      final g = gate('0.1.0+1');
      await g.load();
      expect(g.state, UpdateState.required);
      expect(g.playUrl, startsWith('https://play.google.com/'));
      g.later();
      expect(g.state, UpdateState.required, reason: 'not dismissible');
    });

    test('maintenance', () async {
      reply = (_) => config(maintenance: true);
      final g = gate('0.1.0+1');
      await g.load();
      expect(g.state, UpdateState.maintenance);
    });

    test('the config can\'t be read: the app opens as usual', () async {
      reply = (_) => throw http.ClientException('no network');
      final g = gate('0.1.0+1');
      await g.load();
      expect(g.state, UpdateState.ok);
    });

    test('any answer of 426 from the server: must update', () {
      final g = gate('0.1.0+1');
      g.serverSaysUpdate();
      expect(g.state, UpdateState.required);
    });
  });
}
