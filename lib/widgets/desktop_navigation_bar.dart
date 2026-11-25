import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_library.dart';
import '../navigation/navigation_tabs.dart';
import '../utils/desktop_window_padding.dart';
import 'app_icon.dart';
import 'app_menu.dart';

/// Home supplies its existing profile and session controls to the shell's header.
typedef DesktopHomeHeaderBuilder = Widget Function(Widget actions);

class DesktopNavigationBar extends StatelessWidget {
  const DesktopNavigationBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.libraries,
    required this.selectedLibraryKey,
    required this.onSelectLibrary,
    required this.onSelect,
    required this.onMenu,
    this.homeActions,
  });

  final List<NavigationTab> tabs;
  final NavigationTabId selected;
  final List<MediaLibrary> libraries;
  final String? selectedLibraryKey;
  final ValueChanged<String> onSelectLibrary;
  final ValueChanged<NavigationTabId> onSelect;
  final VoidCallback onMenu;
  final Widget? homeActions;

  static const _utilities = {NavigationTabId.search, NavigationTabId.downloads, NavigationTabId.settings};

  List<AppMenuEntry<VoidCallback>> _libraryEntries(BuildContext context) {
    if (libraries.isEmpty) {
      return [AppMenuItem(label: t.common.viewAll, value: () => onSelect(NavigationTabId.libraries))];
    }
    final titleCounts = <String, int>{};
    for (final library in libraries) {
      titleCounts.update(library.title, (count) => count + 1, ifAbsent: () => 1);
    }
    return [
      for (final library in libraries)
        AppMenuItem(
          label: titleCounts[library.title]! > 1
              ? '${library.title} · ${library.serverName ?? library.serverId ?? library.id}'
              : library.title,
          selected: selected == NavigationTabId.libraries && selectedLibraryKey == library.globalKey,
          value: () => onSelectLibrary(library.globalKey),
        ),
    ];
  }

  Widget _destinations(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurface,
      fontSize: 14,
      fontWeight: .w400,
      letterSpacing: -0.15,
    );
    final primaryTabs = tabs.where((tab) => !_utilities.contains(tab.id));
    if (primaryTabs.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.scaffoldBackgroundColor.withValues(alpha: 0.68),
            shape: StadiumBorder(side: BorderSide(color: colors.onSurface.withValues(alpha: 0.14))),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tab in primaryTabs)
                  Semantics(
                    button: true,
                    selected: selected == tab.id,
                    child: Material(
                      color: selected == tab.id ? colors.onSurface.withValues(alpha: 0.14) : Colors.transparent,
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: tab.id == NavigationTabId.libraries
                          ? AppMenuButton<VoidCallback>(
                              tooltip: t.libraries.selectLibrary,
                              entriesBuilder: _libraryEntries,
                              onSelected: (select) => select(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(tab.getLabel(), maxLines: 1, style: style),
                                    const SizedBox(width: 4),
                                    const AppIcon(Symbols.expand_more_rounded, weight: 400, size: 16),
                                  ],
                                ),
                              ),
                            )
                          : InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: () => onSelect(tab.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Text(tab.getLabel(), maxLines: 1, style: style),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final floating = homeActions != null;
    final background = theme.scaffoldBackgroundColor;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: floating ? null : background,
          gradient: floating
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [background.withValues(alpha: 0.85), background.withValues(alpha: 0)],
                )
              : null,
        ),
        child: SafeArea(
          bottom: false,
          child: DesktopTitleBarPadding(
            reserveWindowControls: true,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width >= 1200 ? 26 : 12, vertical: 10),
              child: Row(
                children: [
                  Tooltip(
                    message: t.settings.navigation,
                    child: InkWell(
                      onTap: onMenu,
                      customBorder: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            SvgPicture.asset(
                              'assets/plezy.svg',
                              width: 23,
                              height: 26,
                              colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              t.app.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: .w500,
                                fontSize: 20,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _destinations(context)),
                  for (final tab in tabs.where((tab) => _utilities.contains(tab.id)))
                    Semantics(
                      label: tab.getLabel(),
                      selected: tab.id == selected,
                      child: IconButton(
                        onPressed: () => onSelect(tab.id),
                        tooltip: tab.getLabel(),
                        icon: AppIcon(
                          tab.icon,
                          size: 20,
                          fill: 0,
                          weight: 400,
                          color: tab.id == selected ? colors.primary : colors.onSurface,
                        ),
                      ),
                    ),
                  if (homeActions != null) ...[const SizedBox(width: 6), homeActions!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
