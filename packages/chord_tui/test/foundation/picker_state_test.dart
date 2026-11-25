import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const items = [
  PickerItem(value: 'careful', label: 'Careful'),
  PickerItem(value: 'balanced', label: 'Balanced'),
  PickerItem(value: 'quick', label: 'Quick'),
  PickerItem(value: 'thorough', label: 'Thorough'),
];

const filter = FzfPickerFilter();

List<String> labels(PickerState<String> s) => [
  for (var i = 0; i < s.results.length; i++) s.resultAt(i).label,
];

void main() {
  testerEdges();
  group('state', () {
    test('opens on the initial value, else the first, else nothing', () {
      expect(
        PickerState.initial(items, initialValue: 'quick').selected,
        'quick',
      );
      expect(
        PickerState.initial(items, initialValue: 'gone').selected,
        'careful',
      );
      expect(PickerState.initial(items).highlighted, 0);
      final empty = PickerState<String>.initial(const []);
      expect(empty.selected, isNull);
      expect(empty.highlighted, -1);
    });

    test('an empty query keeps every item in order, without positions', () {
      final s = PickerState.initial(items).withQuery('', filter);
      expect(labels(s), ['Careful', 'Balanced', 'Quick', 'Thorough']);
      expect(s.results.every((m) => m.matchedPositions.isEmpty), isTrue);
    });

    test('a query ranks by fzf and keeps the highlight if it matches', () {
      var s = PickerState.initial(items, initialValue: 'thorough');
      s = s.withQuery('r', filter);
      expect(labels(s), ['Careful', 'Thorough']);
      expect(s.selected, 'thorough');
      expect(s.highlighted, 1);
      s = s.withQuery('ca', filter);
      expect(labels(s), ['Careful']);
      expect(s.selected, 'careful', reason: 'the first, as thorough is gone');
      expect(s.results.single.matchedPositions, [0, 1]);
      s = s.withQuery('zz', filter);
      expect(s.results, isEmpty);
      expect(s.selected, isNull);
      expect(s.valueOf(1), isNull);
    });

    test('new items are matched again, never read by old indices', () {
      var s = PickerState.initial(items, initialValue: 'quick');
      s = s.withQuery('h', filter);
      expect(labels(s), ['Thorough']);
      expect(s.selected, 'thorough', reason: 'quick is gone: the first result');
      s = s.withItems(const [
        PickerItem(value: 'hush', label: 'Hush'),
        PickerItem(value: 'thorough', label: 'Thorough'),
      ], filter);
      expect(labels(s), containsAll(['Hush', 'Thorough']));
      expect(s.selected, 'thorough');
      s = s.withItems(const [PickerItem(value: 'hush', label: 'Hush')], filter);
      expect(s.selected, 'hush');
      expect(s.valueOf(1), 'hush');
      expect(s.valueOf(2), isNull);
    });

    test('moving stops at the ends, or goes round when asked', () {
      var s = PickerState.initial(items);
      s = s.moved(-1);
      expect(s.selected, 'careful');
      s = s.moved(1).moved(1).moved(1).moved(1);
      expect(s.selected, 'thorough');
      expect(s.moved(1, wrap: true).selected, 'careful');
      expect(
        PickerState.initial(items).moved(-1, wrap: true).selected,
        'thorough',
      );
    });

    test('a limit keeps moves among the first results', () {
      final s = PickerState.initial(items);
      expect(s.moved(-1, wrap: true, limit: 2).selected, 'balanced');
      expect(
        s
            .moved(1, wrap: true, limit: 2)
            .moved(1, wrap: true, limit: 2)
            .selected,
        'careful',
      );
      expect(s.moved(5, limit: 3).selected, 'quick');
      final far = PickerState.initial(items, initialValue: 'thorough');
      expect(
        far.moved(1, wrap: true, limit: 2).selected,
        'balanced',
        reason: 'from the first, as the highlight had no row',
      );
      expect(far.within(2).selected, 'careful');
      expect(far.within(4).selected, 'thorough');
      expect(s.moved(1, limit: 0).selected, 'careful');
    });

    test('numbers count results from one', () {
      final s = PickerState.initial(items).withQuery('r', filter);
      expect(s.valueOf(1), 'careful');
      expect(s.valueOf(2), 'thorough');
      expect(s.valueOf(0), isNull);
      expect(s.valueOf(3), isNull);
    });

    test('the mode is kept across queries', () {
      final s = PickerState.initial(items).withMode(PickerMode.editing);
      expect(s.withQuery('q', filter).mode, PickerMode.editing);
    });
  });

  group('view', () {
    final ones = List.filled(10, 1);

    test('the window moves only when the highlight leaves it', () {
      var v = openPickerView(ones, 0, 4);
      expect(v, (highlighted: 0, top: 0));
      for (var i = 0; i < 3; i++) {
        v = pickerMove(v, ones, 4, 1)!;
      }
      // Four rows, but one is the `… +N more` row: three choices fit.
      expect(v.top, 1);
      v = pickerMove(v, ones, 4, -1)!;
      expect(v.top, 1);
      expect(pickerMove((highlighted: 0, top: 0), ones, 4, -1), isNull);
    });

    test('a tall row is read a line a press before the highlight moves', () {
      final heights = [1, 6, 1];
      // Its first line is already in sight on the second row: no move.
      var v = pickerMove((highlighted: 0, top: 0), heights, 4, 1)!;
      expect(v, (highlighted: 1, top: 0));
      for (final top in [1, 2, 3]) {
        v = pickerMove(v, heights, 4, 1)!;
        expect(v, (highlighted: 1, top: top));
      }
      v = pickerMove(v, heights, 4, 1)!;
      expect(v, (highlighted: 2, top: 4));
      v = pickerMove(v, heights, 4, -1)!;
      expect(v, (highlighted: 1, top: 4), reason: 'back onto its last line');
    });

    test('a resize shows the highlighted row from its first line', () {
      final heights = [1, 6, 1];
      expect(pickerFromFirstLine((highlighted: 1, top: 4), heights, 4), (
        highlighted: 1,
        top: 1,
      ));
    });

    test('lines in sight carry edge marks and count the rows below', () {
      final (:lines, :hidden) = pickerLines(ones, (highlighted: 2, top: 1), 4);
      expect([for (final l in lines) l.index], [1, 2, 3]);
      expect([for (final l in lines) l.edge], ['↑', ' ', '↓']);
      expect(hidden, 6);
    });

    test('rows that fit have no edges and nothing hidden', () {
      final (:lines, :hidden) = pickerLines(
        [1, 2],
        (highlighted: 0, top: 0),
        8,
      );
      expect(lines, hasLength(3));
      expect(lines.every((l) => l.edge == null), isTrue);
      expect([for (final l in lines) l.first], [true, true, false]);
      expect(hidden, 0);
    });

    test('a highlighted row as tall as the budget hides the count', () {
      final (:lines, :hidden) = pickerLines(
        [5, 1, 1],
        (highlighted: 0, top: 0),
        4,
      );
      expect(lines, hasLength(4));
      expect(hidden, 0);
      expect(pickerRoom([5, 1, 1], 0, 0, 4), 4);
    });

    test('numbers are padded to the widest', () {
      expect(pickerNumber(0, 9), '1.');
      expect(pickerNumber(0, 10), '1. ');
      expect(pickerNumber(9, 10), '10.');
    });
  });

  group('the fzf filter', () {
    test("positions are the label's own units, not its NFC form's", () {
      const label = 'cafe\u0301 name';
      final name = filter.match('name', [label]).single;
      expect(name.matchedPositions, [6, 7, 8, 9]);
      expect([for (final p in name.matchedPositions) label[p]].join(), 'name');
      // A hit on the composed é marks both of its units.
      expect(filter.match('é', [label]).single.matchedPositions, [3, 4]);
      expect(filter.match('cafe', [label]).single.matchedPositions, [
        0,
        1,
        2,
        3,
        4,
      ]);
    });

    test("composed labels keep fzf's positions", () {
      expect(filter.match('fe', ['café']).single.matchedPositions, [2, 3]);
      expect(filter.match('sm', ['🙂 smile']).single.matchedPositions, [3, 4]);
    });
  });
}

void testerEdges() {
  group('tester: Picker filter coordinates and state lifetime', () {
    test(
      'Hangul composition maps a hit and following text to original units',
      () {
        const label = '\u1100\u1161\u11a8 end';
        expect(filter.match('각', [label]).single.matchedPositions, [0, 1, 2]);
        expect(filter.match('end', [label]).single.matchedPositions, [4, 5, 6]);
      },
    );
    test('multiple composed clusters preserve offsets around emoji', () {
      const label = 'a\u030a🙂e\u0301 tail';
      expect(filter.match('ae', [label]).single.matchedPositions, [0, 1, 4, 5]);
      expect(filter.match('🙂', [label]).single.matchedPositions, [2, 3]);
      expect(filter.match('tail', [label]).single.matchedPositions, [
        7,
        8,
        9,
        10,
      ]);
    });
    test('normalization reorders marks without dropping original units', () {
      const label = 'a\u0315\u0300 z';
      expect(filter.match('a', [label]).single.matchedPositions, [0, 1, 2]);
      expect(filter.match('z', [label]).single.matchedPositions, [4]);
    });
    test('empty queries bypass a filter and restore original item order', () {
      final called = _TesterCountingFilter();
      var state = PickerState.initial(items, initialValue: 'quick');
      state = state.withQuery('', called);
      expect(called.calls, 0);
      expect(labels(state), ['Careful', 'Balanced', 'Quick', 'Thorough']);
      state = state.withQuery('anything', called);
      expect(called.calls, 1);
      expect(state.selected, 'thorough');
      state = state.withQuery('', called);
      expect(called.calls, 1);
      expect(state.selected, 'thorough');
      expect(state.valueOf(4), 'thorough');
    });
    test('a thousand replacements preserve mode without stale indices', () {
      final initial = PickerState.initial(items).withMode(PickerMode.editing);
      var state = initial.withQuery('same', filter);
      for (var i = 0; i < 1000; i++) {
        state = state.withItems([
          PickerItem(value: 'v$i', label: 'same'),
        ], filter);
      }
      expect(state.mode, PickerMode.editing);
      expect(state.selected, 'v999');
      expect(state.valueOf(1), 'v999');
      expect(initial.items, same(items));
      expect(initial.selected, 'careful');
      expect(initial.query, isEmpty);
      state = state.withItems(const [], filter);
      expect(state.results, isEmpty);
      expect(state.selected, isNull);
      expect(state.moved(1), same(state));
    });
  });
  group('tester: Picker visual-row budget invariants', () {
    for (final heights in const [
      [1],
      [7],
      [1, 7, 1],
      [2, 1, 4, 2],
      [1, 1, 1, 1, 1],
    ]) {
      test('bounded contiguous lines across moves for $heights', () {
        final starts = <int>[];
        var total = 0;
        for (final height in heights) {
          starts.add(total);
          total += height;
        }
        for (var budget = 0; budget <= 8; budget++) {
          var view = openPickerView(heights, 0, budget);
          for (var step = 0; step < 30; step++) {
            final shown = pickerLines(heights, view, budget);
            expect(shown.lines.length, lessThanOrEqualTo(budget));
            expect(shown.hidden, inInclusiveRange(0, heights.length));
            var previous = -1;
            for (final line in shown.lines) {
              expect(line.index, inInclusiveRange(0, heights.length - 1));
              expect(line.line, inInclusiveRange(0, heights[line.index] - 1));
              final absolute = starts[line.index] + line.line;
              if (previous >= 0) expect(absolute, previous + 1);
              expect(absolute, lessThan(total));
              expect(line.first, line.line == 0);
              previous = absolute;
            }
            view =
                pickerMove(view, heights, budget, step < 15 ? 1 : -1) ?? view;
            expect(view.highlighted, inInclusiveRange(0, heights.length - 1));
            if (budget > 0) expect(view.top, inInclusiveRange(0, total));
          }
        }
      });
    }
  });
}

class _TesterCountingFilter implements PickerFilter {
  var calls = 0;
  @override
  List<PickerMatch> match(String query, List<String> labels) {
    calls++;
    return [PickerMatch(index: labels.length - 1, matchedPositions: const [])];
  }
}
