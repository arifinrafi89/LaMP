import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/features/scan/photo_source.dart';

import '../helpers.dart';

class FakePhotos implements PhotoSource {
  int asked = 0;
  PickedFile? next = PickedFile(
      bytes: img.encodeJpg(img.Image(width: 4, height: 3)), name: 'IMG_1.jpg', mime: 'image/jpeg');

  @override
  Future<PickedFile?> camera() async {
    asked++;
    return next;
  }

  @override
  Future<PickedFile?> gallery() => camera();

  @override
  Future<PickedFile?> pdf() => camera();
}

/// Scan (plan 5.5): take a photo, see it, send it, check every doubtful
/// field, confirm. Free on every plan, 10 a month.
void main() {
  final capture = File('test/fixtures/capture_invoice.json').readAsStringSync();
  final salesPage = File('test/fixtures/capture_sales_page.json').readAsStringSync();
  late List<http.Request> sent;
  late http.Response Function(http.Request) captures;
  late FakePhotos photos;

  http.Response ok(String body) =>
      http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});

  MockClient server() => MockClient((req) async {
        sent.add(req);
        final p = req.url.path;
        if (p.endsWith('/usage')) {
          return ok(jsonEncode({
            'plan': 'free', 'scans_used': 7, 'scans_limit': 10,
            'ai_used_bdt': 0.4, 'ai_budget_bdt': 1.2, 'resets_on': '2026-12-01',
          }));
        }
        if (p.endsWith('/confirm')) return ok(capture.replaceFirst('"needs_review"', '"confirmed"'));
        if (p.endsWith('/captures')) return captures(req);
        if (p.endsWith('/today')) return ok(File('test/fixtures/today.json').readAsStringSync());
        return http.Response('{"detail":"no"}', 404, headers: {'content-type': 'application/json'});
      });

  setUp(() {
    sent = [];
    photos = FakePhotos();
    captures = (_) => ok(capture);
  });

  Future<void> open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester,
        session: await signedInSession(),
        at: '/scan',
        locale: locale,
        http: server(),
        photos: photos,
        shrink: (b) async => b);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> photographAndSend(WidgetTester tester) async {
    await tapKey(tester, 'scan-camera');
    await tapKey(tester, 'scan-send');
  }

  testWidgets('one main action, and the free scans left this month', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('scan-camera')), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('3 free scans left this month'), findsOneWidget);
  });

  testWidgets('the photo is shown before anything is sent, and can be taken again', (tester) async {
    await open(tester);
    await tapKey(tester, 'scan-camera');
    expect(find.byType(Image), findsOneWidget);
    expect(sent.where((r) => r.url.path.endsWith('/captures')), isEmpty);
    await tapKey(tester, 'scan-retake');
    expect(photos.asked, 2);
    expect(find.byKey(const ValueKey('scan-send')), findsOneWidget);
  });

  testWidgets('after sending, the doubtful fields wait in the pending colour', (tester) async {
    await open(tester);
    await photographAndSend(tester);
    expect(find.text('Supplier K'), findsOneWidget);
    expect(find.text('Oral saline'), findsWidgets);
    expect(find.text('4 things to check before saving'), findsOneWidget);
    expect(find.text('Check this'), findsNWidgets(3));
    expect(find.textContaining('Lines add up to BDT 7,350'), findsOneWidget);
    final save = tester.widget<ElevatedButton>(find.byKey(const ValueKey('scan-save')));
    expect(save.onPressed, isNull, reason: 'nothing is saved until each one is checked');
  });

  testWidgets('confirming every field and the failed check saves the bill', (tester) async {
    await open(tester);
    await photographAndSend(tester);
    for (final path in ['invoice.due_date', 'invoice.lines[2].qty', 'invoice.lines[2].unit_cost']) {
      await tapKey(tester, 'field-right-$path');
    }
    await tapKey(tester, 'check-ok-Invoice total');
    expect(find.text('Everything is checked'), findsOneWidget);
    await tapKey(tester, 'scan-save');

    final confirm = sent.singleWhere((r) => r.url.path.endsWith('/confirm'));
    expect(confirm.url.path, '/api/v1/pharmacies/green-life/captures/cap-demo/confirm');
    expect(find.text('Bill saved'), findsOneWidget);
    await tapKey(tester, 'scan-today');
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Today')), findsOneWidget);
  });

  testWidgets('after a save, Today and Stock read their figures again', (tester) async {
    await pumpLamp(tester,
        session: await signedInSession(),
        at: '/today',
        http: server(),
        photos: photos,
        shrink: (b) async => b);
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    await photographAndSend(tester);
    for (final path in ['invoice.due_date', 'invoice.lines[2].qty', 'invoice.lines[2].unit_cost']) {
      await tapKey(tester, 'field-right-$path');
    }
    await tapKey(tester, 'check-ok-Invoice total');
    await tapKey(tester, 'scan-save');
    final saved = sent.indexWhere((r) => r.url.path.endsWith('/confirm'));
    await tapKey(tester, 'scan-today');
    expect(sent.skip(saved + 1).where((r) => r.url.path.endsWith('/today')), isNotEmpty,
        reason: 'Today must not keep showing the figures from before the bill');
  });

  testWidgets('a date read with an impossible year still opens the calendar', (tester) async {
    captures = (_) => ok(capture.replaceFirst('"invoice_date": "2026-10-16"', '"invoice_date": "0202-10-16"'));
    await open(tester);
    await photographAndSend(tester);
    await tapKey(tester, 'field-change-invoice.invoice_date');
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('a wrong figure is corrected in place, and the correction is sent', (tester) async {
    await open(tester);
    await photographAndSend(tester);
    await tapKey(tester, 'field-change-invoice.lines[2].unit_cost');
    await tester.enterText(find.byKey(const ValueKey('field-input')), '30x');
    await tapKey(tester, 'field-save');
    expect(find.text('That doesn\'t look like an amount.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field-input')), '300');
    await tapKey(tester, 'field-save');
    expect(find.text('৳ 270'), findsNothing);
    expect(find.text('Check this'), findsNWidgets(2));

    await tapKey(tester, 'field-right-invoice.due_date');
    await tapKey(tester, 'field-right-invoice.lines[2].qty');
    await tapKey(tester, 'check-ok-Invoice total');
    await tapKey(tester, 'scan-save');
    final body = jsonDecode(sent.singleWhere((r) => r.url.path.endsWith('/confirm')).body);
    expect(body['invoice']['lines'][2]['unit_cost'], 300);
  });

  testWidgets('offline: the photo stays, with plain words and Send again', (tester) async {
    captures = (_) => throw http.ClientException('no network');
    await open(tester);
    await photographAndSend(tester);
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    captures = (_) => ok(capture);
    await tapKey(tester, 'scan-send');
    expect(find.text('Supplier K'), findsOneWidget);
  });

  testWidgets('the month\'s free scans used up: says when they come back', (tester) async {
    captures = (_) => http.Response(
        jsonEncode({'detail': 'limit', 'code': 'scan_limit_reached', 'resets_on': '2026-12-01'}), 402,
        headers: {'content-type': 'application/json'});
    await open(tester);
    await photographAndSend(tester);
    expect(find.text("You've used this month's 10 free scans."), findsOneWidget);
    expect(find.text('They start again on Tue 1 Dec.'), findsOneWidget);
  });

  testWidgets('text on the photo that gave orders is flagged, not obeyed', (tester) async {
    captures = (_) => ok(salesPage);
    await open(tester);
    await tapKey(tester, 'scan-kind-sales');
    await photographAndSend(tester);
    expect(latin1.decode(sent.singleWhere((r) => r.url.path.endsWith('/captures')).bodyBytes),
        contains('sales_page'));
    expect(find.textContaining('looked like instructions'), findsOneWidget);
    expect(find.text('Cash sales'), findsNWidgets(2));
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('the review fits at text 1.3 in Bangla · $theme', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpLamp(tester,
          session: await signedInSession(),
          at: '/scan',
          locale: const Locale('bn'),
          http: server(),
          photos: photos,
          shrink: (b) async => b,
          prefs: {'lamp.themeMode': theme});
      await photographAndSend(tester);
      // Scroll through every row; an overflow anywhere throws.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('scan-save')), 300);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('in Bangla, amounts and dates use Bangla digits', (tester) async {
    await open(tester, locale: const Locale('bn'));
    await photographAndSend(tester);
    expect(find.text('৳৭,৫০০'), findsOneWidget);
    // Batch numbers and strengths keep English digits (plan 5.4).
    expect(find.text('PC2510'), findsOneWidget);
    expect(find.text('500 mg'), findsOneWidget);
  });
}
