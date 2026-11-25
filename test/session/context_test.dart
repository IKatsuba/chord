import 'package:chord/session/context.dart' as context;
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  ShellRun done({
    String command = 'ls',
    String stdout = '',
    String stderr = '',
    num? code = 0,
    bool stopped = false,
    String? error,
    bool truncated = false,
  }) => ShellRun(
    command: command,
    stdout: stdout,
    stderr: stderr,
    running: false,
    code: code,
    stopped: stopped,
    error: error,
    truncated: truncated,
  );
  test('cleans colors links progress CRLF and trailing whitespace', () {
    expect(
      context.cleanOutput(
        '\x1b[31mred\x1b[0m \x1b]8;;https://x\x07link\x1b]8;;\x07\r\n10%\r50%\r100%\n\n',
      ),
      'red link\n100%',
    );
    expect(context.cleanOutput('\u009b31mred\u009b0m'), 'red');
  });
  test('only news endings are noted with original precedence', () {
    expect(context.endNote(done()), isNull);
    expect(
      context.endNote(
        const ShellRun(command: 'x', running: true, error: 'ignored'),
      ),
      isNull,
    );
    expect(context.endNote(done(code: 2)), 'Exit code 2');
    expect(context.endNote(done(stopped: true)), 'Stopped by the user');
    expect(
      context.endNote(done(error: 'no shell', stopped: true)),
      'Error: no shell',
    );
  });
  test('held envelopes round trip in order before literal prompt', () {
    final runs = [
      done(stdout: 'a\nb'),
      done(command: 'false', stderr: 'bad', code: 1),
      done(command: 'sleep', code: null, stopped: true),
      done(command: 'big', stdout: 'x', truncated: true),
      done(command: 'missing', code: null, error: 'no shell'),
    ];
    final sent = context.withContext(
      context.shellContext(runs),
      'what failed?',
    );
    expect(
      sent,
      startsWith(
        '<bash-input>ls</bash-input>\n<bash-stdout>a\nb</bash-stdout><bash-stderr></bash-stderr>\n',
      ),
    );
    final split = context.splitContext(sent);
    expect(split.text, 'what failed?');
    expect(split.runs.map((r) => r.command), runs.map((r) => r.command));
    expect(context.shellContext(split.runs), context.shellContext(runs));
    expect(context.withContext('', 'hi'), 'hi');
    expect(context.splitContext('plain').text, 'plain');
    expect(context.splitContext('plain').runs, isEmpty);
    expect(() => split.runs.add(done()), throwsUnsupportedError);
  });
}
