import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/grouped_home_hubs.dart';
import 'package:plezy/media/media_kind.dart';

import '../test_helpers/media_items.dart';

void main() {
  test('one poster per film while remakes and conflicting catalogue matches keep their own slots', () {
    final original = testMediaItem(id: 'a', title: 'The Thing', year: 1982, guid: 'plex://movie/a');
    final localTitle = original.copyWith(id: 'b', title: 'La Cosa');
    final noGuid = testMediaItem(id: 'c', title: 'La Cosa', year: 1982);
    final remake = testMediaItem(id: 'd', title: 'The Thing', year: 2011);
    final distinct = original.copyWith(id: 'e', guid: 'plex://movie/e');
    expect(
      interleaveHubItems([
        [original, remake],
        [localTitle, distinct],
        [noGuid],
      ]),
      [original, remake, distinct],
    );
  });

  test('two libraries can share an episode while later episodes remain separate', () {
    final first = testMediaItem(
      id: 'one',
      kind: MediaKind.episode,
      grandparentTitle: 'Series',
      parentIndex: 1,
      index: 1,
    );
    final copy = first.copyWith(id: 'copy');
    final second = first.copyWith(id: 'two', index: 2);
    expect(
      interleaveHubItems([
        [first, second],
        [copy],
      ]),
      [first, second],
    );
  });
}
