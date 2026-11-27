import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'stock_models.dart';

/// Loads `GET /pharmacies/{pid}/expiry` for the Stock screen, from the phone
/// first when it has been read before.
class StockController extends CachedRead<StockExpiry> {
  StockController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
      : super(api, cache, '/pharmacies/$pid/expiry', StockExpiry.fromJson);

  StockExpiry? get expiry => data;
}
