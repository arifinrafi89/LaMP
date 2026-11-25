/// Adapted from lamp-flutter's `phone_number.dart`: owners sign in with a
/// Banglalink number (D2), so only 019 and 014 pass. The server normalises
/// again to `tel:8801…`; this check only spares a wasted round trip.
library;

enum PhoneResult { ok, invalid, notBanglalink }

class PhoneCheck {
  const PhoneCheck(this.result, [this.e164]);
  final PhoneResult result;

  /// `+8801912345678` when [result] is [PhoneResult.ok].
  final String? e164;
}

/// People write one number as `01912 345678`, `01912-345678`,
/// `8801912345678` or `+880 1912 345678`; all of them mean the same phone.
PhoneCheck checkBanglalink(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.startsWith('+')) {
    if (!s.startsWith('+880')) return const PhoneCheck(PhoneResult.invalid);
    s = s.substring(1);
  }
  if (!RegExp(r'^\d+$').hasMatch(s)) return const PhoneCheck(PhoneResult.invalid);
  if (s.startsWith('880')) s = s.substring(3);
  if (s.startsWith('0')) s = s.substring(1);

  // A Bangladeshi mobile: 1, an operator digit 3–9, then 8 digits.
  if (!RegExp(r'^1[3-9]\d{8}$').hasMatch(s)) return const PhoneCheck(PhoneResult.invalid);
  if (!(s.startsWith('19') || s.startsWith('14'))) {
    return const PhoneCheck(PhoneResult.notBanglalink);
  }
  return PhoneCheck(PhoneResult.ok, '+880$s');
}

/// A number for reading: `+880 1912 345678`.
String formatPhone(String e164) {
  if (e164.startsWith('+880') && e164.length == 14) {
    return '+880 ${e164.substring(4, 8)} ${e164.substring(8)}';
  }
  return e164;
}
