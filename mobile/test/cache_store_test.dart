import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:lamp_shop/core/offline/cache_store.dart';

/// Plan 5.6: every successful read is kept per shop in an encrypted box, so
/// the app opens with the last data when offline.
void main() {
  final today = jsonDecode(File('test/fixtures/today.json').readAsStringSync());
  final at = DateTime.utc(2026, 11, 27, 4, 42);

  group('in memory', () {
    test('keeps what was written, with when', () async {
      final c = MemoryCacheStore();
      expect(await c.read('/pharmacies/green-life/today'), isNull);
      await c.write('/pharmacies/green-life/today', today, at: at);
      final got = await c.read('/pharmacies/green-life/today');
      expect(got!.json, today);
      expect(got.savedAt, at);
      await c.clear();
      expect(await c.read('/pharmacies/green-life/today'), isNull);
    });
  });

  group('on disk (hive_ce)', () {
    late Directory dir;
    final key = List<int>.generate(32, (i) => i * 7 % 256);

    HiveCacheStore store() => HiveCacheStore(
          init: () async => Hive.init(dir.path),
          key: () async => key,
        );

    setUp(() => dir = Directory.systemTemp.createTempSync('lamp_cache_'));
    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('survives closing the app', () async {
      await store().write('/pharmacies/green-life/today', today, at: at);
      await Hive.close();
      final got = await store().read('/pharmacies/green-life/today');
      expect(got!.json, today);
      expect(got.savedAt, at);
    });

    test('is encrypted on the phone', () async {
      await store().write('/pharmacies/green-life/today', today, at: at);
      await Hive.close();
      final raw = dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => latin1.decode(f.readAsBytesSync()))
          .join();
      expect(raw, isNotEmpty);
      expect(raw.contains('cash_now'), isFalse);
      expect(raw.contains('Approve'), isFalse);
    });

    test('clearing it forgets every shop', () async {
      final s = store();
      await s.write('/pharmacies/green-life/today', today, at: at);
      await s.write('/pharmacies/green-life/expiry', {'batches': []}, at: at);
      await s.clear();
      expect(await s.read('/pharmacies/green-life/today'), isNull);
      expect(await s.read('/pharmacies/green-life/expiry'), isNull);
    });

    test('a box it cannot open is started again, not a crash', () async {
      await store().write('/pharmacies/green-life/today', today, at: at);
      await Hive.close();
      // A different key: the old box can't be read with it.
      final other = HiveCacheStore(
        init: () async => Hive.init(dir.path),
        key: () async => List<int>.filled(32, 9),
      );
      expect(await other.read('/pharmacies/green-life/today'), isNull);
      await other.write('/pharmacies/green-life/today', today, at: at);
      expect((await other.read('/pharmacies/green-life/today'))!.json, today);
    });
  });
}
