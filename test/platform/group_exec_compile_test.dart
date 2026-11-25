@Tags(['compile'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:chord/platform/group_exec.dart';
import 'package:test/test.dart';

// Compiled, chord is its own launcher: spawnGroup re-executes the binary,
// whose first statement takes the flag. This builds chord and the group
// fixture, and runs them from `/` with an empty HOME, so no source is in
// reach.
void main() {
  late Directory dir;
  late String chord;
  late String child;

  String source(String path) => Isolate.resolvePackageUriSync(
    Uri.parse('package:chord/platform/group_exec.dart'),
  )!.resolve('../../$path').toFilePath();

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('chord-aot-');
    Directory('${dir.path}/home').createSync();
    chord = '${dir.path}/chord';
    child = '${dir.path}/group_child';
    for (final (script, exe) in [
      (source('bin/chord.dart'), chord),
      (source('test/fixtures/group_child.dart'), child),
    ]) {
      final build = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        script,
        '-o',
        exe,
      ]);
      expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    }
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<ProcessResult> run(String exe, List<String> args) => Process.run(
    exe,
    args,
    workingDirectory: '/',
    environment: {
      'HOME': '${dir.path}/home',
      'PATH': Platform.environment['PATH']!,
    },
    includeParentEnvironment: false,
  ).timeout(const Duration(seconds: 30));

  test('a compiled program\'s child leads its own group', () async {
    final result = await run(child, []);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final [pid, pgid] = (result.stdout as String).trim().split(RegExp(r'\s+'));
    expect(pgid, pid);
  });

  test('its exit code is the child\'s own', () async {
    final result = await run(child, ['sh', '-c', 'exit 7']);
    expect(result.exitCode, 7, reason: '${result.stderr}');
  });

  test('a missing program does not start', () async {
    final result = await run(child, ['chord-no-such-agent']);
    expect(result.exitCode, 2);
    expect(result.stderr, startsWith('cannot start chord-no-such-agent: '));
  });

  test('chord\'s binary takes the flag first: a malformed call exits 126 '
      'with one line', () async {
    final result = await run(chord, [groupExecFlag, 'nonce', 'relative']);
    expect(result.exitCode, 126);
    expect(result.stdout, isEmpty);
    expect(result.stderr, 'chord: malformed $groupExecFlag call\n');
  });

  test('chord\'s binary as the launcher: own group, the frame, the exit '
      'code', () async {
    final result = await run(chord, [
      groupExecFlag,
      'ab12',
      '/bin/sh',
      '--',
      'sh',
      '-c',
      r'echo "$$ $(ps -o pgid= -p $$)"; exit 5',
    ]);
    expect(result.exitCode, 5);
    expect(result.stderr, 'chord-exec ab12 ok\n');
    final [pid, pgid] = (result.stdout as String).trim().split(RegExp(r'\s+'));
    expect(pgid, pid);
  });

  group('tester: compiled launcher boundaries', () {
    test('exec failure emits both frames and keeps the ENOENT exit', () async {
      final result = await run(chord, [
        groupExecFlag,
        'ab12',
        '/chord-no-such-agent',
        '--',
        'agent',
      ]);
      expect(result.exitCode, 127);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'chord-exec ab12 ok\nchord-exec ab12 fail exec 2\n',
      );
    });

    test(
      'compiled reexec preserves empty, Unicode and shell-looking arguments',
      () async {
        final words = ['', '界👩‍💻e\u0301', r'$NAME;*#', 'a\nb', '--'];
        final result = await run(child, [
          '/bin/sh',
          '-c',
          r'''printf '%s\000' "$@"''',
          '-dash',
          ...words,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stderr, isEmpty);
        expect(result.stdout, '${words.join('\u0000')}\u0000');
      },
    );

    test('the compiled launcher restores SIGPIPE before exec', () async {
      final result = await run(chord, [
        groupExecFlag,
        'ab12',
        '/bin/sh',
        '--',
        'sh',
        '-c',
        r'kill -PIPE $$; echo survived',
      ]);
      expect(
        result.exitCode,
        -ProcessSignal.sigpipe.signalNumber,
        reason: '${result.stderr}',
      );
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'chord-exec ab12 ok\n');
    });
  });
}
