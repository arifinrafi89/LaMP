import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app: the export's download, the terms, the
/// Play page. Tests record what would be opened.
typedef OpenLink = Future<bool> Function(Uri uri);

Future<bool> openWithPhone(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
