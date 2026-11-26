import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/l10n/digits.dart';

/// What the owner types: amounts with English or Bangla digits, commas or
/// a taka sign; dates sent to the server as Dhaka `YYYY-MM-DD`.
void main() {
  group('parseAmount', () {
    test('plain and grouped English digits', () {
      expect(parseAmount('25000'), 25000);
      expect(parseAmount('1,82,400'), 182400);
      expect(parseAmount('৳ 2,500.50'), 2500.5);
    });
    test('Bangla digits, as a Bangla keyboard types them', () {
      expect(parseAmount('২৫,০০০'), 25000);
      expect(parseAmount('৳১২.৫'), 12.5);
    });
    test('blank, words or a negative amount are not amounts', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('  '), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('-50'), isNull);
      expect(parseAmount('1.2.3'), isNull);
    });
    test('rounds to 2 decimals, as money is sent (D8)', () {
      expect(parseAmount('10.239'), 10.24);
    });
  });

  group('parseWhole', () {
    test('English and Bangla digits', () {
      expect(parseWhole('30'), 30);
      expect(parseWhole('৩০'), 30);
      expect(parseWhole(' 7 '), 7);
    });
    test('not a whole number', () {
      expect(parseWhole(''), isNull);
      expect(parseWhole('2.5'), isNull);
      expect(parseWhole('x'), isNull);
    });
  });

  group('dates', () {
    test('apiDate is YYYY-MM-DD', () {
      expect(apiDate(DateTime(2026, 3, 7)), '2026-03-07');
    });
    test('dhakaToday turns over at midnight in Dhaka, not UTC', () {
      // 18:30 UTC is 00:30 the next day in Dhaka (UTC+6).
      expect(apiDate(dhakaToday(DateTime.utc(2026, 11, 26, 18, 30))), '2026-11-27');
      expect(apiDate(dhakaToday(DateTime.utc(2026, 11, 26, 17, 59))), '2026-11-26');
    });
  });
}
