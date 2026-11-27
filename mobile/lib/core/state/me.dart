import '../api/api_client.dart';
import '../offline/cache_store.dart';
import '../offline/cached_read.dart';

/// What the owner's plan unlocks (`GET /me`, plan 2.2).
class Entitlements {
  const Entitlements({
    required this.cash,
    required this.plan,
    required this.approvals,
    required this.ask,
    required this.scansLeft,
  });

  final bool cash;
  final bool plan;
  final bool approvals;
  final bool ask;

  /// Null on Plus: no monthly limit.
  final int? scansLeft;

  factory Entitlements.fromJson(Map<String, dynamic> j) => Entitlements(
    cash: j['cash'] == true,
    plan: j['plan'] == true,
    approvals: j['approvals'] == true,
    ask: j['ask'] == true,
    scansLeft: j['scans_left'] as int?,
  );
}

class MeInfo {
  const MeInfo({
    required this.plus,
    required this.plusStatus,
    required this.entitlements,
    required this.demoTools,
    required this.familyJoinRoutes,
  });

  final bool plus;
  final String plusStatus;
  final Entitlements entitlements;

  /// Demo and team-test shops only (the drawn phone, plan 5.7).
  final bool demoTools;

  /// How families can join SMS (plan 3.4): `text`, and `counter` only while
  /// Applink's number masking is off.
  final List<String> familyJoinRoutes;

  /// The owner may type the family's number, with their consent.
  bool get counterRoute => familyJoinRoutes.contains('counter');

  factory MeInfo.fromJson(Map<String, dynamic> j) => MeInfo(
    plus: j['plan'] == 'plus',
    plusStatus: (j['plus_status'] as String?) ?? 'NONE',
    entitlements: Entitlements.fromJson(j['entitlements'] as Map<String, dynamic>),
    demoTools: j['demo_tools'] == true,
    // Masking is on today, so a server that doesn't say means texting only.
    familyJoinRoutes: [
      for (final r in (j['family_join_routes'] as List?) ?? ['text']) r as String,
    ],
  );
}

/// `GET /me`, from the phone first.
class MeController extends CachedRead<MeInfo> {
  MeController(ApiClient api, CacheStore cache, {super.refreshOn}) : super(api, cache, '/me', MeInfo.fromJson);

  MeInfo? get me => data;
}
