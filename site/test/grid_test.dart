import 'package:chord_site/grid.dart';
import 'package:test/test.dart';

int move(int i, GridStep s, {int count = 9, int columns = 3}) =>
    gridMove(i, count: count, columns: columns, step: s);

void main() {
  test('arrows move along rows and between them', () {
    expect(move(0, GridStep.right), 1);
    expect(move(1, GridStep.left), 0);
    expect(move(1, GridStep.down), 4);
    expect(move(4, GridStep.up), 1);
  });

  test('a step off an edge stays put', () {
    expect(move(0, GridStep.left), 0);
    expect(move(2, GridStep.right), 2);
    expect(move(1, GridStep.up), 1);
    expect(move(7, GridStep.down), 7);
  });

  test('down onto a short last row stops at its last card', () {
    expect(move(5, GridStep.down, count: 7), 6);
    expect(move(6, GridStep.right, count: 7), 6);
    expect(move(6, GridStep.down, count: 7), 6);
  });

  test('one column moves up and down only', () {
    expect(move(3, GridStep.down, columns: 1), 4);
    expect(move(3, GridStep.right, columns: 1), 3);
    expect(move(8, GridStep.down, columns: 1), 8);
  });

  test('no cards', () => expect(move(0, GridStep.down, count: 0), 0));
}
