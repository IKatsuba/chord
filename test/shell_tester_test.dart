import 'dart:async';
import 'dart:io';

import 'package:chord/shell.dart';
import 'package:test/test.dart';

void main() {
  group('tester: shell exit, output and stop ownership', () {
    test('shell exit precedes output-holding descendant cleanup', () async {
      final ready = Completer<int>();
      final output = StringBuffer();
      final run = runShell(
        r'sleep 30 & echo $!; exit 7',
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (_, text) {
            output.write(text);
            if (!ready.isCompleted && output.toString().contains('\n')) {
              ready.complete(int.parse(output.toString().trim()));
            }
          },
        ),
      );
      addTearDown(run.stop);
      final pid = await ready.future.timeout(const Duration(seconds: 5));
      addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));
      var ended = false;
      unawaited(run.ended.then((_) => ended = true));
      final exit = await run.exited.timeout(const Duration(seconds: 5));
      expect(exit.code, 7);
      expect(exit.stopped, isFalse);
      expect(ended, isFalse);
      run.stop();
      run.stop();
      final end = await run.ended.timeout(const Duration(seconds: 10));
      expect(end.stopped, isTrue);
      expect(Process.killPid(pid, ProcessSignal.sigcont), isFalse);
      expect(await run.exited, same(exit));
    });

    test('concurrent runs keep stop and stream results separate', () async {
      final ready = Completer<void>();
      final firstOutput = StringBuffer();
      final secondOutput = StringBuffer();
      final first = runShell(
        'echo first; sleep 30; echo forbidden',
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (_, text) {
            firstOutput.write(text);
            if (!ready.isCompleted) ready.complete();
          },
        ),
      );
      addTearDown(first.stop);
      final second = runShell(
        'echo second; echo separate >&2; exit 4',
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (stream, text) => secondOutput.write('$stream:$text'),
        ),
      );
      addTearDown(second.stop);
      await ready.future.timeout(const Duration(seconds: 5));
      first.stop();
      expect(
        (await first.ended.timeout(const Duration(seconds: 10))).stopped,
        isTrue,
      );
      final end = await second.ended.timeout(const Duration(seconds: 5));
      expect(end.code, 4);
      expect(end.stopped, isFalse);
      expect(firstOutput.toString(), 'first\n');
      expect(secondOutput.toString(), contains('ShellStream.stdout:second\n'));
      expect(
        secondOutput.toString(),
        contains('ShellStream.stderr:separate\n'),
      );
      second.stop();
      expect(await second.ended, same(end));
    });

    test('stdin is closed and malformed trailing UTF8 drains', () async {
      final output = StringBuffer();
      final run = runShell(
        r"if read line; then echo unexpected; else printf '\342'; fi",
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (_, text) => output.write(text),
        ),
      );
      addTearDown(run.stop);
      expect((await run.ended.timeout(const Duration(seconds: 5))).code, 0);
      expect(output.toString(), '�');
    });

    test('a pre-spawn stop with missing shell settles both futures', () async {
      final run = runShell(
        'true',
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['./missing-tester-shell'],
        ),
      );
      run.stop();
      run.stop();
      final end = await run.ended.timeout(const Duration(seconds: 5));
      expect(end.stopped, isTrue);
      expect(end.error, isNull);
      expect((await run.exited).stopped, isTrue);
    });

    test('shell arguments are frozen and empty shell is refused', () {
      final shell = ['/bin/sh', '-c'];
      final options = ShellOptions(cwd: '.', shell: shell);
      shell[0] = 'changed';
      expect(options.shell, ['/bin/sh', '-c']);
      expect(() => options.shell!.clear(), throwsUnsupportedError);
      expect(() => ShellOptions(cwd: '.', shell: []), throwsArgumentError);
    });
  });
}
