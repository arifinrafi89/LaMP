import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'today_models.dart';

/// Loads `GET /pharmacies/{pid}/today`: one call, made for slow networks,
/// shown from the phone first when it has been read before.
class TodayController extends CachedRead<TodaySummary> {
  TodayController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
      : super(api, cache, '/pharmacies/$pid/today', TodaySummary.fromJson);

  TodaySummary? get summary => data;
}
