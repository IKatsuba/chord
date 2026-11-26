import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

final dark = ThemeData.dark();
final link = dark.link.merge(Style.underline);
final focused = dark.focus.merge(const Style(inverse: true, underline: true));

MouseEvent at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

Future<void> click(WidgetTester t, int x, int y) async {
  await t.mouse(at(MouseEventKind.press, x, y));
  await t.mouse(at(MouseEventKind.release, x, y));
}

Widget top(Widget child) => Align(alignment: Alignment.topLeft, child: child);

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets('a uri link reads underlined with ↗ and opens through the '
          'terminal on a click', (t) async {
        await t.pumpWidget(
          top(Link('GitHub', uri: Uri.parse('https://github.com/a/b'))),
          size: size,
        );
        expect(t.screen.lines.first, 'GitHub ↗');
        expect(t.screen.styleAt(0, 0), link);
        expect(t.screen.styleAt(7, 0), link);
        await click(t, 3, 0);
        expect(t.terminal.openedUrls, ['https://github.com/a/b']);
        await click(t, 30, 0);
        expect(t.terminal.openedUrls, hasLength(1));
      });

      testWidgets('focused, Enter opens it, and it draws in the focus role '
          'inverse', (t) async {
        await t.pumpWidget(
          top(
            Link(
              'Docs',
              uri: Uri.parse('https://example.com/docs'),
              autofocus: true,
            ),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), focused);
        await t.press('enter');
        expect(t.terminal.openedUrls, ['https://example.com/docs']);
      });

      testWidgets('the help row lists enter while a link has focus', (t) async {
        await t.pumpWidget(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Link('Docs', onPressed: () {}, autofocus: true),
              Focus(child: Text('elsewhere')),
              const Spacer(),
              const KeyHelp(),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.last, 'enter open');
        await t.press('tab');
        await t.pump();
        expect(t.screen.lines.last, '');
      });

      testWidgets('an action link shows its key after the text and invokes '
          'the binding', (t) async {
        var opened = 0;
        await t.pumpWidget(
          Keymap(
            data: KeymapData({
              'site:github': [Chord.parse('ctrl+g')],
            }),
            child: Actions(
              bindings: [
                Binding('g', 'GitHub', () => opened++, id: 'site:github'),
              ],
              child: top(Link('GitHub', action: 'site:github', external: true)),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, 'GitHub ↗ ctrl+g');
        expect(t.screen.styleAt(7, 0), link);
        expect(t.screen.styleAt(9, 0), dark.dim);
        expect(t.screen.styleAt(8, 0).isUnderline, isFalse);
        await click(t, 2, 0);
        await t.press('ctrl+g');
        expect(opened, 2);
        expect(t.terminal.openedUrls, isEmpty);
      });

      testWidgets('an onPressed link has no arrow and runs its callback', (
        t,
      ) async {
        var pressed = 0;
        await t.pumpWidget(
          top(Link('Read about chord_tui', onPressed: () => pressed++)),
          size: size,
        );
        expect(t.screen.lines.first, 'Read about chord_tui');
        await click(t, 0, 0);
        expect(pressed, 1);
      });

      testWidgets('external false draws no arrow on a uri link', (t) async {
        await t.pumpWidget(
          top(Link('Home', uri: Uri.parse('https://e.com'), external: false)),
          size: size,
        );
        expect(t.screen.lines.first, 'Home');
      });

      testWidgets('an unbound action is dim, shows no key and does '
          'nothing', (t) async {
        var opened = 0;
        await t.pumpWidget(
          Keymap(
            data: const KeymapData({'site:github': []}),
            child: Actions(
              bindings: [
                Binding('g', 'GitHub', () => opened++, id: 'site:github'),
              ],
              child: top(Link('GitHub', action: 'site:github')),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, 'GitHub');
        expect(t.screen.styleAt(0, 0), dark.dim);
        await click(t, 1, 0);
        expect(opened, 0);
      });

      testWidgets('with nothing to do it is dim and takes no focus', (t) async {
        await t.pumpWidget(top(Link('Nowhere', autofocus: true)), size: size);
        expect(t.screen.styleAt(0, 0), dark.dim);
        expect(t.focusManager.primaryFocus, isNull);
      });

      testWidgets('it does not wrap', (t) async {
        await t.pumpWidget(
          top(
            SizedBox(
              width: 10,
              child: Link('A long link text', onPressed: () {}),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.first, 'A long lin');
        expect(t.screen.lines[1], '');
      });
    });
  }

  testWidgets('canRequestFocus false: it builds in a list, takes no Tab or '
      'Enter, but its key and a click open it', (t) async {
    var opened = 0;
    await t.pumpWidget(
      Actions(
        bindings: [Binding('g', 'GitHub', () => opened++, id: 'g')],
        child: Focus(
          autofocus: true,
          child: ListView.builder(
            itemCount: 1,
            itemBuilder: (context, _) => top(
              Link(
                'GitHub',
                action: 'g',
                external: true,
                canRequestFocus: false,
              ),
            ),
          ),
        ),
      ),
      size: const Size(80, 24),
    );
    expect(t.screen.lines.first, 'GitHub ↗ g');
    final page = t.focusManager.primaryFocus;
    await t.press('tab');
    expect(t.focusManager.primaryFocus, same(page));
    await t.press('enter');
    expect(opened, 0);
    await t.press('g');
    await click(t, 1, 0);
    expect(opened, 2);
    expect(t.screen.styleAt(0, 0), link);
  });

  test('two of uri, onPressed and action assert', () {
    expect(
      () => Link('x', uri: Uri.parse('https://e.com'), onPressed: () {}),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => Link('x', onPressed: () {}, action: 'a'),
      throwsA(isA<AssertionError>()),
    );
  });
}
