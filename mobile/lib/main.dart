import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

void main() {
  // Web addresses without "#": /customers/GL-7KQM-4XPA, and a family's
  // /me/<code> link (plan 5.2). Does nothing on Android.
  usePathUrlStrategy();
  runApp(const LampApp());
}
