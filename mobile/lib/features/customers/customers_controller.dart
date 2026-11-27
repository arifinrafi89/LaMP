import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/digits.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'customers_models.dart';

/// The version of the words the owner reads to the family before typing
/// their number (plan 3.4 route 2). Sent with the consent so the server
/// records which words were agreed to.
const familyConsentVersion = 'family_sms_v1';

/// `GET /pharmacies/{pid}/customers`, from the phone first.
class CustomersController extends CachedRead<CustomerList> {
  CustomersController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super.list(api, cache, '/pharmacies/$pid/customers', CustomerList.fromJson);

  CustomerList? get customers => data;
}

/// Every change to a customer. Each one goes to the server, then [onSaved]
/// rings so the list (and Today) read again. Money changes take the sheet's
/// own Idempotency-Key, so tapping Save again after a failure can't record
/// a sale or payment twice.
class CustomerActions {
  CustomerActions(this._api, String pid, {VoidCallback? onSaved})
    : _base = '/pharmacies/$pid/customers',
      _onSaved = onSaved;

  final ApiClient _api;
  final String _base;
  final VoidCallback? _onSaved;

  Future<T> _saved<T>(T value) async {
    _onSaved?.call();
    return value;
  }

  static Map<String, dynamic> _map(Object? j) => j as Map<String, dynamic>;

  Future<CustomerCreated> add({required double amount, required DateTime since, required String key}) async {
    final j = await _api.post(_base, {'amount': amount, 'since': apiDate(since)}, idempotencyKey: key);
    return _saved(CustomerCreated.fromJson(_map(j)));
  }

  /// Returns what they owe now.
  Future<double> sale(String code, {required double amount, required DateTime on, required String key}) async {
    final j = await _api.post('$_base/$code/sales', {'amount': amount, 'on': apiDate(on)}, idempotencyKey: key);
    return _saved((_map(j)['amount'] as num).toDouble());
  }

  /// Returns what they owe now.
  Future<double> payment(
    String code, {
    required double amount,
    required DateTime on,
    required String method,
    required String key,
  }) async {
    final j = await _api.post('$_base/$code/payments', {
      'amount': amount,
      'on': apiDate(on),
      'method': method,
    }, idempotencyKey: key);
    return _saved((_map(j)['amount'] as num).toDouble());
  }

  /// The ways to pay, split by the server.
  Future<PlanChoices> choices(String code) async => PlanChoices.fromJson(_map(await _api.get('/cards/$code')));

  Future<void> setPlan(String code, {required int parts, required DateTime firstOn}) async {
    await _api.put('$_base/$code/plan', {'parts': parts, 'first_on': apiDate(firstOn)});
    return _saved(null);
  }

  /// Counter route only (plan 3.4 route 2). [phone] is `+8801…`.
  Future<SmsStatus> addPhone(String code, {required String phone, required String language}) async {
    final j = await _api.post('$_base/$code/phone', {
      'phone': phone,
      'language': language,
      'consent': {'agreed': true, 'wording_version': familyConsentVersion},
    });
    return _saved(SmsStatus.parse(_map(j)['sms_status']));
  }

  Future<SmsStatus> stopSms(String code) async =>
      _saved(SmsStatus.parse(_map(await _api.delete('$_base/$code/phone'))['sms_status']));

  /// One reminder now; the server allows one a day.
  Future<SmsStatus> remind(String code) async =>
      _saved(SmsStatus.parse(_map(await _api.post('$_base/$code/remind', null))['sms_status']));
}
