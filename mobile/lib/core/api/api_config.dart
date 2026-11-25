import 'package:flutter/foundation.dart';

/// Where the server is, per build (plan 5.8):
/// `flutter build apk --dart-define=LAMP_API_URL=https://lamp-api.onrender.com/api/v1`.
///
/// Left unset, web uses `/api/v1` on its own origin (the static site rewrites
/// `/api/*` to the API, plan 2.1) and Android uses the production service.
const _fromBuild = String.fromEnvironment('LAMP_API_URL');

String get lampApiUrl {
  if (_fromBuild.isNotEmpty) return _fromBuild;
  return kIsWeb ? '/api/v1' : 'https://lamp-api.onrender.com/api/v1';
}

/// Sent as `X-App-Version`; the server answers 426 below its minimum.
const lampAppVersion = String.fromEnvironment('LAMP_APP_VERSION', defaultValue: '0.1.0+1');
