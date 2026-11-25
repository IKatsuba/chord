// Original Tool_test.tsx/Guardian_test.tsx: M1 output, terminal, diff, failure,
// headline and Guardian cases. Chord tools/proposals/asks/subagents omitted.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart' hide Folded;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

acp.ToolCallContent text(String value) => acp.ToolCallContent.fromJson({
  'type': 'content',
  'content': {'type': 'text', 'text': value},
});
void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets('Read folds source lines under its headline at $size', (
      t,
    ) async {
      final call = model.ToolCall(
        'a',
        title: 'Read a.txt',
        kind: 'read',
        status: 'completed',
        content: [text('1\n2\n3\n4\n5\n')],
      );
      await t.pumpWidget(Tool(call, expanded: false), size: size);
      expect(t.screen.lines.take(6), [
        '',
        '⏺ Read(a.txt)',
        '  ⎿  1',
        '     2',
        '     3',
        '     … +2 lines (ctrl+o to expand)',
      ]);
      expect(t.screen.styleAt(0, 1).fg, ThemeData.dark().success.fg);
      await t.pumpWidget(Tool(call, expanded: true), size: size);
      expect(t.screen.lines.take(7), [
        '',
        '⏺ Read(a.txt)',
        '  ⎿  1',
        '     2',
        '     3',
        '     4',
        '     5',
      ]);
    });
    testWidgets(
      'terminal newest rows then hidden count then failure at $size',
      (t) async {
        const call = model.ToolCall(
          'a',
          title: 'Run checks',
          kind: 'execute',
          status: 'failed',
          terminals: [
            model.Terminal(
              't',
              output: '1\n2\n3\n4\n5\n',
              exited: true,
              exitCode: 1,
            ),
          ],
        );
        await t.pumpWidget(const Tool(call, expanded: false), size: size);
        expect(t.screen.lines.take(7), [
          '',
          '⏺ Run(checks)',
          '  ⎿  3',
          '     4',
          '     5',
          '     … +2 lines (ctrl+o to expand)',
          '     Exit code 1',
        ]);
        expect(t.screen.styleAt(5, 6).fg, ThemeData.dark().error.fg);
      },
    );
    testWidgets(
      'diffs remain whole with counts and no repeated title at $size',
      (t) async {
        final call = model.ToolCall(
          'a',
          title: 'Edit a.ts',
          status: 'completed',
          content: [
            acp.ToolCallContent.fromJson({
              'type': 'diff',
              'path': 'a.ts',
              'oldText': 'a\nb',
              'newText': 'a\nc\nd',
            }),
          ],
        );
        await t.pumpWidget(Tool(call, expanded: false), size: size);
        expect(t.screen.lines.take(7), [
          '',
          '⏺ Edit(a.ts)',
          '  ⎿  Updated a.ts with 2 additions and 1 removal',
          '     1   a',
          '     2 - b',
          '     2 + c',
          '     3 + d',
        ]);
        final lines = t.screen.lines.toList();
        await t.pumpWidget(Tool(call, expanded: true), size: size);
        expect(t.screen.lines, lines);
      },
    );
    testWidgets(
      'failure wording and multiline headline wrap without losing ANSI at $size',
      (t) async {
        final call = model.ToolCall(
          'a',
          title: 'Bash one\n  two',
          status: 'failed',
          content: [text('\x1b[31mno such file\x1b[0m')],
        );
        await t.pumpWidget(Tool(call, expanded: false), size: size);
        expect(t.screen.lines.take(4), [
          '',
          '⏺ Bash(one',
          '    two)',
          '  ⎿  Error: no such file',
        ]);
        expect(t.screen.styleAt(2, 1).isBold, isTrue);
      },
    );
    testWidgets(
      'Guardian structured states hide, review or draw full block at $size',
      (t) async {
        await t.pumpWidget(
          const Tool(
            model.ToolCall('a', guardian: 'approved'),
            expanded: false,
          ),
          size: size,
        );
        expect(t.screen.text, isEmpty);
        await t.pumpWidget(
          const Tool(
            model.ToolCall('a', guardian: 'inProgress'),
            expanded: false,
          ),
          size: size,
        );
        expect(t.screen.lines.take(2), ['', '  Guardian reviewing…']);
        await t.pumpWidget(
          const Tool(
            model.ToolCall(
              'a',
              title: 'Review',
              guardian: 'denied',
              status: 'failed',
            ),
            expanded: false,
          ),
          size: size,
        );
        expect(t.screen, shows('Failed'));
      },
    );
    testWidgets(
      'ended running tools stop waiting and use pending tone at $size',
      (t) async {
        await t.pumpWidget(
          const Tool(
            model.ToolCall('a', title: 'Run', status: 'in_progress'),
            expanded: false,
            ended: true,
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), ['', '⏺ Run', '']);
        expect(t.screen.styleAt(0, 1).isDim, isTrue);
      },
    );
  }
  testWidgets('CUT furniture uses middle overflow in a narrow room', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 22,
          child: Tool(
            model.ToolCall('a', guardian: 'inProgress'),
            expanded: false,
          ),
        ),
      ),
    );
    expect(t.screen.lines[1], '  Guardian reviewing…');
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 22, child: Folded(123456)),
      ),
    );
    expect(t.screen.lines.first, '     … +1234...expand)');
  });
  testWidgets('review row does not consume the terminal or diff first marker', (
    t,
  ) async {
    const review = PermissionReview('caution', 'check');
    await t.pumpWidget(
      const Tool(
        model.ToolCall(
          'a',
          title: 'Run',
          review: review,
          terminals: [model.Terminal('t', output: 'output')],
        ),
        expanded: false,
      ),
    );
    expect(t.screen.lines.take(4), [
      '',
      '⏺ Run',
      '  ⎿  Reviewed: caution',
      '  ⎿  output',
    ]);
    await t.pumpWidget(
      Tool(
        model.ToolCall(
          'a',
          title: 'Edit',
          review: review,
          content: [
            acp.ToolCallContent.fromJson({
              'type': 'diff',
              'path': 'a',
              'oldText': 'a',
              'newText': 'b',
            }),
          ],
        ),
        expanded: false,
      ),
    );
    expect(t.screen.lines[3], startsWith('  ⎿  Updated a'));
    await t.pumpWidget(
      Tool(
        model.ToolCall(
          'a',
          title: 'Read',
          review: review,
          content: [text('output')],
        ),
        expanded: false,
      ),
    );
    expect(t.screen.lines[3], '     output');
  });
  testWidgets('running marker pulses then stops and disposes its timer', (
    t,
  ) async {
    await t.pumpWidget(const ToolMarker(Tone.running));
    expect(t.screen.styleAt(0, 0).fg, ThemeData.dark().accent.fg);
    await t.pump(const Duration(milliseconds: 550));
    expect(t.screen.styleAt(0, 0).isDim, isTrue);
    await t.pumpWidget(const ToolMarker(Tone.done));
    await t.pump(const Duration(milliseconds: 550));
    expect(t.screen.styleAt(0, 0).fg, ThemeData.dark().success.fg);
  });
}
