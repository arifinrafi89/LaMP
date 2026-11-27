import 'package:http/http.dart' as http;

/// Android (and tests): http's own client, which streams.
http.Client makeHttpClient() => http.Client();
