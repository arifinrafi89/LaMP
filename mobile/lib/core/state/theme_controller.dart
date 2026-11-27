import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light or dark, chosen by the owner and kept between launches.
///
/// [ThemeMode.system] is "not chosen yet", which the app shows as light: a
/// phone read at a shop counter in daylight (see `app.dart`).
class ThemeController extends ChangeNotifier {
  static const String _key = 'lamp.themeMode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// The mode given here applies until a stored preference is read, and
  /// stays if there is none — tests use it to pin a theme.
  ThemeController([this._mode = ThemeMode.system]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      _mode = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => _mode,
      };
      notifyListeners();
    } catch (e) {
      // Storage unavailable is not an error worth surfacing: the app keeps
      // its default until the next launch.
      debugPrint('ThemeController: could not read the stored mode ($e)');
    }
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (e) {
      debugPrint('ThemeController: could not save the mode ($e)');
    }
  }
}
