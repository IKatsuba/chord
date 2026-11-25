import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/selection_layout.dart'
    show shapeSelectionSource;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

// A reply's code block framed as the original's (CTUI-71): the box of
// markdown.ts codeOf and Reply.tsx, code one cell in, cut by character as
// OpenTUI's wrapMode 'char' cuts it. The rows are the original's
// `markdowncode` captures (docs/design/CTUI-71.md), less the transcript's
// three-cell indent.
const _sh =
    '```sh\nbun dev chord --fake --qa capture && tmux capture-pane -t '
    'chord-qa -p > /tmp/screen.txt\n\necho done\n```';

const _rows = {
  116: [
    '┌─ sh ───────────────────────────────────────────────────────────────────────[copy]─[run]─┐',
    '│ bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p > /tmp/screen.txt │',
    '│                                                                                         │',
    '│ echo done                                                                               │',
    '└─────────────────────────────────────────────────────────────────────────────────────────┘',
  ],
  76: [
    '┌─ sh ────────────────────────────────────────────────────────[copy]─[run]─┐',
    '│ bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p >  │',
    '│ /tmp/screen.txt                                                          │',
    '│                                                                          │',
    '│ echo done                                                                │',
    '└──────────────────────────────────────────────────────────────────────────┘',
  ],
  56: [
    '┌─ sh ────────────────────────────────────[copy]─[run]─┐',
    '│ bun dev chord --fake --qa capture && tmux capture-pa │',
    '│ ne -t chord-qa -p > /tmp/screen.txt                  │',
    '│                                                      │',
    '│ echo done                                            │',
    '└──────────────────────────────────────────────────────┘',
  ],
};

SelectionSource _source(String text) => SelectionSource.markdown(
  id: 'reply',
  revision: 0,
  text: text,
  copyCodeBlocks: true,
  runCodeBlockLanguages: const {'sh'},
);

Widget _md(SelectionSource source) => Markdown.fromSelectionSource(
  source,
  onCopyCodeBlock: (_) {},
  onRunCodeBlock: (_) {},
);

List<String> _shown(WidgetTester t) {
  final lines = [for (final line in t.screen.lines) line.trimRight()];
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

void main() {
  for (final MapEntry(key: width, value: rows) in _rows.entries) {
    testWidgets('the sh block is the original\'s box at $width cells', (
      t,
    ) async {
      await t.pumpWidget(_md(_source(_sh)), size: Size(width, 12));
      expect(_shown(t), rows);
      expect(Markdown.heightOf(_source(_sh), width), rows.length);
    });
  }

  testWidgets('the title sits past one rule, with its buttons', (t) async {
    await t.pumpWidget(
      _md(_source('```typescript\nx\n```')),
      size: const Size(80, 6),
    );
    expect(_shown(t), [
      '┌─ typescript ─[copy]─┐',
      '│ x                   │',
      '└─────────────────────┘',
    ]);
  });

  testWidgets('a label shows only from its width and six', (t) async {
    // Six cells for `┌─ ` and ` ─┐`: `abc` takes nine, and eight leave it out.
    for (final (room, top) in [(9, '┌─ abc ─┐'), (8, '┌──────┐')]) {
      await t.pumpWidget(
        Row(
          children: [SizedBox(width: room, child: Markdown('```abc\nx\n```'))],
        ),
        size: const Size(20, 4),
      );
      expect(t.screen.lines.first.trimRight(), top, reason: 'in $room');
    }
  });

  testWidgets('a wide grapheme that does not fit moves whole', (t) async {
    await t.pumpWidget(
      Row(children: [SizedBox(width: 8, child: Markdown('```\nabc中\n```'))]),
      size: const Size(20, 6),
    );
    expect(_shown(t), ['┌──────┐', '│ abc  │', '│ 中   │', '└──────┘']);
  });

  testWidgets('heightOf is the drawn height at every width', (t) async {
    final source = _source(
      'Before.\n\n$_sh\n\n- item\n\n  ```ts\n  中文 a\n  ```',
    );
    for (var width = 4; width <= 100; width++) {
      await t.pumpWidget(_md(source), size: Size(width, 200));
      expect(
        Markdown.heightOf(source, width),
        _shown(t).length,
        reason: 'at $width',
      );
    }
  });

  test('copying wrapped code rows gives the source with no break added', () {
    const code = 'abcdefghij klmnop';
    final shape = shapeSelectionSource(_source('```\n$code\n```'), width: 10);
    expect(shape.rows.length, greaterThan(3));
    expect(shape.selectedText, code);
  });
}
