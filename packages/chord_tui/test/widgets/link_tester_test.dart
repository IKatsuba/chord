import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _top(Widget child) => Align(alignment: Alignment.topLeft, child: child);

MouseEvent _at(MouseEventKind kind, int x, int y) =>
    MouseEvent(kind, position: Offset(x, y), button: MouseButton.primary);

void main() {
  group('CHD-638 tester: Link layout and keys', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('Unicode clips without wrapping across resize at $size', (
        t,
      ) async {
        var calls = 0;
        await t.pumpWidget(
          _top(
            Link(
              '\x1b[31m界👩‍💻e\u0301\x1b[0m',
              onPressed: () => calls++,
              autofocus: true,
            ),
          ),
          size: size,
        );
        for (final edge in [
          Size.zero,
          const Size(1, 1),
          const Size(2, 1),
          const Size(3, 1),
          const Size(4, 1),
          const Size(5, 1),
          size,
        ]) {
          await t.resize(edge);
          expect(
            t.screen.lines.every((line) => cellWidth(line) <= edge.width),
            isTrue,
          );
          expect(t.screen.text, isNot(contains('\x1b')));
        }
        expect(t.screen.lines.first, '界👩‍💻e\u0301');
        expect(t.screen.lines.skip(1).every((line) => line.isEmpty), isTrue);
        await t.press('space');
        expect(calls, 0);
        await t.press('enter');
        expect(calls, 1);
      });
    }

    testWidgets('unbounded row keeps its link and following text', (t) async {
      await t.pumpWidget(
        Row(
          children: [
            Link('界e\u0301', onPressed: () {}),
            Text('end'),
          ],
        ),
      );
      expect(t.screen.lines.first, '界e\u0301end');
    });

    testWidgets('plain-theme focus and help follow focus away and back', (
      t,
    ) async {
      final link = FocusNode(), other = FocusNode();
      addTearDown(link.dispose);
      addTearDown(other.dispose);
      await t.pumpWidget(
        Theme(
          data: ThemeData.plain(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Link('Docs', onPressed: () {}, focusNode: link, autofocus: true),
              Focus(focusNode: other, child: Text('other')),
              const Spacer(),
              const KeyHelp(),
            ],
          ),
        ),
      );
      expect(t.screen.styleAt(0, 0).isInverse, isTrue);
      expect(t.screen.lines.last, 'enter open');
      other.requestFocus();
      await t.pump();
      expect(t.screen.styleAt(0, 0).isInverse, isFalse);
      expect(t.screen.lines.last, '');
      link.requestFocus();
      await t.pump();
      expect(t.screen.styleAt(0, 0).isInverse, isTrue);
      expect(t.screen.lines.last, 'enter open');
    });

    testWidgets('nearest unbound action masks an outer action', (t) async {
      var outer = 0, inner = 0;
      await t.pumpWidget(
        Actions(
          bindings: [Binding('o', 'Outer', () => outer++, id: 'go')],
          child: Keymap(
            data: const KeymapData({'go': []}),
            child: Actions(
              bindings: [Binding('i', 'Inner', () => inner++, id: 'go')],
              child: _top(Link('Go', action: 'go', autofocus: true)),
            ),
          ),
        ),
      );
      expect(t.screen.lines.first, 'Go');
      expect(t.focusManager.primaryFocus, isNull);
      await t.mouse(_at(MouseEventKind.press, 0, 0));
      await t.mouse(_at(MouseEventKind.release, 0, 0));
      await t.press('enter');
      await t.press('i');
      expect((outer, inner), (0, 0));
    });

    testWidgets('keymap updates settle the hint and callback together', (
      t,
    ) async {
      var calls = 0;
      final revision = ValueNotifier(0);
      addTearDown(revision.dispose);
      final link = _top(Link('Go', action: 'go'));
      await t.pumpWidget(
        ListenableBuilder(
          listenable: revision,
          builder: (_) => Keymap(
            data: KeymapData({
              'go': [Chord.parse(revision.value.isEven ? 'g' : 'ctrl+x a')],
            }),
            child: Actions(
              bindings: [Binding('g', 'Go', () => calls++, id: 'go')],
              child: link,
            ),
          ),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        revision.value = i;
      }
      await t.pump();
      expect(t.screen.lines.first, 'Go ctrl+x a');
      await t.press('g');
      expect(calls, 0);
      await t.press('ctrl+x a');
      expect(calls, 1);
    });
  });

  group('CHD-638 tester: Link pointer lifetime', () {
    testWidgets('cancelled and outside releases do not open', (t) async {
      await t.pumpWidget(
        _top(Link('Docs', uri: Uri.parse('https://example.com/docs'))),
      );
      await t.mouse(_at(MouseEventKind.press, 0, 0));
      await t.mouse(_at(MouseEventKind.release, 0, 2));
      await t.mouse(_at(MouseEventKind.press, 0, 0));
      t.host.handleMouse(_at(MouseEventKind.cancel, 0, 0));
      await t.pump();
      await t.mouse(_at(MouseEventKind.release, 0, 0));
      expect(t.terminal.openedUrls, isEmpty);
    });

    testWidgets('a disabled binding cancels a held click and Enter', (t) async {
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
            child: _top(Link('Go', action: 'go', autofocus: true)),
          ),
        ),
      );
      await t.mouse(_at(MouseEventKind.press, 0, 0));
      enabled.value = false;
      await t.pump();
      await t.mouse(_at(MouseEventKind.release, 0, 0));
      await t.press('enter');
      await t.press('g');
      expect(calls, 0);
    });

    testWidgets('removal during capture cannot open or retain focus', (
      t,
    ) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: visible,
          builder: (_) => _top(
            visible.value
                ? Link(
                    'Docs',
                    uri: Uri.parse('https://example.com'),
                    autofocus: true,
                  )
                : Text('removed'),
          ),
        ),
      );
      await t.mouse(_at(MouseEventKind.press, 0, 0));
      visible.value = false;
      await t.pump();
      await t.mouse(_at(MouseEventKind.release, 0, 0));
      await t.press('enter');
      expect(t.terminal.openedUrls, isEmpty);
      expect(t.screen.text, 'removed');
    });
  });
}
