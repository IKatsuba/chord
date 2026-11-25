import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:chord/platform/group_exec.dart';
import 'package:test/test.dart';

void main() {
  final script = Isolate.resolvePackageUriSync(
    Uri.parse('package:chord/platform/group_exec.dart'),
  )!.toFilePath();
  final packages = Isolate.packageConfigSync!.toFilePath();

  Future<ProcessResult> launch(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['--packages=$packages', script, ...args],
  ).timeout(const Duration(seconds: 30));

  test('a malformed call prints one line and exits 126', () async {
    for (final args in [
      [groupExecFlag],
      [groupExecFlag, 'abc', '/bin/sh', '--'],
      [groupExecFlag, 'xyz', '/bin/sh', '--', 'sh'],
      [groupExecFlag, 'abc', 'sh', '--', 'sh'],
      [groupExecFlag, 'abc', '/bin/sh', 'sh', 'sh'],
    ]) {
      final result = await launch(args);
      expect(result.exitCode, 126, reason: '$args');
      expect(result.stdout, isEmpty, reason: '$args');
      expect(result.stderr, 'chord: malformed $groupExecFlag call\n');
    }
  });

  test('the program leads its own group, with argv as given, after the ok '
      'frame', () async {
    final result = await launch([
      groupExecFlag,
      'c0ffee',
      '/bin/sh',
      '--',
      'my-sh',
      '-c',
      r'echo "$$ $(ps -o pgid= -p $$) $(ps -o args= -p $$ | cut -c1-5) $0 $1"',
      '-dash-name',
      'one two',
    ]);
    expect(result.exitCode, 0);
    expect(result.stderr, 'chord-exec c0ffee ok\n');
    final words = (result.stdout as String).trim().split(RegExp(r'\s+'));
    final pid = words.first;
    expect(words[1], pid, reason: 'the pgid is its own pid');
    expect(words.sublist(2), ['my-sh', '-dash-name', 'one', 'two']);
  });

  test('the exit code is the program\'s own', () async {
    final result = await launch([
      groupExecFlag,
      'ab',
      '/bin/sh',
      '--',
      'sh',
      '-c',
      'exit 7',
    ]);
    expect(result.exitCode, 7);
  });

  test('a program that is not there writes the exec frame and exits '
      '127', () async {
    final result = await launch([
      groupExecFlag,
      'ab',
      '/nonexistent/agent',
      '--',
      'agent',
    ]);
    expect(result.exitCode, 127);
    expect(LineSplitter.split(result.stderr as String).toList(), [
      'chord-exec ab ok',
      'chord-exec ab fail exec 2',
    ]);
  });

  test('SIGPIPE is back to its default in the program', () async {
    final result = await launch([
      groupExecFlag,
      'ab',
      '/bin/sh',
      '--',
      'sh',
      '-c',
      'yes | head -n1',
    ]);
    expect(result.exitCode, 0);
    expect(result.stdout, 'y\n');
    expect(result.stderr, 'chord-exec ab ok\n');
  });

  group('tester: launcher boundaries', () {
    test('empty input, wrong flag and empty nonce are rejected', () async {
      for (final args in <List<String>>[
        [],
        ['wrong-flag', 'ab', '/bin/sh', '--', 'sh'],
        [groupExecFlag, '', '/bin/sh', '--', 'sh'],
      ]) {
        final result = await launch(args);
        expect(result.exitCode, 126, reason: '$args');
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'chord: malformed $groupExecFlag call\n');
      }
    });

    test('arguments retain empty strings, Unicode and shell syntax', () async {
      final words = ['', 'one two', '界👩‍💻e\u0301', r'$HOME;*#', 'a\nb', '--'];
      final result = await launch([
        groupExecFlag,
        'ab',
        '/bin/sh',
        '--',
        '-dash',
        '-c',
        r'''printf '%s\000' "$@"''',
        '-dash',
        ...words,
      ]);
      expect(result.exitCode, 0);
      expect(result.stderr, 'chord-exec ab ok\n');
      expect(result.stdout, '${words.join('\u0000')}\u0000');
    });

    test('an exec permission failure follows ok and exits 126', () async {
      final result = await launch([
        groupExecFlag,
        'ab',
        '/bin',
        '--',
        'directory',
      ]);
      expect(result.exitCode, 126);
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'chord-exec ab ok\nchord-exec ab fail exec 13\n');
    });

    test('the replaced process terminates on SIGPIPE', () async {
      final result = await launch([
        groupExecFlag,
        'ab',
        '/bin/sh',
        '--',
        'sh',
        '-c',
        r'kill -PIPE $$; echo survived',
      ]);
      expect(
        result.exitCode,
        -ProcessSignal.sigpipe.signalNumber,
        reason: 'stdout: ${result.stdout} stderr: ${result.stderr}',
      );
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'chord-exec ab ok\n');
    });

    test(
      'the chord entrypoint consumes malformed launcher calls first',
      () async {
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=$packages',
          File('bin/chord.dart').absolute.path,
          groupExecFlag,
        ]).timeout(const Duration(seconds: 30));
        expect(result.exitCode, 126);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'chord: malformed $groupExecFlag call\n');
      },
    );
  });
}
