import 'dart:collection';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  _testerIndexedGeometry();
  test(
    'geometry snapshots heights once and never rereads them on navigation',
    () {
      final source = _CountingHeights(10000);
      final geometry = PickerGeometry(source);
      expect(source.reads, 10000);
      source.reads = 0;
      var view = geometry.open(5000, 8);
      for (var i = 0; i < 100; i++) {
        view = geometry.move(view, 8, 1)!;
        final shown = geometry.lines(view, 8);
        expect(shown.lines, hasLength(7));
        expect(shown.hidden, 10000 - view.top - 7);
        expect(geometry.itemTop(view.highlighted), view.highlighted);
        expect(geometry.heightOf(view.highlighted), 1);
      }
      expect(source.reads, 0);
      expect(geometry.fromFirstLine(view, 4).top, view.highlighted);
      expect(geometry.total, 10000);
    },
  );

  test('geometry owns an immutable snapshot and rejects negative heights', () {
    final heights = [1, 2, 3];
    final geometry = PickerGeometry(heights);
    heights[0] = 100;
    heights.add(4);
    expect(geometry.length, 3);
    expect(geometry.total, 6);
    expect(geometry.itemTop(1), 1);
    expect(() => PickerGeometry([1, -1]), throwsArgumentError);
    expect(
      PickerGeometry([]).lines((highlighted: 0, top: 0), 4).lines,
      isEmpty,
    );
  });

  test('indexed visible lines match a brute force physical-line oracle', () {
    for (final heights in [
      [1, 1, 1, 1, 1],
      [0, 2, 0, 3, 0, 1, 0],
      [0, 0, 0],
      [2, 7, 1, 4],
    ]) {
      final geometry = PickerGeometry(heights);
      for (var highlighted = 0; highlighted < heights.length; highlighted++) {
        for (var budget = 0; budget <= 8; budget++) {
          for (var top = -1; top <= geometry.total + 1; top++) {
            for (final above in [false, true]) {
              final view = (highlighted: highlighted, top: top);
              final actual = geometry.lines(
                view,
                budget,
                countHiddenItemsAbove: above,
              );
              final expected = _bruteLines(heights, view, budget, above);
              final reason = '$heights $view budget=$budget above=$above';
              expect(actual.lines, expected.lines, reason: reason);
              expect(actual.hidden, expected.hidden, reason: reason);
            }
          }
        }
      }
    }
  });

  test('a very tall choice enumerates its visible slice only', () {
    final geometry = PickerGeometry([0, 1 << 40, 0, 1]);
    final view = (highlighted: 1, top: (1 << 39));
    final shown = geometry.lines(view, 4, countHiddenItemsAbove: true);
    expect(shown.hidden, 0);
    expect(shown.lines.map((line) => line.line), [
      for (var i = 0; i < 4; i++) view.top + i,
    ]);
    expect(geometry.move(view, 4, 1)!.top, view.top + 1);
  });

  test('indexed selection moves without comparing all selected values', () {
    final items = [
      for (var i = 0; i < 10000; i++)
        PickerItem(value: _Value(i), label: 'Choice $i'),
    ];
    var state = PickerState.initial(items, initialValue: items.last.value);
    final results = state.results;
    _Value.comparisons = 0;
    for (var i = 0; i < 100; i++) {
      state = state.moved(-1).withMode(PickerMode.editing).within(10000);
      expect(state.highlighted, 9998 - i);
      expect(identical(state.results, results), isTrue);
    }
    expect(state.selected!.index, 9899);
    expect(_Value.comparisons, 0);
  });
}

({List<PickerLine> lines, int hidden}) _bruteLines(
  List<int> heights,
  PickerView view,
  int budget,
  bool above,
) {
  final starts = <int>[];
  var total = 0;
  for (final height in heights) {
    starts.add(total);
    total += height;
  }
  final scrolls = total > budget;
  final rawTop = view.top < 0 ? 0 : view.top;
  final reserve =
      total > budget &&
      heights[view.highlighted] < budget &&
      (above || starts.any((start) => start >= rawTop + budget));
  final fits = scrolls ? budget - (reserve ? 1 : 0) : total;
  final top = scrolls ? view.top.clamp(0, total - fits) : 0;
  final end = top + fits;
  final lines = <PickerLine>[];
  var hidden = 0;
  for (var i = 0; i < heights.length; i++) {
    var visible = false;
    for (var k = 0; k < heights[i]; k++) {
      final at = starts[i] + k;
      if (at < top || at >= end) continue;
      visible = true;
      lines.add((
        index: i,
        line: k,
        first: k == 0,
        edge: !scrolls
            ? null
            : at == top && top > 0
            ? '↑'
            : at == end - 1 && end < total
            ? '↓'
            : ' ',
      ));
    }
    if (!visible && (above || starts[i] >= end)) hidden++;
  }
  return (
    lines: lines,
    hidden: heights[view.highlighted] >= budget ? 0 : hidden,
  );
}

class _CountingHeights extends ListBase<int> {
  _CountingHeights(this.length);
  @override
  final int length;
  var reads = 0;
  @override
  set length(int value) => throw UnsupportedError('Fixed length');
  @override
  int operator [](int index) {
    reads++;
    return 1;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only');
}

class _Value {
  _Value(this.index);
  final int index;
  static var comparisons = 0;
  @override
  bool operator ==(Object other) {
    comparisons++;
    return other is _Value && index == other.index;
  }

  @override
  int get hashCode => index.hashCode;
}

void _testerIndexedGeometry() {
  group('tester: U54a indexed geometry boundaries', () {
    test('empty and singleton geometry survive zero and one row budgets', () {
      for (final heights in <List<int>>[
        [],
        [0],
        [1],
      ]) {
        final geometry = PickerGeometry(heights);
        var view = geometry.open(0, 0);
        expect(geometry.lines(view, 0).lines, isEmpty);
        view = geometry.fromFirstLine(view, 1);
        expect(
          geometry.lines(view, 1).lines.length,
          heights.fold(0, (a, b) => a + b),
        );
        expect(geometry.move(view, 1, 1), isNull);
        expect(geometry.move(view, 1, -1), isNull);
        expect(
          geometry.lines(geometry.fromFirstLine(view, 0), 0).lines,
          isEmpty,
        );
      }
    });

    test('sparse geometry counts hidden zero-height choices on both sides', () {
      final heights = List<int>.filled(10000, 0);
      heights[2] = 2;
      heights[5000] = 3;
      heights[9998] = 1;
      final geometry = PickerGeometry(heights);
      expect(geometry.itemTop(5000), 2);
      expect(geometry.itemTop(9998), 5);
      expect(geometry.itemTop(10000), 6);
      final shown = geometry.lines(
        (highlighted: 9998, top: 4),
        2,
        countHiddenItemsAbove: true,
      );
      expect(shown.lines, [(index: 5000, line: 2, first: false, edge: '↑')]);
      expect(shown.hidden, 9999);
      final last = geometry.lines((highlighted: 9998, top: 5), 2);
      expect(last.lines, [
        (index: 5000, line: 2, first: false, edge: '↑'),
        (index: 9998, line: 0, first: true, edge: ' '),
      ]);
      expect(
        last.hidden,
        1,
        reason: 'the trailing zero-height choice stays hidden',
      );
      heights.fillRange(0, heights.length, 100);
      expect(geometry.total, 6);
    });

    test('tall-row reading and wrap retain first-line resize placement', () {
      final geometry = PickerGeometry([1, 50, 1]);
      for (final budget in [40, 24, 1]) {
        var view = geometry.open(1, budget, top: 1);
        expect(view, (highlighted: 1, top: 1));
        for (var top = 2; top <= 51 - budget; top++) {
          view = geometry.move(view, budget, 1)!;
          expect(view, (highlighted: 1, top: top));
          expect(geometry.lines(view, budget).hidden, 0);
        }
        view = geometry.move(view, budget, 1)!;
        expect(view.highlighted, 2);
        final wrapped = geometry.move(view, budget, 1, wrap: true)!;
        expect(wrapped, (highlighted: 0, top: 0));
        final resized = geometry.fromFirstLine((
          highlighted: 1,
          top: 40,
        ), budget);
        expect(resized, (highlighted: 1, top: 1));
      }
    });

    test('a thousand selected moves read only the selected item', () {
      final items = _TesterGeometryItems(10000);
      var state = PickerState.initial(items, initialValue: 5000);
      final results = state.results;
      items.reads = 0;
      for (var i = 0; i < 1000; i++) {
        state = state
            .moved(i.isEven ? 1 : -1)
            .withMode(PickerMode.editing)
            .within(10000);
        expect(state.selected, i.isEven ? 5001 : 5000);
        expect(state.results, same(results));
      }
      expect(items.reads, 1000);
    });
  });
}

class _TesterGeometryItems extends ListBase<PickerItem<int>> {
  _TesterGeometryItems(this.length);
  @override
  final int length;
  var reads = 0;
  @override
  set length(int value) => throw UnsupportedError('Fixed length');
  @override
  PickerItem<int> operator [](int index) {
    reads++;
    return PickerItem(value: index, label: 'Choice $index');
  }

  @override
  void operator []=(int index, PickerItem<int> value) =>
      throw UnsupportedError('Read only');
}
