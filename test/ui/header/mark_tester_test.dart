import 'package:chord/ui/header/mark_rows.dart';
import 'package:test/test.dart';

void main() {
  group('tester: mark half-cell boundaries', () {
    test('empty, odd and all-empty grids retain their rows and columns', () {
      expect(markRows([], const MarkPlain()), isEmpty);
      expect(markRows([[]], const MarkPlain()), [[]]);
      expect(
        markRows([
          [null, null, null],
        ], const MarkPlain()),
        [
          [(text: '   ', color: null, backgroundColor: null)],
        ],
      );
      expect(
        markRows([
          [null, 0],
          [1, null],
          [0, null],
        ], const MarkTone('green')),
        [
          [(text: '▄▀', color: 'green', backgroundColor: null)],
          [
            (text: '▀', color: 'green', backgroundColor: null),
            (text: ' ', color: null, backgroundColor: null),
          ],
        ],
      );
    });

    test(
      'uniform gradient keeps equal halves solid and merges adjacent runs',
      () {
        expect(
          markRows([
            [0, 0.2, 0.8],
            [1, 0.9, 0],
          ], const MarkGradient(['#123456', '#123456', '#123456'])),
          [
            [(text: '███', color: '#123456', backgroundColor: null)],
          ],
        );
      },
    );
  });
}
