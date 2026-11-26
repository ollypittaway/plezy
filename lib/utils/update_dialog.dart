import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../services/update_service.dart';
import '../widgets/dialog_action_button.dart';
import 'dialogs.dart';

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  Map<String, dynamic> updateInfo, {
  required String title,
  required String dismissLabel,
  bool showSkipVersion = false,
}) {
  return showScopedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final latestVersion = updateInfo['latestVersion'] as String;
      final releaseUrl = updateInfo['releaseUrl'] as String;

      if (UpdateService.supportsApkUpdates && updateInfo['apkUrl'] != null) {
        return _ApkUpdateDialog(info: updateInfo, title: title, dismissLabel: dismissLabel);
      }
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              t.update.versionAvailable(version: latestVersion),
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t.update.currentVersion(version: updateInfo['currentVersion']),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          DialogActionButton(onPressed: () => Navigator.pop(dialogContext), label: dismissLabel),
          if (showSkipVersion)
            DialogActionButton(
              onPressed: () async {
                await UpdateService.skipVersion(latestVersion);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              label: t.update.skipVersion,
            ),
          DialogActionButton(
            onPressed: () async {
              final url = Uri.parse(releaseUrl);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: t.update.viewRelease,
            isPrimary: true,
          ),
        ],
      );
    },
  );
}

class _ApkUpdateDialog extends StatefulWidget {
  final Map<String, dynamic> info;
  final String title;
  final String dismissLabel;

  const _ApkUpdateDialog({required this.info, required this.title, required this.dismissLabel});

  @override
  State<_ApkUpdateDialog> createState() => _ApkUpdateDialogState();
}

class _ApkUpdateDialogState extends State<_ApkUpdateDialog> {
  bool _busy = false;
  String? _message;

  Future<void> _install() async {
    setState(() { _busy = true; _message = null; });
    try {
      final opened = await UpdateService.installApkUpdate(widget.info);
      if (!mounted) return;
      if (opened) {
        Navigator.pop(context);
      } else {
        setState(() {
          _message = 'Allow ${t.app.title} to install unknown apps in Settings, then select Update now again.';
        });
      }
    } catch (_) {
      if (mounted) setState(() { _message = 'Update could not be installed. Please try again.'; });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.update.versionAvailable(version: widget.info['latestVersion'] as String)),
        const SizedBox(height: 8),
        Text(t.update.currentVersion(version: widget.info['currentVersion'] as String)),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Downloading and verifying update…'),
        ],
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
      ],
    ),
    actions: [
      if (!_busy) DialogActionButton(onPressed: () => Navigator.pop(context), label: widget.dismissLabel),
      if (!_busy) DialogActionButton(onPressed: _install, label: 'Update now', isPrimary: true),
    ],
  );
}
