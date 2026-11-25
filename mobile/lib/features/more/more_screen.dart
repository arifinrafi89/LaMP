import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/palette.dart';
import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/ui/lamp_ui.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.tabMore)),
      body: ListView(
        padding: const EdgeInsets.all(Gap.lg),
        children: [
          LampCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final d in moreDestinations)
                  LampRow(
                    icon: d.icon,
                    title: d.title(l),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(d.path),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
