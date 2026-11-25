// The launcher is an interface between chord versions: a running chord
// starts its agents through Platform.resolvedExecutable, which after an
// upgrade is the newer binary (CTUI-150). Everything here is written out
// literally, never through the sources' constants, so a change to the flag,
// the argv shape, the nonce, the frames or the exit codes fails here.
import 'dart:io';
import 'dart:isolate';

import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/process.dart';
import 'package:test/test.dart';

const _flag = '--chord-group-exec';

void main() {
  final packages = Isolate.packageConfigSync!.toFilePath();
  final entry = File('bin/chord.dart').absolute.path;

  test('the flag and the argv a parent sends', () {
    expect(groupExecFlag, _flag);
    final argv = defaultLauncher('0a1b2c3d', '/usr/bin/env');
    // `<chord> [JIT: --packages=… group_exec.dart] <flag> <nonce> <path> --`,
    // the agent's argv0 and arguments after it.
    expect(argv.first, Platform.resolvedExecutable);
    expect(argv.sublist(argv.length - 4), [
      _flag,
      '0a1b2c3d',
      '/usr/bin/env',
      '--',
    ]);
    expect(
      argv,
      hasLength(const bool.fromEnvironment('dart.vm.product') ? 5 : 7),
    );
  });

  test("the parent's nonce is lower-case hex of at most 32 bits", () async {
    // What spawnGroup sends: Random.secure().nextInt(1 << 32) in radix 16.
    final seen = <String>[];
    for (var i = 0; i < 20; i++) {
      final group = await spawnGroup(
        '/bin/sh',
        ['-c', 'exit 0'],
        cwd: Directory.systemTemp.path,
        launcher: (nonce, path) {
          seen.add(nonce);
          return defaultLauncher(nonce, path);
        },
      );
      group.stdout.drain<void>().ignore();
      group.stderr.drain<void>().ignore();
      await group.exit.timeout(const Duration(seconds: 30));
    }
    for (final nonce in seen) {
      expect(nonce, matches(RegExp(r'^[0-9a-f]{1,8}$')));
    }
    // Twenty launches, each compiling group_exec.dart on the JIT: about
    // 0.5 s each on macOS, 1.1 s in an emulated Linux container, and the
    // case near 30 s there under load.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test("the parent reads the launcher's frames as written", () {
    final ok = GroupHandshake('c0ffee');
    expect(ok.add('chord-exec c0ffee ok\nmine'.codeUnits), 'mine'.codeUnits);
    expect(ok.state, HandshakeState.started);
    final exec = GroupHandshake('c0ffee')
      ..add('chord-exec c0ffee ok\n'.codeUnits)
      ..add('chord-exec c0ffee fail exec 2\n'.codeUnits);
    expect(exec.execErrno, 2);
    final setsid = GroupHandshake('c0ffee')
      ..add('chord-exec c0ffee fail setsid 1\n'.codeUnits);
    expect(setsid.state, HandshakeState.failed);
    expect(setsid.failure, startsWith('setsid: '));
  });

  // chord's own entry point takes the flag first, before anything of chord
  // runs: the compiled binary is this file. Run here on the JIT.
  Future<ProcessResult> chord(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['--packages=$packages', entry, ...args],
  ).timeout(const Duration(minutes: 2));

  // Each call compiles bin/chord.dart from source on the JIT: about 7 s
  // idle and 15 s on a loaded Linux container, so a case with two calls
  // passes package:test's default 30 s. A case covers its calls' own
  // bound, two minutes each.
  const entryTimeout = Timeout(Duration(minutes: 5));

  test(
    "chord's entry point: ok frame, the program's argv, its exit code",
    () async {
      final result = await chord([
        _flag,
        'ab12',
        '/bin/sh',
        '--',
        'agent',
        '-c',
        r'echo "$0 $1"; exit 7',
        'zero',
        'one',
      ]);
      expect(result.stderr, 'chord-exec ab12 ok\n');
      expect(result.stdout, 'zero one\n');
      expect(result.exitCode, 7);
    },
    timeout: entryTimeout,
  );

  test(
    "chord's entry point: a missing program, then a malformed call",
    () async {
      final missing = await chord([
        _flag,
        'ab12',
        '/nonexistent/agent',
        '--',
        'agent',
      ]);
      expect(
        missing.stderr,
        'chord-exec ab12 ok\nchord-exec ab12 fail exec 2\n',
      );
      expect(missing.exitCode, 127);
      final malformed = await chord([_flag, 'ab12', '/bin/sh', '--']);
      expect(malformed.stderr, 'chord: malformed --chord-group-exec call\n');
      expect(malformed.exitCode, 126);
    },
    timeout: entryTimeout,
  );
}
