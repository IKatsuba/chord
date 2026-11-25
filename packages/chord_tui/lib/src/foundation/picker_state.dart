import 'package:characters/characters.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../text/fzf.dart';

/// One choice of a picker: the [value] it stands for and the [label] it
/// shows. Values tell choices apart across updates, so they must be unique.
class PickerItem<T> {
  /// A choice of [value], shown as [label].
  const PickerItem({required this.value, required this.label});

  /// What choosing it gives.
  final T value;

  /// What it shows, in plain text.
  final String label;
}

/// A label a query matched: its [index] in the labels given, and the
/// [matchedPositions] a row may emphasise.
class PickerMatch {
  /// A match of label [index].
  const PickerMatch({required this.index, required this.matchedPositions});

  /// Where the label is in the list matched.
  final int index;

  /// The matched UTF-16 code units of the label, ascending.
  final List<int> matchedPositions;
}

/// Ranks labels against a query, best first.
abstract interface class PickerFilter {
  /// The labels [query] matches, best first; never called with an empty
  /// query, which keeps every label in order.
  List<PickerMatch> match(String query, List<String> labels);
}

/// The default [PickerFilter]: fzf's matching and order, case-insensitive,
/// as chord filters its lists. fzf matches a label's NFC form; its
/// positions are mapped back to the label's own UTF-16 code units, a hit
/// on a composed letter marking every unit of the label's grapheme.
class FzfPickerFilter implements PickerFilter {
  /// The fzf filter.
  const FzfPickerFilter();

  @override
  List<PickerMatch> match(String query, List<String> labels) => [
    for (final r in Fzf(labels, casing: FzfCasing.caseInsensitive).find(query))
      PickerMatch(
        index: r.index,
        matchedPositions: _original(labels[r.index], r.positions),
      ),
  ];

  // NFC positions in [label] as the label's own code units, grapheme by
  // grapheme, since composing never crosses a grapheme's edge.
  static List<int> _original(String label, List<int> positions) {
    if (positions.isEmpty || unorm.nfc(label) == label) return positions;
    final hits = positions.toSet();
    final out = <int>[];
    var original = 0, composed = 0;
    for (final g in label.characters) {
      final n = unorm.nfc(g).length;
      var hit = false;
      for (var p = composed; p < composed + n && !hit; p++) {
        hit = hits.contains(p);
      }
      if (hit) {
        for (var u = original; u < original + g.length; u++) {
          out.add(u);
        }
      }
      original += g.length;
      composed += n;
    }
    return out;
  }
}

/// Whether a picker's keys move the highlight or edit its filter.
enum PickerMode {
  /// Keys move, choose and cancel.
  navigation,

  /// Keys edit the filter.
  editing,
}

/// What a picker shows and where its highlight is, as plain data: the
/// items, the query and the results it ranks, the highlighted value and
/// the key mode.
class PickerState<T> {
  const PickerState._(
    this.items,
    this.query,
    this.results,
    this.highlighted,
    this.mode,
  );

  /// The state a picker opens in: every item, [initialValue] highlighted
  /// when it is one, else the first.
  factory PickerState.initial(List<PickerItem<T>> items, {T? initialValue}) {
    final results = _all(items);
    final at = items.indexWhere((i) => i.value == initialValue);
    return PickerState._(
      items,
      '',
      results,
      at >= 0 ? at : (items.isEmpty ? -1 : 0),
      PickerMode.navigation,
    );
  }

  /// The items, as last given.
  final List<PickerItem<T>> items;

  /// The filter's text.
  final String query;

  /// The items the query matches, best first, by index into [items].
  final List<PickerMatch> results;

  /// The highlighted value; null when nothing matches.
  T? get selected => highlighted < 0 ? null : resultAt(highlighted).value;

  /// How keys are read.
  final PickerMode mode;

  static List<PickerMatch> _all<T>(List<PickerItem<T>> items) => [
    for (var i = 0; i < items.length; i++)
      PickerMatch(index: i, matchedPositions: const []),
  ];

  /// The highlighted result's place in [results], or -1.
  final int highlighted;

  /// The item at result [n], counting from 0.
  PickerItem<T> resultAt(int n) => items[results[n].index];

  PickerState<T> _rank(
    List<PickerItem<T>> items,
    String query,
    PickerFilter filter,
  ) {
    final results = query.isEmpty
        ? _all(items)
        : filter.match(query, [for (final i in items) i.label]);
    final kept = results.indexWhere((m) => items[m.index].value == selected);
    return PickerState._(
      items,
      query,
      List.unmodifiable(results),
      kept >= 0 ? kept : (results.isEmpty ? -1 : 0),
      mode,
    );
  }

  /// The results for [query]; the highlight stays on its value while that
  /// still matches, else goes to the first result.
  PickerState<T> withQuery(String query, PickerFilter filter) =>
      _rank(items, query, filter);

  /// The results over new [items]: matched again, so no result points into
  /// the old list.
  PickerState<T> withItems(List<PickerItem<T>> items, PickerFilter filter) =>
      _rank(items, query, filter);

  /// The same, with keys read as [mode].
  PickerState<T> withMode(PickerMode mode) =>
      PickerState._(items, query, results, highlighted, mode);

  /// The highlight moved [step] results: stopping at either end, or round
  /// past them when [wrap], as a dialog's choices go. With [limit], only
  /// the first [limit] results take part, as a dialog with rows for fewer
  /// than all its choices; a highlight past them starts from the first.
  PickerState<T> moved(int step, {bool wrap = false, int? limit}) {
    final all = results.length;
    final n = limit != null && limit < all ? limit : all;
    if (n <= 0) return this;
    final at = highlighted < 0 || highlighted >= n ? 0 : highlighted;
    final next = wrap ? (at + step) % n : (at + step).clamp(0, n - 1);
    return PickerState._(items, query, results, next, mode);
  }

  /// The same, with the highlight on the first result when it is not among
  /// the first [limit].
  PickerState<T> within(int limit) {
    if (results.isEmpty || (highlighted >= 0 && highlighted < limit)) {
      return this;
    }
    return PickerState._(items, query, results, 0, mode);
  }

  /// The value of result [number], counting from 1, if there is one.
  T? valueOf(int number) => number >= 1 && number <= results.length
      ? resultAt(number - 1).value
      : null;
}

/// The highlighted result and the first line in sight, among all the
/// results' lines.
typedef PickerView = ({int highlighted, int top});

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Immutable indexed item heights for repeated picker navigation and layout.
/// Prefixes are computed once; only visible physical lines are enumerated.
class PickerGeometry {
  /// Snapshots nonnegative [heights], in result order.
  factory PickerGeometry(List<int> heights) {
    final copy = List<int>.unmodifiable(heights);
    final starts = <int>[0];
    final nonempty = <int>[];
    for (var i = 0; i < copy.length; i++) {
      final height = copy[i];
      if (height < 0) {
        throw ArgumentError.value(height, 'heights', 'Negative height');
      }
      if (height > 0) nonempty.add(i);
      starts.add(starts.last + height);
    }
    return PickerGeometry._(copy, starts, nonempty);
  }

  PickerGeometry._(this._heights, this._starts, this._nonempty);

  final List<int> _heights;
  final List<int> _starts;
  final List<int> _nonempty;

  /// The number of choices, including zero-height choices.
  int get length => _heights.length;

  /// The combined height of all choices.
  int get total => _starts.last;

  /// The exact height of result [index].
  int heightOf(int index) => _heights[index];

  /// The first physical line of result [index], or [total] at [length].
  int itemTop(int index) => _starts[index];

  // The first item starting at or after line, including zero-height items.
  int _lowerStart(int line) {
    var lo = 0, hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[mid] < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // The first nonempty item whose end is beyond line.
  int _visibleStart(int line) {
    var lo = 0, hi = _nonempty.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[_nonempty[mid] + 1] <= line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _lineTop(int index, int budget, int top, bool first) {
    if (total <= budget) return 0;
    final start = _starts[index];
    final end = _starts[index + 1];
    var next = top;
    if (end - start <= budget) {
      if (start < next) next = start;
      if (end - budget > next) next = end - budget;
    } else if (first) {
      next = start < next
          ? start
          : (start - budget + 1 > next ? start - budget + 1 : next);
    } else {
      next = end > next + budget
          ? end - budget
          : (end - 1 < next ? end - 1 : next);
    }
    return _clamp(next, 0, total - budget);
  }

  /// The visible line budget after reserving the hidden-choice footer.
  int room(
    int highlighted,
    int top,
    int budget, {
    bool countHiddenItemsAbove = false,
  }) {
    if (total <= budget || _heights[highlighted] >= budget) return budget;
    return countHiddenItemsAbove || _lowerStart(top + budget) < length
        ? budget - 1
        : budget;
  }

  int _placed(
    int index,
    int budget,
    int top,
    bool first, {
    bool countHiddenItemsAbove = false,
  }) {
    final whole = _lineTop(index, budget, top, first);
    return room(
              index,
              whole,
              budget,
              countHiddenItemsAbove: countHiddenItemsAbove,
            ) <
            budget
        ? _lineTop(index, budget - 1, top, first)
        : whole;
  }

  /// Reveals [highlighted] minimally from [top], measured in physical lines.
  PickerView open(
    int highlighted,
    int budget, {
    bool countHiddenItemsAbove = false,
    int top = 0,
  }) => (
    highlighted: highlighted,
    top: length == 0
        ? 0
        : _placed(
            highlighted,
            budget,
            top,
            true,
            countHiddenItemsAbove: countHiddenItemsAbove,
          ),
  );

  /// Reveals [view]'s highlighted first line, as after a resize.
  PickerView fromFirstLine(
    PickerView view,
    int budget, {
    bool countHiddenItemsAbove = false,
  }) => length == 0
      ? (highlighted: 0, top: 0)
      : (
          highlighted: view.highlighted,
          top: _placed(
            view.highlighted,
            budget,
            _starts[view.highlighted],
            true,
            countHiddenItemsAbove: countHiddenItemsAbove,
          ),
        );

  /// Moves by [step], reading a tall choice's lines before leaving it.
  /// Returns null when clamping at an end leaves the view unchanged.
  PickerView? move(
    PickerView view,
    int budget,
    int step, {
    bool wrap = false,
    bool countHiddenItemsAbove = false,
  }) {
    if (length == 0) return null;
    final start = _starts[view.highlighted];
    final end = _starts[view.highlighted + 1];
    if (total > budget && end - start > budget) {
      if (step > 0 && end > view.top + budget) {
        return (highlighted: view.highlighted, top: view.top + 1);
      }
      if (step < 0 && start < view.top) {
        return (highlighted: view.highlighted, top: view.top - 1);
      }
    }
    final next = wrap
        ? (view.highlighted + step) % length
        : _clamp(view.highlighted + step, 0, length - 1);
    if (next == view.highlighted) return null;
    final down = wrap ? next > view.highlighted : step > 0;
    return (
      highlighted: next,
      top: _placed(
        next,
        budget,
        view.top,
        down,
        countHiddenItemsAbove: countHiddenItemsAbove,
      ),
    );
  }

  /// Enumerates only visible lines and counts wholly hidden choices.
  /// A highlighted choice filling the budget suppresses the footer.
  ({List<PickerLine> lines, int hidden}) lines(
    PickerView view,
    int budget, {
    bool countHiddenItemsAbove = false,
  }) {
    if (length == 0) return (lines: const [], hidden: 0);
    final scrolls = total > budget;
    final fits = scrolls
        ? room(
            view.highlighted,
            view.top < 0 ? 0 : view.top,
            budget,
            countHiddenItemsAbove: countHiddenItemsAbove,
          )
        : total;
    final top = scrolls ? _clamp(view.top, 0, total - fits) : 0;
    final end = scrolls ? top + fits : total;
    final lines = <PickerLine>[];
    var visible = 0;
    for (var at = _visibleStart(top); fits > 0 && at < _nonempty.length; at++) {
      final i = _nonempty[at];
      final start = _starts[i];
      if (start >= end) break;
      visible++;
      final from = top > start ? top - start : 0;
      final until = end < _starts[i + 1] ? end - start : _heights[i];
      for (var k = from; k < until; k++) {
        final absolute = start + k;
        lines.add((
          index: i,
          line: k,
          first: k == 0,
          edge: !scrolls
              ? null
              : (absolute == top && top > 0)
              ? '↑'
              : (absolute == end - 1 && end < total)
              ? '↓'
              : ' ',
        ));
      }
    }
    final hidden = countHiddenItemsAbove
        ? length - visible
        : length - _lowerStart(end);
    return (
      lines: lines,
      hidden: _heights[view.highlighted] >= budget ? 0 : hidden,
    );
  }
}

/// Reveals [highlighted] minimally from [top], measured in physical lines.
/// A highlighted row taller than the viewport opens on its first line.
PickerView openPickerView(
  List<int> heights,
  int highlighted,
  int budget, {
  bool countHiddenItemsAbove = false,
  int top = 0,
}) => PickerGeometry(heights).open(
  highlighted,
  budget,
  top: top,
  countHiddenItemsAbove: countHiddenItemsAbove,
);

/// [view] again from its highlighted row's first line, as after a resize.
PickerView pickerFromFirstLine(
  PickerView view,
  List<int> heights,
  int budget, {
  bool countHiddenItemsAbove = false,
}) => PickerGeometry(
  heights,
).fromFirstLine(view, budget, countHiddenItemsAbove: countHiddenItemsAbove);

/// The visible budget, less a footer when choices are wholly hidden.
int pickerRoom(
  List<int> heights,
  int highlighted,
  int top,
  int budget, {
  bool countHiddenItemsAbove = false,
}) => PickerGeometry(
  heights,
).room(highlighted, top, budget, countHiddenItemsAbove: countHiddenItemsAbove);

/// Moves the highlight or reads a tall row; null when nothing changes.
PickerView? pickerMove(
  PickerView view,
  List<int> heights,
  int budget,
  int step, {
  bool wrap = false,
  bool countHiddenItemsAbove = false,
}) => PickerGeometry(heights).move(
  view,
  budget,
  step,
  wrap: wrap,
  countHiddenItemsAbove: countHiddenItemsAbove,
);

/// One line in sight of a picker row.
typedef PickerLine = ({int index, int line, bool first, String? edge});

/// The visible lines with edge markers, and wholly hidden choice count.
({List<PickerLine> lines, int hidden}) pickerLines(
  List<int> heights,
  PickerView view,
  int budget, {
  bool countHiddenItemsAbove = false,
}) => PickerGeometry(
  heights,
).lines(view, budget, countHiddenItemsAbove: countHiddenItemsAbove);

/// A result's number as drawn: `1.` padded to the widest, `${count}.`.
String pickerNumber(int index, int count) =>
    '${index + 1}.'.padRight('$count.'.length);
