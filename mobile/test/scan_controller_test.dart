import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lamp_shop/core/api/api_client.dart';
import 'package:lamp_shop/core/api/problem.dart';
import 'package:lamp_shop/features/scan/photo_prep.dart';
import 'package:lamp_shop/features/scan/photo_source.dart';
import 'package:lamp_shop/features/scan/scan_controller.dart';
import 'package:lamp_shop/features/scan/scan_models.dart';

/// Scan (plan 5.5): take a photo, see it, send it, check what was read,
/// confirm. A slow network can't make a double scan, and nothing is saved
/// until every doubtful field is confirmed.
void main() {
  final capture = File('test/fixtures/capture_invoice.json').readAsStringSync();
  late List<http.Request> sent;
  late http.Response Function(http.Request) reply;
  late List<Uint8List> shrunk;

  http.Response ok(String body) =>
      http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});

  ScanController controller({Uint8List Function(Uint8List)? shrink}) => ScanController(
        ApiClient(
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
        ),
        'green-life',
        shrink: (bytes) async {
          shrunk.add(bytes);
          return (shrink ?? (b) => Uint8List.fromList([0xFF, 0xD8, ...b]))(bytes);
        },
      );

  final photo = PickedFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'IMG_0042.jpg', mime: 'image/jpeg');
  final pdf = PickedFile(bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]), name: 'bill.pdf', mime: 'application/pdf');

  setUp(() {
    sent = [];
    shrunk = [];
    reply = (_) => ok(capture);
  });

  test('a photo is shrunk, shown, then sent as the bill it is', () async {
    final scan = controller();
    await scan.take(() async => photo);
    expect(scan.stage, ScanStage.preview);
    expect(shrunk.single, photo.bytes);
    expect(scan.file!.bytes, [0xFF, 0xD8, 1, 2, 3]);
    expect(sent, isEmpty, reason: 'nothing goes until the owner sends it');

    await scan.send();
    final req = sent.single;
    expect(req.url.path, '/api/v1/pharmacies/green-life/captures');
    final body = latin1.decode(req.bodyBytes);
    expect(body, contains('name="kind"\r\n\r\ninvoice'));
    expect(body, contains('filename="bill.jpg"'));
    expect(body, contains('content-type: image/jpeg'));
    expect(scan.stage, ScanStage.review);
    expect(scan.review!.captureId, 'cap-demo');
  });

  test('a sales-book page is sent as one', () async {
    final scan = controller()..kind = ScanKind.salesPage;
    await scan.take(() async => photo);
    await scan.send();
    expect(latin1.decode(sent.single.bodyBytes), contains('name="kind"\r\n\r\nsales_page'));
  });

  test('cancelling the camera leaves the screen as it was', () async {
    final scan = controller();
    await scan.take(() async => null);
    expect(scan.stage, ScanStage.pick);
    expect(scan.problem, isNull);
  });

  test('taking it again asks the same place for a new one', () async {
    final scan = controller();
    var asked = 0;
    await scan.take(() async {
      asked++;
      return photo;
    });
    await scan.retake();
    expect(asked, 2);
    expect(scan.stage, ScanStage.preview);
  });

  test('a PDF goes as it is, without shrinking', () async {
    final scan = controller();
    await scan.take(() async => pdf);
    await scan.send();
    expect(shrunk, isEmpty);
    final body = latin1.decode(sent.single.bodyBytes);
    expect(body, contains('filename="bill.pdf"'));
    expect(body, contains('content-type: application/pdf'));
  });

  test('a file over 8 MB is stopped on the phone', () async {
    final scan = controller();
    final big = PickedFile(bytes: Uint8List(8 * 1024 * 1024 + 1), name: 'big.pdf', mime: 'application/pdf');
    await scan.take(() async => big);
    expect(scan.stage, ScanStage.pick);
    expect(scan.problem!.code, 'too_large');
  });

  test('a picture the phone cannot read says so', () async {
    final scan = controller(shrink: (_) => throw const PhotoUnreadable());
    await scan.take(() async => photo);
    expect(scan.stage, ScanStage.pick);
    expect(scan.problem!.code, 'photo_unreadable');
  });

  test('a failed send keeps the photo, and sending again reuses its key', () async {
    var down = true;
    reply = (_) => down ? throw http.ClientException('no network') : ok(capture);
    final scan = controller();
    await scan.take(() async => photo);
    await scan.send();
    expect(scan.stage, ScanStage.preview);
    expect(scan.problem!.code, ApiProblem.offline);
    expect(scan.file, isNotNull);

    down = false;
    await scan.send();
    expect(scan.stage, ScanStage.review);
    expect(sent, hasLength(2));
    expect(sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key']);
    expect(sent[0].headers['Idempotency-Key'], isNotEmpty);
  });

  test('a new photo gets a new key', () async {
    final scan = controller();
    await scan.take(() async => photo);
    await scan.send();
    scan.startOver();
    expect(scan.stage, ScanStage.pick);
    await scan.take(() async => photo);
    await scan.send();
    expect(sent[1].headers['Idempotency-Key'], isNot(sent[0].headers['Idempotency-Key']));
  });

  test('the month\'s scan limit stops the send and keeps its reset day', () async {
    reply = (_) => http.Response(
        jsonEncode({'detail': 'limit', 'code': 'scan_limit_reached', 'resets_on': '2026-12-01'}), 402,
        headers: {'content-type': 'application/json'});
    final scan = controller();
    await scan.take(() async => photo);
    await scan.send();
    expect(scan.problem!.code, 'scan_limit_reached');
    expect(scan.problem!.resetsOn, DateTime(2026, 12, 1));
  });

  group('saving', () {
    Future<ScanController> reviewing() async {
      final scan = controller();
      await scan.take(() async => photo);
      await scan.send();
      sent.clear();
      return scan;
    }

    test('is refused while a doubtful field is unconfirmed', () async {
      final scan = await reviewing();
      expect(await scan.save(), isFalse);
      expect(sent, isEmpty);
    });

    test('sends what the owner checked, once, then is done', () async {
      final scan = await reviewing();
      final r = scan.review!;
      scan.edit('invoice.lines[2].unit_cost', '300');
      for (final f in r.waiting) {
        scan.confirm(f.path);
      }
      for (final c in r.failedChecks) {
        scan.acknowledge(c);
      }
      reply = (_) => ok(capture.replaceFirst('"needs_review"', '"confirmed"'));
      expect(await scan.save(), isTrue);
      final req = sent.single;
      expect(req.url.path, '/api/v1/pharmacies/green-life/captures/cap-demo/confirm');
      expect(req.headers['Idempotency-Key'], isNotEmpty);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(((body['invoice'] as Map)['lines'] as List)[2]['unit_cost'], 300);
      expect(scan.stage, ScanStage.done);
    });

    test('a failed save stays on the review, and saving again reuses its key', () async {
      final scan = await reviewing();
      for (final f in scan.review!.waiting) {
        scan.confirm(f.path);
      }
      for (final c in scan.review!.failedChecks) {
        scan.acknowledge(c);
      }
      reply = (_) => throw http.ClientException('no network');
      expect(await scan.save(), isFalse);
      expect(scan.stage, ScanStage.review);
      expect(scan.problem!.code, ApiProblem.offline);
      reply = (_) => ok(capture);
      expect(await scan.save(), isTrue);
      expect(sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key']);
    });
  });

  group('scans left this month', () {
    test('a free shop sees how many are left', () async {
      reply = (_) => ok(jsonEncode({
            'plan': 'free', 'scans_used': 7, 'scans_limit': 10,
            'ai_used_bdt': 0.4, 'ai_budget_bdt': 1.2, 'resets_on': '2026-12-01',
          }));
      final scan = controller();
      await scan.loadUsage();
      expect(sent.single.url.path, '/api/v1/pharmacies/green-life/usage');
      expect(scan.scansLeft, 3);
      expect(scan.resetsOn, DateTime(2026, 12, 1));
    });

    test('Plus has no count to show', () async {
      reply = (_) => ok(jsonEncode({
            'plan': 'plus', 'scans_used': 40, 'scans_limit': null,
            'ai_used_bdt': 2, 'ai_budget_bdt': 12, 'resets_on': '2026-12-01',
          }));
      final scan = controller();
      await scan.loadUsage();
      expect(scan.scansLeft, isNull);
    });

    test('when it can\'t be read, the screen carries on without it', () async {
      reply = (_) => http.Response('{"detail":"down"}', 503, headers: {'content-type': 'application/json'});
      final scan = controller();
      await scan.loadUsage();
      expect(scan.scansLeft, isNull);
      expect(scan.problem, isNull);
    });
  });
}
