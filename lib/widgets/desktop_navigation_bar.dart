import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile_avatar.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../focus/focusable_action_bar.dart';
import '../media/media_library.dart';
import '../navigation/navigation_tabs.dart';
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/desktop_window_padding.dart';
import 'app_icon.dart';
import 'splash_logo.dart';
import '../screens/settings/announcement_settings_screen.dart';
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
    this.onOpenProfile,
    this.overlayArtwork = false,
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
  final VoidCallback? onOpenProfile;
  final bool overlayArtwork;
  final bool remoteNavigation;
  final FocusNode? remoteHomeFocusNode;
  final VoidCallback? onNavigateDown;

  @override
  State<DesktopNavigationBar> createState() => _DesktopNavigationBarState();
}

class _DesktopNavigationBarState extends State<DesktopNavigationBar> {
  final primaryKey = GlobalKey<FocusableActionBarState>();
  final utilityKey = GlobalKey<FocusableActionBarState>();
  final _profileActionsScope = FocusScopeNode(debugLabel: 'desktop_profile_actions');

  @override
  void dispose() {
    _profileActionsScope.dispose();
    super.dispose();
  }

  void _focusProfileActions() {
    // Home actions intentionally exclude traversal. Request their actual node
    // directly rather than relying on directional focus geometry.
    for (final node in _profileActionsScope.descendants) {
      if (node.debugLabel == 'desktop_header_refresh' && node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
  }
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
    final style = navigationPillLabelStyle(theme);
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
              shape: StadiumBorder(side: navigationPillOutline(colors)),
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
            shape: StadiumBorder(side: navigationPillOutline(colors)),
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
    final floating = homeActions != null || widget.overlayArtwork;
    final activeProvider = context.watch<ActiveProfileProvider?>();
    final profile = activeProvider?.active;
    final background = theme.scaffoldBackgroundColor;
    final utilities = <({String id, String label, IconData icon, VoidCallback open, bool selected})>[
      for (final id in [NavigationTabId.search, NavigationTabId.downloads, NavigationTabId.settings]) ...[
        if (id == NavigationTabId.settings)
          (id: 'notifications', label: t.announcements.title, icon: Symbols.notifications_rounded,
           open: () => AnnouncementSettingsScreen.open(context), selected: false),
        for (final tab in tabs.where((tab) => tab.id == id))
          (id: id.name, label: tab.getLabel(), icon: tab.icon, open: () => onSelect(id), selected: selected == id),
      ],
    ];
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
              padding: PageLayout.padding(context, top: 10, bottom: 10),
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
                            const OffstageMark(size: 26),
                            const SizedBox(width: 7),
                            OffstageWordmark(width: 77, color: theme.colorScheme.onSurface),
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
                      onNavigateRight: homeActions == null || remoteNavigation ? null : _focusProfileActions,
                      actions: [
                        for (final action in utilities)
                          FocusableAction(debugLabel: 'desktop_utility_${action.id}', icon: action.icon, iconSize: 20, iconFill: 0, tooltip: action.label, onPressed: action.open),
                        if (widget.onOpenProfile != null)
                          FocusableAction(
                            debugLabel: 'desktop_profile',
                            tooltip: t.profiles.sectionTitle,
                            onPressed: widget.onOpenProfile,
                            builder: (context, state) => Container(
                              width: 44, height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(tokens(context).radiusMd), border: Border.all(color: state.showFocus ? colors.primary : Colors.transparent, width: 2)),
                              child: profile == null
                                  ? const AppIcon(Symbols.account_circle_rounded, size: 30)
                                  : ProfileAvatar(profile: profile, size: 32, avatarUrl: activeProvider?.avatarUrlFor(profile.id), showLockBadge: false),
                            ),
                          ),
                      ],
                    ),
                  if (!remoteNavigation)
                  for (final action in utilities)
                    Semantics(
                      label: action.label,
                      selected: action.selected,
                      child: IconButton(
                        onPressed: action.open,
                        tooltip: action.label,
                        icon: AppIcon(
                          action.icon,
                          size: 20,
                          fill: 0,
                          weight: 400,
                          color: action.selected ? colors.primary : colors.onSurface,
                        ),
                      ),
                    ),
                  if (homeActions != null && !remoteNavigation) ...[
                    const SizedBox(width: 6),
                    if (remoteNavigation)
                      DesktopRemoteHeaderBridge(
                        focusUtilities: () => utilityKey.currentState?.getFocusNode(utilities.length - 1)?.requestFocus(),
                        child: FocusScope(node: _profileActionsScope, child: homeActions!),
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
