import 'dart:collection';

import 'media_hub.dart';
import 'media_item.dart';
import 'media_server_client.dart';

/// Keep the position of the first matching shelf in the user's Home order.
List<MediaHub> groupHomeHubs(List<MediaHub> hubs) {
  final byTitle = <String, List<MediaHub>>{};
  for (final hub in hubs) {
    if (hub.title.isNotEmpty) (byTitle[hub.title] ??= []).add(hub);
  }
  final result = <MediaHub>[];
  for (final hub in hubs) {
    if (hub.title.isEmpty) {
      result.add(hub);
      continue;
    }
    final sources = byTitle.remove(hub.title);
    if (sources != null) result.add(sources.length == 1 ? hub : _combine(sources));
  }
  return result;
}

MediaHub _combine(List<MediaHub> sources) {
  final first = sources.first;
  final libraries = <String>{};
  for (final hub in sources) {
    final library = hub.collectionLibraryTitle;
    if (library != null) {
      libraries.add(library);
    } else {
      libraries.addAll(hub.items.map((item) => item.libraryTitle).nonNulls);
    }
  }
  libraries.removeWhere((name) => name.trim().isEmpty);
  final items = interleaveHubItems(sources.map((source) => source.items));
  final sameServer = sources.every((source) => source.serverId == first.serverId);
  return MediaHub(
    id: 'grouped-home/${Uri.encodeComponent(first.title)}',
    title: first.title,
    collectionLibraryTitle: libraries.isEmpty ? null : libraries.join(', '),
    type: sources.every((source) => source.type == first.type) ? first.type : 'mixed',
    serverId: sameServer ? first.serverId : null,
    serverName: sameServer ? first.serverName : null,
    items: items.take(defaultHubPreviewLimit).toList(),
    // Source totals may overlap. Only the loaded unique count is known.
    size: items.length,
    more: items.length > defaultHubPreviewLimit || sources.any((source) => source.more),
    sources: sources,
  );
}

/// Alternate libraries while preserving their individual rankings. Separate
/// library editions stay playable, even if they share a movie title or GUID.
List<MediaItem> interleaveHubItems(Iterable<List<MediaItem>> lists) {
  final active = Queue.of(lists.map((items) => items.iterator));
  final seen = <String>{};
  final result = <MediaItem>[];
  while (active.isNotEmpty) {
    final iterator = active.removeFirst();
    if (!iterator.moveNext()) continue;
    final item = iterator.current;
    if (seen.add(item.globalKey)) result.add(item);
    active.addLast(iterator);
  }
  return result;
}
