import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/api/api_config.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/lamp_auth_service.dart';
import 'core/auth/token_store.dart';
import 'core/constants/app_theme.dart';
import 'core/constants/palette.dart';
import 'core/offline/cache_store.dart';
import 'core/router.dart';
import 'core/state/locale_controller.dart';
import 'core/state/session_controller.dart';
import 'core/state/shop_changes.dart';
import 'core/state/theme_controller.dart';
import 'features/customers/share_text.dart';
import 'features/scan/photo_prep.dart';
import 'features/scan/photo_source.dart';
import 'l10n/app_localizations.dart';

/// The owner's app: providers, router, theme and language.
class LampApp extends StatefulWidget {
  const LampApp({
    super.key,
    this.session,
    this.initialLocation = '/today',
    this.locale,
    this.httpClient,
    this.photoSource,
    this.shrinkPhoto,
    this.cache,
    this.shareText,
    this.shareFile,
  });

  /// Injected by tests; built against the real server otherwise.
  final SessionController? session;
  final String initialLocation;

  /// Pins the language (tests). Null: the stored choice, else the phone's.
  final Locale? locale;

  /// The transport under every [ApiClient]; tests serve fixtures through it.
  final http.Client? httpClient;

  /// Camera, gallery and files; tests give a fake.
  final PhotoSource? photoSource;

  /// Makes a photo ready to send; tests skip the isolate.
  final ShrinkPhoto? shrinkPhoto;

  /// The offline cache; tests keep it in memory.
  final CacheStore? cache;

  /// The share sheet; tests record what is shared.
  final ShareText? shareText;

  /// Sharing a file (the credit record's PDF); tests record it.
  final ShareFile? shareFile;

  @override
  State<LampApp> createState() => _LampAppState();
}

class _LampAppState extends State<LampApp> {
  final _theme = ThemeController();
  late final _locale = LocaleController(widget.locale);
  late final ApiClient _api;
  late final SessionController _session;
  late final GoRouter _router;
  late final PhotoSource _photos = widget.photoSource ?? DevicePhotoSource();
  late final CacheStore _cache = widget.cache ?? HiveCacheStore();
  final _changes = ShopChanges();

  @override
  void initState() {
    super.initState();
    final injected = widget.session;
    if (injected != null) {
      _session = injected;
      _api = _client(refresh: _session.refreshNow);
    } else {
      // The auth calls get their own client that never refreshes: the
      // refresh call must not trigger another refresh.
      _session = SessionController(
        auth: LampAuthService(_client(refresh: () async => false)),
        store: SecureTokenStore(),
        device: _device,
        cookieRefresh: kIsWeb,
      );
      _api = _client(refresh: _session.refreshNow);
    }
    _router = buildRouter(session: _session, initialLocation: widget.initialLocation);
    _session.addListener(_forgetOnSignOut);
    if (_session.status == SessionStatus.restoring) _session.restore();
  }

  /// Signed out, by choice or because the session ended: what the phone kept
  /// for this shop goes too, so the next owner on this phone never sees it.
  void _forgetOnSignOut() {
    if (_session.status == SessionStatus.signedOut) _cache.clear();
  }

  ApiClient _client({required Future<bool> Function() refresh}) => ApiClient(
        baseUrl: lampApiUrl,
        appVersion: lampAppVersion,
        language: () => _locale.languageFor(null),
        accessToken: () => _session.accessToken,
        refresh: refresh,
        http: widget.httpClient,
      );

  static Future<DeviceInfo> _device() async {
    const key = 'lamp.deviceId';
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(key);
    if (id == null) {
      id = newUuid();
      await prefs.setString(key, id);
    }
    return DeviceInfo(
      id: id,
      name: kIsWeb ? 'Web browser' : 'Android phone',
      os: kIsWeb ? 'web' : defaultTargetPlatform.name,
      appVersion: lampAppVersion,
    );
  }

  @override
  void dispose() {
    _session.removeListener(_forgetOnSignOut);
    _router.dispose();
    _theme.dispose();
    _changes.dispose();
    _locale.dispose();
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _theme),
        ChangeNotifierProvider.value(value: _locale),
        ChangeNotifierProvider.value(value: _session),
        Provider.value(value: _api),
        Provider<PhotoSource>.value(value: _photos),
        Provider<CacheStore>.value(value: _cache),
        ChangeNotifierProvider<ShopChanges>.value(value: _changes),
        Provider<ShrinkPhoto>.value(value: widget.shrinkPhoto ?? shrinkPhotoInBackground),
        Provider<ShareText>.value(value: widget.shareText ?? shareWithPhone),
        Provider<ShareFile>.value(value: widget.shareFile ?? shareFileWithPhone),
      ],
      child: Consumer2<ThemeController, LocaleController>(
        builder: (context, theme, locale, _) => MaterialApp.router(
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          locale: locale.locale,
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
                textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}
