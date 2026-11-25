import 'dart:collection';

import '../utils/external_ids.dart';
import 'media_hub.dart';
import 'media_item.dart';
import 'media_kind.dart';
import 'media_server_client.dart';
import 'title_copies.dart' show foldTitle;

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

/// Alternate libraries, keeping the first shelf position for each title.
List<MediaItem> interleaveHubItems(Iterable<List<MediaItem>> lists) {
  final active = Queue.of(lists.map((items) => items.iterator));
  final seen = <String>{};
  final titles = _HubTitles();
  final result = <MediaItem>[];
  while (active.isNotEmpty) {
    final iterator = active.removeFirst();
    if (!iterator.moveNext()) continue;
    final item = iterator.current;
    if (seen.add(item.globalKey) && titles.add(item)) result.add(item);
    active.addLast(iterator);
  }
  return result;
}

/// Uses identities already present in shelf responses, including on View All
/// pages. A title/year fallback cannot override conflicting catalogue IDs.
class _HubTitles {
  final _byId = <(MediaKind, int?, int?, String, Object), Map<String, Object>>{};
  final _byName = <(MediaKind, String, int?, int?, int?), List<Map<String, Object>>>{};

  bool add(MediaItem item) {
    final kind = item.kind;
    if (kind != MediaKind.movie && kind != MediaKind.show && kind != MediaKind.episode && kind != MediaKind.season) {
      return true;
    }
    final guid = item.guid;
    final providers = item.raw?['ProviderIds'];
    final guids = item.raw?['Guid'];
    final external = providers is Map<String, dynamic>
        ? ExternalIds.fromJellyfinProviderIds(providers)
        : ExternalIds.fromGuids(guids is List ? guids : const []).fillFrom(ExternalIds.fromLegacyPlexGuid(guid));
    final ids = <String, Object>{
      if (guid != null && guid.startsWith('plex://')) 'plex': guid,
      'imdb': ?external.imdb,
      'tmdb': ?external.tmdb,
      'tvdb': ?external.tvdb,
      'anidb': ?external.anidb,
    };
    final child = kind == MediaKind.season || kind == MediaKind.episode;
    final title = foldTitle(switch (kind) {
      MediaKind.season => item.parentTitle ?? '',
      MediaKind.episode => item.grandparentTitle ?? '',
      _ => item.title ?? '',
    });
    final season = switch (kind) {
      MediaKind.episode => item.parentIndex,
      MediaKind.season => item.index,
      _ => null,
    };
    final episode = kind == MediaKind.episode ? item.index : null;
    final hasName = title.isNotEmpty && (!child || season != null) && (kind != MediaKind.episode || episode != null);
    final byName = hasName ? _byName.putIfAbsent((kind, title, item.year, season, episode), () => []) : null;
    bool compatible(Map<String, Object> known) =>
        ids.entries.every((entry) => known[entry.key] == null || known[entry.key] == entry.value);
    final match =
        ids.entries
            .map((entry) => _byId[(kind, season, episode, entry.key, entry.value)])
            .nonNulls
            .where(compatible)
            .firstOrNull ??
        byName?.where(compatible).firstOrNull;
    final identity = (match ?? <String, Object>{})..addAll(ids);
    for (final entry in ids.entries) {
      _byId[(kind, season, episode, entry.key, entry.value)] = identity;
    }
    if (byName != null && !byName.contains(identity)) byName.add(identity);
    return match == null;
  }
}
