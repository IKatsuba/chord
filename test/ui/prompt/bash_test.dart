import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/prompt/bash.dart';
import 'package:test/test.dart';

void main() {
  test(
    'prefix starts mode only from an empty ordinary draft, history keeps it',
    () {
      expect(entersBash(false, '', '!'), '');
      expect(entersBash(false, '', '!ls -la'), 'ls -la');
      expect(entersBash(false, 'hi', 'hi!'), isNull);
      expect(entersBash(false, '', 'ls'), isNull);
      expect(entersBash(true, '', '!'), isNull);
      expect(typedText(true, 'ls'), '!ls');
      expect(typedText(false, 'ls'), 'ls');
      expect(bashCommand('!ls'), 'ls');
      expect(bashCommand('ls'), isNull);
    },
  );
  test(
    'output is stdout then stderr; helper folds but actual full view does not',
    () {
      final run = ShellRun(
        command: 'ls',
        running: false,
        stdout: List.generate(25, (i) => 'line $i').join('\n'),
        stderr: 'oops\n',
        code: 3,
      );
      final folded = shellView(run, false, 'esc'),
          full = shellView(run, true, 'esc');
      expect(folded.lines.length, shellLines);
      expect(folded.hidden, 16);
      expect(full.lines.length, 26);
      expect(full.hidden, 0);
      expect(full.lines.last, (text: 'oops', stderr: true));
      expect(full.note, (text: 'Exit code 3', failed: true));
    },
  );
  test('running stopped silent success and truncated notes retain wording', () {
    expect(
      shellView(const ShellRun(command: 'x', running: true), true, 'esc').note,
      (text: 'Running… (esc to stop)', failed: false),
    );
    expect(
      shellView(const ShellRun(command: 'x', running: true), true, null).note,
      (text: 'Running…', failed: false),
    );
    expect(
      shellView(
        const ShellRun(command: 'x', running: false, stopped: true),
        true,
        'esc',
      ).note,
      (text: 'Stopped by the user', failed: false),
    );
    expect(
      shellView(const ShellRun(command: 'x', running: false), true, 'esc').note,
      (text: '(No output)', failed: false),
    );
    expect(
      shellView(
        const ShellRun(command: 'x', running: false, stdout: 'ok'),
        true,
        'esc',
      ).note,
      isNull,
    );
    expect(
      shellView(
        const ShellRun(command: 'x', running: false, truncated: true),
        true,
        'esc',
      ).lines.single.text,
      '… output cut',
    );
  });
}
