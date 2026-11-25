import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester U1 tool helper boundaries', () {
    test('every M1 kind supplies a name for an untitled call', () {
      for (final (kind, name) in [
        ('read', 'Read'),
        ('edit', 'Update'),
        ('delete', 'Delete'),
        ('move', 'Move'),
        ('search', 'Search'),
        ('execute', 'Bash'),
        ('think', 'Think'),
        ('fetch', 'Fetch'),
        ('switch_mode', 'Mode'),
        ('other', 'Tool'),
        ('future_kind', 'Tool'),
      ]) {
        final line = headline(ToolCall('call', title: '  ', kind: kind));
        expect((line.name, line.arg), (name, null), reason: kind);
      }
    });

    test('turn identity survives cancellation and permission waits', () {
      for (final turn in <TurnState>[
        const Working('active', 0),
        const Cancelling('active', 0, 1),
        const AwaitingPermission('active', 0, []),
      ]) {
        expect(turnEnded(turn, 'active'), isFalse);
        expect(turnEnded(turn, 'older'), isTrue);
      }
      expect(turnEnded(const Idle(), 'active'), isTrue);
      expect(
        turnEnded(
          const AwaitingPermission('active', 0, [], between: true),
          'active',
        ),
        isTrue,
      );
    });

    test('first line keeps metadata and trims only the right edge', () {
      const line = Headline(
        'Bash',
        arg: '  echo hi\t \nnext',
        tag: ' (MCP)',
        note: ' done',
      );
      final first = firstLine(line);
      expect(
        (first.name, first.arg, first.tag, first.note),
        ('Bash', '  echo hi', ' (MCP)', ' done'),
      );
      expect(line.arg, '  echo hi\t \nnext');
    });

    test('MCP JSON escapes every terminal control in keys and values', () {
      final controls = String.fromCharCodes([
        ...List.generate(32, (i) => i),
        ...List.generate(33, (i) => 127 + i),
      ]);
      final text = mcpArguments({
        controls: controls,
        'nested': [false, null],
      })!;
      expect(text, isNot(contains(RegExp('[\u0000-\u001f\u007f-\u009f]'))));
      expect(text, contains(r'\u001b'));
      expect(text, contains(r'\u009f'));
      expect(text, contains('nested: [false,null]'));
      final filed = headline(
        const ToolCall(
          'call',
          title: 'mcp__ignored__ignored',
          rawInput: {'wrong': true},
          mcp: McpCall('actual', {'right': false}, server: ''),
        ),
      );
      expect((filed.name, filed.arg), (' - actual', 'right: false'));
    });

    test('zero one and unbounded room have finite stable layouts', () {
      const line = Headline('Read', arg: 'a');
      // The original wrapLine clamps its text room to one cell.
      expect(
        headlineRows(line, 0).map((row) => row.map((g) => g.text).join()),
        ['R', 'e', 'a', 'd', '(', 'a', ')'],
      );
      final one = headlineRows(line, 1);
      expect(one.map(TextLayout.lineWidth), everyElement(lessThanOrEqualTo(1)));
      expect(one.expand((r) => r).map((g) => g.text).join(), 'Read(a)');
      expect(headlineRows(line, unbounded), hasLength(1));
    });

    test('wide and combining graphemes stay whole at each wrap edge', () {
      for (final width in [2, 3, 4, 7, 76, 116]) {
        for (var edge = 0; edge <= width; edge++) {
          final argument = '${'x' * edge}界👩‍💻e\u0301界';
          final rows = headlineRows(Headline('R', arg: argument), width);
          expect(
            rows.map(TextLayout.lineWidth),
            everyElement(lessThanOrEqualTo(width)),
          );
          final glyphs = rows.expand((row) => row).toList();
          expect(glyphs.map((g) => g.text).join(), 'R($argument)');
          expect(glyphs.where((g) => g.text == '👩‍💻'), hasLength(1));
          expect(glyphs.where((g) => g.text == 'e\u0301'), hasLength(1));
        }
      }
    });
  });
}
