/// Customers who owe the shop (plan 2.2, 3.4). Amounts only: a card has a
/// label like "Customer 004" and a code, never a name or a medicine.
library;

/// Where the family's SMS stands (plan 3.4).
enum SmsStatus {
  none,

  /// The family texted the join text; waiting for Banglalink ("Joining").
  pending,
  on,
  stopped,
  failed;

  /// An unknown word reads as none, so a new state can't break the list.
  static SmsStatus parse(Object? v) => switch (v) {
    'PENDING' => pending,
    'ON' => on,
    'STOPPED' => stopped,
    'FAILED' => failed,
    _ => none,
  };
}

/// The keyword every family text starts with (plan 3.5).
const _joinKeyword = 'LAMP ';

/// The short code families text (plan 3.1).
const shortCode = '21213';

/// What the family texts to join: "LAMP GL7KQM4XPA" to 21213 (plan 3.5).
class JoinText {
  const JoinText(this.text, this.to);

  final String text;
  final String to;

  /// The plan's format, for a card the server sent without one: the keyword
  /// and the code without its dashes.
  factory JoinText.forCode(String code) => JoinText(_joinKeyword + code.replaceAll('-', ''), shortCode);

  static JoinText read(Object? j, String code) {
    if (j is Map && j['text'] is String && j['to'] is String) {
      return JoinText(j['text'] as String, j['to'] as String);
    }
    return JoinText.forCode(code);
  }
}

DateTime _day(Object? s) => DateTime.parse(s as String);

class PlanPart {
  const PlanPart(this.n, this.dueOn, this.amount, [this.paid]);

  final int n;
  final DateTime dueOn;
  final double amount;

  /// Null while the server doesn't say (contract v1 has no such field).
  final bool? paid;

  factory PlanPart.fromJson(Map<String, dynamic> j) =>
      PlanPart(j['n'] as int, _day(j['due_on']), (j['amount'] as num).toDouble(), j['paid'] as bool?);
}

/// Weekly parts the family agreed to, as the server sends them. Contract v1
/// splits what is owed now across every part, so a passed date says nothing
/// about payment; only a server that marks parts `paid` can show progress.
class CustomerPlan {
  const CustomerPlan(this.parts, this.firstOn, this.schedule);

  final int parts;
  final DateTime firstOn;
  final List<PlanPart> schedule;

  factory CustomerPlan.fromJson(Map<String, dynamic> j) => CustomerPlan(j['parts'] as int, _day(j['first_on']), [
    for (final p in j['schedule'] as List) PlanPart.fromJson(p as Map<String, dynamic>),
  ]);

  /// Whether the server said which parts are paid.
  bool get paidKnown => schedule.isNotEmpty && schedule.every((p) => p.paid != null);

  int get paidCount => schedule.where((p) => p.paid == true).length;

  /// The first part not yet paid, when the server says.
  PlanPart? get nextUnpaid {
    if (!paidKnown) return null;
    for (final p in schedule) {
      if (p.paid == false) return p;
    }
    return null;
  }
}

class Customer {
  const Customer({
    required this.code,
    required this.label,
    required this.amount,
    required this.since,
    required this.daysOutstanding,
    required this.plan,
    required this.smsStatus,
    required this.trusted,
    required this.join,
  });

  final String code;
  final String label;

  /// What they owe now.
  final double amount;
  final DateTime since;
  final int daysOutstanding;
  final CustomerPlan? plan;
  final SmsStatus smsStatus;

  /// Every part so far paid on time.
  final bool trusted;
  final JoinText join;

  /// Texting the join text starts SMS, unless it's on or starting already.
  bool get canJoin => smsStatus != SmsStatus.on && smsStatus != SmsStatus.pending;

  factory Customer.fromJson(Map<String, dynamic> j) {
    final code = j['code'] as String;
    final plan = j['plan'];
    return Customer(
      code: code,
      label: j['label'] as String,
      amount: (j['amount'] as num).toDouble(),
      since: _day(j['since']),
      daysOutstanding: j['days_outstanding'] as int,
      plan: plan is Map<String, dynamic> ? CustomerPlan.fromJson(plan) : null,
      smsStatus: SmsStatus.parse(j['sms_status']),
      trusted: j['trusted'] == true,
      join: JoinText.read(j['join'], code),
    );
  }
}

class CustomerList {
  const CustomerList(this.items);

  final List<Customer> items;

  factory CustomerList.fromJson(List<dynamic> j) =>
      CustomerList([for (final c in j) Customer.fromJson(c as Map<String, dynamic>)]);

  Customer? byCode(String code) {
    for (final c in items) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// `POST /customers`: the new card.
class CustomerCreated {
  const CustomerCreated(this.code, this.label, this.join);

  final String code;
  final String label;
  final JoinText join;

  factory CustomerCreated.fromJson(Map<String, dynamic> j) {
    final code = j['code'] as String;
    return CustomerCreated(code, j['label'] as String, JoinText.read(j['join'], code));
  }
}

class PlanOption {
  const PlanOption(this.parts, this.partAmount);

  final int parts;

  /// The first part; the last one takes any remainder.
  final double partAmount;
}

/// The ways to pay, from the card (`GET /cards/{code}`): the server does the
/// splitting (D8).
class PlanChoices {
  const PlanChoices({
    required this.amount,
    required this.asOf,
    required this.latestFirstOn,
    required this.options,
    required this.plan,
  });

  final double amount;
  final DateTime asOf;
  final DateTime latestFirstOn;
  final List<PlanOption> options;
  final CustomerPlan? plan;

  factory PlanChoices.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'];
    return PlanChoices(
      amount: (j['amount'] as num).toDouble(),
      asOf: _day(j['as_of']),
      latestFirstOn: _day(j['latest_first_on']),
      options: [
        for (final o in j['options'] as List)
          PlanOption((o as Map)['parts'] as int, (o['part_amount'] as num).toDouble()),
      ],
      plan: plan is Map<String, dynamic> ? CustomerPlan.fromJson(plan) : null,
    );
  }
}
