import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lamp_shop/core/l10n/digits.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';

import '../helpers.dart';

/// Plan 5.6, Phase 1: the app opens with the last data, offline. Screens
/// render from the cache first, then refresh, and say how old it is.
void main() {
  final today = File('test/fixtures/today.json').readAsStringSync();
  final expiry = File('test/fixtures/expiry.json').readAsStringSync();
  const todayPath = '/pharmacies/green-life/today';
  const expiryPath = '/pharmacies/green-life/expiry';

  // 10:42 in Dhaka, today: what the indicator shows as "updated 10:42".
  final d = dhakaToday();
  final at1042 = DateTime.utc(d.year, d.month, d.day, 4, 42);

  late MemoryCacheStore cache;
  late bool down;
  late Completer<void>? hold;

  MockClient server() => MockClient((req) async {
        if (hold != null) await hold!.future;
        if (down) throw http.ClientException('no network');
        final body = req.url.path.endsWith('/expiry') ? expiry : today;
        return http.Response(body, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });

  setUp(() {
    cache = MemoryCacheStore();
    down = false;
    hold = null;
  });

  Future<void> open(WidgetTester tester, String at, {Locale locale = const Locale('en')}) async {
    await pumpLamp(tester,
        session: await signedInSession(), at: at, locale: locale, http: server(), cache: cache);
  }

  /// Lets the GET's two retries and their backoff run out.
  Future<void> waitOutRetries(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('a good read is kept for next time', (tester) async {
    await open(tester, '/today');
    final kept = await cache.read(todayPath);
    expect(kept, isNotNull);
    expect((kept!.json as Map)['cash_now'], 39150);
    expect(find.textContaining('Updated '), findsOneWidget);
  });

  testWidgets('offline, Today opens with the last figures and says how old', (tester) async {
    await cache.write(todayPath, jsonDecode(today), at: at1042);
    down = true;
    await open(tester, '/today');
    // Shown at once from the phone, before the network gives up.
    expect(find.text('৳ 39,150'), findsOneWidget);
    await waitOutRetries(tester);
    expect(find.text('৳ 39,150'), findsOneWidget);
    expect(find.text('Offline · updated 10:42'), findsOneWidget);
    expect(find.text('Try again'), findsNothing, reason: 'there is data to show');
  });

  testWidgets('the kept figures show first, then the fresh ones replace them', (tester) async {
    final old = jsonDecode(today) as Map<String, dynamic>..['cash_now'] = 1000;
    await cache.write(todayPath, old, at: at1042);
    hold = Completer();
    await open(tester, '/today');
    expect(find.text('৳ 1,000'), findsOneWidget);
    hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('৳ 39,150'), findsOneWidget);
    expect(find.text('৳ 1,000'), findsNothing);
  });

  testWidgets('offline, Stock opens with the last batches', (tester) async {
    await cache.write(expiryPath, jsonDecode(expiry), at: at1042);
    down = true;
    await open(tester, '/stock');
    await waitOutRetries(tester);
    expect(find.text('৳ 18,400'), findsOneWidget);
    expect(find.text('Offline · updated 10:42'), findsOneWidget);
  });

  testWidgets('offline with nothing kept: plain words and Try again', (tester) async {
    down = true;
    await open(tester, '/stock');
    await waitOutRetries(tester);
    expect(find.text("You're offline. Check your connection."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('in Bangla, the time has Bangla digits', (tester) async {
    await cache.write(todayPath, jsonDecode(today), at: at1042);
    down = true;
    await open(tester, '/today', locale: const Locale('bn'));
    await waitOutRetries(tester);
    expect(find.text('অফলাইন · আপডেট ১০:৪২'), findsOneWidget);
  });

  testWidgets('kept from an earlier day, it shows the day', (tester) async {
    await cache.write(todayPath, jsonDecode(today), at: DateTime.utc(2026, 10, 16, 4, 42));
    down = true;
    await open(tester, '/today');
    await waitOutRetries(tester);
    expect(find.text('Offline · updated Fri 16 Oct'), findsOneWidget);
  });

  testWidgets('an answer the app cannot read: plain words, never a stuck screen', (tester) async {
    await pumpLamp(tester,
        session: await signedInSession(),
        at: '/today',
        http: MockClient((_) async => http.Response('{"shape": "changed"}', 200,
            headers: {'content-type': 'application/json'})),
        cache: cache);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(await cache.read(todayPath), isNull, reason: 'an unreadable answer is not kept');
  });

  testWidgets('a page that is not JSON, such as a proxy error page: plain words', (tester) async {
    await pumpLamp(tester,
        session: await signedInSession(),
        at: '/stock',
        http: MockClient((_) async => http.Response('<html>Bad gateway</html>', 200,
            headers: {'content-type': 'text/html'})),
        cache: cache);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.textContaining('JSON'), findsNothing);
  });

  testWidgets('signing out forgets what was kept', (tester) async {
    final session = await signedInSession();
    await pumpLamp(tester, session: session, at: '/today', http: server(), cache: cache);
    expect(await cache.read(todayPath), isNotNull);
    await session.signOut();
    await tester.pumpAndSettle();
    expect(await cache.read(todayPath), isNull);
  });
}
