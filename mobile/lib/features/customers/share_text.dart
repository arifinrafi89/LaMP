import 'package:share_plus/share_plus.dart';

/// Hands text to the phone's share sheet (SMS, WhatsApp, Messenger); on web,
/// the browser's. Tests record what would be shared.
typedef ShareText = Future<void> Function(String text);

Future<void> shareWithPhone(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
