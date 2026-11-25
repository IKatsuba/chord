// The note a resumed session's transcript closes with, naming the agents it
// left open (design CTUI-35 section 7, interface I11): the original's
// leftOpenLine word for word, drawn after a gap as a dim ⏺ beside a dim line
// that keeps a record's own colours, as ../chord's Transcript.tsx draws
// `left_open` through <Ansi>.
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/agents/agents.dart' show leftOpenLine;
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// The original's test value for a saved name: red, a reset, an erased
/// line and an OSC 8 link, of which only the colour and the words stay.
const _escaped =
    '\x1b[31mred\x1b[0m\x1b[2K \x1b]8;;https://example.com\x07link\x1b]8;;\x07';

/// The transcript's width in a window [columns] wide: the window keeps a
/// column each side, as the original's captures show.
int _transcript(int columns) => columns - 2;

Future<List<String>> _drawn(
  WidgetTester t,
  List<model.LeftOpen> agents,
  Size size,
) async {
  await t.pumpWidget(
    TranscriptEntry(model.LeftOpenEntry('history-left', agents)),
    size: Size(_transcript(size.width), size.height),
  );
  return [for (final row in t.screen.lines) row.trimRight()];
}

void main() {
  _testerLeftOpenEdges();

  group('CTUI-37 tester: resumed team note boundaries', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('team note survives tiny room and resize at $size', (
        t,
      ) async {
        const agents = [
          (name: 'bugfix', runtime: 'fake', team: 'bugfix', agents: 2),
          (name: 'bugfix 2', runtime: 'fake', team: 'bugfix', agents: 1),
        ];
        const widget = TranscriptEntry(
          model.LeftOpenEntry('history-left', agents),
        );
        await t.pumpWidget(widget, size: const Size(0, 1));
        await t.pumpWidget(widget, size: const Size(1, 1));
        await t.pumpWidget(widget, size: size);
        await t.pump();
        final line = t.screen.lines
            .map((row) => row.trim())
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(
          line,
          contains('team bugfix (2 agents) and team bugfix 2 (1 agent)'),
        );
        expect(line, contains('/team run bugfix starts the team again'));
        expect(RegExp('/team run bugfix').allMatches(line), hasLength(1));
      });
    }
  });
  test('one agent is said in the singular, as the original says it', () {
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
      ]),
      'parser (codex) was open when this session was left and is not '
      'reopened · /resume lists it',
    );
  });

  test('two or more are said in the plural, listed as English lists', () {
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
        (name: 'docs', runtime: 'claude', team: null, agents: null),
      ]),
      'parser (codex) and docs (claude) were open when this session was left '
      'and are not reopened · /resume lists them',
    );
    expect(
      leftOpenLine([
        (name: 'parser', runtime: 'codex', team: null, agents: null),
        (name: 'docs', runtime: 'claude', team: null, agents: null),
        (name: 'printer', runtime: 'gemini', team: null, agents: null),
      ]).split(' were ').first,
      'parser (codex), docs (claude), and printer (gemini)',
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the note is a dim ⏺ beside a dim line after a gap at $size', (
      t,
    ) async {
      final rows = await _drawn(t, [
        (name: 'parser', runtime: 'codex', team: null, agents: null),
        (name: 'docs', runtime: 'claude', team: null, agents: null),
      ], size);
      expect(rows[0], '');
      expect(rows[1], startsWith('⏺ parser (codex) and docs (claude) were'));
      final note = rows.skip(1).takeWhile((row) => row.isNotEmpty).toList();
      // Wrapped rows hang under the line's start, never under the mark.
      expect(note.skip(1).every((row) => row.startsWith('  ')), isTrue);
      expect(
        note.map((row) => row.substring(2).trim()).join(' '),
        'parser (codex) and docs (claude) were open when this session was '
        'left and are not reopened · /resume lists them',
      );
      expect(t.screen.styleAt(0, 1).isDim, isTrue, reason: 'the mark');
      for (var y = 1; y <= note.length; y++) {
        for (var x = 2; x < note[y - 1].length; x++) {
          expect(t.screen.styleAt(x, y).isDim, isTrue, reason: '($x, $y)');
        }
      }
    });

    testWidgets("a saved name's colour stays inside the dim line, its other "
        'escapes go, and it wraps as the original did at $size', (t) async {
      final rows = await _drawn(t, [
        (
          name: _escaped,
          runtime: '\x1b[32mcodex\x1b[39m',
          team: null,
          agents: null,
        ),
      ], size);
      // ../chord docs/qa/evidence/CHD-337/source120.ansi and source80.ansi,
      // the window's margin column taken off.
      expect(
        rows.skip(1).takeWhile((row) => row.isNotEmpty),
        size.width == 120
            ? [
                '⏺ red link (codex) was open when this session was left and '
                    'is not reopened · /resume lists it',
              ]
            : [
                '⏺ red link (codex) was open when this session was left and '
                    'is not reopened · /',
                '  resume lists it',
              ],
      );
      final red = t.screen.styleAt(2, 1), link = t.screen.styleAt(6, 1);
      final codex = t.screen.styleAt(12, 1), after = t.screen.styleAt(18, 1);
      expect((red.fg, red.isDim), (Colors.red, true));
      // The reset after `red` goes back to the line's dim.
      expect((link.fg, link.isDim), (null, true));
      expect((codex.fg, codex.isDim), (Colors.green, true));
      expect((after.fg, after.isDim), (null, true));
    });
  }
}

void _testerLeftOpenEdges() {
  group('CTUI-35 tester: left-open Unicode edges', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'ANSI and graphemes survive tiny room then a resized frame at $size',
        (t) async {
          const note = TranscriptEntry(
            model.LeftOpenEntry('history-left', [
              (
                name: '\x1b[31m界🙂e\u0301\x1b[0m',
                runtime: 'fake',
                team: null,
                agents: null,
              ),
              (name: 'docs', runtime: 'fake', team: null, agents: null),
            ]),
          );
          await t.pumpWidget(note, size: const Size(0, 1));
          await t.pumpWidget(note, size: const Size(1, 1));
          await t.pumpWidget(note, size: Size(size.width - 2, size.height));
          await t.pump();
          final text = t.screen.lines.join('\n');
          expect(text, contains('界🙂e\u0301'));
          expect(text, contains('docs (fake)'));
          expect(text, isNot(contains('\x1b')));
          expect(t.screen.styleAt(2, 1).fg, Colors.red);
          expect(t.screen.styleAt(2, 1).isDim, isTrue);
          await t.pumpWidget(const SizedBox(), size: size);
          expect(t.screen.lines.every((line) => line.trim().isEmpty), isTrue);
        },
      );
    }
  });
}
