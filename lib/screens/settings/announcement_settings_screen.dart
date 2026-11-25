import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../services/announcement_service.dart';
import '../../widgets/settings_page.dart';

class AnnouncementSettingsScreen extends StatefulWidget {
  const AnnouncementSettingsScreen({super.key});

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
    final feedback = error ?? service.status;
    return SettingsPage(
      title: Text(t.announcements.title),
      padding: const EdgeInsets.all(20),
      children: [
        if (url == null) ...[
          Text(t.announcements.pairHint),
          const SizedBox(height: 12),
          TextField(
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
        ] else ...[
          ListTile(
            title: Text(url.authority),
            subtitle: Text(t.announcements.connected),
            trailing: TextButton(
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
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: t.common.refresh,
                onPressed: busy ? null : () => run(service.refresh),
              ),
            ],
          ),
          if (service.messages.isEmpty) Text(t.announcements.empty),
          for (final notice in service.messages) ListTile(title: Text(notice.title), subtitle: Text(notice.body)),
        ],
        if (feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(feedback, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
