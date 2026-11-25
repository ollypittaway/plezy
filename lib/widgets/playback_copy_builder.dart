import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../exceptions/media_server_exceptions.dart';
import '../media/media_item.dart';
import '../media/media_item_merge.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../utils/media_server_http_client.dart';

/// Resolves the file for the detail page's current playback target. TV
/// focus can move through several episodes before settling on one.
class PlaybackCopyBuilder extends StatefulWidget {
  final MediaItem? target;
  final List<MediaItem>? initialCopies;
  final Widget Function(
    MediaItem? selected,
    List<MediaItem> copies,
    ValueChanged<MediaItem> select,
    FourKPlayback? fourK,
  )
  builder;

  const PlaybackCopyBuilder({super.key, required this.target, this.initialCopies, required this.builder});

  @override
  State<PlaybackCopyBuilder> createState() => _PlaybackCopyBuilderState();
}

class _PlaybackCopyBuilderState extends State<PlaybackCopyBuilder> {
  String? _key;
  Map<String, MediaServerClient> _clients = const {};
  AbortController? _request;
  Timer? _debounce;
  List<MediaItem> _matches = const [];
  MediaItem? _preferred;

  @override
  Widget build(BuildContext context) {
    final servers = context.watch<MultiServerProvider?>();
    final hidden = context.watch<HiddenLibrariesProvider?>();
    final clients = servers?.serverManager.visibleOnlineClients ?? const <String, MediaServerClient>{};
    final target = widget.target;
    if (target?.globalKey != _key || !mapEquals(clients, _clients)) {
      final initial = _request == null && _key == null ? widget.initialCopies : null;
      _request?.abort();
      _debounce?.cancel();
      _key = target?.globalKey;
      _clients = clients;
      _matches = const [];
      if (target != null && servers != null && clients.isNotEmpty) {
        if (initial != null &&
            initial.any((item) => item.globalKey == target.globalKey) &&
            initial.every((item) => item.mediaVersions?.isNotEmpty == true)) {
          _matches = initial;
        } else {
          final request = _request = AbortController();
          _debounce = Timer(const Duration(milliseconds: 250), () => _load(servers, target, request));
        }
      }
    }
    final available = mergeLibraryCopies([?target], _matches)
        .where(
          (item) =>
              clients.containsKey(item.serverId) && hidden?.hiddenLibraryKeys.contains(item.libraryGlobalKey) != true,
        )
        .where(
          (item) => item.mediaVersions?.isNotEmpty != true || item.mediaVersions!.any((version) => version.isPlayable),
        )
        .toList();
    final libraries = context.watch<LibrariesProvider?>()?.libraries;
    final menuCopies = available.where((item) {
      final library =
          item.libraryTitle ??
          libraries?.where((library) => library.globalKey == item.libraryGlobalKey).firstOrNull?.title;
      if (isFourKLibraryTitle(library)) return false;
      final versions = item.mediaVersions?.where((version) => version.isPlayable);
      return versions == null || versions.isEmpty || versions.any((version) => !version.is4K);
    }).toList();
    final order = {
      for (final (index, library) in (libraries ?? const <MediaLibrary>[]).indexed) library.globalKey: index,
    };
    int rank(MediaItem item) => order[item.libraryGlobalKey] ?? order.length + defaultLibraryRank(item.libraryTitle);
    mergeSort(menuCopies, compare: (a, b) => rank(a).compareTo(rank(b)));
    final preferred = _preferred;
    final selected =
        menuCopies.where((item) => item.globalKey == preferred?.globalKey).firstOrNull ??
        menuCopies
            .where((item) => item.libraryGlobalKey != null && item.libraryGlobalKey == preferred?.libraryGlobalKey)
            .firstOrNull ??
        available.where((item) => item.globalKey == target?.globalKey).firstOrNull ??
        menuCopies.firstOrNull ??
        available.firstOrNull;
    return widget.builder(
      selected,
      menuCopies,
      (item) => setState(() => _preferred = item),
      findFourKPlayback([?selected, ...available]),
    );
  }

  Future<void> _load(MultiServerProvider servers, MediaItem target, AbortController request) async {
    if (request.isAborted) return;
    try {
      final matches = await servers.aggregationService.playbackCopies(target, abort: request);
      if (mounted && !request.isAborted) setState(() => _matches = matches);
    } on MediaServerHttpException {
      if (!request.isAborted) rethrow;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _request?.abort();
    super.dispose();
  }
}
