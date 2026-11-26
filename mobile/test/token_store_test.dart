import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/auth/auth_service.dart';
import 'package:lamp_shop/core/auth/token_store.dart';

/// What is saved for the next launch reads back as the same session.
void main() {
  test('a stored session survives the trip through JSON', () {
    const s = StoredSession(
      refreshToken: 'r-1',
      owner: OwnerInfo(id: 'o-1', phoneMasked: '+880 19•• ••5678', language: 'en'),
      pharmacy: PharmacyInfo(id: 'green-life', name: 'Green Life Pharmacy', setupComplete: true),
    );
    final back = StoredSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.refreshToken, 'r-1');
    expect(back.owner.toJson(), s.owner.toJson());
    expect(back.pharmacy!.toJson(), s.pharmacy!.toJson());
  });

  test('a session with no shop yet keeps no shop', () {
    const s = StoredSession(owner: OwnerInfo(id: 'o-1', phoneMasked: 'x', language: 'bn'));
    final back = StoredSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.pharmacy, isNull);
    expect(back.refreshToken, isNull);
  });
}
