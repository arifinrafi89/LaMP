import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';

/// Plan 5.2: bottom navigation Today · Scan · Customers · Ask · More, with
/// Stock, Cash, Plan, Approvals, Credit record, LaMP Plus, History, Settings
/// and Help under More. Web URLs match the routes.
void main() {
  Future<void> pumpApp(WidgetTester tester,
      {String at = '/today', Locale locale = const Locale('en')}) async {
    await pumpLamp(tester, session: await signedInSession(), at: at, locale: locale);
  }

  NavigationBar bar(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar));

  testWidgets('the bottom bar has the five tabs, Today first', (tester) async {
    await pumpApp(tester);
    for (final label in ['Today', 'Scan', 'Customers', 'Ask', 'More']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
          findsOneWidget);
    }
    expect(bar(tester).selectedIndex, 0);
  });

  testWidgets('tapping a tab opens its screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Customers')));
    await tester.pumpAndSettle();
    expect(bar(tester).selectedIndex, 2);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Customers')),
        findsOneWidget);
  });

  testWidgets('More lists the nine other screens', (tester) async {
    await pumpApp(tester, at: '/more');
    for (final label in [
      'Stock', 'Cash', 'Plan', 'Approvals', 'Credit record',
      'LaMP Plus', 'History', 'Settings', 'Help',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 100,
          scrollable: find.byType(Scrollable).last);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a screen under More keeps More selected', (tester) async {
    await pumpApp(tester, at: '/more');
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Stock')),
        findsOneWidget);
    expect(bar(tester).selectedIndex, 4);
  });

  testWidgets('a deep link opens the right tab', (tester) async {
    await pumpApp(tester, at: '/approvals');
    expect(bar(tester).selectedIndex, 4);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Approvals')),
        findsOneWidget);
  });

  testWidgets('Bangla labels in Bangla', (tester) async {
    await pumpApp(tester, locale: const Locale('bn'));
    expect(find.text('আজ'), findsWidgets);
    expect(find.text('ক্রেতা'), findsOneWidget);
  });

  testWidgets('light theme by default (field world)', (tester) async {
    await pumpApp(tester);
    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
