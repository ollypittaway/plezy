import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/widgets/featured_metadata.dart';

void main() {
  testWidgets('a featured episode uses scores from one title and keeps its own year and runtime', (tester) async {
    const episode = MediaItem.plex(
      id: 'episode',
      kind: MediaKind.episode,
      grandparentId: 'show',
      durationMs: 2700000,
      year: 2026,
      ratings: [MediaRatingSource(source: 'audience', value: 6)],
    );
    const show = MediaItem.plex(
      id: 'show',
      kind: MediaKind.show,
      year: 2018,
      durationMs: 3600000,
      genres: ['History', 'Drama'],
      ratings: [MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.1)],
    );
    LocaleSettings.setLocaleSync(AppLocale.en);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: FeaturedMetadata(item: episode, details: show, centered: true),
            ),
          ),
        ),
      ),
    );
    expect(find.text('91  CRITICS', findRichText: true), findsOneWidget);
    expect(find.textContaining('AUDIENCE', findRichText: true), findsNothing);
    expect(find.text('2026  ·  45min  ·  History  ·  Drama'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
