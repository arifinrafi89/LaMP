import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Web: the browser's fetch, because http's browser client holds a streamed
/// answer until it ends (plan 5.3). `cors` keeps responses readable (the
/// default `noCors` hides them); the refresh cookie still goes same-origin.
http.Client makeHttpClient() => FetchClient(mode: RequestMode.cors);
