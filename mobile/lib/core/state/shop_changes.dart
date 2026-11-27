import 'package:material_ui/material_ui.dart';

/// Rings when something the owner saved changes the shop's figures (a bill
/// confirmed in Scan), so screens kept alive in other tabs, such as Today
/// and Stock, read theirs again instead of showing the old ones.
class ShopChanges extends ChangeNotifier {
  void saved() => notifyListeners();
}
