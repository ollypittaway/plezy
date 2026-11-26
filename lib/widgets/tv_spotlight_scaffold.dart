import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../models/catalog/catalog_item.dart';
import '../navigation/main_screen_scope.dart';
import '../services/settings_service.dart';
import '../utils/debouncer.dart';
import '../utils/layout_constants.dart';
import '../utils/formatters.dart';
import 'tv_browse_rail.dart';
import 'tv_spotlight_background.dart';

class TvSpotlightController extends ValueNotifier<MediaItem?> {
  TvSpotlightController({Duration settleDelay = const Duration(milliseconds: 150), this.blankWhileMoving = false})
    : _settleDelay = settleDelay,
      _debouncer = Debouncer(settleDelay),
      super(null);

  final Duration _settleDelay;
  final Debouncer _debouncer;
  final bool blankWhileMoving;
  bool _moving = false;
  bool get isMoving => _moving;
  String? _pendingKey;
  int _selectionGeneration = 0;
  bool _disposed = false;

  void select(MediaItem item, {Future<MediaItem> Function()? prepare}) {
    if (blankWhileMoving && _pendingKey == item.globalKey) return;
    _pendingKey = item.globalKey;
    final generation = ++_selectionGeneration;
    if (blankWhileMoving && !_moving && value?.globalKey != item.globalKey) {
      _moving = true;
      notifyListeners();
    }
    Future<void> apply() async {
      final prepared = prepare == null ? item : await prepare();
      if (_disposed || generation != _selectionGeneration) return;
      final wasMoving = _moving;
      _moving = false;
      if (value?.globalKey == item.globalKey) {
        if (wasMoving) notifyListeners();
        return;
      }
      value = prepared;
    }

    if (_settleDelay == Duration.zero) {
      apply();
    } else {
      _debouncer.run(apply);
    }
  }

  MediaItem? resolve(Iterable<MediaHub> hubs) {
    MediaItem? fallback;
    final current = value;
    for (final hub in hubs) {
      if (hub.items.isEmpty) continue;
      fallback ??= hub.items.first;
      if (current == null) continue;
      for (final item in hub.items) {
        if (item.globalKey == current.globalKey) return blankWhileMoving ? current : item;
      }
    }
    return fallback;
  }

  @override
  void dispose() {
    _disposed = true;
    _debouncer.dispose();
    super.dispose();
  }
}

typedef TvSpotlightClientResolver = MediaServerClient? Function(MediaItem? item);

/// Shared full-screen TV backdrop and foreground stack used by hub rails.
class TvSpotlightScaffold extends StatelessWidget {
  const TvSpotlightScaffold({
    super.key,
    required this.hubs,
    required this.spotlightListenable,
    required this.resolveSpotlight,
    required this.resolveClient,
    required this.foreground,
    this.hideSpoilers,
    this.lightweightTransitions = false,
    this.exploreLayout = false,
  });

  final List<MediaHub> hubs;
  final ValueListenable<MediaItem?> spotlightListenable;
  final MediaItem? Function() resolveSpotlight;
  final TvSpotlightClientResolver resolveClient;
  final Widget foreground;
  final bool? hideSpoilers;
  final bool lightweightTransitions;
  final bool exploreLayout;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final settings = SettingsService.instance;
    final scale = TvLayoutConstants.scaleForSize(size);
    final railSize = MainScreenFocusScope.foregroundSizeOf(context);
    final fullBleedWidth = MainScreenFocusScope.fullBleedWidthOf(context);
    final railHeight = hubs.isEmpty
        ? 0.0
        : TvBrowseRailLayout.estimateHeight(
            size: railSize,
            hubs: hubs,
            density: settings.read(SettingsService.libraryDensity),
            episodePosterMode: settings.read(SettingsService.episodePosterMode),
            fullCardLayout: settings.read(SettingsService.tvFullCardLayout),
            gridSpacing: settings.read(SettingsService.gridSpacing),
            tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
            widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
          );
    final spotlightTop = (size.height * 0.075).clamp(64.0 * scale, 120.0 * scale).toDouble();
    final minimumSpotlightBottom = railHeight + (8 * scale);
    final baseSpotlightBottom = (size.height * (exploreLayout ? 0.34 : 0.48)).clamp(120.0, 820.0).toDouble();
    final desiredSpotlightBottom = minimumSpotlightBottom > baseSpotlightBottom
        ? minimumSpotlightBottom
        : baseSpotlightBottom;
    final maxSpotlightBottom = (size.height - spotlightTop - (96 * scale)).clamp(0.0, double.infinity).toDouble();
    final spotlightBottom = desiredSpotlightBottom > maxSpotlightBottom ? maxSpotlightBottom : desiredSpotlightBottom;
    final spotlightLeft = TvLayoutConstants.contentInsetForScale(scale);

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Builder(
              builder: (context) {
                final foregroundLeft = MainScreenFocusScope.foregroundLeftOf(context);
                return SideNavigationBleedBuilder(
                  targetBleed: foregroundLeft,
                  child: ValueListenableBuilder<MediaItem?>(
                    valueListenable: spotlightListenable,
                    builder: (context, _, _) {
                      final spotlight = resolveSpotlight();
                      final moving = spotlightListenable is TvSpotlightController && (spotlightListenable as TvSpotlightController).isMoving;
                      final background = _CatalogSpotlightBackground(
                        item: spotlight,
                        client: resolveClient(spotlight),
                        hideSpoilers: hideSpoilers ?? settings.read(SettingsService.hideSpoilers),
                        contentTop: spotlightTop,
                        contentBottom: spotlightBottom,
                        contentLeft: spotlightLeft + foregroundLeft,
                        targetWidthPx: lightweightTransitions
                            ? (size.width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 2560).toInt()
                            : (size.width * MediaQuery.devicePixelRatioOf(context)).ceil(),
                        lightweightTransitions: lightweightTransitions,
                        exploreLayout: exploreLayout,
                      );
                      return exploreLayout ? _ExploreHeroGate(moving: moving, hero: background) : background;
                    },
                  ),
                  builder: (context, animatedBleed, child) =>
                      Positioned(top: 0, bottom: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
                );
              },
            ),
            foreground,
          ],
        ),
      ),
    );
  }
}

class _CatalogSpotlightBackground extends StatefulWidget {
  const _CatalogSpotlightBackground({
    required this.item,
    required this.client,
    required this.hideSpoilers,
    required this.contentTop,
    required this.contentBottom,
    required this.contentLeft,
    required this.targetWidthPx,
    required this.lightweightTransitions,
    required this.exploreLayout,
    this.onArtworkReady,
    this.onLogoReady,
    super.key,
  });

  final MediaItem? item;
  final MediaServerClient? client;
  final bool hideSpoilers;
  final double contentTop;
  final double contentBottom;
  final double contentLeft;
  final int targetWidthPx;
  final bool lightweightTransitions;
  final bool exploreLayout;
  final VoidCallback? onArtworkReady;
  final VoidCallback? onLogoReady;

  @override
  State<_CatalogSpotlightBackground> createState() => _CatalogSpotlightBackgroundState();
}

class _CatalogSpotlightBackgroundState extends State<_CatalogSpotlightBackground> {
  CatalogItem? _catalogItem;
  MediaItem? _renderItem;
  Color? _accentColor;

  @override
  void initState() {
    super.initState();
    _rehydrateCatalogItem();
  }

  @override
  void didUpdateWidget(_CatalogSpotlightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.item, oldWidget.item)) {
      _rehydrateCatalogItem();
    } else if (widget.targetWidthPx != oldWidget.targetWidthPx) {
      _projectArtwork();
    }
  }

  void _rehydrateCatalogItem() {
    _catalogItem = widget.item?.catalogItem;
    _projectArtwork();
  }

  void _projectArtwork() {
    final item = widget.item;
    final catalogItem = _catalogItem;
    if (item == null || catalogItem == null) {
      _renderItem = item;
      _accentColor = null;
      return;
    }

    final bannerUrl = catalogItem.bannerUrl;
    final backdrop = catalogItem.backdropFor(widget.targetWidthPx) ?? bannerUrl;
    final logoUrl = catalogItem.logoUrl;
    _renderItem = item.copyWith(
      summary: catalogItem.overview ?? item.summary,
      artPath: backdrop ?? item.artPath,
      backdropPaths: backdrop == null ? item.backdropPaths : [backdrop],
      clearLogoPath: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
    );
    _accentColor = _parseAccentColor(catalogItem.accentColor);
  }

  Color? _parseAccentColor(String? value) {
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value ?? '');
    final hex = match?.group(1);
    if (hex == null) return null;
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }

  Widget? _buildNextEpisodeMetadata(BuildContext context) {
    final nextEpisode = _catalogItem?.nextEpisode;
    if (nextEpisode == null) return null;
    final duration = formatDurationTextual(nextEpisode.timeUntil(DateTime.now()).inMilliseconds);
    final episode = nextEpisode.episode;
    final label = episode == null
        ? t.explore.badge.nextAiringIn(duration: duration)
        : t.explore.badge.nextEpisodeIn(episode: episode, duration: duration);
    final scale = TvLayoutConstants.scaleOf(context);
    return Text(
      label,
      maxLines: 1,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 16 * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _accentColor;
    final background = TvSpotlightBackground(
      item: _renderItem,
      client: widget.client,
      hideSpoilers: widget.hideSpoilers,
      contentTop: widget.contentTop,
      contentBottom: widget.contentBottom,
      contentLeft: widget.contentLeft,
      compact: true,
      lightweightTransitions: widget.lightweightTransitions,
      exploreLayout: widget.exploreLayout,
      onArtworkReady: widget.onArtworkReady,
      onLogoReady: widget.onLogoReady,
      metadataTrailing: _buildNextEpisodeMetadata(context),
    );
    if (accentColor == null) return background;
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: Color.alphaBlend(accentColor.withValues(alpha: 0.18), theme.scaffoldBackgroundColor),
      ),
      child: background,
    );
  }
}

/// Keeps the black scrim opaque until both images in the replacement hero
/// have actually painted a decoded frame (or their terminal fallback).
class _ExploreHeroGate extends StatefulWidget {
  const _ExploreHeroGate({required this.moving, required this.hero});
  final bool moving;
  final _CatalogSpotlightBackground hero;

  @override
  State<_ExploreHeroGate> createState() => _ExploreHeroGateState();
}

class _ExploreHeroGateState extends State<_ExploreHeroGate> {
  bool _artworkReady = false;
  bool _logoReady = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant _ExploreHeroGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hero.item, widget.hero.item)) {
      _generation++;
      _artworkReady = false;
      _logoReady = false;
    }
  }

  void _ready(int generation, {required bool artwork}) {
    if (!mounted || generation != _generation) return;
    if (artwork ? _artworkReady : _logoReady) return;
    setState(() {
      if (artwork) { _artworkReady = true; } else { _logoReady = true; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.hero;
    final generation = _generation;
    final ready = !widget.moving && _artworkReady && _logoReady;
    return Stack(fit: StackFit.expand, children: [
      _CatalogSpotlightBackground(
        key: ValueKey(generation),
        item: hero.item, client: hero.client, hideSpoilers: hero.hideSpoilers,
        contentTop: hero.contentTop, contentBottom: hero.contentBottom,
        contentLeft: hero.contentLeft, targetWidthPx: hero.targetWidthPx,
        lightweightTransitions: hero.lightweightTransitions, exploreLayout: true,
        onArtworkReady: () => _ready(generation, artwork: true),
        onLogoReady: () => _ready(generation, artwork: false),
      ),
      IgnorePointer(child: AnimatedOpacity(
        opacity: ready ? 0 : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero
            : Duration(milliseconds: ready ? 250 : 150),
        child: const ColoredBox(color: Colors.black),
      )),
    ]);
  }
}

/// Pins a toolbar to the top of the viewport across the full bleed width,
/// sliding with the sidebar so it stays put while the content box translates.
///
/// Excluded from default focus traversal so that initial/tab-switch focus
/// lands on content (hero/rails) rather than the toolbar; its buttons stay
/// reachable via explicit UP from the content. Reads the offset aspect from
/// its own element, so a sidebar flip rebuilds only this overlay.
class TvToolbarOverlay extends StatelessWidget {
  const TvToolbarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fullBleedWidth = MainScreenFocusScope.fullBleedWidthOf(context);
    return SideNavigationBleedBuilder(
      targetBleed: MainScreenFocusScope.sideNavigationBleedOf(context),
      child: ExcludeFocusTraversal(child: child),
      builder: (context, animatedBleed, child) =>
          Positioned(top: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
    );
  }
}
