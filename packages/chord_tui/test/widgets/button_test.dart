import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final dark = ThemeData.dark();
final face = dark.accent.merge(const Style(bold: true, inverse: true));

MouseEvent at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

/// The first row and column of [text] on the screen.
(int, int) find(WidgetTester t, String text) {
  for (final (y, line) in t.screen.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) return (x, y);
  }
  throw StateError('"$text" is not on the screen:\n${t.screen.text}');
}

void main() {
  group('Actions.maybeBindingOf', () {
    testWidgets('finds the nearest Actions holding the id', (t) async {
      Binding? found, missing;
      await t.pumpWidget(
        Actions(
          bindings: [Binding('a', 'Outer', () {}, id: 'x')],
          child: Actions(
            bindings: [Binding('b', 'Inner', () {}, id: 'y')],
            child: Builder(
              builder: (context) {
                found = Actions.maybeBindingOf(context, 'x');
                missing = Actions.maybeBindingOf(context, 'z');
                return Text('');
              },
            ),
          ),
        ),
      );
      expect(found!.description, 'Outer');
      expect('${found!.chord}', 'a');
      expect(missing, isNull);
    });

    testWidgets('the nearest wins, and the keymap is applied', (t) async {
      Binding? found;
      await t.pumpWidget(
        Keymap(
          data: KeymapData({
            'x': [Chord.parse('ctrl+k')],
          }),
          child: Actions(
            bindings: [Binding('a', 'Outer', () {}, id: 'x')],
            child: Actions(
              bindings: [Binding('b', 'Inner', () {}, id: 'x')],
              child: Builder(
                builder: (context) {
                  found = Actions.maybeBindingOf(context, 'x');
                  return Text('');
                },
              ),
            ),
          ),
        ),
      );
      expect(found!.description, 'Inner');
      expect('${found!.chord}', 'ctrl+k');
    });

    testWidgets('a dependent rebuilds when the binding changes', (t) async {
      final enabled = ValueNotifier(true);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: enabled,
          builder: (context) => Actions(
            bindings: [
              Binding('a', 'Act', () {}, id: 'x', enabled: enabled.value),
            ],
            child: const _ShowsEnabled(),
          ),
        ),
      );
      expect(t.screen, shows('enabled true'));
      enabled.value = false;
      await t.pump();
      expect(t.screen, shows('enabled false'));
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('a FilledButton is three rows of the inverse accent with '
          'its key under it', (t) async {
        var pressed = 0;
        await t.pumpWidget(
          Actions(
            bindings: [
              Binding('i', 'Install', () => pressed++, id: 'site:install'),
            ],
            child: Align(
              alignment: Alignment.topLeft,
              child: FilledButton(
                action: 'site:install',
                child: Text('Install chord'),
              ),
            ),
          ),
          size: size,
        );
        final (x, y) = find(t, 'Install chord');
        expect((x, y), (4, 1));
        for (var row = 0; row < 3; row++) {
          expect(t.screen.styleAt(0, row), face, reason: 'row $row');
          expect(t.screen.styleAt(4 + 13 + 3, row), face, reason: 'row $row');
        }
        expect(t.screen.styleAt(4 + 13 + 4, 1), isNot(face));
        expect(t.screen.lines[3], '       press i');
        expect(t.screen.styleAt(7, 3), dark.dim);
        expect(t.screen.styleAt(13, 3), dark.text.merge(Style.bold));
        await t.press('i');
        expect(pressed, 1);
      });

      testWidgets('an OutlinedButton is a rounded frame around its bold '
          'label', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: OutlinedButton(
              onPressed: () {},
              child: Text('Watch it run'),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.take(3).toList(), [
          '╭──────────────────╮',
          '│   Watch it run   │',
          '╰──────────────────╯',
        ]);
        expect(t.screen.styleAt(0, 0), dark.border);
        expect(t.screen.styleAt(4, 1), dark.text.merge(Style.bold));
        expect(t.screen.lines[3], '', reason: 'no action, no key row');
      });

      testWidgets('focused, Enter and space press it, and it takes the focus '
          'role', (t) async {
        var pressed = 0;
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton(
                  autofocus: true,
                  onPressed: () => pressed++,
                  child: Text('Save'),
                ),
                OutlinedButton(
                  autofocus: false,
                  onPressed: () {},
                  child: Text('Back'),
                ),
              ],
            ),
          ),
          size: size,
        );
        expect(
          t.screen.styleAt(0, 0),
          dark.focus.merge(const Style(bold: true, inverse: true)),
        );
        await t.press('enter');
        await t.press('space');
        expect(pressed, 2);
        await t.press('tab');
        await t.pump();
        expect(t.screen.styleAt(0, 0), face);
        expect(t.screen.styleAt(0, 3), dark.focus);
      });

      testWidgets('focus also underlines the label, so it shows without '
          'colour', (t) async {
        await t.pumpWidget(
          Theme(
            data: ThemeData.plain(),
            child: Align(
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton(
                    autofocus: true,
                    onPressed: () {},
                    child: Text('Save'),
                  ),
                  OutlinedButton(onPressed: () {}, child: Text('Back')),
                ],
              ),
            ),
          ),
          size: size,
        );
        final plain = ThemeData.plain();
        // Filled label at (4, 1), outlined label at (4, 4).
        expect(t.screen.styleAt(4, 1).isUnderline, isTrue);
        expect(t.screen.styleAt(0, 1).isUnderline, isFalse, reason: 'padding');
        expect(t.screen.styleAt(4, 4).isUnderline, isFalse);
        await t.press('tab');
        await t.pump();
        expect(t.screen.styleAt(4, 1).isUnderline, isFalse);
        expect(
          t.screen.styleAt(4, 4),
          plain.text.merge(const Style(bold: true, underline: true)),
        );
      });

      testWidgets('a press and release inside presses it; a release outside '
          'does not', (t) async {
        var pressed = 0;
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: FilledButton(onPressed: () => pressed++, child: Text('Go')),
          ),
          size: size,
        );
        await t.mouse(at(MouseEventKind.press, 1, 1));
        await t.mouse(at(MouseEventKind.release, 2, 2));
        expect(pressed, 1);
        await t.mouse(at(MouseEventKind.press, 1, 1));
        await t.mouse(at(MouseEventKind.move, 30, 10));
        await t.mouse(at(MouseEventKind.release, 30, 10));
        expect(pressed, 1);
      });

      testWidgets('without onPressed or action it is disabled: dim, not '
          'focusable, no press', (t) async {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton(autofocus: true, child: Text('Off')),
                OutlinedButton(child: Text('Off')),
              ],
            ),
          ),
          size: size,
        );
        expect(
          t.screen.styleAt(0, 0),
          dark.dim.merge(const Style(bold: true, inverse: true)),
        );
        expect(t.screen.styleAt(0, 3), dark.dim);
        expect(t.focusManager.primaryFocus?.debugLabel, isNot('button'));
      });

      testWidgets('an action follows its binding: disabled with it, and its '
          'key as the keymap moves it', (t) async {
        final enabled = ValueNotifier(false);
        var pressed = 0;
        await t.pumpWidget(
          Keymap(
            data: KeymapData({
              'site:watch': [Chord.parse('ctrl+w')],
            }),
            child: ListenableBuilder(
              listenable: enabled,
              builder: (context) => Actions(
                bindings: [
                  Binding(
                    'w',
                    'Watch',
                    () => pressed++,
                    id: 'site:watch',
                    enabled: enabled.value,
                  ),
                ],
                child: Align(
                  alignment: Alignment.topLeft,
                  child: OutlinedButton(
                    action: 'site:watch',
                    child: Text('Watch it run'),
                  ),
                ),
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), dark.dim);
        expect(t.screen, shows('press ctrl+w'));
        await t.mouse(at(MouseEventKind.press, 2, 1));
        await t.mouse(at(MouseEventKind.release, 2, 1));
        expect(pressed, 0);
        enabled.value = true;
        await t.pump();
        expect(t.screen.styleAt(0, 0), dark.border);
        await t.mouse(at(MouseEventKind.press, 2, 1));
        await t.mouse(at(MouseEventKind.release, 2, 1));
        expect(pressed, 1);
      });

      testWidgets('a keymap that unbinds the action leaves it disabled with '
          'no key row', (t) async {
        await t.pumpWidget(
          Keymap(
            data: const KeymapData({'site:watch': []}),
            child: Actions(
              bindings: [Binding('w', 'Watch', () {}, id: 'site:watch')],
              child: Align(
                alignment: Alignment.topLeft,
                child: FilledButton(action: 'site:watch', child: Text('Watch')),
              ),
            ),
          ),
          size: size,
        );
        expect(
          t.screen.styleAt(0, 0),
          dark.dim.merge(const Style(bold: true, inverse: true)),
        );
        expect(t.screen.lines[3], '');
      });

      testWidgets('showShortcut false draws no key row', (t) async {
        await t.pumpWidget(
          Actions(
            bindings: [Binding('i', 'Install', () {}, id: 'i')],
            child: Align(
              alignment: Alignment.topLeft,
              child: FilledButton(
                action: 'i',
                showShortcut: false,
                child: Text('Install'),
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines[3], '');
      });
    });
  }

  test('onPressed and action together assert', () {
    expect(
      () => FilledButton(onPressed: () {}, action: 'x', child: Text('x')),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('an action no Actions declares asserts', (t) async {
    await t.pumpWidget(
      FilledButton(action: 'nowhere', child: Text('x')),
      size: const Size(120, 40),
    );
    expect(t.screen, shows('Failed assertion'));
  });
}

class _ShowsEnabled extends StatelessWidget {
  const _ShowsEnabled();

  @override
  Widget build(BuildContext context) =>
      Text('enabled ${Actions.maybeBindingOf(context, 'x')?.enabled}');
}
