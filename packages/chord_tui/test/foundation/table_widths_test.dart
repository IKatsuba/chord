import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('equal flex columns split the room, the rest in column order', () {
    expect(
      solveColumnWidths(
        specs: const [FlexColumnWidth(), FlexColumnWidth(), FlexColumnWidth()],
        natural: const [0, 0, 0],
        available: 11,
      ),
      [4, 4, 3],
    );
  });

  test('fixed and intrinsic come first, flex shares the rest by weight', () {
    expect(
      solveColumnWidths(
        specs: const [
          FixedColumnWidth(9),
          IntrinsicColumnWidth(maxWidth: 6),
          FlexColumnWidth(1),
          FlexColumnWidth(2),
        ],
        natural: const [0, 20, 0, 0],
        available: 40,
        furniture: 6,
      ),
      // 40 - 6 - 9 - 6 = 19: 6.33 and 12.66, floored to 6 and 12, plus one.
      [9, 6, 7, 12],
    );
  });

  test('an intrinsic column under its cap keeps its natural width', () {
    expect(
      solveColumnWidths(
        specs: const [IntrinsicColumnWidth(maxWidth: 32), FlexColumnWidth()],
        natural: const [7, 0],
        available: 20,
        furniture: 2,
      ),
      [7, 11],
    );
  });

  test('flex gets nothing when the others already overflow', () {
    expect(
      solveColumnWidths(
        specs: const [FixedColumnWidth(30), FlexColumnWidth()],
        natural: const [0, 9],
        available: 20,
      ),
      [30, 0],
    );
  });

  test('with no limit flex columns take their natural width', () {
    expect(
      solveColumnWidths(
        specs: const [FlexColumnWidth(), FixedColumnWidth(2)],
        natural: const [13, 99],
        available: null,
      ),
      [13, 2],
    );
  });

  test('no columns give no widths', () {
    expect(
      solveColumnWidths(specs: const [], natural: const [], available: 10),
      isEmpty,
    );
  });

  test('huge finite weights share the room exactly', () {
    expect(
      solveColumnWidths(
        specs: const [FlexColumnWidth(1e308), FlexColumnWidth(1e308)],
        natural: const [0, 0],
        available: 80,
      ),
      [40, 40],
    );
    expect(
      solveColumnWidths(
        specs: const [FlexColumnWidth(1e308), FlexColumnWidth(1e-300)],
        natural: const [0, 0],
        available: 80,
      ),
      [80, 0],
    );
  });

  test('a weight must be positive and finite', () {
    for (final w in [0.0, -1.0, double.infinity, double.nan]) {
      expect(() => FlexColumnWidth(w), throwsA(isA<AssertionError>()));
    }
  });
  group('tester: Table allocation invariants', () {
    test('equal weights conserve room with at most one remainder cell', () {
      for (var columns = 1; columns <= 8; columns++) {
        for (var room = 0; room <= 80; room++) {
          final widths = solveColumnWidths(
            specs: List.filled(columns, const FlexColumnWidth()),
            natural: List.filled(columns, 0),
            available: room,
          );
          expect(widths.fold(0, (a, b) => a + b), room);
          expect(widths.first - widths.last, inInclusiveRange(0, 1));
          for (var i = 1; i < columns; i++) {
            expect(widths[i - 1], greaterThanOrEqualTo(widths[i]));
          }
        }
      }
    });
    test('tiny and huge finite weights conserve room beside furniture', () {
      for (final weights in const [
        [1e-300, 1e-300, 1e-300],
        [1e308, 1e-300, 1e308],
        [1e-300, 1e308, 1e-100],
      ]) {
        for (var room = 0; room < 50; room++) {
          final widths = solveColumnWidths(
            specs: [for (final w in weights) FlexColumnWidth(w)],
            natural: const [0, 0, 0],
            available: room + 7,
            furniture: 7,
          );
          expect(widths, everyElement(greaterThanOrEqualTo(0)));
          expect(widths.fold(0, (a, b) => a + b), room);
        }
      }
    });
  });
}
