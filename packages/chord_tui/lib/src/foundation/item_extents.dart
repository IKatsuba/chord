import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'scroll_state.dart';

/// Every item's height in rows at one width, with the version each was
/// measured under, and their running sum.
class ItemExtents {
  /// Extents with no height measured yet.
  ItemExtents();

  final List<int?> _heights = [];
  final List<Object?> _versions = [];
  int? _width;

  // _tops[i] is the row item i starts at, valid for i <= _validTops.
  Int64List _tops = Int64List(1);
  int _validTops = 0;

  /// How many items there are.
  int get length => _heights.length;

  /// Sets the item count, dropping the heights past it.
  set length(int n) {
    if (n == _heights.length) return;
    if (n < _heights.length) {
      _heights.length = n;
      _versions.length = n;
      if (_validTops > n) _validTops = n;
    } else {
      _dirtyFrom(_heights.length);
      _heights.addAll(List.filled(n - _heights.length, null));
      _versions.addAll(List.filled(n - _versions.length, null));
    }
  }

  /// Sets the width heights are measured at; a new width drops them all.
  set width(int w) {
    if (w == _width) return;
    _width = w;
    clear();
  }

  /// Drops every height.
  void clear() {
    _heights.fillRange(0, _heights.length, null);
    _versions.fillRange(0, _versions.length, null);
    _validTops = 0;
  }

  /// Drops every item and gives back the running sum's buffer, as the
  /// owner is disposed while something may still hold it.
  void dispose() {
    length = 0;
    _tops = Int64List(1);
    _validTops = 0;
  }

  /// How many running sums the buffer holds room for, for tests.
  @visibleForTesting
  int get topsCapacity => _tops.length;

  /// The height of item [i], or null when it is not measured.
  int? heightOf(int i) => _heights[i];

  /// Whether item [i] has a height.
  bool isKnown(int i) => _heights[i] != null;

  /// Records that item [i] is [height] rows under [version].
  void record(int i, int height, Object? version) {
    if (_heights[i] != height) _dirtyFrom(i);
    _heights[i] = height;
    _versions[i] = version;
  }

  /// Drops the height of item [i].
  void drop(int i) {
    if (_heights[i] == null) return;
    _heights[i] = null;
    _dirtyFrom(i);
  }

  /// Drops each height whose item's version differs from the one it was
  /// measured under.
  void checkVersions(Object? Function(int index) versionOf) {
    for (var i = 0; i < _heights.length; i++) {
      if (_heights[i] == null) continue;
      final v = versionOf(i);
      final old = _versions[i];
      if (!identical(v, old) && v != old) drop(i);
    }
  }

  void _dirtyFrom(int i) {
    if (_validTops > i) _validTops = i;
  }

  void _ensureTops(int upTo) {
    if (upTo <= _validTops) return;
    if (_tops.length <= _heights.length) {
      final grown = Int64List(_heights.length * 2 + 1)
        ..setRange(0, _validTops + 1, _tops);
      _tops = grown;
    }
    for (var i = _validTops; i < upTo; i++) {
      _tops[i + 1] = _tops[i] + (_heights[i] ?? 0);
    }
    _validTops = upTo;
  }

  /// The row item [i] starts at; unmeasured items count as 0 rows.
  /// [i] may be [length], for the total.
  int itemTop(int i) {
    _ensureTops(i);
    return _tops[i];
  }

  /// Every item's rows together.
  int get total => itemTop(length);

  /// The item [row] falls in, and how far in; null with no items.
  ///
  /// It is the last item starting at or above [row], so a zero-height item
  /// never anchors a row another item takes.
  ListAnchor? anchorAt(int row) {
    if (length == 0) return null;
    _ensureTops(length);
    var lo = 0;
    var hi = length - 1;
    if (row < 0) row = 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= row) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return ListAnchor(lo, row - _tops[lo]);
  }

  /// The row [anchor] is at now, as far into its item as it still reaches;
  /// null when the item is gone.
  int? topOf(ListAnchor anchor) {
    if (anchor.index >= length) return null;
    final h = _heights[anchor.index] ?? 0;
    final within = anchor.rowsInto < h - 1 ? anchor.rowsInto : h - 1;
    return itemTop(anchor.index) + (within > 0 ? within : 0);
  }
}
