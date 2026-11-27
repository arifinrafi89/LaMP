import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';

/// The price the owner agrees to, as the consent records it (plan 3.3).
const plusPriceText = 'BDT 50 a month + VAT';

/// The version of the consent words on the Plus screen.
const plusConsentVersion = 'plus_v1';

/// Where the owner's LaMP Plus stands (plan 3.3).
enum PlusStatus {
  none,

  /// Agreed; Banglalink sent a code to the owner's phone.
  otpSent,

  /// Waiting for Banglalink to confirm.
  pending,
  active,

  /// The renewal couldn't be charged (low balance).
  blocked,
  stopped;

  static PlusStatus parse(Object? v) => switch (v) {
    'OTP_SENT' => otpSent,
    'PENDING' => pending,
    'ACTIVE' => active,
    'BLOCKED' => blocked,
    'STOPPED' => stopped,
    _ => none,
  };
}

class PlusState {
  const PlusState(this.status, this.renewsOn);

  final PlusStatus status;
  final DateTime? renewsOn;

  factory PlusState.fromJson(Map<String, dynamic> j) =>
      PlusState(PlusStatus.parse(j['status']), DateTime.tryParse((j['renews_on'] as String?) ?? ''));
}

/// `GET /pharmacies/{pid}/plus`, from the phone first.
class PlusController extends CachedRead<PlusState> {
  PlusController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super(api, cache, '/pharmacies/$pid/plus', PlusState.fromJson);

  PlusState? get plus => data;
}

/// Subscribe, confirm with the code, cancel. Each change rings [onSaved], so
/// `/me` reads again and the Plus screens unlock or lock at once.
class PlusActions {
  PlusActions(this._api, String pid, {VoidCallback? onSaved}) : _base = '/pharmacies/$pid/plus', _onSaved = onSaved;

  final ApiClient _api;
  final String _base;
  final VoidCallback? _onSaved;

  Future<PlusState> _saved(Object? j) async {
    _onSaved?.call();
    return PlusState.fromJson(j as Map<String, dynamic>);
  }

  /// The owner tapped Agree: the consent, then a code on the Plus app.
  Future<PlusState> subscribe() async => _saved(
    await _api.post('$_base/subscribe', {
      'consent': {'price_text': plusPriceText, 'wording_version': plusConsentVersion},
    }),
  );

  Future<PlusState> confirm(String otp) async => _saved(await _api.post('$_base/otp', {'otp': otp}));

  Future<PlusState> cancel() async => _saved(await _api.post('$_base/cancel', null));
}
