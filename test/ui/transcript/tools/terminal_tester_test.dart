import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/terminal.dart' as tools;
import 'package:test/test.dart';

void main() {
  group('tester U2 terminal boundaries', () {
    test('every tail boundary preserves blank lines and Unicode', () {
      final source = ['  first  ', '', '界👩‍💻e\u0301', 'last'];
      for (var count = 0; count <= source.length; count++) {
        final terminal = Terminal('t', output: source.take(count).join('\n'));
        final full = tools.terminalView(terminal, true);
        final tail = tools.terminalView(terminal, false);
        expect(tail.hidden + tail.lines.length, full.lines.length);
        expect(tail.lines, full.lines.skip(tail.hidden).toList());
        expect(tail.lines.length, lessThanOrEqualTo(3));
      }
    });

    test('signal precedence and empty truncated output stay explicit', () {
      final killed = tools.terminalView(
        const Terminal('t', exited: true, exitCode: 7, signal: '  \n'),
        false,
      );
      expect((killed.note!.text, killed.note!.failed), ('Killed', true));
      final truncated = tools.terminalView(
        const Terminal('t', exited: true, truncated: true),
        true,
      );
      expect(truncated.lines, ['… output cut']);
      expect(truncated.hidden, 0);
      expect(truncated.note!.text, '(No output)');
      expect(tools.isEmpty(truncated), isFalse);
    });

    test('large integral doubles keep the original JavaScript spelling', () {
      final terminal = Terminal(
        't',
        exited: true,
        exitCode: 1000000000000000100.0,
      );
      final view = tools.terminalView(terminal, false);
      expect(view.note!.text, 'Exit code 1000000000000000100');
      expect(terminal.exitCode, 1000000000000000100.0);
    });
  });
}
