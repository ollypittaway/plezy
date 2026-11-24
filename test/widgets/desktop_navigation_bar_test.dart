import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/desktop_navigation_bar.dart';

void main() {
  testWidgets('desktop header routes its visible destinations and opens the library menu', (tester) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    final selections = <NavigationTabId>[];
    var opened = false;
    Future<void> pump({required bool offline}) => tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: DesktopNavigationBar(
            tabs: NavigationTab.getVisibleTabs(isOffline: offline, hasLiveTv: true, hasExplore: true),
            selected: offline ? NavigationTabId.downloads : NavigationTabId.discover,
            onSelect: selections.add,
            onMenu: () => opened = true,
          ),
        ),
      ),
    );

    await pump(offline: false);
    await tester.tap(find.text(t.navigation.libraries));
    await tester.tap(find.byTooltip(t.common.search));
    await tester.tap(find.byTooltip(t.settings.navigation));
    expect(selections, [NavigationTabId.libraries, NavigationTabId.search]);
    expect(opened, isTrue);

    await pump(offline: true);
    expect(find.text(t.navigation.libraries), findsNothing);
    expect(find.byTooltip(t.common.search), findsNothing);
    await tester.tap(find.byTooltip(t.navigation.downloads));
    expect(selections.last, NavigationTabId.downloads);
  });
}
