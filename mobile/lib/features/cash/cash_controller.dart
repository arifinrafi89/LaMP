import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'cash_models.dart';

/// `GET /pharmacies/{pid}/forecast`, from the phone first.
class CashController extends CachedRead<Forecast> {
  CashController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super(api, cache, '/pharmacies/$pid/forecast', Forecast.fromJson);

  Forecast? get forecast => data;
}
