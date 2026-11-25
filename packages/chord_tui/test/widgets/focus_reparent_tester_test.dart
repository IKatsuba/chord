import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester CTUI-174: focus rebuild boundaries', () {
    for (final size in const [
      Size(120, 40),
      Size(80, 24),
      Size(1, 1),
      Size.zero,
    ]) {
      testWidgets('reparent retains Unicode editing with $size room', (
        t,
      ) async {
        final c = TextAreaController(text: '界🙂e\u0301\x1b[31m');
        final node = FocusNode(), other = FocusNode();
        final shifted = ValueNotifier(false);
        addTearDown(c.dispose);
        addTearDown(node.dispose);
        addTearDown(other.dispose);
        addTearDown(shifted.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: shifted,
            builder: (_) => Column(
              children: [
                if (shifted.value)
                  Text('one')
                else ...[
                  Text('one'),
                  Text('two'),
                ],
                SizedBox(
                  width: size.width,
                  child: TextArea(controller: c, focusNode: node, maxHeight: 3),
                ),
                Focus(focusNode: other, child: Text('other')),
              ],
            ),
          ),
          size: size,
        );
        node.requestFocus();
        await t.pump();
        final initial = c.text;
        for (final move in [true, false, true, false]) {
          shifted.value = move;
          await t.pump();
          expect(node.hasPrimaryFocus, isTrue);
          await t.type('X');
          expect(c.text, '${initial}X');
          await t.press('backspace');
          expect(c.text, initial);
        }
        other.requestFocus();
        shifted.value = true;
        await t.pump();
        expect(other.hasPrimaryFocus, isTrue);
        await t.type('Z');
        expect(c.text, initial);
        node.requestFocus();
        await t.resize(const Size(80, 24));
        await t.type('Y');
        expect(c.text, '${initial}Y');
        for (var i = 0; i < 1000; i++) {
          shifted.value = i.isEven;
        }
        await t.pump();
        expect(node.hasPrimaryFocus, isTrue);
        await t.type('Q');
        expect(c.text, '${initial}YQ');
        await t.pumpWidget(const SizedBox());
        Timer.run(() => c.text = 'late update');
        await t.pump(const Duration(milliseconds: 5));
        expect(node.attached, isFalse);
        expect(t.focusManager.primaryFocus, isNot(same(node)));
      });
    }

    for (final excluded in [true, false]) {
      test(
        'moving a focused subtree rejects ${excluded ? 'excluded' : 'inactive'} ancestors',
        () {
          final manager = FocusManager();
          addTearDown(manager.dispose);
          final origin = FocusScopeNode()..attach(manager.root);
          final parent = FocusNode()..attach(origin);
          final leaf = FocusNode()..attach(parent);
          final destination = excluded
              ? (FocusNode()..descendantsAreFocusable = false)
              : FocusScopeNode(active: false);
          destination.attach(manager.root);
          leaf.requestFocus();
          parent.attach(destination);
          expect(leaf.hasPrimaryFocus, isFalse);
          expect(manager.primaryFocus, same(origin));
          leaf.requestFocus();
          expect(leaf.hasPrimaryFocus, isFalse);
        },
      );
    }

    test('cross-manager move never transfers the old primary focus', () {
      final first = FocusManager(), second = FocusManager();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final node = FocusNode()..attach(first.root);
      node.requestFocus();
      node.attach(second.root);
      expect(first.primaryFocus, isNot(same(node)));
      expect(second.primaryFocus, isNot(same(node)));
      node.requestFocus();
      expect(second.primaryFocus, same(node));
    });
  });
}
