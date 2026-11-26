import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/account_preferences_target.dart';
import '../../services/settings_service.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/backend_badge.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import '../libraries/state_messages.dart';
import 'account_preferences_detail_screen.dart';

/// Entry point for the Account preferences section: the preferences that live
/// on a media-server account rather than on this device.
///
/// With one account a picker would be a single row in front of the only
/// destination there is, so that account's rows are rendered here instead. With
/// several, the account has to be chosen first — a Plex profile and a Jellyfin
/// user store entirely separate values.
class AccountPreferencesScreen extends StatelessWidget {
  final List<AccountPreferenceTarget> targets;

  final AccountSettingsGroup group;
  const AccountPreferencesScreen({super.key, required this.targets, this.group = AccountSettingsGroup.all});

  @override
  Widget build(BuildContext context) {
    final title = Text(switch (group) {
      AccountSettingsGroup.tracks => t.viewerSettings.languages,
      AccountSettingsGroup.library => t.viewerSettings.libraryPreferences,
      AccountSettingsGroup.all => t.accountPreferences.sectionTitle,
    });

    if (targets.isEmpty) {
      return SettingsPage.slivers(
        profileLayout: true,
        title: title,
        slivers: [
          if (group == AccountSettingsGroup.tracks) const SliverToBoxAdapter(child: TrackSelectionSettings()),
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Symbols.account_circle_rounded,
              message: t.accountPreferences.noAccounts,
              subtitle: t.accountPreferences.noAccountsHint,
            ),
          ),
        ],
      );
    }

    if (targets.length == 1) {
      return SettingsPage.slivers(
        profileLayout: true,
        title: title,
        slivers: [
          AccountPreferencesBody(key: ValueKey(targets.first.ref), target: targets.first, group: group),
          if (group == AccountSettingsGroup.tracks) const SliverToBoxAdapter(child: TrackSelectionSettings()),
        ],
      );
    }

    final theme = Theme.of(context);

    return SettingsPage(
      profileLayout: true,
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            t.accountPreferences.pickAccount,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        SettingsGroup(
          children: [
            for (final target in targets)
              FocusableListTile(
                key: ValueKey(target.ref.key),
                leading: BackendBadge(backend: target.backend, size: 24),
                title: Text(target.label),
                subtitle: target.subtitle != null ? Text(target.subtitle!) : null,
                trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountPreferencesDetailScreen(target: target, group: group),
                  ),
                ),
              ),
          ],
        ),
        if (group == AccountSettingsGroup.tracks) const TrackSelectionSettings(),
        const SizedBox(height: 24),
      ],
    );
  }
}

class TrackSelectionSettings extends StatelessWidget {
  const TrackSelectionSettings({super.key});

  @override
  Widget build(BuildContext context) => SettingsGroup(
    title: t.viewerSettings.trackSelection,
    children: [
      SettingSwitchTile(
        pref: SettingsService.rememberTrackSelections,
        icon: Symbols.bookmark_rounded,
        title: t.settings.rememberTrackSelections,
        subtitle: '${t.settings.rememberTrackSelectionsDescription} · ${t.settings.rememberTrackSelectionsBackendRule}',
      ),
      SettingSwitchTile(
        pref: SettingsService.followServerTrackSelections,
        icon: Symbols.dns_rounded,
        title: t.settings.followServerTrackSelections,
        subtitle: t.settings.followServerTrackSelectionsDescription,
      ),
    ],
  );
}
