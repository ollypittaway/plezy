import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile_avatar.dart';
import '../../services/settings_service.dart';
import '../../services/announcement_service.dart';
import '../../services/viewer_settings_sync.dart';
import '../../theme/mono_theme.dart';
import '../../widgets/profile_settings_layout.dart';
import '../profile/profile_switch_screen.dart';

class ViewerSettingsBody extends StatelessWidget {
  const ViewerSettingsBody({super.key, required this.onPair});
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final profiles = context.watch<ActiveProfileProvider>();
    final viewer = profiles.active;
    final panel = context.watch<AnnouncementService?>();
    final sync = context.watch<ViewerSettingsSync?>();
    final theme = Theme.of(context);
    final strings = t.viewerSettings;
    final settings = SettingsService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(strings.myProfile, style: theme.textTheme.titleMedium),
        ),
        _Row(
          label: strings.viewer,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              ProfileAvatar(
                profile: viewer,
                size: 36,
                avatarUrl: viewer == null ? null : profiles.avatarUrlFor(viewer.id),
              ),
              if (viewer != null) Text(viewer.displayName),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
                child: Text(t.screens.switchProfile),
              ),
            ],
          ),
        ),
        _Row(
          label: strings.accent,
          hint: strings.accentHint,
          child: ValueListenableBuilder(
            valueListenable: settings.listenable(SettingsService.viewerAccent),
            builder: (context, selected, _) => Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                for (final accent in [null, ...ViewerAccent.values])
                  Builder(
                    builder: (context) {
                      final id = accent?.name ?? 'default';
                      final label = switch (accent) {
                        null => strings.themeDefault,
                        ViewerAccent.teal => strings.teal,
                        ViewerAccent.blue => strings.blue,
                        ViewerAccent.violet => strings.violet,
                        ViewerAccent.rose => strings.rose,
                        ViewerAccent.amber => strings.amber,
                      };
                      final color = accent?.forBrightness(theme.brightness) ?? theme.colorScheme.onSurface;
                      return Semantics(
                        selected: selected == id,
                        child: IconButton(
                          tooltip: label,
                          onPressed: () => settings.write(SettingsService.viewerAccent, id),
                          icon: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent == null ? null : color,
                              border: Border.all(color: color),
                            ),
                            child: selected == id
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: accent == null
                                        ? color
                                        : ThemeData.estimateBrightnessForColor(color) == Brightness.light
                                        ? Colors.black
                                        : Colors.white,
                                  )
                                : accent == null
                                ? Icon(Icons.contrast, size: 16, color: color)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        _Row(
          label: strings.sync,
          hint: strings.syncDescription,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sync?.enabled == true
                    ? sync!.busy
                          ? strings.syncing
                          : sync.failed
                          ? strings.retry
                          : sync.synced
                          ? strings.upToDate
                          : strings.localOnly
                    : strings.localOnly,
              ),
              if (panel?.url == null && panel?.automaticPairing == true)
                Text(panel!.status ?? t.announcements.connecting)
              else if (sync?.panel.url == null)
                TextButton(onPressed: onPair, child: Text(strings.pair))
              else if (sync?.available != true)
                Text(strings.plexRequired)
              else
                Wrap(
                  children: [
                    if (sync!.enabled)
                      TextButton(onPressed: sync.busy ? null : sync.sync, child: Text(strings.syncNow)),
                    TextButton(
                      onPressed: () async {
                        if (sync.enabled) {
                          await sync.setEnabled(false);
                          return;
                        }
                        final host = sync.panel.url;
                        final approved = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(strings.sync),
                            content: Text(strings.consent(host: host!.authority)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(strings.enable)),
                            ],
                          ),
                        );
                        if (approved == true && context.mounted && sync.panel.url == host) await sync.setEnabled(true);
                      },
                      child: Text(sync.enabled ? strings.disable : strings.enable),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.hint});
  final String label;
  final String? hint;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        if (hint != null)
          Text(hint!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: SettingsColumns(label: title, detail: child),
        ),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }
}
