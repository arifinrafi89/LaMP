import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/features/sms_phone_mock/keypad.dart';

/// The drawn phone's keypad (plan 5.7): multi-tap letters, as on a real
/// basic phone. `#` switches letters and numbers, `*` deletes.
void main() {
  final t0 = DateTime(2026, 11, 27, 10);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('one press, the first letter; again quickly, the next', () {
    final k = MultiTap();
    k.press('5', at(0));
    expect(k.text, 'J');
    k.press('5', at(300));
    expect(k.text, 'K');
    k.press('5', at(600));
    expect(k.text, 'L');
    k.press('5', at(900));
    expect(k.text, '5', reason: 'the digit ends the cycle');
    k.press('5', at(1200));
    expect(k.text, 'J', reason: 'then round again');
  });

  test('a pause, or another key, starts a new letter', () {
    final k = MultiTap();
    k.press('2', at(0));
    k.press('2', at(2000));
    expect(k.text, 'AA');
    k.press('3', at(2100));
    expect(k.text, 'AAD');
  });

  test('LAMP, then a space, then a card code with digits', () {
    final k = MultiTap();
    var ms = 0;
    void tap(String key, [int times = 1]) {
      for (var i = 0; i < times; i++) {
        k.press(key, at(ms));
        ms += 200;
      }
      ms += 2000; // let the letter settle
    }

    tap('5', 3); // L
    tap('2'); // A
    tap('6'); // M
    tap('7'); // P
    tap('0'); // space
    tap('4'); // G
    tap('5', 3); // L
    tap('#'); // numbers
    tap('7'); // 7
    tap('#'); // letters
    tap('5', 2); // K
    expect(k.text, 'LAMP GL7K');
    expect(k.letters, isTrue);
  });

  test('* deletes the last character', () {
    final k = MultiTap();
    k.press('2', at(0));
    k.press('3', at(100));
    k.press('*', at(200));
    expect(k.text, 'A');
    k.press('*', at(300));
    k.press('*', at(400));
    expect(k.text, '', reason: 'nothing left to delete is fine');
  });

  test('in numbers, every key is its digit', () {
    final k = MultiTap();
    k.press('#', at(0));
    expect(k.letters, isFalse);
    for (final d in ['1', '2', '1', '3']) {
      k.press(d, at(100));
    }
    expect(k.text, '1213');
  });

  test('a filled-in text, then cleared', () {
    final k = MultiTap()..fill('LAMP GL7KQM4XPA');
    expect(k.text, 'LAMP GL7KQM4XPA');
    k.press('*', at(0));
    expect(k.text, 'LAMP GL7KQM4XP');
    k.clear();
    expect(k.text, '');
  });
}
