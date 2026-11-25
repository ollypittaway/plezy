import 'package:collection/collection.dart';

import 'media_item.dart';
import 'media_item_merge.dart';
import 'media_title_groups.dart';

/// An unavailable file should not displace a copy that the server can play.
/// Listing rows often omit file details, so only explicit failures are skipped.
MediaItem preferredCollectionCopy(List<MediaItem> copies, Map<String, int> libraryOrder) {
  if (copies.length == 1) return copies.single;
  final available = copies.where((item) {
    final versions = item.mediaVersions;
    return versions == null || versions.isEmpty || versions.any((version) => version.isPlayable);
  }).toList();
  return preferredLibraryCopy(available.isEmpty ? copies : available, libraryOrder);
}

/// Keeps the first position of each title while sparse server pages arrive.
/// Unloaded positions remain addressable at their original server offsets.
class CollectionItems {
  final items = <int, MediaItem>{};
  final _skipped = <int>[];
  final int sourceCount;

  CollectionItems(Map<int, MediaItem> loaded, this.sourceCount, Map<String, int> libraryOrder) {
    final indices = loaded.keys.toList()..sort();
    final groups = groupMediaCopiesByTitle(indices.map((i) => loaded[i]!));
    final firstCopies = {
      for (final group in groups) group.first.globalKey: preferredCollectionCopy(group, libraryOrder),
    };
    for (final index in indices) {
      final visibleIndex = index - _skipped.length;
      final copy = firstCopies.remove(loaded[index]!.globalKey);
      if (copy == null) {
        _skipped.add(visibleIndex);
      } else {
        items[visibleIndex] = copy;
      }
    }
  }

  int get length => sourceCount - _skipped.length;

  int sourceIndex(int visibleIndex) => visibleIndex + lowerBound(_skipped, visibleIndex + 1);
}
