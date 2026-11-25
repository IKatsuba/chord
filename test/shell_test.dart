import 'dart:async';
import 'dart:io';

import 'package:chord/shell.dart';
import 'package:test/test.dart';

void main() {
  test(
    'command uses given cwd and drains both streams before ending',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-shell-');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/marker.txt').writeAsString('');
      final out = {ShellStream.stdout: '', ShellStream.stderr: ''};
      final run = runShell(
        'ls; echo oops >&2; exit 3',
        ShellOptions(
          cwd: dir.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (stream, text) => out[stream] = out[stream]! + text,
        ),
      );
      addTearDown(run.stop);
      final end = await run.ended.timeout(const Duration(seconds: 5));
      expect(end.code, 3);
      expect(end.error, isNull);
      expect(out, {
        ShellStream.stdout: 'marker.txt\n',
        ShellStream.stderr: 'oops\n',
      });
    },
  );

  test('stop is idempotent and closes a descendant holding output', () async {
    final output = StringBuffer(), ready = Completer<void>();
    final run = runShell(
      'echo before; sleep 30; echo after',
      ShellOptions(
        cwd: Directory.current.path,
        shell: ['/bin/sh', '-c'],
        onOutput: (_, text) {
          output.write(text);
          if (!ready.isCompleted) ready.complete();
        },
      ),
    );
    addTearDown(run.stop);
    await ready.future.timeout(const Duration(seconds: 5));
    run.stop();
    run.stop();
    final end = await run.ended.timeout(const Duration(seconds: 10));
    expect(end.stopped, isTrue);
    expect(output.toString(), 'before\n');
    expect(end.code, isNull);
    expect(end.error, isNull);
  });

  test(
    'stop waits for TERM-ignoring descendant after shell and pipes end',
    () async {
      final ready = Completer<int>();
      final out = StringBuffer();
      final run = runShell(
        r"(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & echo $!; wait",
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (_, text) {
            out.write(text);
            if (!ready.isCompleted && out.toString().contains('\n')) {
              ready.complete(int.parse(out.toString().trim()));
            }
          },
        ),
      );
      addTearDown(run.stop);
      final pid = await ready.future.timeout(const Duration(seconds: 5));
      addTearDown(() {
        Process.killPid(pid, ProcessSignal.sigkill);
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      run.stop();
      final end = await run.ended.timeout(const Duration(seconds: 10));
      expect(end.stopped, isTrue);
      expect(
        Process.killPid(pid, ProcessSignal.sigcont),
        isFalse,
        reason: 'descendant outlived command cleanup',
      );
    },
  );

  test(
    'stopped output callback failure still kills and reaps detached child',
    () async {
      late final ShellProcess run;
      int? pid;
      addTearDown(() {
        if (pid != null) Process.killPid(pid!, ProcessSignal.sigkill);
      });
      run = runShell(
        r"(trap '' TERM; exec sleep 30) >/dev/null 2>&1 & pid=$!; sleep 0.15; echo $pid; wait",
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onOutput: (_, text) {
            pid = int.parse(text.trim());
            run.stop();
            throw StateError('output failed after stop');
          },
        ),
      );
      addTearDown(run.stop);
      final end = await run.ended.timeout(const Duration(seconds: 10));
      expect(end.stopped, isTrue);
      expect(pid, isNotNull);
      expect(
        Process.killPid(pid!, ProcessSignal.sigcont),
        isFalse,
        reason: 'callback failure cancelled group cleanup',
      );
    },
  );

  test(
    'stop before asynchronous spawn completes still stops its group',
    () async {
      final run = runShell(
        'sleep 30',
        ShellOptions(cwd: Directory.current.path, shell: ['/bin/sh', '-c']),
      );
      run.stop();
      expect(
        (await run.ended.timeout(const Duration(seconds: 10))).stopped,
        isTrue,
      );
    },
  );

  test(
    'missing shell settles both futures with error rather than rejection',
    () async {
      final run = runShell(
        'true',
        ShellOptions(cwd: Directory.current.path, shell: ['./missing-shell']),
      );
      final end = await run.ended;
      expect(end.error, isNotEmpty);
      expect((await run.exited).error, end.error);
    },
  );

  test('signal exit keeps its shell code and signal name', () async {
    final run = runShell(
      r'kill -TERM $$',
      ShellOptions(cwd: Directory.current.path, shell: ['/bin/sh', '-c']),
    );
    final end = await run.ended.timeout(const Duration(seconds: 5));
    expect(end.code, 143);
    expect(end.signal, 'SIGTERM');
    expect(end.stopped, isFalse);
  });

  test('UTF8 output split across reads is decoded as one character', () async {
    final output = StringBuffer();
    final run = runShell(
      r"printf '\342'; sleep 0.03; printf '\202\254'",
      ShellOptions(
        cwd: Directory.current.path,
        shell: ['/bin/sh', '-c'],
        onOutput: (_, text) => output.write(text),
      ),
    );
    expect((await run.ended.timeout(const Duration(seconds: 5))).code, 0);
    expect(output.toString(), '€');
  });

  group("a monitor's lines", () {
    Future<(ShellEnd, List<String>)> lines(String script) async {
      final seen = <String>[];
      final run = runShell(
        script,
        ShellOptions(
          cwd: Directory.current.path,
          shell: ['/bin/sh', '-c'],
          onLine: seen.add,
          reap: true,
        ),
      );
      addTearDown(run.stop);
      return (await run.ended.timeout(const Duration(seconds: 5)), seen);
    }

    test('stdout splits on LF or CRLF, a lone CR kept, the unended last '
        'handed on, stderr dropped', () async {
      final (end, seen) = await lines(
        r"printf 'a\r\nb\n\nc\rd\n'; echo err >&2; sleep 0.03; printf 'e'",
      );
      expect(end.code, 0);
      expect(seen, ['a', 'b', '', 'c\rd', 'e']);
    });

    test('a line split across reads is one line', () async {
      final (_, seen) = await lines(r"printf 'he'; sleep 0.03; printf 'y\n'");
      expect(seen, ['hey']);
    });

    test("a reaped command ends with its shell's code, what it left in the "
        'background gone with it', () async {
      final (end, seen) = await lines(r'sleep 30 & echo $!; exit 5');
      expect(end.code, 5);
      final pid = int.parse(seen.single);
      expect(Process.killPid(pid, ProcessSignal.sigcont), isFalse);
    });
  });

  test(
    'a shell that does not start says so before it ends, why in its end',
    () async {
      final run = runShell(
        'true',
        ShellOptions(cwd: Directory.current.path, shell: ['/nonexistent/sh']),
      );
      expect(await run.failed, '/nonexistent/sh did not start');
      final end = await run.ended;
      expect(end.error, contains('cannot start /nonexistent/sh'));
      expect(
        await runShell(
          'true',
          ShellOptions(cwd: Directory.current.path, shell: ['/bin/sh', '-c']),
        ).failed,
        isNull,
      );
    },
  );
}
