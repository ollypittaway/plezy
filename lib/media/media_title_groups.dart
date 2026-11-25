import '../utils/external_ids.dart';
import 'media_item.dart';
import 'media_kind.dart';
import 'title_copies.dart' show foldTitle;

/// Ordered groups of copies using identifiers already present on listing rows.
/// A title/year fallback cannot override conflicting catalogue IDs.
List<List<MediaItem>> groupMediaCopiesByTitle(Iterable<MediaItem> items, {bool requireReleaseYear = false}) {
  final index = _TitleIndex(requireReleaseYear);
  for (final item in items) {
    index.add(item);
  }
  return index.groups;
}

class _TitleGroup {
  final copies = <MediaItem>[];
  final ids = <String, Object>{};
}

class _TitleIndex {
  _TitleIndex(this.requireReleaseYear);
  final bool requireReleaseYear;
  final groups = <List<MediaItem>>[];
  final _seen = <String>{};
  final _byId = <(MediaKind, int?, int?, String, Object), _TitleGroup>{};
  final _byName = <(MediaKind, String, int?, int?, int?), List<_TitleGroup>>{};

  void add(MediaItem item) {
    if (!_seen.add(item.globalKey)) return;
    final kind = item.kind;
    if (kind != MediaKind.movie && kind != MediaKind.show && kind != MediaKind.episode && kind != MediaKind.season) {
      groups.add([item]);
      return;
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
    final hasName =
        title.isNotEmpty &&
        (child || !requireReleaseYear || item.year != null) &&
        (!child || season != null) &&
        (kind != MediaKind.episode || episode != null);
    final byName = hasName ? _byName.putIfAbsent((kind, title, item.year, season, episode), () => []) : null;
    bool compatible(_TitleGroup group) =>
        ids.entries.every((entry) => group.ids[entry.key] == null || group.ids[entry.key] == entry.value);
    final match =
        ids.entries
            .map((entry) => _byId[(kind, season, episode, entry.key, entry.value)])
            .nonNulls
            .where(compatible)
            .firstOrNull ??
        byName?.where(compatible).firstOrNull;
    final identity = match ?? _TitleGroup();
    if (match == null) groups.add(identity.copies);
    identity.copies.add(item);
    identity.ids.addAll(ids);
    for (final entry in ids.entries) {
      _byId[(kind, season, episode, entry.key, entry.value)] = identity;
    }
    if (byName != null && !byName.contains(identity)) byName.add(identity);
  }
}
