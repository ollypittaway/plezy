import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/media_server_http_client.dart';
import 'media_item.dart';
import 'media_item_merge.dart';
import 'media_kind.dart';
import 'media_server_client.dart';

/// A title to find across libraries. Seasons and episodes are matched
/// through their series and their season and episode numbers.
class TitleQuery {
  const TitleQuery.movie({required String title, int? year, ExternalIds ids = const ExternalIds(), String? plexGuid})
    : this._title(MediaKind.movie, title: title, year: year, ids: ids, plexGuid: plexGuid);

  const TitleQuery._title(
    this.kind, {
    required this.title,
    this.year,
    this.ids = const ExternalIds(),
    this.plexGuid,
    this.season,
    this.requireExactYear = false,
  }) : showTitle = null,
       showYear = null,
       showIds = const ExternalIds(),
       showPlexGuid = null,
       episode = null;

  const TitleQuery.episode({
    required String this.showTitle,
    this.showYear,
    this.showIds = const ExternalIds(),
    this.showPlexGuid,
    required int this.season,
    required int this.episode,
    this.ids = const ExternalIds(),
    this.title = '',
    this.requireExactYear = false,
  }) : kind = MediaKind.episode,
       year = null,
       plexGuid = null;

  final MediaKind kind;

  /// The movie's title, or the episode's own (unused for lookups).
  final String title;
  final int? year;

  /// The movie's IDs, or the episode's own.
  final ExternalIds ids;
  final String? plexGuid;
  final String? showTitle;
  final int? showYear;
  final ExternalIds showIds;
  final String? showPlexGuid;
  final int? season;
  final int? episode;

  /// A file-selection shortcut needs a known matching year when neither
  /// server can verify a catalogue ID. A title alone can name a remake.
  final bool requireExactYear;

  /// Resolve a library card using its own server's identifiers. A series'
  /// year and ids belong to the series, never to the episode's air date.
  static Future<TitleQuery?> forLibraryItem(MediaItem item, MediaServerClient client, AbortController abort) async {
    final child = item.kind == MediaKind.episode || item.kind == MediaKind.season;
    final season = item.kind == MediaKind.episode ? item.parentIndex : item.index;
    if (child && (season == null || (item.kind == MediaKind.episode && item.index == null))) return null;
    MediaItem? series;
    if (child) {
      final id = item.kind == MediaKind.episode ? item.grandparentId : item.parentId;
      if (id != null) {
        try {
          series = await client.fetchItem(id);
        } catch (e) {
          appLogger.d('Series lookup for library copies failed', error: e);
        }
      }
    }
    abort.throwIfAborted();
    Future<ExternalIds> idsFor(MediaItem? target) async {
      if (target == null) return const ExternalIds();
      final providers = target.raw?['ProviderIds'];
      if (providers is Map<String, dynamic>) return ExternalIds.fromJellyfinProviderIds(providers);
      try {
        return await client.fetchExternalIds(target.id);
      } catch (e) {
        return ExternalIds.fromLegacyPlexGuid(target.guid);
      }
    }

    final parent = child ? series : item;
    final ids = await idsFor(parent);
    abort.throwIfAborted();
    final guid = parent?.guid;
    final plexGuid = guid != null && guid.startsWith('plex://') ? guid : null;
    final title = parent?.title ?? (item.kind == MediaKind.episode ? item.grandparentTitle : item.parentTitle) ?? '';
    if (item.kind == MediaKind.episode) {
      return TitleQuery.episode(
        showTitle: title,
        showYear: series?.year,
        showIds: ids,
        showPlexGuid: plexGuid,
        season: season!,
        episode: item.index!,
        ids: await idsFor(item),
        title: item.title ?? '',
        requireExactYear: true,
      );
    }
    return TitleQuery._title(
      item.kind,
      title: title,
      year: parent?.year,
      ids: ids,
      plexGuid: plexGuid,
      season: child ? season : null,
      requireExactYear: true,
    );
  }
}

/// The most title-search hits checked against the query's IDs when no item
/// matched by ID.
const int _titleFallbackLimit = 5;

extension TitleCopiesLookup on MediaServerClient {
  /// Every copy of [query] on this server, each with its versions.
  ///
  /// Movies and shows come from [findByExternalIds]. Only when that finds
  /// nothing does a title search run: same folded title, a year at most one
  /// apart, and no catalogue ID that contradicts the query's. An episode is
  /// then the show's episode with the query's season and episode numbers,
  /// dropped when its own IDs contradict the query's. Failures throw, so the
  /// caller can tell "not on this server" from "couldn't ask".
  Future<List<MediaItem>> findTitleCopies(TitleQuery query, {AbortController? abort}) async {
    final List<MediaItem> found;
    if (query.kind != MediaKind.episode) {
      found = await _titleItems(
        kind: query.kind == MediaKind.season ? MediaKind.show : query.kind,
        title: query.title,
        year: query.year,
        ids: query.ids,
        plexGuid: query.plexGuid,
        requireExactYear: query.requireExactYear,
        abort: abort,
      );
      if (query.kind == MediaKind.show) return found;
      if (query.kind == MediaKind.season) {
        final seasons = <MediaItem>[];
        for (final show in found) {
          abort?.throwIfAborted();
          for (final child in await fetchChildren(show.id)) {
            if (child.kind == MediaKind.season && child.index == query.season) {
              seasons.add(
                child.copyWith(
                  libraryId: child.libraryId ?? show.libraryId,
                  libraryTitle: child.libraryTitle ?? show.libraryTitle,
                ),
              );
            }
          }
        }
        return seasons;
      }
    } else {
      final shows = await _titleItems(
        kind: MediaKind.show,
        title: query.showTitle ?? '',
        year: query.showYear,
        ids: query.showIds,
        plexGuid: query.showPlexGuid,
        requireExactYear: query.requireExactYear,
        abort: abort,
      );
      final episodes = <MediaItem>[];
      for (final show in shows) {
        abort?.throwIfAborted();
        for (final episode in await _episodesOf(show, season: query.season!, episode: query.episode!, abort: abort)) {
          episodes.add(
            episode.copyWith(
              libraryId: episode.libraryId ?? show.libraryId,
              libraryTitle: episode.libraryTitle ?? show.libraryTitle,
            ),
          );
        }
      }
      found = query.ids.hasAny ? await _withoutContradictions(episodes, query.ids, abort: abort) : episodes;
    }
    return _withVersions(found, abort: abort);
  }

  Future<List<MediaItem>> _titleItems({
    required MediaKind kind,
    required String title,
    required int? year,
    required ExternalIds ids,
    required String? plexGuid,
    required bool requireExactYear,
    AbortController? abort,
  }) async {
    final titles = [if (title.trim().isNotEmpty) title.trim()];
    if (ids.hasAny || plexGuid != null) {
      final byId = await findByExternalIds(ids, kind: kind, titles: titles, year: year, plexGuid: plexGuid);
      abort?.throwIfAborted();
      if (byId != null && byId.isNotEmpty) return byId;
    }
    if (titles.isEmpty || (requireExactYear && year == null)) return const [];
    final hits = await searchItems(titles.single, limit: 50, abort: abort);
    abort?.throwIfAborted();
    final folded = foldTitle(titles.single);
    final sameTitle = [
      for (final hit in hits)
        if (hit.kind == kind &&
            foldTitle(hit.title ?? '') == folded &&
            (requireExactYear ? year == hit.year : _yearsAgree(year, hit.year)) &&
            !(plexGuid != null && hit.guid?.startsWith('plex://') == true && plexGuid != hit.guid))
          hit,
    ];
    if (!ids.hasAny) return sameTitle;
    return _withoutContradictions(sameTitle.take(_titleFallbackLimit).toList(), ids, abort: abort);
  }

  /// [items] minus those whose catalogue IDs name another title than [ids].
  /// An item whose IDs can't be read stays: nothing contradicts it.
  Future<List<MediaItem>> _withoutContradictions(
    List<MediaItem> items,
    ExternalIds ids, {
    AbortController? abort,
  }) async {
    final kept = <MediaItem>[];
    for (final item in items) {
      abort?.throwIfAborted();
      ExternalIds own;
      try {
        own = await fetchExternalIds(item.id);
      } catch (error, stackTrace) {
        if (abort?.isAborted ?? false) rethrow;
        appLogger.w('Could not read external IDs of ${item.id}', error: error, stackTrace: stackTrace);
        own = const ExternalIds();
      }
      if (!contradicts(own, ids)) kept.add(item);
    }
    return kept;
  }

  /// The episodes of [show] numbered [season]x[episode]. A Plex show whose
  /// seasons are hidden lists its episodes directly.
  Future<List<MediaItem>> _episodesOf(
    MediaItem show, {
    required int season,
    required int episode,
    AbortController? abort,
  }) async {
    bool isTarget(MediaItem item) =>
        item.kind == MediaKind.episode && item.index == episode && (item.parentIndex ?? season) == season;
    final children = await fetchChildren(show.id);
    abort?.throwIfAborted();
    final matches = [
      for (final child in children)
        if (isTarget(child)) child,
    ];
    for (final seasonItem in children) {
      if (seasonItem.kind != MediaKind.season || seasonItem.index != season) continue;
      final episodes = await _seasonEpisodes(show, seasonItem);
      abort?.throwIfAborted();
      matches.addAll(episodes.where(isTarget));
    }
    return matches;
  }

  Future<List<MediaItem>> _seasonEpisodes(MediaItem show, MediaItem season) async {
    final Object client = this;
    if (client is! SeasonEpisodePagingClient) return fetchChildren(season.id);
    const pageSize = 200;
    final items = <MediaItem>[];
    while (true) {
      final page = await client.fetchSeasonEpisodesPage(show.id, season.id, start: items.length, size: pageSize);
      items.addAll(page.items);
      if (page.items.length < pageSize || items.length >= page.totalCount) return items;
    }
  }

  /// [items] with their versions: rows that came without them are fetched.
  Future<List<MediaItem>> _withVersions(List<MediaItem> items, {AbortController? abort}) async {
    final result = <MediaItem>[];
    for (final item in items) {
      if (item.mediaVersions?.isNotEmpty ?? false) {
        result.add(item);
        continue;
      }
      abort?.throwIfAborted();
      try {
        final full = await fetchItem(item.id);
        result.add(full == null ? item : mergeLibraryCopy(item, full));
      } catch (error, stackTrace) {
        // The row itself still names the copy; its length may be on the row.
        appLogger.w('Could not read versions of ${item.id}', error: error, stackTrace: stackTrace);
        result.add(item);
      }
    }
    return result;
  }
}

bool _yearsAgree(int? wanted, int? found) => wanted == null || found == null || (wanted - found).abs() <= 1;

/// [title] lower-cased with everything but letters and digits removed, so
/// punctuation, articles' spacing and case don't tell two titles apart.
String foldTitle(String title) => title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Whether some catalogue holds different IDs in [a] and [b] (SDK.md §9.3):
/// then they name different titles whatever else they share.
bool contradicts(ExternalIds a, ExternalIds b) =>
    (a.imdb != null && b.imdb != null && a.imdb != b.imdb) ||
    (a.tmdb != null && b.tmdb != null && a.tmdb != b.tmdb) ||
    (a.tvdb != null && b.tvdb != null && a.tvdb != b.tvdb) ||
    (a.anidb != null && b.anidb != null && a.anidb != b.anidb);
