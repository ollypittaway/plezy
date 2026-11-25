import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../utils/quality_preset_labels.dart';
import '../utils/snackbar_helper.dart';
import 'dialog_action_button.dart';

typedef _Adjustment = ({Pref<Object?> pref, String title, String detail});

/// App-scoped so changing profiles or resuming a window cannot repeat the prompt.
class StartupPlaybackCheck {
  StartupPlaybackCheck(this.settings);

  final SettingsService settings;
  bool _checked = false;

  Future<void> run(BuildContext context, {required bool mobile, required bool hasPlex}) async {
    if (_checked) return;
    _checked = true;
    final quality = settings.read(SettingsService.defaultQualityPreset);
    final cellular = settings.read(SettingsService.cellularQualityPreset);
    final adjustments = <_Adjustment>[
      if (!quality.isOriginal)
        (
          pref: SettingsService.defaultQualityPreset,
          title: t.settings.defaultQualityTitle,
          detail: t.playbackCheck.originalQuality(current: qualityPresetLabel(quality)),
        ),
      if (mobile && cellular != null && !cellular.isOriginal)
        (
          pref: SettingsService.cellularQualityPreset,
          title: t.settings.cellularQualityTitle,
          detail: t.playbackCheck.cellularQuality(current: qualityPresetLabel(cellular)),
        ),
      if (hasPlex && !settings.read(SettingsService.directPlayCoveredQuality))
        (
          pref: SettingsService.directPlayCoveredQuality,
          title: t.playbackCheck.directPlay,
          detail: t.playbackCheck.enableDirectPlay,
        ),
    ];
    if (adjustments.isEmpty) return;
    final fixed = await showScopedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlaybackCheckDialog(
        settings: settings,
        adjustments: adjustments,
        increasesMobileData: mobile && !(cellular ?? quality).isOriginal,
      ),
    );
    if (fixed == true && context.mounted) showAppSnackBar(context, t.playbackCheck.saved);
  }
}

class _PlaybackCheckDialog extends StatefulWidget {
  const _PlaybackCheckDialog({required this.settings, required this.adjustments, required this.increasesMobileData});

  final SettingsService settings;
  final List<_Adjustment> adjustments;
  final bool increasesMobileData;

  @override
  State<_PlaybackCheckDialog> createState() => _PlaybackCheckDialogState();
}

class _PlaybackCheckDialogState extends State<_PlaybackCheckDialog> {
  late final _remaining = widget.adjustments.toList();
  bool _saving = false;
  bool _failed = false;

  Future<void> _fix() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      // Each recommendation is the corresponding setting's existing default.
      // Retain a failed write for retry, even if the preference cache changed.
      while (_remaining.isNotEmpty) {
        await widget.settings.reset(_remaining.first.pref);
        if (!mounted) return;
        _remaining.removeAt(0);
      }
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      appLogger.w('Could not save startup playback settings', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _failed = true;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(t.playbackCheck.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.playbackCheck.description),
              for (final change in _remaining) ...[
                const SizedBox(height: 16),
                Text(change.title, style: theme.textTheme.titleSmall),
                Text(change.detail, style: theme.textTheme.bodyMedium),
              ],
              if (widget.increasesMobileData) ...[const SizedBox(height: 16), Text(t.playbackCheck.mobileData)],
              if (_failed) ...[
                const SizedBox(height: 16),
                Text(t.playbackCheck.saveFailed, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          DialogActionButton(
            label: t.playbackCheck.ignore,
            onPressed: _saving ? null : () => Navigator.pop(context, false),
          ),
          DialogActionButton(
            autofocus: true,
            isPrimary: true,
            label: _failed ? t.common.retry : t.playbackCheck.fix,
            onPressed: _saving ? null : _fix,
          ),
        ],
      ),
    );
  }
}
