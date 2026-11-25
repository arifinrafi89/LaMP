import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/constants/palette.dart';
import '../core/state/theme_controller.dart';
import '../l10n/app_localizations.dart';

/// Cycles light → dark → follow the phone.
///
/// The icon shows the mode that is *in force*, not the one a tap would move to,
/// and the tooltip names it — an icon alone cannot distinguish "dark because
/// you chose dark" from "dark because your phone is".
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    final c = context.lamp;
    final l = L10n.of(context);
    final label = switch (controller.mode) {
      ThemeMode.system => l.themeDefault,
      ThemeMode.light => l.themeLight,
      ThemeMode.dark => l.themeDark,
    };

    return IconButton(
      tooltip: l.themeIs(label),
      icon: Icon(controller.icon, color: c.inkMuted),
      onPressed: () async {
        await controller.cycle();
        if (!context.mounted) return;
        final now = switch (controller.mode) {
          ThemeMode.system => l.themeDefault,
          ThemeMode.light => l.themeLight,
          ThemeMode.dark => l.themeDark,
        };
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(l.themeIs(now)),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      },
    );
  }
}
