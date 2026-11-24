import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../navigation/navigation_tabs.dart';
import '../utils/desktop_window_padding.dart';
import 'app_icon.dart';

/// Primary desktop destinations. The menu opens the existing library rail,
/// including its server groups, offline reconnect and window controls.
class DesktopNavigationBar extends StatelessWidget {
  const DesktopNavigationBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onMenu,
  });

  final List<NavigationTab> tabs;
  final NavigationTabId selected;
  final ValueChanged<NavigationTabId> onSelect;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final utilityTabs = {NavigationTabId.search, NavigationTabId.downloads, NavigationTabId.settings};
    final browseTabs = tabs.where((tab) => !utilityTabs.contains(tab.id));
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: DesktopTitleBarPadding(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onMenu,
                tooltip: t.settings.navigation,
                icon: AppIcon(Symbols.menu_rounded, color: colors.primary),
              ),
              const SizedBox(width: 4),
              Text(t.app.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: .w800, letterSpacing: -0.8)),
              const SizedBox(width: 20),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: browseTabs.isEmpty
                      ? const SizedBox.shrink()
                      : DecoratedBox(
                          decoration: ShapeDecoration(
                            color: colors.surface,
                            shape: StadiumBorder(side: BorderSide(color: colors.outline)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Row(
                              children: [
                                for (final tab in browseTabs)
                                  Semantics(
                                    selected: tab.id == selected,
                                    child: TextButton(
                                      onPressed: () => onSelect(tab.id),
                                      style: TextButton.styleFrom(
                                        foregroundColor: tab.id == selected
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                        backgroundColor: tab.id == selected
                                            ? colors.primary.withValues(alpha: 0.17)
                                            : null,
                                        shape: const StadiumBorder(),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                      ),
                                      child: Text(tab.getLabel()),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              for (final tab in tabs.where((tab) => utilityTabs.contains(tab.id)))
                Semantics(
                  selected: tab.id == selected,
                  child: IconButton(
                    onPressed: () => onSelect(tab.id),
                    tooltip: tab.getLabel(),
                    icon: AppIcon(tab.icon, color: tab.id == selected ? colors.primary : colors.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
