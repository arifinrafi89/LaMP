import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/auth/phone_number.dart';

/// Owners sign in with a Banglalink number (D2): 019 and 014 only.
void main() {
  group('checkBanglalink', () {
    test('the ways people write one number all mean the same phone', () {
      for (final raw in [
        '01912345678', '01912-345678', '019 1234 5678',
        '8801912345678', '+880 1912 345678', '1912345678',
      ]) {
        final c = checkBanglalink(raw);
        expect(c.result, PhoneResult.ok, reason: raw);
        expect(c.e164, '+8801912345678', reason: raw);
      }
    });

    test('014 is Banglalink too', () {
      expect(checkBanglalink('01412345678').e164, '+8801412345678');
    });

    test('another operator is a valid number but not Banglalink', () {
      for (final raw in ['01712345678', '01812345678', '01312345678', '01512345678']) {
        expect(checkBanglalink(raw).result, PhoneResult.notBanglalink, reason: raw);
      }
    });

    test('not a mobile number at all', () {
      for (final raw in ['', '019123', 'abc', '+1 415 555 0100', '019123456789']) {
        expect(checkBanglalink(raw).result, PhoneResult.invalid, reason: raw);
      }
    });
  });

  test('formatPhone groups for reading', () {
    expect(formatPhone('+8801912345678'), '+880 1912 345678');
  });
}
