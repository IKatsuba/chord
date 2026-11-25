import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('delegate validates identities without resolving unmounted sources', () {
    final ids = ['a', 'b'];
    var resolutions = 0;
    final delegate = SelectionChildDelegate(
      itemCount: 2,
      idAt: (i) => ids[i],
      indexOfId: (id) => ids.indexOf(id as String),
      sourceAt: (i) {
        resolutions++;
        return SelectionSource.text(
          id: ids[i],
          revision: 0,
          text: TextSpan(ids[i]),
        );
      },
      separatorBefore: (_) => ' / ',
    );
    expect(resolutions, 0);
    ids[0] = 'replacement';
    expect(delegate.idAt(0), 'a');
    expect(delegate.indexOfId('a'), 0);
    expect(delegate.indexOfId('absent'), isNull);
    expect(delegate.separatorBefore(0), '');
    expect(delegate.separatorBefore(1), ' / ');
    expect(delegate.sourceAt(1).id, 'b');
    expect(resolutions, 1);
    expect(() => delegate.sourceAt(0), throwsStateError);
  });

  test(
    'duplicate IDs and inconsistent reverse lookup are rejected eagerly',
    () {
      SelectionChildDelegate make(
        Object Function(int) ids,
        int? Function(Object) lookup,
      ) => SelectionChildDelegate(
        itemCount: 2,
        idAt: ids,
        indexOfId: lookup,
        sourceAt: (_) => throw StateError('Must stay lazy'),
      );
      expect(() => make((_) => 'same', (_) => 0), throwsArgumentError);
      expect(() => make((i) => i, (_) => null), throwsArgumentError);
      expect(
        () => SelectionChildDelegate(
          itemCount: -1,
          idAt: (i) => i,
          indexOfId: (_) => null,
          sourceAt: (_) => throw StateError('Must stay lazy'),
        ),
        throwsArgumentError,
      );
    },
  );
}
