import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _button(
  bool filled, {
  String? action,
  void Function()? onPressed,
  FocusNode? focusNode,
  bool autofocus = false,
  String label = 'Go',
}) => filled
    ? FilledButton(
        action: action,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: Text(label),
      )
    : OutlinedButton(
        action: action,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: Text(label),
      );

Widget _top(Widget child) => Align(alignment: Alignment.topLeft, child: child);

MouseEvent _at(
  MouseEventKind kind,
  int x,
  int y, {
  MouseButton button = MouseButton.primary,
}) => MouseEvent(kind, position: Offset(x, y), button: button);

void main() {
  for (final filled in [true, false]) {
    group('CHD-638 tester: ${filled ? 'filled' : 'outlined'} button', () {
      testWidgets('a press on the hint cannot become a face click', (t) async {
        var calls = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('g', 'Go', () => calls++, id: 'go')],
            child: _top(_button(filled, action: 'go')),
          ),
        );
        expect(t.screen, shows('press g'));
        await t.mouse(_at(MouseEventKind.press, 4, 3));
        await t.mouse(_at(MouseEventKind.release, 4, 1));
        expect(calls, 0, reason: 'both endpoints must be inside the face');
      });

      testWidgets('a cancelled or secondary press cannot invoke', (t) async {
        var calls = 0;
        await t.pumpWidget(_top(_button(filled, onPressed: () => calls++)));
        await t.mouse(_at(MouseEventKind.press, 4, 1));
        t.host.handleMouse(_at(MouseEventKind.cancel, 4, 1));
        await t.pump();
        await t.mouse(_at(MouseEventKind.release, 4, 1));
        await t.mouse(
          _at(MouseEventKind.press, 4, 1, button: MouseButton.secondary),
        );
        await t.mouse(
          _at(MouseEventKind.release, 4, 1, button: MouseButton.secondary),
        );
        expect(calls, 0);
      });

      testWidgets('a binding disabled during a press cannot invoke', (t) async {
        var calls = 0;
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (_) => Actions(
              bindings: [
                Binding(
                  'g',
                  'Go',
                  () => calls++,
                  id: 'go',
                  enabled: enabled.value,
                ),
              ],
              child: _top(_button(filled, action: 'go', autofocus: true)),
            ),
          ),
        );
        await t.mouse(_at(MouseEventKind.press, 4, 1));
        enabled.value = false;
        await t.pump();
        await t.mouse(_at(MouseEventKind.release, 4, 1));
        await t.press('enter');
        await t.press('space');
        await t.press('g');
        expect(calls, 0);
      });

      testWidgets('a removed pressed button leaves no capture or callback', (
        t,
      ) async {
        var calls = 0;
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: visible,
            builder: (_) => _top(
              visible.value
                  ? _button(filled, autofocus: true, onPressed: () => calls++)
                  : Text('gone'),
            ),
          ),
        );
        await t.mouse(_at(MouseEventKind.press, 4, 1));
        visible.value = false;
        await t.pump();
        await t.mouse(_at(MouseEventKind.release, 4, 1));
        await t.press('enter');
        expect(calls, 0);
        expect(t.screen.text, 'gone');
      });

      testWidgets('live keymap hints and dispatch agree after 1000 changes', (
        t,
      ) async {
        var calls = 0;
        final revision = ValueNotifier(0);
        addTearDown(revision.dispose);
        final button = _top(_button(filled, action: 'go'));
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) => Keymap(
              data: KeymapData({
                'go': [Chord.parse(revision.value.isEven ? 'g' : 'ctrl+x a')],
              }),
              child: Actions(
                bindings: [Binding('g', 'Go', () => calls++, id: 'go')],
                child: button,
              ),
            ),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          revision.value = i;
        }
        await t.pump();
        expect(t.screen, shows('press ctrl+x a'));
        await t.press('g');
        expect(calls, 0);
        await t.press('ctrl+x a');
        expect(calls, 1);
      });

      testWidgets('a supplied focus node can be replaced and revisited', (
        t,
      ) async {
        var calls = 0;
        final first = FocusNode(), second = FocusNode(), other = FocusNode();
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(other.dispose);
        final current = ValueNotifier(first);
        addTearDown(current.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: current,
            builder: (_) => Column(
              children: [
                _top(
                  _button(
                    filled,
                    focusNode: current.value,
                    autofocus: true,
                    onPressed: () => calls++,
                  ),
                ),
                Focus(focusNode: other, child: Text('other')),
              ],
            ),
          ),
        );
        current.value = second;
        await t.pump();
        second.requestFocus();
        await t.pump();
        await t.press('enter');
        other.requestFocus();
        await t.pump();
        await t.press('space');
        second.requestFocus();
        await t.pump();
        await t.press('space');
        expect(calls, 2);
        expect(first.hasFocus, isFalse);
      });

      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets('Unicode and escape labels survive every edge at $size', (
          t,
        ) async {
          var calls = 0;
          await t.pumpWidget(
            _top(
              _button(
                filled,
                label: '\x1b[31m界👩‍💻e\u0301\x1b[0m',
                autofocus: true,
                onPressed: () => calls++,
              ),
            ),
            size: size,
          );
          for (final edge in [
            Size.zero,
            const Size(1, 1),
            const Size(2, 3),
            const Size(3, 3),
            const Size(7, 3),
            const Size(8, 3),
            size,
          ]) {
            await t.resize(edge);
            expect(
              t.screen.lines.every((line) => cellWidth(line) <= edge.width),
              isTrue,
            );
            expect(t.screen.text, isNot(contains('\x1b')));
          }
          expect(t.screen, shows('界👩‍💻e\u0301'));
          await t.press('enter');
          await t.press('space');
          expect(calls, 2);
        });
      }

      testWidgets('unbounded parent sizes the face to its label', (t) async {
        await t.pumpWidget(
          Row(
            children: [_button(filled, onPressed: () {}, label: '界e\u0301')],
          ),
        );
        expect(t.screen, shows('界e\u0301'));
        expect(t.screen.text, isNot(contains('Error')));
      });
    });
  }
}
