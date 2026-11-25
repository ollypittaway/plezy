import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../exceptions/media_server_exceptions.dart';
import '../media/media_item.dart';
import '../media/media_item_merge.dart';
import '../media/media_server_client.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../utils/media_server_http_client.dart';

/// Resolves the file for the detail page's current playback target. TV
/// focus can move through several episodes before settling on one.
class PlaybackCopyBuilder extends StatefulWidget {
  final MediaItem? target;
  final List<MediaItem>? initialCopies;
  final Widget Function(FourKPlayback?) builder;

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
    final available = [?target, ..._matches].where(
      (item) => clients.containsKey(item.serverId) && hidden?.hiddenLibraryKeys.contains(item.libraryGlobalKey) != true,
    );
    return widget.builder(findFourKPlayback(available));
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
