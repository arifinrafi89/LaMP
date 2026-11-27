import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/core/state/me.dart';
import 'package:lamp_shop/features/customers/customers_models.dart';

/// Customers (plan 2.2, 3.4): amounts only, never a name; families join by
/// texting the join text to 21213.
void main() {
  final rows = jsonDecode(File('test/fixtures/customers.json').readAsStringSync()) as List;
  final list = CustomerList.fromJson(rows);

  group('a customer', () {
    test('reads every row, in the server\'s order', () {
      expect(list.items.map((c) => c.label), ['Customer 001', 'Customer 003', 'Customer 004', 'Customer 005']);
      final c = list.byCode('GL-7KQM-4XPA')!;
      expect(c.amount, 6500);
      expect(c.since, DateTime(2026, 11, 3));
      expect(c.daysOutstanding, 24);
      expect(c.trusted, isTrue);
      expect(c.smsStatus, SmsStatus.on);
    });

    test('reads the plan and its parts', () {
      final p = list.byCode('GL-7KQM-4XPA')!.plan!;
      expect(p.parts, 4);
      expect(p.firstOn, DateTime(2026, 11, 26));
      expect(p.schedule.map((s) => s.dueOn.day), [26, 3, 10, 17]);
      expect(p.schedule.every((s) => s.amount == 1625), isTrue);
      expect(list.byCode('GL-3HFD-9WQT')!.plan, isNull);
    });

    test('without paid marks, no progress is claimed', () {
      final p = list.byCode('GL-7KQM-4XPA')!.plan!;
      expect(p.paidKnown, isFalse);
      expect(p.nextUnpaid, isNull);
    });

    test('with paid marks: how many are paid, and the next one', () {
      final p = CustomerPlan.fromJson({
        'parts': 4,
        'first_on': '2026-11-26',
        'schedule': [
          for (final (i, d) in ['2026-11-26', '2026-12-03', '2026-12-10', '2026-12-17'].indexed)
            {'n': i + 1, 'due_on': d, 'amount': 1625.0, 'paid': i < 1},
        ],
      });
      expect(p.paidKnown, isTrue);
      expect(p.paidCount, 1);
      expect(p.nextUnpaid!.n, 2);
    });

    test('every SMS state, and an unknown one reads as none', () {
      SmsStatus s(String v) => SmsStatus.parse(v);
      expect(
        [s('NONE'), s('PENDING'), s('ON'), s('STOPPED'), s('FAILED'), s('NEW_ONE')],
        [SmsStatus.none, SmsStatus.pending, SmsStatus.on, SmsStatus.stopped, SmsStatus.failed, SmsStatus.none],
      );
    });

    test('the family can text to join unless SMS is on or joining', () {
      expect(list.byCode('GL-7KQM-4XPA')!.canJoin, isFalse, reason: 'ON');
      expect(list.byCode('GL-3HFD-9WQT')!.canJoin, isFalse, reason: 'PENDING');
      expect(list.byCode('GL-5RTY-6UIO')!.canJoin, isTrue, reason: 'STOPPED');
      expect(list.byCode('GL-8NBV-2KLM')!.canJoin, isTrue, reason: 'NONE');
    });

    test('the join text comes from the server', () {
      final j = list.byCode('GL-7KQM-4XPA')!.join;
      expect(j.text, 'LAMP GL7KQM4XPA');
      expect(j.to, '21213');
    });

    test('a row without one gets the plan\'s format: LAMP and the code without dashes', () {
      final j = list.byCode('GL-8NBV-2KLM')!.join;
      expect(j.text, 'LAMP GL8NBV2KLM');
      expect(j.to, '21213');
    });

    test('an unknown code is not found', () {
      expect(list.byCode('GL-0000-0000'), isNull);
    });

    test('a newly added card', () {
      final c = CustomerCreated.fromJson({'code': 'GL-2WSX-3EDC', 'label': 'Customer 006'});
      expect(c.label, 'Customer 006');
      expect(c.join.text, 'LAMP GL2WSX3EDC');
    });
  });

  group('plan choices', () {
    final card = PlanChoices.fromJson(
      jsonDecode(File('test/fixtures/card.json').readAsStringSync()) as Map<String, dynamic>,
    );

    test('come from the card: the server splits the amount, never the app', () {
      expect(card.options.map((o) => o.parts), [1, 2, 4]);
      expect(card.options.map((o) => o.partAmount), [2450, 1225, 612]);
      expect(card.asOf, DateTime(2026, 11, 27));
      expect(card.latestFirstOn, DateTime(2026, 12, 11));
      expect(card.plan, isNull);
    });
  });

  group('/me', () {
    final me = MeInfo.fromJson(jsonDecode(File('test/fixtures/me.json').readAsStringSync()) as Map<String, dynamic>);

    test('reads the plan, what it unlocks and the join routes', () {
      expect(me.plus, isFalse);
      expect(me.entitlements.ask, isFalse);
      expect(me.entitlements.scansLeft, 7);
      expect(me.demoTools, isFalse);
      expect(me.counterRoute, isFalse);
    });

    test('the counter route only when the server lists it', () {
      final j = jsonDecode(File('test/fixtures/me.json').readAsStringSync()) as Map<String, dynamic>;
      expect(
        MeInfo.fromJson({
          ...j,
          'family_join_routes': ['text', 'counter'],
        }).counterRoute,
        isTrue,
      );
      expect(
        MeInfo.fromJson({...j}..remove('family_join_routes')).counterRoute,
        isFalse,
        reason: 'masking is on today, so only texting',
      );
    });
  });
}
