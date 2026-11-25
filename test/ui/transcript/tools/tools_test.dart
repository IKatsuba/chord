// Original tools_test.ts: chord server/cuts/sent messages/settings/questions
// and subagents omitted for M1. Summary cases follow after U2a/U2.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:test/test.dart';

void main() {
  test('a title starting with a verb reads as Verb(arg)', () {
    final line = headline(const ToolCall('a', title: 'Read src/main.tsx'));
    expect((line.name, line.arg), ('Read', 'src/main.tsx'));
    expect(
      headline(const ToolCall('a', title: 'Edit `src/a.ts`')).arg,
      'src/a.ts',
    );
  });
  test(
    'a multiline verb-first command keeps its full argument and only one verb',
    () {
      const command = "printf 'one\ntwo\nthree\nfour\n'; exit 1";
      final line = headline(
        const ToolCall('a', title: 'Bash $command', kind: 'execute'),
      );
      expect((line.name, line.arg), ('Bash', command));
    },
  );
  test('a bare command or description is named by its kind', () {
    for (final (title, kind, name, arg) in [
      ('`ls -la`', 'execute', 'Bash', 'ls -la'),
      ('grep TODO', 'search', 'Search', 'grep TODO'),
      ('Task', null, 'Task', null),
      ('', null, 'Tool', null),
      ('', 'fetch', 'Fetch', null),
    ]) {
      final line = headline(ToolCall('a', title: title, kind: kind));
      expect((line.name, line.arg), (name, arg));
    }
  });
  test('a title of several lines is the argument whole, every line kept', () {
    const title = "cat <<'EOF'\n## One\n\n  - indented\nEOF";
    expect(
      headline(const ToolCall('a', title: title, kind: 'execute')).arg,
      title,
    );
    expect(
      firstLine(const Headline('Bash', arg: "cat <<'EOF'  \nEOF")).arg,
      "cat <<'EOF'",
    );
    const bare = Headline('Bash');
    expect(firstLine(bare), same(bare));
  });
  test('MCP headlines and arguments preserve JSON and escape controls', () {
    final line = headline(
      const ToolCall(
        'a',
        title: 'mcp__notes__save_note',
        rawInput: {'text': 'one\ntwo', 'n': 2},
      ),
    );
    expect(
      (line.name, line.tag, line.arg),
      ('notes - save_note', ' (MCP)', r'text: "one\ntwo", n: 2'),
    );
    expect(mcpArguments(null), isNull);
    expect(mcpArguments(<String, Object?>{}), isNull);
    expect(mcpArguments([1, true]), '[1,true]');
    expect(mcpArguments({'a\u0085': '\u007f'}), r'a\u0085: "\u007f"');
  });
  test('MCP title fallback preserves spaces and real newlines', () {
    final line = headline(
      const ToolCall('a', title: 'mcp__notes server__save\nnote'),
    );
    expect((line.name, line.tag), ('notes server - save\nnote', ' (MCP)'));
    final filed = headline(
      const ToolCall(
        'a',
        title: 'mcp__notes server__save\nnote',
        mcp: McpCall('actual', {}, server: 'filed'),
      ),
    );
    expect(filed.name, 'filed - actual');
  });
  test('filed MCP wrapper overrides title only when it has a server', () {
    final filed = headline(
      const ToolCall(
        'a',
        title: 'Other',
        mcp: McpCall('tool.name', {'x': 1}, server: 'server.name'),
      ),
    );
    expect((filed.name, filed.arg), ('server.name - tool.name', 'x: 1'));
    expect(
      headline(
        const ToolCall('a', title: 'Read a', mcp: McpCall('ignored', {})),
      ).name,
      'Read',
    );
  });
  test(
    'headline rows keep indent, real newlines, styles and closing punctuation',
    () {
      List<String> rows(Headline h, int width) => headlineRows(
        h,
        width,
      ).map((row) => row.map((g) => g.text).join()).toList();
      expect(rows(const Headline('Bash', arg: 'f\n    two words'), 10), [
        'Bash(f',
        '    two',
        'words)',
      ]);
      expect(rows(const Headline('Fetch', arg: 'https://example.com/a'), 10), [
        'Fetch(http',
        's://exampl',
        'e.com/a)',
      ]);
      for (final width in [76, 116]) {
        final laidOut = headlineRows(
          const Headline('Bash', arg: 'one\n\n\x1b[31mred\x1b[0m'),
          width,
        );
        expect(laidOut.map((row) => row.map((g) => g.text).join()), [
          'Bash(one',
          '',
          'red)',
        ]);
        expect(laidOut.first.first.style.isBold, isTrue);
        expect(laidOut.last.first.style.fg, isNotNull);
        expect(laidOut.last.last.style.fg, isNull);
      }
    },
  );
  test('the status picks the tone; no status is pending', () {
    for (final (status, tone) in [
      (null, Tone.pending),
      ('in_progress', Tone.running),
      ('completed', Tone.done),
      ('failed', Tone.failed),
    ]) {
      expect(toneOf(ToolCall('a', status: status)), tone);
      expect(toneOf(ToolCall('a', status: status), asked: true), Tone.pending);
    }
  });
  test('a call left unfinished by what ran it waits on nothing', () {
    expect(turnEnded(const Idle(), 'a'), isTrue);
    expect(turnEnded(const Working('a', 0), 'a'), isFalse);
    expect(turnEnded(const Cancelling('a', 0, 1), 'b'), isTrue);
    expect(
      turnEnded(const AwaitingPermission('a', 0, [], between: true), 'a'),
      isTrue,
    );
    expect(turnEnded(const AwaitingPermission('a', 0, []), 'a'), isFalse);
  });
  test('Guardian presentation follows only its structured status', () {
    expect(
      guardianView(const ToolCall('a', guardian: 'approved')),
      GuardianView.hidden,
    );
    expect(
      guardianView(const ToolCall('a', guardian: 'inProgress')),
      GuardianView.reviewing,
    );
    for (final value in [null, 'denied', 'timedOut', 'aborted', 'unknown']) {
      expect(guardianView(ToolCall('a', guardian: value)), GuardianView.block);
    }
  });
}
