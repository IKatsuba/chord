// A Focus going leaves its node to the Focus that has since taken it up:
// when a column's children shift, an editor's new Focus is built before the
// old one is disposed, and the node must stay attached and focused.
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a shifted editor keeps its node and focus at $size', (
      t,
    ) async {
      final c = TextAreaController(text: 'a' * 19);
      final f = FocusNode();
      addTearDown(c.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: c,
          builder: (context) {
            // Past 20 characters the rows above give way to one, so the
            // editor's row lands on another element than before.
            final shifted = c.text.length > 20;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shifted) Text('^') else ...[Text('q'), Text('q2')],
                Row(children: [Text('x')]),
                SizedBox(
                  width: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('N '),
                      Expanded(
                        child: TextArea(
                          controller: c,
                          focusNode: f,
                          maxHeight: shifted ? 3 : 2,
                        ),
                      ),
                    ],
                  ),
                ),
                Text('hint'),
              ],
            );
          },
        ),
        size: size,
      );
      f.requestFocus();
      c.cursor = 19;
      await t.pump();
      await t.type('bbbbb');
      expect(f.hasFocus, isTrue);
      expect(c.text, '${'a' * 19}bbbbb');
      expect(t.screen.lines.take(5), [
        '^',
        'x',
        'N aaaaaaaaaa',
        '  aaaaaaaaab',
        '  bbbb',
      ]);
      // Back under the threshold the rows above return, the editor's row
      // shifting down, the old Focus going before the new one is built.
      for (var i = 0; i < 6; i++) {
        await t.press('backspace');
      }
      expect(f.hasFocus, isTrue);
      await t.type('c');
      expect(c.text, '${'a' * 18}c');
      expect(t.screen.lines.take(5), [
        'q',
        'q2',
        'x',
        'N aaaaaaaaaa',
        '  aaaaaaaac',
      ]);
    });
  }

  group('a focused node moved within its tree', () {
    late FocusManager manager;
    late FocusNode node;
    setUp(() {
      manager = FocusManager();
      node = FocusNode()..attach(manager.root);
      node.requestFocus();
    });
    tearDown(() => manager.dispose());

    test('keeps the focus where it may be held', () {
      final other = FocusNode()..attach(manager.root);
      node.attach(other);
      expect(node.hasPrimaryFocus, isTrue);
    });

    test('loses it under a node that excludes its descendants', () {
      final excluding = FocusNode()
        ..attach(manager.root)
        ..descendantsAreFocusable = false;
      node.attach(excluding);
      expect(node.hasFocus, isFalse);
      expect(manager.primaryFocus, isNull);
    });

    test('loses it in an inactive scope', () {
      final hidden = FocusScopeNode(active: false)..attach(manager.root);
      node.attach(hidden);
      expect(node.hasFocus, isFalse);
    });

    test('into another scope ends a chord begun in the first', () {
      var finished = 0;
      final a = FocusScopeNode()..attach(manager.root);
      final b = FocusScopeNode()..attach(manager.root);
      node
        ..attach(a)
        ..requestFocus();
      b.bindings = [Binding('ctrl+x c', 'Finish', () => finished++)];
      a.bindings = [Binding('ctrl+x d', 'Other', () {})];
      manager.dispatchKey(KeyCombo.parse('ctrl+x').toEvent());
      expect(manager.pendingChord, isNotEmpty);
      node.attach(b);
      expect(node.hasPrimaryFocus, isTrue);
      expect(manager.pendingChord, isEmpty);
      manager.dispatchKey(KeyCombo.parse('c').toEvent());
      expect(finished, 0);
    });
  });
}
