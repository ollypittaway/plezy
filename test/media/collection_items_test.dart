import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/collection_items.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_version.dart';

import '../test_helpers/media_items.dart';

void main() {
  final kids = testMediaItem(
    id: 'kids',
    title: 'Holiday',
    year: 2024,
    libraryId: '3',
    libraryTitle: 'Kids Movies',
    serverId: 's',
  );
  final movies = kids.copyWith(id: 'movies', libraryId: '1', libraryTitle: 'Movies');
  final uhd = kids.copyWith(id: 'uhd', libraryId: '2', libraryTitle: '4K Movies');
  final other = kids.copyWith(id: 'other', title: 'Another film');

  test('out-of-order pages preserve slots and map skeletons back to server offsets', () {
    final rows = CollectionItems({5: movies, 7: uhd, 0: kids, 1: kids, 2: other}, 10, {'s:2': 0, 's:1': 1, 's:3': 2});
    expect(rows.length, 7);
    expect(rows.items, {0: uhd, 1: other});
    expect(List.generate(rows.length, rows.sourceIndex), [0, 2, 3, 4, 6, 8, 9]);
  });

  test('falls through missing libraries and explicitly unavailable versions', () {
    final unavailable = movies.copyWith(
      mediaVersions: const [
        MediaVersion(
          id: 'file',
          parts: [MediaPart(id: 'part', exists: false)],
        ),
      ],
    );
    expect(preferredCollectionCopy([kids, uhd], {}), uhd);
    expect(preferredCollectionCopy([kids, unavailable, uhd], {}), uhd);
    expect(preferredCollectionCopy([kids, uhd], {'s:3': 0}), kids);
  });
}
