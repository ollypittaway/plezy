part of '../media_detail_screen.dart';

/// What the download action button shows for one download state.
class _DownloadButtonSpec {
  final Widget icon;
  final String? tooltip;
  final Color? foregroundColor;

  /// False while the download pipeline owns the item (queueing, queued,
  /// downloading): the button renders disabled.
  final bool interactive;

  const _DownloadButtonSpec({required this.icon, this.tooltip, this.foregroundColor, this.interactive = true});
}

extension _MediaDetailActionButtons on _MediaDetailScreenState {
  Widget _buildActionButtons(MediaItem metadata) {
    // Tie asynchronous playback prompts to the actionable subtree, not the
    // route's State: a deleted first-route detail intentionally stays mounted.
    return Builder(
      builder: (context) {
        var target = _playbackTargetItem(metadata);
        if (target == null && metadata.isShow) {
          final firstSeason = defaultPlaybackSeason(_seasons);
          if (firstSeason != null) target = _seasonEpisodePager.stateFor(firstSeason.id).items.firstOrNull;
        }
        return PlaybackCopyBuilder(
          target: !widget.isOffline && (target?.isMovie == true || target?.isEpisode == true) ? target : null,
          initialCopies: widget.initialPlaybackCopies,
          builder: (selected, copies, select, fourK) => ValueListenableBuilder<int>(
            valueListenable: _playbackStatusRevision,
            builder: (_, _, _) =>
                _buildAvailableActionButtons(context, metadata, selected ?? target, copies, select, fourK),
          ),
        );
      },
    );
  }

  Widget _buildAvailableActionButtons(
    BuildContext context,
    MediaItem metadata,
    MediaItem? selected,
    List<MediaItem> copies,
    ValueChanged<MediaItem> select,
    FourKPlayback? fourK,
  ) {
    final isTv = PlatformDetector.usesTvPresentation();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final actionSize = isTv ? _tvDetailActionSize * tvScale : 48.0;
    final libraries = context.watch<LibrariesProvider?>()?.libraries;
    String? libraryName(MediaItem item) =>
        item.libraryTitle ??
        libraries?.where((library) => library.globalKey == item.libraryGlobalKey).firstOrNull?.title;
    final playItem = selected ?? metadata;
    final sameLibrary =
        playItem.serverId == metadata.serverId &&
        (playItem.libraryId == null || playItem.libraryId == metadata.libraryId);
    final library =
        libraryName(playItem) ?? (sameLibrary ? libraryName(metadata) ?? widget.metadata.libraryTitle : null);
    final label4k = t.mediaMenu.playIn4k;
    final probe = _playbackSources[playItem.globalKey];
    final versionItem = probe?.item.mediaVersions?.isNotEmpty == true ? probe!.item : playItem;
    final versions = versionItem.mediaVersions ?? const [];
    final settings = SettingsService.instanceOrNull;
    final preference = settings == null || versions.length < 2 || widget.isOffline
        ? null
        : readMediaVersionPreference(settings, versionItem)?.resolveIndex(versions);
    final hdIndex = widget.isOffline ? null : preferredNon4kVersionIndex(versions);
    final index = hdIndex ?? probe?.mediaIndex ?? preference ?? versions.indexWhere((version) => version.isPlayable);
    final version = index < 0 ? null : versions.elementAtOrNull(index);
    final primarySource = primaryFourKPlayback(
      versionItem,
      index,
      fourK,
      preferFourKLibrary: hdIndex == null && preference == null && isFourKLibraryTitle(library),
    );
    // An offline multi-version title needs the identity of the file actually downloaded.
    final offlineFourK =
        widget.isOffline &&
        (probe?.mediaIndex != null
            ? version?.is4K == true
            : versions.isNotEmpty && versions.every((version) => version.is4K));
    if (widget.isOffline && probe == null && versions.length > 1) _scheduleTargetProbe(context, playItem);
    final primaryFourK = primarySource != null || offlineFourK;
    final episodePrefix = _remoteSelectedEpisode != null && (metadata.isShow || metadata.isSeason)
        ? formatSeasonEpisodeLabel(_remoteSelectedEpisode!.parentIndex, _remoteSelectedEpisode!.index)
        : null;
    final basePlayButtonLabel = primaryFourK
        ? label4k
        : metadata.isVideoContent && library != null && library.isNotEmpty
        ? t.mediaMenu.playFromLibrary(library: library)
        : _getPlayButtonLabel(metadata);
    final playButtonLabel = episodePrefix == null ? basePlayButtonLabel : '$episodePrefix · $basePlayButtonLabel';
    final naturalLabelWidth = math.min(isTv ? 260.0 * tvScale : 260.0, MediaQuery.sizeOf(context).width * .32);
    var maxLabelWidth = naturalLabelWidth;
    final playIcon = _getPlayButtonIcon(playItem);
    final playActionLabel = playIcon == Symbols.resume_rounded ? t.common.resume : t.common.play;
    final playSemanticsLabel = primaryFourK || (library != null && metadata.isVideoContent)
        ? playButtonLabel
        : playButtonLabel.isEmpty
        ? playActionLabel
        : '$playActionLabel $playButtonLabel';
    final playIconSize = isTv ? 22 * tvScale : 20.0;
    final playTextStyle = TextStyle(fontSize: isTv ? 17 * tvScale : 16, fontWeight: .w700);
    final playButtonIcon = AppIcon(playIcon, fill: 1, size: playIconSize);

    // Split "Play Version" segment (#1881): a visible second Play segment
    // that surfaces multiple versions without opening the ⋮ menu. Only when
    // the item itself carries a real choice — a movie/episode with more than
    // one inline version — and its server is reachable (offline playback and
    // unreachable servers have at most one playable version, so the picker
    // would offer versions that can't play; see #1440). Transcode-only
    // quality picking deliberately stays in the ⋮ menu: a chevron on every
    // item would stop signaling "multiple versions exist".
    final itemServerId = serverIdOrNull(playItem.serverId);
    final showVersionSplit =
        !widget.isOffline &&
        (playItem.isMovie || playItem.isEpisode) &&
        (playItem.mediaVersions?.length ?? 0) > 1 &&
        itemServerId != null &&
        context.read<MultiServerProvider>().serverManager.isClientOnline(itemServerId);
    // M3E split-button geometry: stadium outer corners, small joined inner
    // corners, a hairline gap between the two segments, and a trailing
    // segment narrower than a full action so it reads as Play's appendix.
    final splitGap = isTv ? 2.0 * tvScale : 2.0;
    final versionSegmentWidth = actionSize * 0.75;
    final splitInnerRadius = Radius.circular(isTv ? 8.0 * tvScale : 8.0);
    final splitOuterRadius = Radius.circular(actionSize / 2);
    final hasLibraryMenu = copies.any((copy) => copy.globalKey != playItem.globalKey);
    if (hasLibraryMenu && _pendingEpisodeLibraryFocus == _remoteSelectedEpisode?.globalKey &&
        _pendingEpisodeLibraryFocus != null) {
      final pending = _pendingEpisodeLibraryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_canUseDetail || _pendingEpisodeLibraryFocus != pending ||
            !_playButtonFocusNode.hasFocus || _libraryMenuFocusNode.context == null) return;
        _pendingEpisodeLibraryFocus = null;
        _libraryMenuFocusNode.requestFocus();
      });
    }
    final playShape = hasLibraryMenu || showVersionSplit
        ? RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.horizontal(start: splitOuterRadius, end: splitInnerRadius),
          )
        : null;

    Future<void> playFourKFile(FourKPlayback fourK) async {
      if (!_canUseDetail) return;
      await navigateToFourKPlayback(context, fourK, isLaunchCurrent: () => _canUseDetail);
      if (_canUseDetail) await _refreshWatchState();
    }

    final VoidCallback? playFourK = fourK == null ? null : () => playFourKFile(fourK);

    Future<void> onPlayPressed() async {
      if (!_canUseDetail) return;
      if (primarySource != null) {
        await playFourKFile(primarySource);
        return;
      }
      if (selected == null && (metadata.isShow || metadata.isSeason)) {
        await _playFirstEpisode();
        return;
      }
      await navigateToVideoPlayerWithRefresh(
        context,
        metadata: playItem,
        isOffline: widget.isOffline,
        onRefresh: _refreshWatchState,
        isLaunchCurrent: () => _canUseDetail,
      );
    }

    Future<void> chooseLibrary() async {
      final anchor = chipAnchorRect(_libraryMenuKey);
      if (anchor == null) return;
      final multipleServers = copies.map((item) => item.serverId).toSet().length > 1;
      final picked = await showAnchoredSelectionMenu<MediaItem>(
        context,
        anchorRect: anchor,
        options: copies,
        selected: selected,
        labelOf: (item) => [
          libraryName(item) ?? item.serverName ?? t.libraries.selectLibrary,
          ?libraryCopyQualityLabel(item),
          if (multipleServers && libraryName(item) != null) ?item.serverName,
        ].join(' • '),
      );
      if (picked != null && context.mounted && _canUseDetail) select(picked);
    }

    Future<void> onPlayVersionPressed() async {
      if (!_canUseDetail) return;
      final didNavigate = await promptAndPlayVersion(context, playItem);
      // Same post-playback refresh plain Play gets from
      // navigateToVideoPlayerWithRefresh; the split segment is online-only.
      if (didNavigate && mounted) unawaited(_refreshWatchState());
    }

    final primaryTrailer = _getPrimaryTrailer();

    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    final colorScheme = Theme.of(context).colorScheme;

    // In keyboard/d-pad mode, focused buttons get a prominent style.
    // overlayColor is set to transparent to prevent the Material focus
    // overlay from dimming the background color we set.
    final focusBg = colorScheme.inverseSurface;
    final focusFg = colorScheme.onInverseSurface;
    final tonalBg = colorScheme.secondaryContainer;
    final idleBg = isTv ? tonalBg.withValues(alpha: 0.38) : tonalBg;
    final tonalFg = colorScheme.onSecondaryContainer;
    final noOverlay = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return Colors.transparent;
      return null; // default for other states
    });

    ButtonStyle actionButtonStyle({
      Color? foregroundColor,
      EdgeInsetsGeometry? padding,
      bool showFocus = false,
      OutlinedBorder? shape,
    }) {
      if (!isKeyboardMode && !isTv) {
        if (padding != null) {
          return FilledButton.styleFrom(padding: padding, shape: shape);
        }
        return IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          foregroundColor: foregroundColor,
        );
      }

      return ButtonStyle(
        padding: padding != null ? WidgetStatePropertyAll(padding) : null,
        minimumSize: WidgetStatePropertyAll(padding == null ? Size.square(actionSize) : Size(0, actionSize)),
        maximumSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        fixedSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        overlayColor: noOverlay,
        backgroundColor: WidgetStatePropertyAll(showFocus ? focusBg : idleBg),
        foregroundColor: WidgetStatePropertyAll(showFocus ? focusFg : foregroundColor ?? tonalFg),
        shape: shape != null ? WidgetStatePropertyAll(shape) : null,
      );
    }

    // Plays the resolved trailer. Shared by the row's trailer button and the
    // ⋮ menu item so the trailer stays reachable when the row hides its button.
    final VoidCallback? onPlayTrailer = primaryTrailer == null
        ? null
        : () =>
              unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer, isLaunchCurrent: () => _canUseDetail));

    final gap = isTv ? 8.0 * tvScale : 12.0;

    Widget playButton(FocusableActionBuildState state) {
      return Semantics(
        label: playSemanticsLabel,
        button: true,
        onTap: onPlayPressed,
        excludeSemantics: true,
        child: SizedBox(
          height: actionSize,
          child: FilledButton(
            onPressed: onPlayPressed,
            style: actionButtonStyle(
              showFocus: state.showFocus,
              padding: .symmetric(horizontal: isTv ? 17 * tvScale : 16, vertical: isTv ? 9 * tvScale : 0),
              shape: playShape,
            ),
            child: playButtonLabel.isNotEmpty
                ? Row(
                    mainAxisSize: .min,
                    children: [
                      playButtonIcon,
                      SizedBox(width: isTv ? 7 * tvScale : 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxLabelWidth),
                        child: Text(
                          playButtonLabel,
                          style: playTextStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : playButtonIcon,
          ),
        ),
      );
    }

    // The trailing segment of the split Play button. A plain FilledButton
    // (not IconButton) so both segments share color roles and focus styling.
    Widget splitButton(FocusableActionBuildState state, {required bool libraryMenu}) {
      final action = libraryMenu ? chooseLibrary : onPlayVersionPressed;
      final label = libraryMenu ? t.libraries.selectLibrary : t.mediaMenu.playVersion;
      return Semantics(
        key: libraryMenu ? _libraryMenuKey : null,
        label: label,
        button: true,
        onTap: action,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: SizedBox(
            width: versionSegmentWidth,
            height: actionSize,
            child: FilledButton(
              onPressed: action,
              style: actionButtonStyle(
                showFocus: state.showFocus,
                padding: .zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadiusDirectional.horizontal(start: splitInnerRadius, end: splitOuterRadius),
                ),
              ),
              child: AppIcon(
                !libraryMenu && hasLibraryMenu ? Symbols.video_settings_rounded : Symbols.keyboard_arrow_down_rounded,
                fill: 1,
                size: playIconSize,
              ),
            ),
          ),
        ),
      );
    }

    Widget iconActionButton(
      FocusableActionBuildState state, {
      required Widget icon,
      required VoidCallback? onPressed,
      String? tooltip,
      Color? foregroundColor,
    }) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        iconSize: isTv ? 21 * tvScale : 20,
        style: actionButtonStyle(foregroundColor: foregroundColor, showFocus: state.showFocus),
      );
    }

    final playAction = FocusableAction(
      debugLabel: 'detail_play',
      focusNode: _playButtonFocusNode,
      autofocus: isKeyboardMode,
      onPressed: onPlayPressed,
      builder: (context, state) => playButton(state),
    );

    final libraryAction = hasLibraryMenu
        ? FocusableAction(
            debugLabel: 'detail_play_library',
            focusNode: _libraryMenuFocusNode,
            spacingBefore: splitGap,
            onPressed: chooseLibrary,
            builder: (_, state) => splitButton(state, libraryMenu: true),
          )
        : null;
    final versionAction = showVersionSplit
        ? FocusableAction(
            debugLabel: 'detail_play_version',
            spacingBefore: splitGap,
            onPressed: onPlayVersionPressed,
            builder: (context, state) => splitButton(state, libraryMenu: false),
          )
        : null;

    final fourKAction = metadata.isVideoContent && !primaryFourK
        ? FocusableAction(
            debugLabel: 'detail_play_4k',
            onPressed: playFourK,
            builder: (context, state) => SizedBox(
              height: actionSize,
              child: FilledButton.tonal(
                onPressed: playFourK,
                style: playFourK == null
                    ? null
                    : actionButtonStyle(
                        showFocus: state.showFocus,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                child: Text(label4k, style: playTextStyle),
              ),
            ),
          )
        : null;
    final compactFourK = fourKAction == null
        ? null
        : FocusableAction(
            debugLabel: 'detail_play_4k_compact',
            onPressed: playFourK,
            builder: (context, state) => IconButton.filledTonal(
              tooltip: label4k,
              icon: const AppIcon(Symbols.four_k_rounded),
              onPressed: playFourK,
              style: playFourK == null ? null : actionButtonStyle(showFocus: state.showFocus),
            ),
          );

    final trailerAction = primaryTrailer == null
        ? null
        : FocusableAction(
            debugLabel: 'detail_trailer',
            onPressed: onPlayTrailer,
            builder: (context, state) => iconActionButton(
              state,
              onPressed: onPlayTrailer,
              icon: const AppIcon(Symbols.theaters_rounded, fill: 1),
              tooltip: t.tooltips.playTrailer,
            ),
          );

    final shuffleAction = (metadata.isShow || metadata.isSeason)
        ? FocusableAction(
            debugLabel: 'detail_shuffle',
            onPressed: () async {
              await _handleShufflePlayWithQueue(context, metadata);
            },
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () async {
                await _handleShufflePlayWithQueue(context, metadata);
              },
              icon: const AppIcon(Symbols.shuffle_rounded, fill: 1),
              tooltip: t.tooltips.shufflePlay,
            ),
          )
        : null;

    final downloadAction = !widget.isOffline && !PlatformDetector.isAppleTV()
        ? FocusableAction(
            debugLabel: 'detail_download',
            onPressed: () => unawaited(_handleDownloadButtonPressed(context, metadata)),
            builder: (context, state) =>
                _buildDownloadButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
          )
        : null;

    final watchedAction = FocusableAction(
      debugLabel: 'detail_watched',
      onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
      builder: (context, state) =>
          _buildWatchedToggleButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
    );

    // Watchlist toggle for the connected catalog sources (Trakt, MAL).
    // Membership reads each source's session snapshot — no per-open API
    // call. Filled when the item is on ANY source's watchlist; with several
    // candidates the press opens a source chooser.
    // Not in the compact tiers: on narrow screens it drops away first and
    // stays reachable through the ⋮ menu's watchlist entry.
    final watchlistStates = [
      for (final candidate in _watchlistCandidates) candidate.source.isOnWatchlist(metadata.kind, candidate.ids),
    ];
    final bool? onWatchlist = watchlistStates.contains(true)
        ? true
        : watchlistStates.contains(false)
        ? false
        : null;
    final watchlistAction = _watchlistCandidates.isEmpty
        ? null
        : FocusableAction(
            debugLabel: 'detail_watchlist',
            onPressed: () => unawaited(_handleWatchlistTogglePressed(metadata)),
            builder: (context, state) => KeyedSubtree(
              key: _watchlistButtonKey,
              child: iconActionButton(
                state,
                onPressed: onWatchlist == null ? null : () => unawaited(_handleWatchlistTogglePressed(metadata)),
                icon: AppIcon(
                  (onWatchlist ?? false) ? Symbols.bookmark_added_rounded : Symbols.bookmark_add_rounded,
                  fill: 1,
                ),
                tooltip: (onWatchlist ?? false) ? t.explore.removeFromWatchlist : t.explore.addToWatchlist,
              ),
            ),
          );

    void showMoreActions() => _contextMenuKey.currentState?.showContextMenu(context);

    final moreActionsAction = widget.isOffline
        ? null
        : FocusableAction(
            debugLabel: 'detail_more',
            onPressed: showMoreActions,
            builder: (context, state) => _buildMoreActionsButton(
              metadata,
              actionButtonStyle,
              tvScale,
              onPlayTrailer: onPlayTrailer,
              showFocus: state.showFocus,
            ),
          );

    final allActions = <FocusableAction>[
      playAction,
      ?libraryAction,
      ?versionAction,
      ?fourKAction,
      ?trailerAction,
      ?shuffleAction,
      ?downloadAction,
      watchedAction,
      ?watchlistAction,
      ?moreActionsAction,
    ];

    double labelWidth(String label) {
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: playTextStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final textWidth = textPainter.width;
      textPainter.dispose();
      return textWidth;
    }

    final playChromeWidth = playIconSize + (isTv ? 41 * tvScale : 40);
    final estimatedPlayWidth = playButtonLabel.isEmpty
        ? 64.0
        : math.max(64.0, math.min(naturalLabelWidth, labelWidth(playButtonLabel)) + playChromeWidth);
    final fourKWidth = math.max(64.0, labelWidth(label4k) + 32);
    double estimatedRowWidth(List<FocusableAction> actions) {
      if (actions.isEmpty) return 0;
      var width = estimatedPlayWidth;
      for (var i = 1; i < actions.length; i++) {
        final actionWidth = (identical(actions[i], versionAction) || identical(actions[i], libraryAction))
            ? versionSegmentWidth
            : identical(actions[i], fourKAction)
            ? fourKWidth
            : actionSize;
        width += (actions[i].spacingBefore ?? gap) + actionWidth;
      }
      return width;
    }

    List<FocusableAction> compactActionsFor(double maxWidth) {
      if (widget.isOffline) {
        final compact = <FocusableAction>[playAction, ?compactFourK, watchedAction];
        if (maxWidth.isFinite && estimatedRowWidth(compact) > maxWidth) return [playAction];
        return compact;
      }

      final medium = <FocusableAction>[
        playAction,
        ?libraryAction,
        ?versionAction,
        ?compactFourK,
        ?downloadAction,
        watchedAction,
        ?moreActionsAction,
      ];
      if (!maxWidth.isFinite || estimatedRowWidth(medium) <= maxWidth) return medium;

      final compact = <FocusableAction>[
        playAction,
        ?libraryAction,
        ?versionAction,
        ?compactFourK,
        watchedAction,
        ?moreActionsAction,
      ];
      if (estimatedRowWidth(compact) <= maxWidth) return compact;

      return [playAction, ?libraryAction, if (!hasLibraryMenu) ?versionAction, ?compactFourK, ?moreActionsAction];
    }

    Widget actionBar(List<FocusableAction> actions) {
      return FocusableActionBar(
        actions: actions,
        spacing: gap,
        onFocusChange: isTv ? _setTvDetailActionRowFocus : null,
        onNavigateUp: _focusAboveActionRow,
        onNavigateDown: _focusBelowActionRow,
      );
    }

    // Off TV the track status sits at the row's far end, right-aligned so it
    // reads as information about the row rather than a sixth button. It takes
    // only the leftover width and is the first thing to go, so the buttons
    // never compact because of it. On TV the hero is a 60% column, so the
    // status is placed at the screen edge by _buildTvDetailScreen instead.
    Widget? tracksStatusFor(List<FocusableAction> actions, double maxWidth) {
      if (isTv || !maxWidth.isFinite) return null;
      final remaining = maxWidth - estimatedRowWidth(actions) - gap;
      if (remaining < 160) return null;
      return _buildPlaybackTracksStatus(context, playItem, isTv: false, tvScale: tvScale, maxWidth: remaining);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        // Keep the usual TV shortcuts unless the library controls need space.
        final actions = (isTv && library == null && !hasLibraryMenu) || estimatedRowWidth(allActions) <= maxWidth
            ? allActions
            : compactActionsFor(maxWidth);
        final otherActionsWidth = estimatedRowWidth(actions) - estimatedPlayWidth;
        maxLabelWidth = (maxWidth - otherActionsWidth - playChromeWidth).clamp(0.0, naturalLabelWidth);
        final status = tracksStatusFor(actions, maxWidth);
        if (status == null) return actionBar(actions);
        return SizedBox(
          height: actionSize,
          child: Row(
            children: [
              actionBar(actions),
              Expanded(
                child: Align(alignment: .centerRight, child: status),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleWatchlistTogglePressed(MediaItem metadata) async {
    if (!_canUseDetail) return;
    final candidates = _watchlistCandidates;
    if (candidates.isEmpty || _watchlistMutationInFlight) return;
    // Parity with the disabled pointer button: while every membership is
    // still unknown, a dpad press kicks the snapshot loads instead of
    // opening a chooser whose selection would silently no-op.
    if (candidates.every((c) => c.source.isOnWatchlist(metadata.kind, c.ids) == null)) {
      for (final candidate in candidates) {
        unawaited(candidate.source.ensureWatchlistLoaded());
      }
      return;
    }
    if (candidates.length == 1) {
      await _toggleWatchlistOn(metadata, candidates.single);
      return;
    }

    // Several providers can hold this item: choose per press. Each entry
    // shows that source's current membership.
    final renderBox = _watchlistButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final choice = await showWatchlistSourceChooser(
      context,
      kind: metadata.kind,
      candidates: candidates,
      anchorRect: renderBox.localToGlobal(Offset.zero) & renderBox.size,
      focusFirstItem: true,
    );
    if (choice == null || !_canUseDetail) return;
    await _toggleWatchlistOn(metadata, choice);
  }

  Future<void> _toggleWatchlistOn(MediaItem metadata, WatchlistCandidate candidate) async {
    if (!_canUseDetail) return;
    final current = candidate.source.isOnWatchlist(metadata.kind, candidate.ids);
    if (current == null || _watchlistMutationInFlight) return;
    _watchlistMutationInFlight = true;
    try {
      // Optimistic inside the source; the row/screens listening to
      // watchlistChanges (including this one) rebuild immediately.
      await mutateWatchlistMembership(metadata.kind, candidate, add: !current);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.explore.watchlistUpdateFailed);
    } finally {
      _watchlistMutationInFlight = false;
    }
  }

  Future<void> _handleWatchedTogglePressed(MediaItem metadata) async {
    if (!_canUseDetail) return;
    try {
      final isWatched = metadata.isWatched;
      final outcome = await WatchActions.setWatched(context, metadata, watched: !isWatched, offline: widget.isOffline);
      if (!mounted || !_canUseDetail) return;
      switch (outcome) {
        case WatchMarkOutcome.queuedOffline:
          showAppSnackBar(context, isWatched ? t.messages.markedAsUnwatchedOffline : t.messages.markedAsWatchedOffline);
        case WatchMarkOutcome.marked:
          _watchStateChanged = true;
          showSuccessSnackBar(context, isWatched ? t.messages.markedAsUnwatched : t.messages.markedAsWatched);
        case WatchMarkOutcome.skipped:
          break;
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(e)));
      }
    }
  }

  Widget _buildWatchedToggleButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return IconButton.filledTonal(
      onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
      icon: AppIcon(metadata.isWatched ? Symbols.remove_done_rounded : Symbols.check_rounded, fill: 1),
      tooltip: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
      iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
      style: actionButtonStyle(showFocus: showFocus),
    );
  }

  Widget _buildMoreActionsButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    VoidCallback? onPlayTrailer,
    bool showFocus = false,
  }) {
    return MediaContextMenu(
      key: _contextMenuKey,
      item: metadata,
      onRefresh: (source) => unawaited(_refreshItemInPlace(source)),
      onPlayTrailer: onPlayTrailer,
      child: Builder(
        builder: (buttonContext) => IconButton.filledTonal(
          onPressed: () {
            if (!_canUseDetail) return;
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final position = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
              _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
            }
          },
          icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
          iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
          style: actionButtonStyle(showFocus: showFocus),
        ),
      ),
    );
  }

  /// Shared retry pipeline for failed/cancelled downloads: confirm download
  /// restrictions, re-resolve the version, then replace the existing download
  /// with a fresh queue entry.
  Future<void> _retryDownload(DownloadProvider downloadProvider, MediaItem metadata, String globalKey) async {
    if (!_canUseDetail) return;
    if (!await confirmBackgroundDownloadRestrictions(context) || !mounted || !_canUseDetail) return;

    final client = _getMediaClientForMetadata(context);
    if (client == null) return;

    final versionConfig = await _resolveDownloadVersion(context, metadata, client);
    if (versionConfig == null || !_canUseDetail) return;

    await downloadProvider.deleteDownload(globalKey);
    if (!_canUseDetail) return;
    try {
      await downloadProvider.queueDownload(metadata, client, versionConfig: versionConfig);
      if (mounted) showSuccessSnackBar(context, t.downloads.downloadQueued);
    } on CellularDownloadBlockedException {
      if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
    }
  }

  Future<void> _handleDownloadButtonPressed(BuildContext context, MediaItem metadata) async {
    if (!_canUseDetail || !context.mounted) return;
    final downloadProvider = context.read<DownloadProvider>();
    final globalKey = metadata.globalKey;
    final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
    final progress = downloadProvider.getProgress(globalKey);

    if (downloadProvider.isQueueing(globalKey) ||
        progress?.status == DownloadStatus.queued ||
        progress?.status == DownloadStatus.downloading) {
      return;
    }

    if (progress?.status == DownloadStatus.paused) {
      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      await downloadProvider.resumeDownload(globalKey, client);
      if (_canUseDetail && context.mounted) showAppSnackBar(context, t.downloads.downloadResumed);
      return;
    }

    if (progress?.status == DownloadStatus.failed) {
      // A failed download is the likeliest moment for the restriction to be
      // the actual cause, so check before spending another attempt on it.
      await _retryDownload(downloadProvider, metadata, globalKey);
      return;
    }

    if (progress?.status == DownloadStatus.cancelled) {
      final retry = await showConfirmDialog(
        context,
        title: t.downloads.cancelledDownloadTitle,
        message: t.downloads.cancelledDownloadMessage,
        cancelText: t.common.delete,
        confirmText: t.common.retry,
      );
      if (!_canUseDetail || !context.mounted) return;

      if (!retry) {
        await downloadProvider.deleteDownload(globalKey);
        if (_canUseDetail && context.mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
      } else {
        await _retryDownload(downloadProvider, metadata, globalKey);
      }
      return;
    }

    if (progress?.status == DownloadStatus.partial) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }
      if (!await confirmBackgroundDownloadRestrictions(context) || !_canUseDetail || !context.mounted) return;

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;

      final versionConfig = await _resolveDownloadVersion(context, metadata, client);
      if (versionConfig == null || !_canUseDetail || !context.mounted) return;

      final count = await downloadProvider.queueMissingEpisodes(metadata, client, versionConfig: versionConfig);
      if (_canUseDetail && context.mounted) {
        final message = count > 0 ? t.downloads.episodesQueued(count: count) : t.downloads.allEpisodesAlreadyDownloaded;
        showAppSnackBar(context, message);
      }
      return;
    }

    if (downloadProvider.isDownloaded(globalKey)) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }

      final canDownloadMore = metadata.isShow || metadata.isSeason;
      Future<void> confirmAndDelete() async {
        final confirmed = await showDeleteConfirmation(
          context,
          title: t.downloads.deleteDownload,
          message: t.downloads.deleteConfirm(title: metadata.displayTitle),
        );
        if (confirmed && _canUseDetail && context.mounted) {
          await downloadProvider.deleteDownload(globalKey);
          if (_canUseDetail && context.mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
        }
      }

      if (!canDownloadMore) {
        await confirmAndDelete();
        return;
      }

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      await queueDownloadWithFeedback(
        context,
        metadata: metadata,
        client: client,
        downloadProvider: downloadProvider,
        onDelete: confirmAndDelete,
      );
      return;
    }

    final client = _getMediaClientForMetadata(context);
    if (client == null) return;

    await queueDownloadWithFeedback(context, metadata: metadata, client: client, downloadProvider: downloadProvider);
  }

  Widget _buildDownloadButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final iconSize = PlatformDetector.isTV() ? 21.0 * tvScale : 20.0;
        final spec = _downloadButtonSpec(context, downloadProvider, metadata, iconSize: iconSize);
        return IconButton.filledTonal(
          onPressed: spec.interactive ? () => unawaited(_handleDownloadButtonPressed(context, metadata)) : null,
          icon: spec.icon,
          tooltip: spec.tooltip,
          iconSize: iconSize,
          style: actionButtonStyle(foregroundColor: spec.foregroundColor, showFocus: showFocus),
        );
      },
    );
  }

  /// Presentation of the download button for the item's current download
  /// state, in precedence order: queueing → queued → downloading → paused →
  /// failed → cancelled → partial → downloaded → not downloaded. The first
  /// three are non-interactive; [_handleDownloadButtonPressed] handles the rest.
  _DownloadButtonSpec _downloadButtonSpec(
    BuildContext context,
    DownloadProvider downloadProvider,
    MediaItem metadata, {
    required double iconSize,
  }) {
    final globalKey = metadata.globalKey;
    final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
    final progress = downloadProvider.getProgress(globalKey);
    final currentFile = progress?.currentFile;

    if (debugLoggingEnabled && progress != null) {
      appLogger.d('UI rebuilding for $globalKey: status=${progress.status}, progress=${progress.progress}%');
    }

    // Queueing (building download queue)
    if (downloadProvider.isQueueing(globalKey)) {
      return _DownloadButtonSpec(icon: LoadingIndicatorBox(size: iconSize), interactive: false);
    }

    // Queued (waiting to download)
    if (progress?.status == DownloadStatus.queued) {
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.schedule_rounded, fill: 1),
        tooltip: currentFile != null && currentFile.contains('episodes')
            ? t.downloads.queuedFilesTooltip(files: currentFile)
            : t.downloads.queuedTooltip,
        interactive: false,
      );
    }

    // Downloading (active download); the tooltip carries the episode count
    // for shows/seasons.
    if (progress?.status == DownloadStatus.downloading) {
      return _DownloadButtonSpec(
        icon: _buildRadialProgress(progress?.progressPercent),
        tooltip: currentFile != null && currentFile.contains('episodes')
            ? t.downloads.downloadingFilesTooltip(files: currentFile)
            : t.downloads.downloadingTooltip,
        interactive: false,
      );
    }

    // Paused (can resume)
    if (progress?.status == DownloadStatus.paused) {
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.pause_circle_outline_rounded, fill: 1),
        tooltip: t.downloads.resumeDownload,
        foregroundColor: Colors.amber,
      );
    }

    // Failed (can retry)
    if (progress?.status == DownloadStatus.failed) {
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.error_outline_rounded, fill: 1),
        tooltip: t.downloads.retryDownload,
        foregroundColor: Colors.red,
      );
    }

    // Cancelled (can delete or retry)
    if (progress?.status == DownloadStatus.cancelled) {
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.cancel_rounded, fill: 1),
        tooltip: t.downloads.cancelledDownload,
        foregroundColor: Colors.grey,
      );
    }

    // A sync rule shows the same icon whether the download is partial (its
    // normal state) or complete; only the tooltip differs.
    _DownloadButtonSpec syncRuleSpec({required bool complete}) {
      final syncRule = downloadProvider.getSyncRule(ruleKey);
      final isEnabled = syncRule?.enabled ?? true;
      final keepStatus = t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?');
      final String tooltip;
      if (complete) {
        tooltip = keepStatus;
      } else if (currentFile != null) {
        tooltip = t.downloads.syncingFile(file: currentFile, status: keepStatus);
      } else {
        tooltip = t.downloads.keepSynced;
      }
      return _DownloadButtonSpec(
        icon: AppIcon(isEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1),
        tooltip: tooltip,
        foregroundColor: isEnabled ? Colors.teal : Colors.grey,
      );
    }

    // Partial download (some episodes downloaded, not all)
    if (progress?.status == DownloadStatus.partial) {
      if (downloadProvider.hasSyncRule(ruleKey)) return syncRuleSpec(complete: false);
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.downloading_rounded, fill: 1),
        tooltip: currentFile != null
            ? t.downloads.downloadedFileClickToComplete(file: currentFile)
            : t.downloads.partialDownloadClickToComplete,
        foregroundColor: Colors.orange,
      );
    }

    // Downloaded/complete (can delete)
    if (downloadProvider.isDownloaded(globalKey)) {
      if (downloadProvider.hasSyncRule(ruleKey)) return syncRuleSpec(complete: true);
      // Shows/seasons may have more episodes to fetch; movies/episodes don't.
      final canDownloadMore = metadata.isShow || metadata.isSeason;
      return _DownloadButtonSpec(
        icon: const AppIcon(Symbols.download_rounded, fill: 1),
        tooltip: canDownloadMore ? t.downloads.manage : t.downloads.deleteDownload,
        foregroundColor: Colors.orange,
      );
    }

    // Not downloaded (default - can download)
    return _DownloadButtonSpec(
      icon: const AppIcon(Symbols.download_rounded, fill: 1),
      tooltip: t.downloads.downloadNow,
    );
  }
}
