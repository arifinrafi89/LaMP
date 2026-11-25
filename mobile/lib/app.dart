import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_theme.dart';
import 'core/constants/palette.dart';
import 'core/router.dart';
import 'core/state/theme_controller.dart';
import 'l10n/app_localizations.dart';

/// The owner's app: providers, router, theme and language.
class LampApp extends StatefulWidget {
  const LampApp({super.key, this.initialLocation = '/today', this.locale});

  final String initialLocation;

  /// Null follows the phone's language (Bangla or English, else English).
  final Locale? locale;

  @override
  State<LampApp> createState() => _LampAppState();
}

class _LampAppState extends State<LampApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);
  final _theme = ThemeController();

  @override
  void dispose() {
    _router.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _theme,
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp.router(
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          locale: widget.locale,
          supportedLocales: L10n.supportedLocales,
          // material_ui carries its own Material localizations; the generated
          // L10n.localizationsDelegates would pull in the deprecated ones.
          // `delegates` (plural) brings the matching Cupertino and widgets ones.
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          // The field world: light by default, for a phone read at a shop
          // counter in daylight. Dark only when the owner picks it.
          themeMode: theme.mode == ThemeMode.system ? ThemeMode.light : theme.mode,
          theme: LaMPTheme.build(LampWorld.field, Brightness.light),
          darkTheme: LaMPTheme.build(LampWorld.field, Brightness.dark),
          builder: (context, child) {
            // Text may grow to 1.3x (plan 5.8); the layout test checks it.
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: media.textScaler.clamp(
                  minScaleFactor: 0.9,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}
