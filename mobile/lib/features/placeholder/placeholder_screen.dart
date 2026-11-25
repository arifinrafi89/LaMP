import 'package:material_ui/material_ui.dart';

import '../../core/constants/palette.dart';
import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_ui.dart';

/// Stands in for a screen until its task lands (plan section 7).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.destination});

  final LampDestination destination;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final title = destination.title(l);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: LampEmpty(
          icon: destination.icon,
          title: title,
          message: l.screenComingSoon,
        ),
      ),
    );
  }
}
