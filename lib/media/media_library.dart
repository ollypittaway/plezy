import '../utils/global_key_utils.dart';
import 'ids.dart';
import 'media_backend.dart';
import 'media_kind.dart';

const _defaultLibraryNames = ['movies', '4k movies', 'kids movies', 'tv shows', '4k tv shows', 'kids tv shows'];
final _libraryWhitespace = RegExp(r'\s+');
final _fourKLibrary = RegExp(r'\b(?:4[\s-]?k|uhd|ultra[\s-]?hd|2160p)\b', caseSensitive: false);

int defaultLibraryRank(String? title) {
  final rank = _defaultLibraryNames.indexOf((title ?? '').trim().toLowerCase().replaceAll(_libraryWhitespace, ' '));
  return rank < 0 ? _defaultLibraryNames.length : rank;
}

bool isFourKLibraryTitle(String? title) => title != null && _fourKLibrary.hasMatch(title);

/// A top-level browseable section on a server (Plex library section, Jellyfin
/// view).
class MediaLibrary {
  /// Backend-opaque identifier (Plex section id like `"5"`, Jellyfin view UUID).
  final String id;
  final MediaBackend backend;
  final String title;

  /// Primary media kind held by this library — drives default UI affordances
  /// (poster shape, sort options). For mixed libraries this is [MediaKind.unknown].
  final MediaKind kind;

  /// Explicit item kinds for this library's flat root browse. Mixed libraries
  /// use this when no single [kind] can describe the server's root view.
  final List<MediaKind> defaultBrowseKinds;

  /// Optional ISO language code of the library's metadata locale.
  final String? language;

  /// Server-side last-update timestamp in seconds.
  final int? updatedAt;
  final int? createdAt;

  /// Whether the user has hidden this library from the home browser.
  final bool hidden;

  /// True for individually-shared items presented as a virtual library
  /// (Plex's "shared with me" surface). Jellyfin returns no such marker.
  final bool isShared;

  final String? serverId;
  final String? serverName;

  const MediaLibrary({
    required this.id,
    required this.backend,
    required this.title,
    this.kind = MediaKind.unknown,
    this.defaultBrowseKinds = const [],
    this.language,
    this.updatedAt,
    this.createdAt,
    this.hidden = false,
    this.isShared = false,
    this.serverId,
    this.serverName,
  });

  String get globalKey => serverId != null ? buildGlobalKey(ServerId(serverId!), id) : id;
}
