import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's language: Bangla or English (plan 5.4). Null follows the phone.
/// Chosen on Welcome, changed later in Settings, kept between launches.
class LocaleController extends ChangeNotifier {
  LocaleController([this._locale]) {
    _load();
  }

  static const _key = 'lamp.locale';

  Locale? _locale;
  Locale? get locale => _locale;

  /// `bn` or `en` for the server's Accept-Language and the OTP SMS.
  String languageFor(BuildContext? context) {
    final code = _locale?.languageCode ??
        (context == null ? null : Localizations.maybeLocaleOf(context)?.languageCode);
    return code == 'bn' ? 'bn' : 'en';
  }

  Future<void> _load() async {
    if (_locale != null) return;
    try {
      final stored = (await SharedPreferences.getInstance()).getString(_key);
      if (stored == null) return;
      _locale = Locale(stored);
      notifyListeners();
    } catch (e) {
      debugPrint('LocaleController: could not read the language ($e)');
    }
  }

  Future<void> set(Locale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, locale.languageCode);
    } catch (e) {
      debugPrint('LocaleController: could not save the language ($e)');
    }
  }
}
