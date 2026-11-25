// Original tools_test.ts: summary M1 cases. Chord servers, questions,
// settings, sent messages, subagents and proposals remain out of M1.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:test/test.dart';

acp.ToolCallContent text(String value) => acp.ToolCallContent.fromJson({
  'type': 'content',
  'content': {'type': 'text', 'text': value},
});
acp.ToolCallContent diff() => acp.ToolCallContent.fromJson({
  'type': 'diff',
  'path': 'a.ts',
  'oldText': 'a\nb\n',
  'newText': 'a\nc\nd\n',
});
void main() {
  test('a call with no output says where it is, unless its turn ended', () {
    for (final (status, expected) in [
      (null, ['Waiting…']),
      ('in_progress', ['Running…']),
      ('completed', <String>[]),
      ('failed', ['Failed']),
    ]) {
      final call = ToolCall('a', status: status);
      expect(summary(call, false).lines, expected);
      expect(
        summary(call, true, ended: true).lines,
        status == 'failed' ? ['Failed'] : [],
      );
    }
  });
  test('long output is drawn whole, only Read keeps three lines', () {
    for (final kind in ['read', 'other']) {
      final call = ToolCall(
        'a',
        status: 'completed',
        kind: kind,
        content: [text('1\n2\n3\n4\n5\n')],
      );
      expect(
        summary(call, false).lines,
        kind == 'read' ? ['1', '2', '3'] : ['1', '2', '3', '4', '5'],
      );
      expect(summary(call, false).hidden, kind == 'read' ? 2 : 0);
      expect(summary(call, true).lines, ['1', '2', '3', '4', '5']);
    }
  });
  test('long result rows wrap by words, keeping color over wraps', () {
    final call = ToolCall(
      'a',
      content: [
        text('\x1b[31mone two three four five six seven eight nine ten\x1b[0m'),
      ],
    );
    final view = summary(call, false, width: 20);
    expect(view.lines, [
      'one two three four',
      'five six seven eight',
      'nine ten',
    ]);
    expect(view.hidden, 0);
    expect(view.rows.every((row) => row.first.style.fg != null), isTrue);
  });
  test('a failed call says Error before output', () {
    expect(
      summary(
        ToolCall('a', status: 'failed', content: [text('no such file')]),
        false,
      ).lines,
      ['Error: no such file'],
    );
  });
  test('diffs draw under lines, whole regardless of expansion', () {
    final view = summary(
      ToolCall('a', status: 'completed', content: [text('done'), diff()]),
      false,
    );
    expect(view.lines, ['done']);
    expect(
      (
        view.diffs.single.path,
        view.diffs.single.view.added,
        view.diffs.single.view.removed,
      ),
      ('a.ts', 2, 1),
    );
    expect(view.diffs.single.view.hidden, 0);
    for (final status in ['pending', 'in_progress', 'completed', 'failed']) {
      expect(
        summary(ToolCall('a', status: status, content: [diff()]), false).lines,
        status == 'failed' ? ['Failed'] : [],
      );
    }
  });
  test('a terminal draws its output in place of the call working', () {
    expect(
      summary(
        const ToolCall('a', status: 'in_progress', terminals: [Terminal('t')]),
        false,
      ).lines,
      ['Running…'],
    );
    final view = summary(
      const ToolCall(
        'a',
        status: 'in_progress',
        terminals: [Terminal('t', output: '1\n2\n3\n4\n')],
      ),
      false,
    );
    expect(view.lines, isEmpty);
    expect(view.terminals.single.lines, ['2', '3', '4']);
    expect(view.terminals.single.hidden, 1);
  });
  test('a failing exit says the failure without Failed', () {
    for (final code in [0, 1]) {
      final view = summary(
        ToolCall(
          'a',
          status: 'failed',
          terminals: [
            Terminal('t', output: 'boom\n', exited: true, exitCode: code),
          ],
        ),
        false,
      );
      expect(view.lines, code == 1 ? [] : ['Failed']);
      if (code == 1) expect(view.terminals.single.note?.text, 'Exit code 1');
    }
  });
  test('nontext content labels, whitespace and CRLF match the original', () {
    final view = summary(
      ToolCall(
        'a',
        content: [
          text('\r\n'),
          text('a\r\nb  \n'),
          acp.ToolCallContent.fromJson({
            'type': 'content',
            'content': {'type': 'image'},
          }),
        ],
      ),
      false,
    );
    expect(view.lines, ['a', 'b', '[image]']);
  });
}
