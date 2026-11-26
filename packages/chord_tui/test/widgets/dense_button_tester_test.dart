import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _button(
  bool filled, {
  required String label,
  String? action,
  void Function()? onPressed,
  FocusNode? focusNode,
  bool autofocus = false,
}) => filled
    ? FilledButton(
        dense: true,
        action: action,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: Text(label),
      )
    : OutlinedButton(
        dense: true,
        action: action,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: Text(label),
      );

Widget _top(Widget child) => Align(alignment: Alignment.topLeft, child: child);

MouseEvent _at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  for (final filled in [true, false]) {
    group('CHD-638 tester: dense ${filled ? 'filled' : 'outlined'} button', () {
      testWidgets('plain-theme focus and activation leave and return', (
        t,
      ) async {
        final button = FocusNode(), other = FocusNode();
        addTearDown(button.dispose);
        addTearDown(other.dispose);
        var calls = 0;
        await t.pumpWidget(
          Theme(
            data: ThemeData.plain(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _button(
                  filled,
                  label: 'Run',
                  onPressed: () => calls++,
                  focusNode: button,
                  autofocus: true,
                ),
                Focus(focusNode: other, child: Text('other')),
              ],
            ),
          ),
        );
        expect(t.screen.styleAt(1, 0).isUnderline, isTrue);
        await t.press('enter');
        await t.press('space');
        other.requestFocus();
        await t.pump();
        expect(t.screen.styleAt(1, 0).isUnderline, isFalse);
        await t.press('enter');
        expect(calls, 2);
        button.requestFocus();
        await t.resize(const Size(120, 40));
        await t.press('space');
        expect(calls, 3);
        expect(t.screen.styleAt(1, 0).isUnderline, isTrue);
      });

      testWidgets(
        'the inline key is inside the face; the next row is outside',
        (t) async {
          var calls = 0;
          await t.pumpWidget(
            Actions(
              bindings: [Binding('k', 'Run', () => calls++, id: 'run')],
              child: _top(_button(filled, label: 'Run', action: 'run')),
            ),
          );
          final x = t.screen.lines.first.indexOf('k');
          expect(x, greaterThanOrEqualTo(0));
          await t.mouse(_at(MouseEventKind.press, x, 0));
          await t.mouse(_at(MouseEventKind.release, x, 0));
          expect(calls, 1);
          await t.mouse(_at(MouseEventKind.press, x, 1));
          await t.mouse(_at(MouseEventKind.release, x, 0));
          expect(calls, 1);
          expect(t.screen.lines[1], '');
        },
      );

      testWidgets(
        'Unicode and ANSI labels stay on one row across tiny resizes',
        (t) async {
          await t.pumpWidget(
            _top(
              _button(
                filled,
                label: '\x1b[31m界👩‍💻e\u0301\x1b[0m',
                onPressed: () {},
              ),
            ),
            size: Size.zero,
          );
          for (final size in [
            const Size(1, 1),
            const Size(2, 2),
            const Size(5, 3),
            const Size(80, 24),
            const Size(120, 40),
          ]) {
            await t.resize(size);
            expect(
              t.screen.lines.every((line) => cellWidth(line) <= size.width),
              isTrue,
            );
            expect(
              t.screen.lines.skip(1).every((line) => line.isEmpty),
              isTrue,
            );
            expect(t.screen.text, isNot(contains('\x1b')));
          }
          expect(t.screen, shows('界👩‍💻e\u0301'));
        },
      );

      testWidgets('a held click uses the latest disabled binding state', (
        t,
      ) async {
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        var calls = 0;
        await t.pumpWidget(
          ListenableBuilder(
            listenable: enabled,
            builder: (_) => Actions(
              bindings: [
                Binding(
                  'k',
                  'Run',
                  () => calls++,
                  id: 'run',
                  enabled: enabled.value,
                ),
              ],
              child: _top(
                _button(filled, label: 'Run', action: 'run', autofocus: true),
              ),
            ),
          ),
        );
        await t.mouse(_at(MouseEventKind.press, 1, 0));
        enabled.value = false;
        await t.pump();
        await t.mouse(_at(MouseEventKind.release, 1, 0));
        await t.press('enter');
        await t.press('space');
        expect(calls, 0);
      });

      testWidgets(
        'a rebound inline key and dispatch settle after 1000 updates',
        (t) async {
          final revision = ValueNotifier(0);
          addTearDown(revision.dispose);
          var calls = 0;
          final button = _top(_button(filled, label: 'Run', action: 'run'));
          await t.pumpWidget(
            ListenableBuilder(
              listenable: revision,
              builder: (_) => Keymap(
                data: KeymapData({
                  'run': [
                    Chord.parse(revision.value.isEven ? 'k' : 'ctrl+x a'),
                  ],
                }),
                child: Actions(
                  bindings: [Binding('k', 'Run', () => calls++, id: 'run')],
                  child: button,
                ),
              ),
            ),
          );
          for (var i = 0; i < 1000; i++) {
            revision.value = i;
          }
          await t.pump();
          expect(t.screen.lines.first, contains('Run  ctrl+x a'));
          expect(t.screen.lines[1], '');
          await t.press('k');
          expect(calls, 0);
          await t.press('ctrl+x a');
          expect(calls, 1);
        },
      );
    });
  }
}
