import 'package:intl/intl.dart';

/// Bangla digits for amounts and dates (plan 5.4).
///
/// The server and the chat always send English digits and "BDT 19,000". In
/// Bangla, what the screen shows is converted here, for display only. Card
/// codes, phone numbers, the short code and medicine strengths keep English
/// digits, as printed on the card, the SIM and the box.
///
/// A Dart port of LaMP.ai's `bnNumbers` (frontend/src/lib/bangla-text.ts,
/// reference only), plus the phone and short-code rule.

const _bn = '০১২৩৪৫৬৭৮৯';

String bnDigits(String s) =>
    s.replaceAllMapped(RegExp('[0-9]'), (m) => _bn[int.parse(m[0]!)]);

final _bdt = RegExp(r'(?<![A-Za-z])BDT (?=\d)');

// A number not joined to a letter or hyphen (GL-7KQM-4XPA, 4G), not a
// customer label (Customer 003), and not followed by a unit (500 mg).
final _number = RegExp(
  r'(?<![A-Za-z0-9-]|Customer )\d[\d,]*(?:\.\d+)?'
  r'(?![\d,.]*(?:[A-Za-z]|-[A-Za-z0-9]|\s?(?:mg|mcg|ml|g)\b))',
);

/// Five or more bare digits: a phone number (019…, 8801…) or the short code
/// (77000). Amounts are grouped with commas, so they never match.
final _codeLike = RegExp(r'^\d{5,}$');

String bnNumbers(String text) => text
    .replaceAll(_bdt, '৳')
    .replaceAllMapped(_number, (m) {
      final n = m[0]!;
      if (!_precededByTaka(m) && _codeLike.hasMatch(n)) return n;
      return bnDigits(n);
    });

bool _precededByTaka(Match m) =>
    m.start > 0 && m.input.substring(m.start - 1, m.start) == '৳';

final _lakh = NumberFormat('#,##,###', 'en_IN');

/// A whole-taka amount: `৳ 1,82,400` in English, `৳১,৮২,৪০০` in Bangla.
/// Money from the server has 2 decimals; the app does no money math (D8), it
/// only rounds for display.
String formatMoney(num amount, {required bool bangla}) {
  final sign = amount < 0 ? '-' : '';
  final grouped = _lakh.format(amount.abs().round());
  return bangla ? '$sign৳${bnDigits(grouped)}' : '$sign৳ $grouped';
}

const _enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _enMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _bnDays = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহস্পতি', 'শুক্র', 'শনি', 'রবি'];
const _bnMonths = [
  'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টে', 'অক্টো', 'নভে', 'ডিসে',
];

/// `Thu 29 Oct`, or `বৃহস্পতি ২৯ অক্টো`. Dates are already Dhaka dates
/// (`YYYY-MM-DD` from the server), so no time zone is applied here.
String formatDay(DateTime day, {required bool bangla}) {
  // Spelled out rather than through DateFormat, which needs locale data
  // loaded first and would format nothing until it was.
  if (!bangla) {
    return '${_enDays[day.weekday - 1]} ${day.day} ${_enMonths[day.month - 1]}';
  }
  return '${_bnDays[day.weekday - 1]} ${bnDigits('${day.day}')} '
      '${_bnMonths[day.month - 1]}';
}

/// Bangla digits back to English, for what the owner types.
String enDigits(String s) =>
    s.replaceAllMapped(RegExp('[০-৯]'), (m) => '${_bn.indexOf(m[0]!)}');

final _amount = RegExp(r'^\d+(?:\.\d+)?$');

/// An amount typed in either language: `25000`, `1,82,400`, `৳ ২,৫০০`.
/// Null when it isn't a positive-or-zero number. Rounded to 2 decimals,
/// the way money is sent to the server (D8).
double? parseAmount(String typed) {
  final s = enDigits(typed).replaceAll(RegExp(r'[৳,\s]'), '');
  if (!_amount.hasMatch(s)) return null;
  return (double.parse(s) * 100).round() / 100;
}

/// A whole number typed in either language (days, quantities).
int? parseWhole(String typed) {
  final s = enDigits(typed).trim();
  if (!RegExp(r'^\d+$').hasMatch(s)) return null;
  return int.parse(s);
}

/// Today's date in Dhaka (UTC+6, no daylight saving), whatever the phone's
/// own time zone. [now] is for tests.
DateTime dhakaToday([DateTime? now]) {
  final d = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 6));
  return DateTime(d.year, d.month, d.day);
}

/// `2026-11-26`, the date format of every API field (plan 2.1).
String apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
