import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:test/test.dart';

import '../../tool/npm.dart';
import '../../tool/release/build.dart';
import '../../tool/release/runner.dart';
import '../../tool/targets.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

final node = whichSync('node');

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('npm_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('the layout', () {
    late ProcessReleaseRunner runner;
    setUp(() {
      runner = ProcessReleaseRunner(root: root.path, env: Platform.environment);
      for (final target in targets) {
        (File(p.join(root.path, binaryOf(target)))..createSync(recursive: true))
            .writeAsStringSync('binary of $target\n');
      }
      File(p.join(root.path, 'LICENSE')).writeAsStringSync('MIT\n');
      (File(
        p.join(root.path, 'README.md'),
      )..createSync(recursive: true)).writeAsStringSync('# chord\n');
    });

    String read(String path) =>
        File(p.join(root.path, npmFolder, path)).readAsStringSync();
    String mode(String path) =>
        (FileStat.statSync(p.join(root.path, npmFolder, path)).modeString());

    test('has a package per target and the main one', () async {
      await layOutNpm(runner, root.path, version: '1.2.3', notices: 'N\n');
      expect(
        Directory(
          p.join(root.path, npmFolder),
        ).listSync().map((e) => p.basename(e.path)).toList()..sort(),
        [
          'chord',
          'chord-darwin-arm64',
          'chord-darwin-x64',
          'chord-linux-arm64',
          'chord-linux-x64',
        ],
      );
      for (final target in targets) {
        final dir = 'chord-${target.name}';
        expect(read('$dir/bin/chord'), 'binary of $target\n');
        expect(mode('$dir/bin/chord'), 'rwxr-xr-x');
        expect(read('$dir/LICENSE'), 'MIT\n');
        expect(read('$dir/NOTICES'), 'N\n');
        expect(
          read('$dir/package.json'),
          manifestText(platformManifest(target, '1.2.3')),
        );
      }
      expect(read('chord/bin/chord.js'), shim);
      expect(mode('chord/bin/chord.js'), 'rwxr-xr-x');
      expect(read('chord/README.md'), '# chord\n');
      expect(read('chord/LICENSE'), 'MIT\n');
      expect(read('chord/package.json'), manifestText(mainManifest('1.2.3')));
    });

    test('stops on a missing binary before writing anything', () async {
      File(p.join(root.path, binaryOf(targets[2]))).deleteSync();
      await expectLater(
        layOutNpm(runner, root.path, version: '1.2.3', notices: 'N'),
        dies('Missing binaries; build them first:\n'),
      );
      expect(Directory(p.join(root.path, npmFolder)).existsSync(), isFalse);
    });

    test('stops without LICENSE', () async {
      File(p.join(root.path, 'LICENSE')).deleteSync();
      await expectLater(
        layOutNpm(runner, root.path, version: '1.2.3', notices: 'N'),
        dies('LICENSE is missing: every package carries the licence'),
      );
    });

    test('stops with an empty LICENSE before writing anything', () async {
      File(p.join(root.path, 'LICENSE')).writeAsStringSync('\n');
      await expectLater(
        layOutNpm(runner, root.path, version: '1.2.3', notices: 'N'),
        dies('LICENSE is empty: every package carries the licence'),
      );
      expect(Directory(p.join(root.path, npmFolder)).existsSync(), isFalse);
    });

    test('stops with empty NOTICES before writing anything', () async {
      await expectLater(
        layOutNpm(runner, root.path, version: '1.2.3', notices: ' \n'),
        dies('NOTICES is empty: every platform package carries the notices'),
      );
      expect(Directory(p.join(root.path, npmFolder)).existsSync(), isFalse);
    });
  });

  group('the manifests', () {
    test("a platform package names its os and cpu, as the original's", () {
      expect(platformManifest(targets[1], '1.2.3'), {
        'name': '@chorded/chord-darwin-x64',
        'version': '1.2.3',
        'license': 'MIT',
        'repository': {
          'type': 'git',
          'url': 'git+https://github.com/IKatsuba/chord.git',
        },
        'homepage': 'https://github.com/IKatsuba/chord#readme',
        'bugs': {'url': 'https://github.com/IKatsuba/chord/issues'},
        'description': 'The chord binary for darwin-x64.',
        'os': ['darwin'],
        'cpu': ['x64'],
        'files': ['bin/', 'NOTICES'],
      });
    });

    test('the main package depends on every target at its exact version', () {
      final main = mainManifest('1.0.0-next.2');
      expect(main['name'], '@chorded/chord');
      expect(main['bin'], {'chord': 'bin/chord.js'});
      expect(main['optionalDependencies'], {
        '@chorded/chord-darwin-arm64': '1.0.0-next.2',
        '@chorded/chord-darwin-x64': '1.0.0-next.2',
        '@chorded/chord-linux-x64': '1.0.0-next.2',
        '@chorded/chord-linux-arm64': '1.0.0-next.2',
      });
    });

    test('are written with two spaces and a final newline', () {
      expect(manifestText({'a': 1}), '{\n  "a": 1\n}\n');
    });
  });

  group('the shim on node', () {
    late String shimPath;
    late String binary;

    setUp(() {
      final modules = p.join(root.path, 'node_modules', '@chorded');
      shimPath = p.join(modules, 'chord', 'bin', 'chord.js');
      (File(shimPath)..createSync(recursive: true)).writeAsStringSync(shim);
      final platform = switch (Platform.operatingSystem) {
        'macos' => 'darwin',
        final os => os,
      };
      final arch = Platform.version.contains('arm64') ? 'arm64' : 'x64';
      binary = p.join(modules, 'chord-$platform-$arch', 'bin', 'chord');
      File(binary)
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''#!/bin/sh
case "$1" in
  args) printf '%s|' "$@"; exit 3 ;;
  hup) kill -HUP $$ ;;
  wait|silent)
    trap 'echo "got TERM"; exit 7' TERM
    echo $$ > "$2"
    [ "$1" = wait ] && echo ready
    while :; do sleep 0.05; done ;;
esac
''');
      Process.runSync('chmod', ['755', binary]);
    });

    test('passes the arguments and leaves with the status', () async {
      final ran = await Process.run(node!, [shimPath, 'args', 'a b', '-c']);
      expect((ran.exitCode, ran.stdout), (3, 'args|a b|-c|'));
    });

    test("re-raises the binary's SIGHUP", () async {
      final ran = await Process.run(node!, [shimPath, 'hup']);
      expect(ran.exitCode, -ProcessSignal.sighup.signalNumber);
    });

    /// Starts [script] on node with the waiting binary, sends SIGTERM to node
    /// once the binary is ready, and answers node's exit code, what it
    /// printed, and the binary's PID. Every wait is bounded, and node and
    /// the binary are both killed and reaped before it returns, whatever
    /// happened.
    Future<({int? code, String out, int? child})> terminate(
      String script, {
      String mode = 'wait',
      Duration limit = const Duration(seconds: 10),
    }) async {
      final pidFile = p.join(root.path, 'child.pid');
      final process = await Process.start(node!, [script, mode, pidFile]);
      final said = StringBuffer();
      final ready = Completer<void>();
      final drained = process.stdout.transform(utf8.decoder).listen((chunk) {
        said.write(chunk);
        if (said.toString().contains('ready') && !ready.isCompleted) {
          ready.complete();
        }
      }).asFuture<void>();
      int? child;
      int? code;
      try {
        await ready.future.timeout(limit);
        child = int.parse(File(pidFile).readAsStringSync().trim());
        process.kill(ProcessSignal.sigterm);
        code = await process.exitCode.timeout(limit);
      } on TimeoutException {
        // The assertions say what did not happen.
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(limit, onTimeout: () => 0);
        // Read again here: the binary may have started without saying so.
        child ??= await _pidIn(pidFile, const Duration(seconds: 2));
        if (child != null && _alive(child)) {
          Process.killPid(child, ProcessSignal.sigkill);
          await _gone(child, limit);
        }
        // The binary shares node's stdout; it ends once both are gone.
        await drained.timeout(limit, onTimeout: () {});
      }
      return (code: code, out: said.toString(), child: child);
    }

    test('forwards SIGTERM to the binary', () async {
      final ran = await terminate(shimPath);
      expect(ran.code, 7);
      expect(ran.out, contains('got TERM'));
      expect(_alive(ran.child!), isFalse);
    });

    test('a shim that does not forward leaves no binary behind', () async {
      // The negative control: without forwarding, node dies by SIGTERM and
      // the binary would keep running; the cleanup still reaps it.
      final broken = p.join(p.dirname(shimPath), 'broken.js');
      final text = shim.replaceFirst(
        'process.on(signal, () => child.kill(signal));',
        '',
      );
      expect(text, isNot(shim));
      File(broken).writeAsStringSync(text);
      final ran = await terminate(broken);
      expect(ran.code, -ProcessSignal.sigterm.signalNumber);
      expect(ran.out, isNot(contains('got TERM')));
      expect(ran.child, isNotNull);
      expect(_alive(ran.child!), isFalse);
    });

    test('a binary that never says it is ready is still reaped', () async {
      // The other negative control: readiness never comes, so no SIGTERM is
      // sent; the binary's PID is read in the cleanup all the same.
      final ran = await terminate(
        shimPath,
        mode: 'silent',
        limit: const Duration(seconds: 2),
      );
      expect(ran.code, isNull);
      expect(ran.out, isNot(contains('ready')));
      expect(ran.child, isNotNull);
      expect(_alive(ran.child!), isFalse);
    });

    test('says so when no platform package is installed', () async {
      File(binary).deleteSync();
      final ran = await Process.run(node!, [shimPath]);
      expect(ran.exitCode, 1);
      expect(
        ran.stderr,
        matches(
          RegExp(
            r'^chord: no @chorded/chord-\w+-\w+ is installed\. chord runs on '
            r'macOS and Linux, arm64 and x64; reinstall @chorded/chord on one '
            r'of those, with optional dependencies\.\n$',
          ),
        ),
      );
    });

    group('tester: shim launch and argument boundaries', () {
      Future<({int code, String out, String err})> runNode(
        List<String> args,
      ) async {
        final process = await Process.start(node!, [shimPath, ...args]);
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        try {
          final code = await process.exitCode.timeout(
            const Duration(seconds: 10),
          );
          return (code: code, out: await out, err: await err);
        } finally {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          await out;
          await err;
        }
      }

      test(
        'empty, Unicode and escape-containing arguments stay separate',
        () async {
          final ran = await runNode([
            'args',
            '',
            '界 😀 e\u0301',
            '\u001b[31m',
            '--',
          ]);
          expect(ran.code, 3);
          expect(ran.out, 'args||界 😀 e\u0301|\u001b[31m|--|');
          expect(ran.err, isEmpty);
        },
      );

      test(
        'a resolved binary that cannot execute reports a launch error',
        () async {
          final mode = await Process.run('chmod', ['644', binary]);
          expect(mode.exitCode, 0);
          final ran = await runNode([]);
          expect(ran.code, 1);
          expect(ran.err, contains('did not start:'));
          expect(ran.err, contains('EACCES'));
        },
      );

      test('a child that ends by SIGINT is re-raised by the shim', () async {
        File(binary).writeAsStringSync('#!/bin/sh\nkill -INT \$\$\n');
        final ran = await runNode([]);
        expect(ran.code, -ProcessSignal.sigint.signalNumber);
      });
    });
  }, skip: node == null ? 'node is not on PATH' : false);
}

/// Whether a process [pid] still exists, as `kill -0` answers.
bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// Waits up to [limit] for [pid] to be gone.
Future<void> _gone(int pid, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (_alive(pid) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The PID written in [path], waiting up to [limit] for it; null if none.
Future<int?> _pidIn(String path, Duration limit) async {
  final deadline = DateTime.now().add(limit);
  while (true) {
    final file = File(path);
    final text = file.existsSync() ? file.readAsStringSync().trim() : '';
    if (int.tryParse(text) case final pid?) return pid;
    if (DateTime.now().isAfter(deadline)) return null;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
