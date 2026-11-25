import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamp_shop/features/today/today_models.dart';

/// GET /pharmacies/{pid}/today (plan 2.2), with Green Life's golden numbers
/// (LaMP.ai docs/PLAN.md §6): short BDT 19,000 on 26 Oct, BDT 18,400
/// expiring within 60 days, BDT 9,200 of it able to go back.
void main() {
  Map<String, dynamic> fixture() =>
      jsonDecode(File('test/fixtures/today.json').readAsStringSync()) as Map<String, dynamic>;

  test('reads every field the Today screen shows', () {
    final t = TodaySummary.fromJson(fixture());
    expect(t.asOf, DateTime(2026, 10, 16));
    expect(t.cashNow, 39150);
    expect(t.nextProblem!.kind, 'shortfall');
    expect(t.nextProblem!.date, DateTime(2026, 10, 26));
    expect(t.nextProblem!.amount, 19000);
    expect(t.expiringValue, 18400);
    expect(t.returnEligible, 9200);
    expect(t.approvalsWaiting, 2);
    expect(t.oneThing!.kind, 'approve');
    expect(t.oneThing!.actionId, 'act-1');
    expect(t.alerts.single.title, 'Send back stock worth BDT 9,200');
    expect(t.alerts.single.severity, 'warning');
  });

  test('a quiet day has no problem and nothing to do', () {
    final j = fixture()
      ..['next_problem'] = null
      ..['one_thing'] = null
      ..['alerts'] = [];
    final t = TodaySummary.fromJson(j);
    expect(t.nextProblem, isNull);
    expect(t.oneThing, isNull);
    expect(t.alerts, isEmpty);
  });

  test('integer money is read as money too', () {
    final t = TodaySummary.fromJson(fixture()..['cash_now'] = 500);
    expect(t.cashNow, 500.0);
  });
}
