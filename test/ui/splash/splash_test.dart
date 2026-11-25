import 'dart:math' as math;

import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/header/mark.dart';
import 'package:chord/ui/header/mark_rows.dart';
import 'package:chord/ui/splash/splash.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

List<String> text(int step, [MarkGrid grid = splashMark]) => [
  for (final row in markRows(splashFrame(grid, step), const MarkPlain()))
    row.map((segment) => segment.text).join(),
];

void main() {
  test('the path is the circle every 45°, counter-clockwise from the top', () {
    for (final (step, place) in splashPath.indexed) {
      final angle = step * math.pi / 4;
      expect(place, (
        column: -math.sin(angle).round(),
        half: 2 - (2 * math.cos(angle)).round(),
      ));
    }
    // Left first.
    expect(splashPath[1].column, -1);
  });

  test('every step moves one half row and at most one column', () {
    for (final (step, place) in splashPath.indexed) {
      final next = splashPath[(step + 1) % splashPath.length];
      expect((next.half - place.half).abs(), 1);
      expect((next.column - place.column).abs(), lessThanOrEqualTo(1));
    }
  });

  test('the box keeps its size at every step, so the lines never move', () {
    for (final (grid, rows, columns) in [(splashMark, 10, 11), (mark, 6, 6)]) {
      for (var step = 0; step < splashPath.length; step++) {
        final drawn = text(step, grid);
        expect(drawn, hasLength(rows));
        for (final row in drawn) {
          expect(row.length, columns);
        }
      }
    }
  });

  test('the top centre is the mark one column in', () {
    expect(text(0), [
      ' ██▄       ',
      ' ████▄     ',
      ' ██████▄   ',
      '  ▀██████▄ ',
      '  ▄██████▀ ',
      ' ██████▀   ',
      ' ████▀     ',
      ' ██▀       ',
      '           ',
      '           ',
    ]);
  });

  test('an odd half row is a drawing of its own, not the rows moved', () {
    expect(text(1), [
      '▄▄         ',
      '███▄       ',
      '█████▄     ',
      '▀██████▄   ',
      '  ███████  ',
      '▄██████▀   ',
      '█████▀     ',
      '███▀       ',
      '▀▀         ',
      '           ',
    ]);
    expect(text(5, mark), [
      '      ',
      '  ▄   ',
      '  ██▄ ',
      '   ███',
      '  ██▀ ',
      '  ▀   ',
    ]);
  });

  test('the mark is 8 rows from 24×16, 4 from 16×9, none below', () {
    expect(splashMarkFor(120, 40), same(splashMark));
    expect(splashMarkFor(80, 24), same(splashMark));
    expect(splashMarkFor(24, 16), same(splashMark));
    expect(splashMarkFor(24, 15), same(mark));
    expect(splashMarkFor(44, 12), same(mark));
    expect(splashMarkFor(16, 9), same(mark));
    expect(splashMarkFor(15, 40), isNull);
    expect(splashMarkFor(40, 8), isNull);
  });

  test('the lines say the start, then its seconds and the keys once slow', () {
    expect(splashLines(agent: 'claude', elapsed: 0, closing: false), (
      'Starting claude…',
      '',
    ));
    expect(
      splashLines(agent: 'claude', elapsed: slowStartMs - 1, closing: false),
      ('Starting claude…', ''),
    );
    expect(splashLines(agent: 'claude', elapsed: 12400, closing: false), (
      'Starting claude… 12s',
      slowHint,
    ));
    expect(slowHint, 'esc for the window · ctrl+c to quit');
  });

  test('an armed quit and the stop take the first line', () {
    const armed = 'Press ctrl+c again to quit';
    expect(
      splashLines(
        agent: 'claude',
        elapsed: 12000,
        armed: armed,
        closing: false,
      ),
      (armed, slowHint),
    );
    expect(
      splashLines(agent: 'claude', elapsed: 0, armed: armed, closing: false),
      (armed, ''),
    );
    expect(
      splashLines(agent: 'claude', elapsed: 12000, armed: armed, closing: true),
      ('Stopping claude…', slowHint),
    );
  });

  test('the block is centred, rounding up and left, as the frames are', () {
    final quick = splashLines(agent: 'claude', elapsed: 0, closing: false);
    final slow = splashLines(agent: 'claude', elapsed: 12000, closing: false);
    expect(splashLayout(80, 24, splashMark, quick), (
      top: 5,
      markLeft: 34,
      lineLefts: (32, 40),
    ));
    expect(splashLayout(120, 40, splashMark, quick).top, 13);
    expect(splashLayout(120, 40, splashMark, quick).markLeft, 54);
    expect(splashLayout(44, 12, mark, slow), (
      top: 1,
      markLeft: 19,
      lineLefts: (12, 4),
    ));
    expect(splashLayout(40, 7, null, slow), (
      top: 2,
      markLeft: 0,
      lineLefts: (10, 2),
    ));
    // A line wider than the screen starts at its left edge.
    expect(splashLayout(20, 7, null, slow).lineLefts, (0, 0));
  });

  test('the splash holds the screen until the start ends or esc leaves it', () {
    AppState at(StartPhase phase, {bool closing = false}) => AppState(
      start: StartState(phase: phase),
      closing: closing,
    );
    final starting = at(StartPhase.starting);
    expect(splashShown(true, false, starting), isTrue);
    expect(
      splashShown(true, false, at(StartPhase.starting, closing: true)),
      isTrue,
    );
    expect(splashShown(true, false, at(StartPhase.connected)), isFalse);
    expect(splashShown(true, false, at(StartPhase.failed)), isFalse);
    expect(splashShown(true, true, starting), isFalse);
    expect(splashShown(false, false, starting), isFalse);
  });

  group('tester: splash boundary geometry', () {
    test('zero and one cell retain nonnegative placement without a mark', () {
      for (final columns in [0, 1]) {
        for (final rows in [0, 1]) {
          final grid = splashMarkFor(columns, rows);
          expect(grid, isNull);
          expect(splashLayout(columns, rows, grid, ('界👩‍💻é', slowHint)), (
            top: 0,
            markLeft: 0,
            lineLefts: (0, 0),
          ));
        }
      }
    });

    test('line centring measures wide and combining graphemes in cells', () {
      for (final columns in [80, 120]) {
        final layout = splashLayout(columns, 24, null, ('界', 'é'));
        expect(layout.lineLefts, ((columns - 2) ~/ 2, (columns - 1) ~/ 2));
      }
    });

    test(
      'repeated frames neither change the source grid nor retain output edits',
      () {
        final before = [
          for (final row in splashMark) [...row],
        ];
        for (var step = 0; step < 1000; step++) {
          final frame = splashFrame(splashMark, step);
          expect(frame, splashFrame(splashMark, step % splashPath.length));
          frame.first[0] = 0.123;
        }
        expect(splashMark, before);
      },
    );

    test(
      'slow threshold is exact and closing never bypasses opt-out or Esc',
      () {
        expect(splashStepMs, 300);
        expect(splashLines(agent: 'fake', elapsed: 5000, closing: false), (
          'Starting fake… 5s',
          slowHint,
        ));
        for (final phase in StartPhase.values) {
          final closing = AppState(
            start: StartState(phase: phase),
            closing: true,
          );
          expect(splashShown(true, false, closing), isTrue);
          expect(splashShown(false, false, closing), isFalse);
          expect(splashShown(true, true, closing), isFalse);
        }
      },
    );
  });
}
