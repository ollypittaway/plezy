import 'dart:collection';
import 'dart:math' as math;

import 'collection_items.dart';
import 'media_hub.dart';
import 'media_item.dart';
import 'media_title_groups.dart';
import 'media_server_client.dart';

/// Keep the position of the first matching shelf in the user's Home order.
List<MediaHub> groupHomeHubs(List<MediaHub> hubs, {Map<String, int> libraryOrder = const {}}) {
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
    if (sources == null) continue;
    if (sources.length > 1) {
      result.add(_combine(sources, libraryOrder));
    } else if (hub.isCollectionShelf) {
      final unique = interleaveHubItems([itemsInHubLibrary(hub, hub.items)], libraryOrder: libraryOrder);
      result.add(
        unique.length == hub.items.length
            ? hub
            : hub.copyWith(
                items: unique,
                size: math.max(hub.size, hub.items.length) - hub.items.length + unique.length,
              ),
      );
    } else {
      result.add(hub);
    }
  }
  return result;
}

MediaHub _combine(List<MediaHub> sources, Map<String, int> libraryOrder) {
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
  final items = interleaveHubItems(
    sources.map((source) => itemsInHubLibrary(source, source.items)),
    libraryOrder: libraryOrder,
  );
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

/// Some collection endpoints report the library only on the enclosing shelf.
List<MediaItem> itemsInHubLibrary(MediaHub hub, List<MediaItem> items) {
  // Plex may include the section ID on preview members and omit it when the
  // same collection is expanded. Only inherit an unambiguous section.
  final sourceLibraryId =
      hub.libraryId ??
      (hub.isCollectionShelf && hub.collectionLibraryTitle != null
          ? hub.items.map((item) => item.libraryId).nonNulls.toSet().singleOrNull
          : null);
  return items.map((item) {
    if (item.serverId != null && hub.serverId != null && item.serverId != hub.serverId) return item;
    final serverId = item.serverId ?? hub.serverId;
    final sameTitle =
        item.libraryTitle == null ||
        hub.collectionLibraryTitle == null ||
        item.libraryTitle == hub.collectionLibraryTitle;
    final libraryId = item.libraryId ?? (sameTitle ? sourceLibraryId : null);
    final sameLibrary = sourceLibraryId == null || item.libraryId == null || item.libraryId == sourceLibraryId;
    final title = item.libraryTitle ?? (sameLibrary ? hub.collectionLibraryTitle : null);
    if (item.serverId == serverId && item.libraryId == libraryId && item.libraryTitle == title) return item;
    return item.copyWith(serverId: serverId, libraryId: libraryId, libraryTitle: title);
  }).toList();
}

/// Alternate libraries, keeping the first shelf position for each title.
List<MediaItem> interleaveHubItems(Iterable<List<MediaItem>> lists, {Map<String, int> libraryOrder = const {}}) {
  final active = Queue.of(lists.map((items) => items.iterator));
  final result = <MediaItem>[];
  while (active.isNotEmpty) {
    final iterator = active.removeFirst();
    if (!iterator.moveNext()) continue;
    result.add(iterator.current);
    active.addLast(iterator);
  }
  return [for (final group in groupMediaCopiesByTitle(result)) preferredCollectionCopy(group, libraryOrder)];
}
