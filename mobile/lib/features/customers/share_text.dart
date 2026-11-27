import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands text to the phone's share sheet (SMS, WhatsApp, Messenger); on web,
/// the browser's. Tests record what would be shared.
typedef ShareText = Future<void> Function(String text);

Future<void> shareWithPhone(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}

/// Hands a file to the share sheet (save it, or send it by WhatsApp or email).
typedef ShareFile = Future<void> Function(Uint8List bytes, String name, String mimeType);

Future<void> shareFileWithPhone(Uint8List bytes, String name, String mimeType) async {
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: mimeType)]));
}
