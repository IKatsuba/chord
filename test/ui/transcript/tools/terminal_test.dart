// Original terminal_test.ts: all six cases carried over; none left out.
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/terminal.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('a folded terminal keeps its latest lines and counts those above', () {
    final view = terminalView(
      Terminal(
        't',
        output: List.generate(7, (i) => 'line ${i + 1}').join('\n'),
      ),
      false,
    );
    expect(view.lines, ['line 5', 'line 6', 'line 7']);
    expect(view.hidden, 4);
    expect(view.note, isNull);
  });
  test('ctrl+o shows the whole output, and says where its start was cut', () {
    const terminal = Terminal('t', output: 'a\nb\nc\nd\ne\n', truncated: true);
    expect(terminalView(terminal, true).lines, [
      '… output cut',
      'a',
      'b',
      'c',
      'd',
      'e',
    ]);
    expect(terminalView(terminal, true).hidden, 0);
    expect(terminalView(terminal, false).lines, ['c', 'd', 'e']);
  });
  test('the output is drawn as the reducer keeps it, tabs already spaces', () {
    expect(
      terminalView(
        const Terminal('t', output: 'a       b\n界      d\n\n'),
        true,
      ).lines,
      ['a       b', '界      d'],
    );
  });
  test('a failing exit says its code; success says nothing more', () {
    final failed = terminalView(
      const Terminal('t', output: 'boom\n', exited: true, exitCode: 2),
      false,
    );
    expect((failed.note?.text, failed.note?.failed), ('Exit code 2', true));
    expect(
      terminalView(
        const Terminal('t', output: 'ok\n', exited: true, exitCode: 0),
        false,
      ).note,
      isNull,
    );
    expect(
      terminalView(
        const Terminal('t', exited: true, signal: 'SIGTERM'),
        false,
      ).note?.text,
      'Killed by SIGTERM',
    );
  });
  test('exit numbers use the original JavaScript display spelling', () {
    for (final (code, shown) in [
      (2.0, '2'),
      (2.5, '2.5'),
      (1e20, '100000000000000000000'),
      (1e21, '1e+21'),
    ]) {
      final terminal = Terminal('t', exited: true, exitCode: code);
      expect(terminalView(terminal, false).note?.text, 'Exit code $shown');
      expect(terminal.exitCode, same(code));
    }
  });
  test('an agent signal name is drawn on one line in its own tone', () {
    expect(
      terminalView(
        const Terminal('t', signal: 'SIG\nTERM\n'),
        false,
      ).note?.text,
      'Killed by SIG TERM',
    );
    expect(
      terminalView(const Terminal('t', signal: ''), false).note?.text,
      'Killed',
    );
  });
  test('a terminal that wrote nothing is empty until it ends', () {
    expect(isEmpty(terminalView(const Terminal('t'), false)), isTrue);
    expect(
      isEmpty(terminalView(const Terminal('t', output: '\n'), false)),
      isTrue,
    );
    final note = terminalView(
      const Terminal('t', exited: true, exitCode: 0),
      false,
    ).note;
    expect((note?.text, note?.failed), ('(No output)', false));
  });
}
