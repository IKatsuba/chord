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

  group('a failed exec, from the files where they show it', () {
    // A tree of paths: each is a directory (searchable or not), a file, or
    // a link that does not resolve; any other path is not there.
    ({int code, int errno}) failure(
      String path,
      Map<String, String> tree, {
      int read = 99,
      Set<String> runnable = const {},
      Map<String, String> lines = const {},
    }) => execFailure(
      path,
      read: read,
      kind: (path, {required followLinks}) => switch (tree[path]) {
        'dir' || 'locked' => FileSystemEntityType.directory,
        'file' => FileSystemEntityType.file,
        'loop' when !followLinks => FileSystemEntityType.link,
        _ => FileSystemEntityType.notFound,
      },
      searchable: (dir) => tree[dir] == 'dir',
      runnable: runnable.contains,
      firstLine: (path) => lines[path],
    );
    final root = {'/': 'dir', '/a': 'dir'};

    test('a program not there is 127 and ENOENT', () {
      expect(failure('/a/agent', root), (code: 127, errno: 2));
      expect(failure('/a/b/agent', root), (code: 127, errno: 2));
    });

    test('one under a directory that may not be searched is the errno '
        'read: the files cannot show it is not there', () {
      final tree = {...root, '/a/locked': 'locked'};
      expect(failure('/a/locked/agent', tree, read: 13), (
        code: 126,
        errno: 13,
      ));
      expect(failure('/a/locked/agent', tree, read: 2), (code: 127, errno: 2));
    });

    test('a link that does not resolve is the errno read', () {
      final tree = {...root, '/a/agent': 'loop'};
      expect(failure('/a/agent', tree, read: 40), (code: 126, errno: 40));
    });

    test('a directory, or a file without x, is 126 and EACCES', () {
      expect(failure('/a', root, read: 22), (code: 126, errno: 13));
      final tree = {...root, '/a/agent': 'file'};
      expect(failure('/a/agent', tree, read: 22), (code: 126, errno: 13));
    });

    test("a script's #! interpreter not there is 127 and ENOENT; one the "
        'files cannot show is the errno read', () {
      final tree = {...root, '/a/sh': 'file', '/a/locked': 'locked'};
      ({int code, int errno}) script(String line, int read) => failure(
        '/a/sh',
        tree,
        read: read,
        runnable: {'/a/sh'},
        lines: {'/a/sh': line},
      );
      expect(script('#!/nonexistent/interpreter', 99), (code: 127, errno: 2));
      expect(script('#!/a/locked/interp -e', 13), (code: 126, errno: 13));
      expect(script('#! /a/sh -e', 8), (code: 126, errno: 8));
    });
  });

  // Run as a user who cannot search the directory: root can.
  final unprivileged =
      Process.runSync('id', ['-u']).stdout.toString().trim() != '0';

  test('a program under a directory that may not be searched is not said to '
      'be missing', () async {
    final dir = Directory.systemTemp.createTempSync('chord-exec-locked-');
    final locked = Directory('${dir.path}/locked')..createSync();
    final agent = File('${locked.path}/agent')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', ['755', agent.path]);
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() {
      Process.runSync('chmod', ['755', locked.path]);
      dir.deleteSync(recursive: true);
    });
    final result = await launch([groupExecFlag, 'ab', agent.path, '--', 'a']);
    expect(result.exitCode, 126, reason: '${result.stderr}');
    expect(
      result.stderr,
      startsWith('chord-exec ab ok\nchord-exec ab fail exec '),
    );
    expect(result.stderr, isNot(endsWith(' fail exec 2\n')));
  }, skip: unprivileged ? false : 'root searches every directory');

  test("a script whose #! interpreter is under a directory that may not be "
      'searched is not said to be missing', () async {
    final dir = Directory.systemTemp.createTempSync('chord-exec-locked-');
    final locked = Directory('${dir.path}/locked')..createSync();
    File('${locked.path}/interp').writeAsStringSync('');
    final script = File('${dir.path}/agent')
      ..writeAsStringSync('#!${locked.path}/interp\n');
    Process.runSync('chmod', ['755', script.path]);
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() {
      Process.runSync('chmod', ['755', locked.path]);
      dir.deleteSync(recursive: true);
    });
    final result = await launch([groupExecFlag, 'ab', script.path, '--', 'a']);
    expect(result.exitCode, 126, reason: '${result.stderr}');
    expect(result.stderr, isNot(endsWith(' fail exec 2\n')));
  }, skip: unprivileged ? false : 'root searches every directory');

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
    // The case covers three launches, each with its own 30-second bound.
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
    }, timeout: const Timeout(Duration(minutes: 2)));

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
        ]).timeout(const Duration(minutes: 2));
        expect(result.exitCode, 126);
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'chord: malformed $groupExecFlag call\n');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
