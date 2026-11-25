import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_geometry.dart';
import 'package:chord_tui/src/text/selection_layout.dart';
import 'package:test/test.dart';

void main() {
  test(
    'pure exposure rejects partial wide endpoints and retains covered interior',
    () {
      final owner = Object(), cover = Object();
      final layout = shapeSelectionSource(
        SelectionSource.text(
          id: 'text',
          revision: 0,
          text: const TextSpan('a界b'),
        ),
        width: 8,
      );
      final surface = SelectionSurface(
        owner: owner,
        layout: layout,
        origin: Offset.zero,
        bounds: const Rect(0, 0, 8, 1),
        clip: const Rect(0, 0, 8, 1),
        order: 0,
      );
      final cells = {
        for (var x = 0; x < 4; x++) Offset(x, 0): SelectionCellOwner(owner, 0),
        const Offset(2, 0): SelectionCellOwner(cover, 1),
      };
      final geometry = SelectionGeometry([surface], cells);
      expect(geometry.hit(const Offset(1, 0)), isNull);
      final first = geometry.hit(Offset.zero)!.position;
      expect(geometry.resolve(const Offset(1, 0), first)!.position, first);
      expect(geometry.resolve(const Offset(9, 0), first)!.position.offset, 3);
      expect(geometry.hit(const Offset(3, 0))!.position.offset, 2);
    },
  );

  test('genuine blank LF boundary uses content lane and later paint mask', () {
    final owner = Object();
    final layout = shapeSelectionSource(
      SelectionSource.code(
        id: 'code',
        revision: 0,
        text: '\nend',
        lineNumbers: true,
      ),
      width: 12,
    );
    final surface = SelectionSurface(
      owner: owner,
      layout: layout,
      origin: Offset.zero,
      bounds: const Rect(0, 0, 12, 2),
      clip: const Rect(0, 0, 12, 2),
      order: 0,
    );
    final geometry = SelectionGeometry(
      [surface],
      {const Offset(6, 0): SelectionCellOwner(Object(), 1)},
    );
    final left = geometry.hit(const Offset(4, 0))!.position;
    expect(left.offset, 0);
    expect(geometry.hit(const Offset(5, 0))!.position, left);
    expect(geometry.hit(const Offset(0, 0)), isNull);
    expect(geometry.hit(const Offset(6, 0)), isNull);
  });
}
