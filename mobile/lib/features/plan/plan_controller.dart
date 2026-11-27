import '../../core/api/api_client.dart';
import '../../core/offline/cache_store.dart';
import '../../core/offline/cached_read.dart';
import 'plan_models.dart';

/// `POST /pharmacies/{pid}/funding-plan` with no body: the server's plan for
/// the next short day. Contract v1 has no GET for it; kept on the phone like
/// any read.
class PlanController extends CachedRead<MoneyPlan> {
  PlanController(ApiClient api, CacheStore cache, String pid, {super.refreshOn})
    : super(
        api,
        cache,
        '/pharmacies/$pid/funding-plan',
        MoneyPlan.fromJson,
        fetch: () => api.post('/pharmacies/$pid/funding-plan', null),
      );

  MoneyPlan? get plan => data;
}
