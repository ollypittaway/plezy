import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../exceptions/media_server_exceptions.dart';
import '../media/media_item.dart';
import '../media/media_item_merge.dart';
import '../media/media_item_types.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import 'dialogs.dart';
import 'formatters.dart';
import 'media_server_http_client.dart';

typedef PlaybackLibraryChoice = ({MediaItem item, List<MediaItem>? matches});
final _activePickers = <NavigatorState>{};

Future<PlaybackLibraryChoice?> choosePlaybackLibrary(
  BuildContext context,
  MediaItem item, {
  List<MediaItem> known = const [],
}) async {
  if (!item.isVideoContent) return (item: item, matches: null);
  final servers = context.read<MultiServerProvider?>();
  final hidden = context.read<HiddenLibrariesProvider?>();
  final navigator = Navigator.of(context);
  final route = ModalRoute.of(context);
  if (!_activePickers.add(navigator)) return null;
  final abort = AbortController();
  final loading = ScopedLoadingDialogController();
  var finished = false;
  final timer = Timer(const Duration(milliseconds: 250), () {
    if (!context.mounted || route?.isCurrent == false) return;
    loading.show(
      context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
      onDisposed: () {
        if (!finished) abort.abort();
      },
    );
  });
  try {
    final matches = await Future.any([
      servers?.aggregationService.playbackCopies(item, abort: abort) ?? Future.value([item]),
      abort.trigger.then((_) => <MediaItem>[]),
    ]);
    await hidden?.ensureInitialized();
    finished = true;
    timer.cancel();
    await loading.dismiss();
    if (!context.mounted || abort.isAborted || route?.isCurrent == false) return null;
    final online = servers?.serverManager.visibleOnlineClients;
    final hiddenKeys = hidden?.hiddenLibraryKeys;
    final choices = mergeLibraryCopies(known, matches)
        .where(
          (copy) =>
              (copy.globalKey == item.globalKey || hiddenKeys?.contains(copy.libraryGlobalKey) != true) &&
              (online == null || online.containsKey(copy.serverId)) &&
              (copy.mediaVersions?.isNotEmpty != true || copy.mediaVersions!.any((v) => v.isPlayable)),
        )
        .toList();
    final picked = choices.length > 1
        ? await _pick(context, choices, known.length > 1 ? t.discover.selectVersion : t.libraries.selectLibrary)
        : choices.firstOrNull ?? item;
    if (picked == null) return null;
    return (item: picked, matches: matches.any((m) => m.globalKey == picked.globalKey) ? matches : null);
  } on MediaServerHttpException {
    if (!abort.isAborted) rethrow;
    return null;
  } finally {
    finished = true;
    timer.cancel();
    await loading.dismiss();
    abort.abort();
    _activePickers.remove(navigator);
  }
}

Future<MediaItem?> _pick(BuildContext context, List<MediaItem> copies, String title) {
  // Rows say only what tells the copies apart: the episode when the copies
  // stopped at different ones, the server when they span several.
  final showEpisode = copies.map((copy) => (copy.parentIndex, copy.index)).toSet().length > 1;
  final showServer = copies.map((copy) => copy.serverId).toSet().length > 1;
  final libraries = context.read<LibrariesProvider?>()?.libraries;
  final libraryNames = {
    if (libraries != null)
      for (final lib in libraries) lib.globalKey: lib.title,
  };
  String label(MediaItem copy) {
    final library = copy.libraryTitle ?? libraryNames[copy.libraryGlobalKey];
    return [
      if (showEpisode && copy.isEpisode) ?formatSeasonEpisodeLabel(copy.parentIndex, copy.index),
      library ?? copy.serverName ?? copy.backend.dialect?.productName ?? 'Plex',
      ?libraryCopyQualityLabel(copy),
      if (showServer && library != null) ?copy.serverName,
    ].join(' • ');
  }

  return showOptionPickerDialog<MediaItem>(
    context,
    title: title,
    options: [for (final copy in copies) (icon: null, label: label(copy), value: copy)],
  );
}
