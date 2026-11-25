import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../focus/focusable_action_bar.dart';
import '../media/media_library.dart';
import '../navigation/navigation_tabs.dart';
import '../utils/desktop_window_padding.dart';
import 'app_icon.dart';
import 'app_menu.dart';

/// Home supplies its existing profile and session controls to the shell's header.
typedef DesktopHomeHeaderBuilder = Widget Function(Widget actions);

class DesktopRemoteHeaderBridge extends InheritedWidget {
  const DesktopRemoteHeaderBridge({super.key, required this.focusUtilities, required super.child});
  final VoidCallback focusUtilities;
  static DesktopRemoteHeaderBridge? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DesktopRemoteHeaderBridge>();
  @override
  bool updateShouldNotify(DesktopRemoteHeaderBridge oldWidget) => focusUtilities != oldWidget.focusUtilities;
}

class DesktopNavigationBar extends StatefulWidget {
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
    this.remoteNavigation = false,
    this.remoteHomeFocusNode,
    this.onNavigateDown,
  });

  final List<NavigationTab> tabs;
  final NavigationTabId selected;
  final List<MediaLibrary> libraries;
  final String? selectedLibraryKey;
  final ValueChanged<String> onSelectLibrary;
  final ValueChanged<NavigationTabId> onSelect;
  final VoidCallback onMenu;
  final Widget? homeActions;
  final bool remoteNavigation;
  final FocusNode? remoteHomeFocusNode;
  final VoidCallback? onNavigateDown;

  @override
  State<DesktopNavigationBar> createState() => _DesktopNavigationBarState();
}

class _DesktopNavigationBarState extends State<DesktopNavigationBar> {
  final primaryKey = GlobalKey<FocusableActionBarState>();
  final utilityKey = GlobalKey<FocusableActionBarState>();
  final libraryMenuKey = GlobalKey<AppMenuButtonState<VoidCallback>>();
  List<NavigationTab> get tabs => widget.tabs;
  NavigationTabId get selected => widget.selected;
  List<MediaLibrary> get libraries => widget.libraries;
  String? get selectedLibraryKey => widget.selectedLibraryKey;
  ValueChanged<String> get onSelectLibrary => widget.onSelectLibrary;
  ValueChanged<NavigationTabId> get onSelect => widget.onSelect;
  VoidCallback get onMenu => widget.onMenu;
  Widget? get homeActions => widget.homeActions;
  bool get remoteNavigation => widget.remoteNavigation;
  FocusNode? get remoteHomeFocusNode => widget.remoteHomeFocusNode;
  VoidCallback? get onNavigateDown => widget.onNavigateDown;
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

  Widget _destinations(BuildContext context, {VoidCallback? onNavigateRight, GlobalKey<FocusableActionBarState>? remoteKey}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurface,
      fontSize: 14,
      fontWeight: .w400,
      letterSpacing: -0.15,
    );
    final primaryTabs = tabs.where((tab) => !_utilities.contains(tab.id)).toList();
    if (primaryTabs.isEmpty) return const SizedBox.shrink();
    if (remoteNavigation) {
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
              child: FocusableActionBar(
                key: remoteKey,
                onNavigateLeft: primaryTabs.first.id == NavigationTabId.discover ? onMenu : null,
                onNavigateDown: onNavigateDown,
                onNavigateRight: onNavigateRight,
                actions: [
                  for (final tab in primaryTabs)
                    FocusableAction(
                      debugLabel: 'desktop_remote_${tab.id.name}',
                      focusNode: tab.id == primaryTabs.first.id ? remoteHomeFocusNode : null,
                      onPressed: tab.id == NavigationTabId.libraries
                          ? () { libraryMenuKey.currentState?.showButtonMenu(); }
                          : () => onSelect(tab.id),
                      builder: (context, state) => Material(
                        color: state.showFocus
                            ? colors.inverseSurface
                            : selected == tab.id ? colors.onSurface.withValues(alpha: 0.14) : Colors.transparent,
                        shape: const StadiumBorder(),
                        child: tab.id == NavigationTabId.libraries
                            ? AppMenuButton<VoidCallback>(
                                key: libraryMenuKey,
                                tooltip: t.libraries.selectLibrary,
                                entriesBuilder: _libraryEntries,
                                onSelected: (select) => select(),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(tab.getLabel(), style: state.showFocus ? style.copyWith(color: colors.onInverseSurface) : style),
                                    const SizedBox(width: 4),
                                    AppIcon(Symbols.expand_more_rounded, size: 16, color: state.showFocus ? colors.onInverseSurface : colors.onSurface),
                                  ]),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Text(tab.getLabel(), style: state.showFocus ? style.copyWith(color: colors.onInverseSurface) : style),
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
    final utilityTabs = [for (final id in [NavigationTabId.search, NavigationTabId.downloads, NavigationTabId.settings]) ...tabs.where((tab) => tab.id == id)];
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
                      canRequestFocus: !remoteNavigation,
                      onTap: onMenu,
                      customBorder: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/gucciplexa-mark.png',
                              width: 26,
                              height: 26,
                              excludeFromSemantics: true,
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
                  Expanded(child: _destinations(context, remoteKey: primaryKey, onNavigateRight: () => utilityKey.currentState?.requestFocusOnFirst())),
                  if (remoteNavigation)
                    FocusableActionBar(
                      key: utilityKey,
                      onNavigateLeft: () {
                        final count = tabs.where((tab) => !_utilities.contains(tab.id)).length;
                        primaryKey.currentState?.getFocusNode(count - 1)?.requestFocus();
                      },
                      onNavigateDown: onNavigateDown,
                      onNavigateRight: homeActions == null ? null : () {
                        final action = utilityKey.currentState?.getFocusNode(utilityTabs.length - 1);
                        action?.focusInDirection(TraversalDirection.right);
                      },
                      actions: [
                        for (final tab in utilityTabs)
                          FocusableAction(debugLabel: 'desktop_utility_${tab.id.name}', icon: tab.icon, iconSize: 20, iconFill: 0, tooltip: tab.getLabel(), onPressed: () => onSelect(tab.id)),
                      ],
                    ),
                  if (!remoteNavigation)
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
                  if (homeActions != null) ...[
                    const SizedBox(width: 6),
                    if (remoteNavigation)
                      DesktopRemoteHeaderBridge(
                        focusUtilities: () => utilityKey.currentState?.getFocusNode(utilityTabs.length - 1)?.requestFocus(),
                        child: homeActions!,
                      )
                    else homeActions!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
