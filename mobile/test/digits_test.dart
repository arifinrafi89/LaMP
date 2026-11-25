import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/l10n/digits.dart';

/// Plan 5.4: in Bangla, amounts and dates show Bangla digits and ৳; card
/// codes, phone numbers, the short code and medicine strengths keep English
/// digits. Ported from LaMP.ai's `bnNumbers` (frontend/src/lib/bangla-text.ts).
void main() {
  group('bnDigits', () {
    test('maps every digit', () {
      expect(bnDigits('0123456789'), '০১২৩৪৫৬৭৮৯');
    });
    test('leaves everything else alone', () {
      expect(bnDigits('a-b, c.'), 'a-b, c.');
    });
  });

  group('bnNumbers (chat and server text, display only)', () {
    test('BDT amounts become ৳ with Bangla digits', () {
      expect(bnNumbers('Short BDT 19,000 on 26 Oct'), 'Short ৳১৯,০০০ on ২৬ Oct');
    });
    test('decimals keep their point', () {
      expect(bnNumbers('BDT 10.00'), '৳১০.০০');
    });
    test('card codes keep English digits', () {
      expect(bnNumbers('Card GL-7KQM-4XPA'), 'Card GL-7KQM-4XPA');
    });
    test('customer labels keep English digits', () {
      expect(bnNumbers('Customer 003 owes BDT 500'), 'Customer 003 owes ৳৫০০');
    });
    test('medicine strengths keep English digits', () {
      expect(bnNumbers('Napa 500 mg and Seclo 20mg'), 'Napa 500 mg and Seclo 20mg');
    });
    test('phone numbers keep English digits', () {
      expect(bnNumbers('Call 01912345678'), 'Call 01912345678');
      expect(bnNumbers('tel 8801412345678'), 'tel 8801412345678');
    });
    test('the short code keeps English digits', () {
      expect(bnNumbers('send STOP LAMP to 77000'), 'send STOP LAMP to 77000');
    });
    test('a word that merely contains BDT is not an amount', () {
      expect(bnNumbers('XBDT 5'), 'XBDT ৫');
    });
  });

  group('formatMoney', () {
    test('English: ৳, a space, lakh grouping, whole taka', () {
      expect(formatMoney(182400, bangla: false), '৳ 1,82,400');
      expect(formatMoney(6500.4, bangla: false), '৳ 6,500');
    });
    test('Bangla: ৳ joined to Bangla digits', () {
      expect(formatMoney(19000, bangla: true), '৳১৯,০০০');
    });
    test('negative amounts keep their sign before the taka sign', () {
      expect(formatMoney(-1625, bangla: false), '-৳ 1,625');
    });
  });

  group('formatDay', () {
    final thu = DateTime(2026, 10, 29);
    test('English', () {
      expect(formatDay(thu, bangla: false), 'Thu 29 Oct');
    });
    test('Bangla weekday, day and month', () {
      expect(formatDay(thu, bangla: true), 'বৃহস্পতি ২৯ অক্টো');
    });
  });
}
