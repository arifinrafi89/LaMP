import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/features/approvals/approvals_models.dart';
import 'package:lamp_shop/features/cash/cash_models.dart';
import 'package:lamp_shop/features/plan/plan_models.dart';

/// Cash, Plan and Approvals (plan 2.2, Plus): every figure is the server's;
/// the app shows them and adds nothing up (D8).
void main() {
  Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

  group('cash', () {
    final f = Forecast.fromJson(fixture('forecast') as Map<String, dynamic>);

    test('reads the start, every day and every short day', () {
      expect(f.startCash, 39150);
      expect(f.days, hasLength(30));
      expect(f.shortfalls.first.date, DateTime(2026, 10, 26));
      expect(f.shortfalls.first.amount, 19000);
      expect(f.shortfalls.first.cause, 'Supplier A order BDT 60,000');
    });

    test('days with something named in them, and the day a shortfall falls on', () {
      expect(f.namedDays.map((d) => d.date.day).take(3), [18, 22, 26]);
      final d = f.dayOf(DateTime(2026, 10, 26))!;
      expect(d.items.single.label, 'Supplier A order');
      expect(d.items.single.amount, -60000);
      expect(d.balance, -17350);
      expect(d.short, isTrue);
      expect(f.dayOf(DateTime(2026, 10, 16))!.short, isFalse);
    });
  });

  group('plan', () {
    final p = MoneyPlan.fromJson(fixture('funding_plan') as Map<String, dynamic>);

    test('reads what to cover, by when, and how that was worked out', () {
      expect(p.need.amount, 8200);
      expect(p.need.neededBy, DateTime(2026, 10, 26));
      expect(p.need.explain.map((r) => r.op), ['start', '-', '=']);
      expect(p.totalCost, 0);
      expect(p.naiveCost, 421.64);
    });

    test('the steps; a loan is only ever the fallback, never sent to Approvals', () {
      expect(p.steps.map((s) => s.kind), ['trim_order', 'extension_request', 'loan_application']);
      expect(p.toPropose.map((s) => s.kind), ['trim_order', 'extension_request']);
      expect(p.fallbacks.single.fallbackFor, 'extension_request');
    });

    test('the other ways, eligible or not, with why', () {
      expect(p.options, hasLength(6));
      final wallet = p.options.firstWhere((o) => o.key == 'wallet_loan');
      expect(wallet.costBdt, 181.97);
      expect(wallet.aprPct, 9.0);
      expect(wallet.certain, isTrue);
      final bank = p.options.firstWhere((o) => o.key == 'bank_sme_loan');
      expect(bank.eligible, isFalse);
      expect(bank.reason, isNotEmpty);
    });

    test('an order and the lines worth cutting', () {
      final orders = [for (final o in fixture('orders') as List) Order.fromJson(o as Map<String, dynamic>)];
      expect(orders.single.id, 'o-1');
      expect(orders.single.supplier, 'Supplier A');
      final t = Trim.fromJson(fixture('trim') as Map<String, dynamic>);
      expect(t.saving, 10800);
      expect(t.cuts.single.product, 'Montelukast 10 mg, box of 30');
      expect(t.cuts.single.qty, 30);
      expect(t.cuts.single.suggestedQty, 12);
    });
  });

  group('approvals', () {
    final a = ActionList.fromJson(fixture('actions') as List);

    test('what waits for the owner, then what was decided', () {
      expect(a.waiting.map((x) => x.id), ['act-4', 'act-3']);
      expect(a.done.map((x) => x.id), ['act-1', 'act-0']);
    });

    test('one action: what it is, its amount and who suggested it', () {
      final x = a.byId('act-3')!;
      expect(x.kind, 'trim_order');
      expect(x.summary, 'Cut Montelukast from 30 to 12 boxes');
      expect(x.amount, 10800);
      expect(x.byLamp, isTrue);
      expect(a.byId('act-4')!.byLamp, isFalse);
      expect(a.byId('act-1')!.resultSummary, 'Return sent. Your next bills should be BDT 9,200 lower.');
    });

    test('an approved request for more days: the message for the supplier, in the owner\'s language', () {
      final x = LampAction.fromJson({
        ...((fixture('actions') as List).first as Map<String, dynamic>),
        'status': 'executed',
        'result': {
          'summary': 'Your message to Supplier A is ready.',
          'share_text_en': 'Dear Supplier A, could we have 20 more days on BDT 8,200?',
          'share_text_bn': 'প্রিয় Supplier A, ৳৮,২০০-এর জন্য আরও ২০ দিন পেতে পারি?',
          'supplier_phone': '+8801912000111',
        },
      });
      expect(x.shareText(bangla: false), startsWith('Dear Supplier A'));
      expect(x.shareText(bangla: true), startsWith('প্রিয়'));
      expect(x.supplierPhone, '+8801912000111');
      expect(a.byId('act-1')!.shareText(bangla: false), isNull);
    });

    test('an unknown status or kind is kept, not a crash', () {
      final x = LampAction.fromJson({
        'id': 'x',
        'kind': 'new_kind',
        'status': 'new_status',
        'payload': {},
        'proposed_by': 'owner',
        'created_at': '2026-11-27T00:00:00Z',
      });
      expect(x.waiting, isFalse);
      expect(x.amount, isNull);
      expect(x.summary, isNull);
    });

    test('pause', () {
      expect(PauseState.fromJson(fixture('pause') as Map<String, dynamic>).paused, isFalse);
    });
  });
}
