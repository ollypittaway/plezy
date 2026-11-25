import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_rating.dart';
import '../utils/content_utils.dart';
import '../utils/formatters.dart';
import '../utils/rating_utils.dart';
import 'media_rating_badge.dart';

/// The Home carousel shows the series logo for episodes. When series metadata
/// is available, use its scores and genres alongside the episode's own runtime.
class FeaturedMetadata extends StatelessWidget {
  const FeaturedMetadata({super.key, required this.item, this.details, required this.centered});

  final MediaItem item;
  final MediaItem? details;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = details;
    final isSeries = detail != null && item.isEpisode && detail.id == item.grandparentId;
    final listing = mediaRatingsFor(item);
    final extra = detail == null ? const <MediaRatingSource>[] : mediaRatingsFor(detail);
    final scores = [
      ...extra,
      if (!isSeries || extra.isEmpty) ...listing,
    ].where((rating) => rating.value.isFinite && rating.value >= 0 && rating.value <= 10).toList();
    MediaRatingSource? firstFrom(List<String> sources) {
      for (final source in sources) {
        for (final score in scores) {
          if (score.source == source) return score;
        }
      }
      return null;
    }

    final critics = firstFrom(const ['rottenTomatoesCritic', 'rottenTomatoes', 'critic', 'metacritic']);
    final audience = firstFrom(const [
      'rottenTomatoesAudience',
      'audience',
      'imdb',
      'tmdb',
      'trakt',
      'letterboxd',
      'simkl',
      'mal',
      'anilist',
    ]);
    final fallback = critics == null && audience == null ? scores.firstOrNull : null;
    final genres = detail?.genres?.isNotEmpty == true ? detail!.genres : item.genres;
    final year = item.year ?? (isSeries ? null : detail?.year);
    final runtime = item.durationMs ?? (isSeries ? null : detail?.durationMs);
    final certificate = item.contentRating ?? detail?.contentRating;
    final facts = [
      if (year != null) year.toString(),
      if (runtime != null && runtime > 0) formatDurationTextual(runtime),
      ...?genres?.where((genre) => genre.trim().isNotEmpty).take(3),
      if (certificate != null && certificate.isNotEmpty) formatContentRating(certificate),
    ];

    if (critics == null && audience == null && fallback == null && facts.isEmpty) return const SizedBox.shrink();

    final factStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.25,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        alignment: centered ? WrapAlignment.center : WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 3,
        children: [
          if (critics != null) _FeaturedScore(rating: critics, label: t.common.ratingSource.critic),
          if (audience != null) _FeaturedScore(rating: audience, label: t.common.ratingSource.audience),
          if (fallback != null) _FeaturedScore(rating: fallback, label: t.discover.rating),
          if (facts.isNotEmpty)
            Text(facts.join('  ·  '), textAlign: centered ? TextAlign.center : TextAlign.start, style: factStyle),
        ],
      ),
    );
  }
}

class _FeaturedScore extends StatelessWidget {
  const _FeaturedScore({required this.rating, required this.label});

  final MediaRatingSource rating;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (rating.value * 10).round();
    final source = ratingSourceLabel(rating.source) ?? label;
    return Tooltip(
      message: '$source · $value/100',
      excludeFromSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value',
              style: TextStyle(
                color: theme.brightness == Brightness.dark ? const Color(0xff65df95) : const Color(0xff16653c),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: '  ${label.toUpperCase()}',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.25,
              ),
            ),
          ],
        ),
        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.2),
        semanticsLabel: '$label, $source, $value/100',
      ),
    );
  }
}
