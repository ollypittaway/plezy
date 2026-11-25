import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_library.dart';
import '../navigation/navigation_tabs.dart';
import '../utils/desktop_window_padding.dart';
import '../utils/text_measure_cache.dart';
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
  static const _labelPadding = 12.0;

  Widget _destinations(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodyMedium!.copyWith(fontSize: 14, fontWeight: .w400, letterSpacing: -0.15);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double buttonWidth(String label) =>
        cachedSingleLineTextSize(
          label,
          style: style,
          textScaler: scaler,
          textDirection: direction,
        ).width.ceilToDouble() +
        _labelPadding * 2;

    final primaryTabs = tabs.where((tab) => !_utilities.contains(tab.id)).toList();
    if (primaryTabs.isEmpty) return const SizedBox.shrink();

    Widget link(String label, bool active, VoidCallback onTap) => Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? colors.onSurface.withValues(alpha: 0.14) : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _labelPadding, vertical: 8),
            child: Text(label, maxLines: 1, style: style.copyWith(color: colors.onSurface)),
          ),
        ),
      ),
    );

    final titleCounts = <String, int>{};
    for (final lib in libraries) {
      titleCounts.update(lib.title, (count) => count + 1, ifAbsent: () => 1);
    }
    String libraryLabel(MediaLibrary lib) =>
        titleCounts[lib.title]! > 1 ? '${lib.title} · ${lib.serverName ?? lib.serverId ?? lib.id}' : lib.title;

    // Keep Home and other top-level destinations available before budgeting
    // the remaining width for library names in the user's order.
    final available =
        constraints.maxWidth -
        8 -
        primaryTabs
            .where((tab) => tab.id != NavigationTabId.libraries)
            .fold(0.0, (width, tab) => width + buttonWidth(tab.getLabel()));
    final libraryWidths = [for (final lib in libraries) buttonWidth(libraryLabel(lib))];
    var directCount = libraries.length;
    if (libraryWidths.fold(0.0, (sum, width) => sum + width) > available) {
      var remaining = available - 40; // reserve the library picker button
      directCount = 0;
      for (final width in libraryWidths) {
        if (width > remaining) break;
        directCount++;
        remaining -= width;
      }
    }

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
                  if (tab.id != NavigationTabId.libraries || libraries.isEmpty)
                    link(tab.getLabel(), tab.id == selected, () => onSelect(tab.id))
                  else ...[
                    for (final lib in libraries.take(directCount))
                      link(
                        libraryLabel(lib),
                        selected == tab.id && selectedLibraryKey == lib.globalKey,
                        () => onSelectLibrary(lib.globalKey),
                      ),
                    if (directCount < libraries.length)
                      AppMenuButton<String>(
                        tooltip: t.libraries.selectLibrary,
                        entriesBuilder: (_) => [
                          for (final lib in libraries)
                            AppMenuItem(
                              value: lib.globalKey,
                              label: libraryLabel(lib),
                              selected: selected == tab.id && selectedLibraryKey == lib.globalKey,
                            ),
                        ],
                        onSelected: onSelectLibrary,
                        child: Semantics(
                          button: true,
                          label: t.libraries.selectLibrary,
                          selected:
                              selected == tab.id &&
                              libraries.skip(directCount).any((lib) => lib.globalKey == selectedLibraryKey),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (directCount == 0) Text(tab.getLabel(), style: style),
                                const AppIcon(Symbols.expand_more_rounded, weight: 400, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
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
                  Expanded(child: LayoutBuilder(builder: _destinations)),
                  for (final tab in tabs.where((tab) => _utilities.contains(tab.id)))
                    if (tab.id == NavigationTabId.search && width >= 1180)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Semantics(
                          selected: tab.id == selected,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(math.min(width * 0.14, 220), 36),
                              alignment: AlignmentDirectional.centerStart,
                              foregroundColor: colors.onSurface,
                              backgroundColor: background.withValues(alpha: 0.58),
                              side: BorderSide(color: colors.onSurface.withValues(alpha: 0.16)),
                              shape: const StadiumBorder(),
                              textStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: .w400),
                            ),
                            onPressed: () => onSelect(tab.id),
                            icon: const AppIcon(Symbols.search_rounded, weight: 400, size: 18),
                            label: Text(tab.getLabel()),
                          ),
                        ),
                      )
                    else
                      Semantics(
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
