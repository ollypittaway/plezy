import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/desktop_navigation_bar.dart';

void main() {
  testWidgets('desktop header opens named libraries, search and offline destinations', (tester) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const libraries = [
      MediaLibrary(id: '1', title: 'Film archive', serverId: 'a', backend: MediaBackend.plex),
      MediaLibrary(id: '2', title: 'TV series', serverId: 'a', backend: MediaBackend.plex),
    ];
    final selections = <NavigationTabId>[];
    final librarySelections = <String>[];
    var opened = false;
    Future<void> pump({required bool offline}) => tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: DesktopNavigationBar(
            tabs: NavigationTab.getVisibleTabs(isOffline: offline, hasLiveTv: true, hasExplore: true),
            selected: offline ? NavigationTabId.downloads : NavigationTabId.libraries,
            libraries: libraries,
            selectedLibraryKey: libraries.first.globalKey,
            onSelectLibrary: librarySelections.add,
            onSelect: selections.add,
            onMenu: () => opened = true,
          ),
        ),
      ),
    );

    await pump(offline: false);
    expect(find.text(t.navigation.libraries), findsNothing);
    expect(find.text('Film archive'), findsOneWidget);
    await tester.tap(find.text('TV series'));
    expect(librarySelections, [libraries.last.globalKey]);
    await tester.tap(find.text(t.common.search));
    await tester.tap(find.byTooltip(t.settings.navigation));
    expect(selections, [NavigationTabId.search]);
    expect(opened, isTrue);

    await pump(offline: true);
    expect(find.text('Film archive'), findsNothing);
    expect(find.text(t.common.search), findsNothing);
    await tester.tap(find.byTooltip(t.navigation.downloads));
    expect(selections.last, NavigationTabId.downloads);
  });

  testWidgets('overflow picker opens the correct library when server titles overlap', (tester) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    final libraries = [
      for (final server in ['North', 'South'])
        MediaLibrary(id: '1', title: 'Films', serverId: server, serverName: server, backend: MediaBackend.plex),
      for (var i = 1; i <= 16; i++)
        MediaLibrary(id: 'archive$i', title: 'Archive $i', serverId: 'North', backend: MediaBackend.plex),
    ];
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(
          body: DesktopNavigationBar(
            tabs: NavigationTab.getVisibleTabs(isOffline: false, hasExplore: true),
            selected: NavigationTabId.discover,
            libraries: libraries,
            selectedLibraryKey: null,
            onSelectLibrary: selected.add,
            onSelect: (_) {},
            onMenu: () {},
          ),
        ),
      ),
    );
    expect(find.text('Archive 16'), findsNothing);
    await tester.tap(find.byTooltip(t.libraries.selectLibrary));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Films · South').last);
    await tester.pumpAndSettle();
    expect(selected, [libraries[1].globalKey]);
    expect(tester.takeException(), isNull);
  });
}
