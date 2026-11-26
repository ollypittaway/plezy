import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../services/announcement_service.dart';
import '../../widgets/settings_page.dart';
import '../../focus/focusable_text_field.dart';

class AnnouncementSettingsScreen extends StatefulWidget {
  const AnnouncementSettingsScreen({super.key, this.embedded = false});
  final bool embedded;

  static void open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnnouncementSettingsScreen()));
  }

  @override
  State<AnnouncementSettingsScreen> createState() => _AnnouncementSettingsScreenState();
}

class _AnnouncementSettingsScreenState extends State<AnnouncementSettingsScreen> {
  final link = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      link.clear();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = t.announcements.connectionError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AnnouncementService>();
    final url = service.url;
    final profileId = context.watch<ActiveProfileProvider?>()?.activeId;
    final notices = service.visibleMessages(profileId);
    final feedback = error ?? service.status;
    final children = <Widget>[
      if (url == null || service.automaticPairing)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.announcements.automaticPairing),
          subtitle: Text(t.announcements.automaticHint),
          value: service.automaticPairing,
          onChanged: busy ? null : (value) => run(() => service.setAutomaticPairing(value)),
        ),
      if (url == null && !service.automaticPairing) ...[
        Text(t.announcements.pairHint),
        const SizedBox(height: 12),
        FocusableTextField(
          controller: link,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: t.announcements.link),
          onSubmitted: (_) => run(() => service.pair(link.text)),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : () => run(() => service.pair(link.text)),
            child: Text(t.announcements.pair),
          ),
        ),
      ] else if (url != null) ...[
        ListTile(
          title: Text(url.authority),
          subtitle: Text(t.announcements.connected),
          trailing: service.automaticPairing
              ? null
              : TextButton(
                  onPressed: busy ? null : () => run(service.disconnect),
                  child: Text(t.announcements.disconnect),
                ),
        ),
        if (service.supportsPush)
          SwitchListTile(
            title: Text(t.announcements.mobilePush),
            value: service.pushEnabled,
            subtitle: Text(service.pushAvailable ? t.announcements.background : t.announcements.configurePush),
            onChanged: busy || (!service.pushAvailable && !service.pushEnabled)
                ? null
                : (value) => run(() => service.setPush(value)),
          ),
        const Divider(),
        Row(
          children: [
            Expanded(child: Text(t.announcements.recent, style: Theme.of(context).textTheme.titleMedium)),
            if (notices.isNotEmpty)
              TextButton(
                onPressed: busy ? null : () => run(() => service.dismissMessages(profileId, notices.map((n) => n.id))),
                child: Text(t.libraries.clearAll),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: t.common.refresh,
              onPressed: busy ? null : () => run(service.refresh),
            ),
          ],
        ),
        if (notices.isEmpty) Text(t.announcements.empty),
        for (final notice in notices)
          ListTile(
            title: Text(notice.title),
            subtitle: Text(notice.body),
            trailing: IconButton(
              tooltip: '${t.common.clear} ${notice.title}',
              icon: const Icon(Icons.close),
              onPressed: busy ? null : () => run(() => service.dismissMessages(profileId, [notice.id])),
            ),
          ),
      ],
      if (feedback != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(feedback, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ];
    if (widget.embedded) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return SettingsPage(title: Text(t.announcements.title), padding: const EdgeInsets.all(20), children: children);
  }
}
