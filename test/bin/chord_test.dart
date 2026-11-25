import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/version.dart';
import 'package:test/test.dart';

import '../fixtures/fake.dart';

void main() {
  group('tester: entrypoint output and exit codes', () {
    late Directory emptyPath;
    late List<String> chord;

    // The runner assigns setUpAll its fixed 12-minute scaffold timeout;
    // compilation stays outside each case's runtime bound.
    setUpAll(() {
      emptyPath = Directory.systemTemp.createTempSync('chord-bin-path-');
      chord = fixtureCommand('bin/chord.dart');
    });
    tearDownAll(() => emptyPath.deleteSync());

    Future<ProcessResult> invoke(List<String> args) async {
      final process = await Process.start(
        chord.first,
        [...chord.skip(1), ...args],
        workingDirectory: '.',
        environment: {'PATH': emptyPath.path},
      );
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      final int code;
      try {
        code = await process.exitCode.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        rethrow;
      }
      return ProcessResult(process.pid, code, await out, await err);
    }

    test(
      'both version forms flush exactly one line from the real entrypoint',
      () async {
        for (final entry in {
          '--version': 'chord $version',
          '-V': version,
        }.entries) {
          final result = await invoke([entry.key]);
          expect(result.exitCode, 0);
          expect(result.stdout, '${entry.value}\n');
          expect(result.stderr, isEmpty);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('help and agents help print without entering terminal mode', () async {
      for (final args in [
        ['--help'],
        ['agents', '--help'],
      ]) {
        final result = await invoke(args);
        expect(result.exitCode, 0);
        expect(result.stdout, startsWith('Usage: chord'));
        expect(result.stdout, isNot(contains('\x1b')));
        expect(result.stderr, isEmpty);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'piped agents output flushes the complete unwrapped catalog',
      () async {
        final result = await invoke(['agents']);
        expect(result.exitCode, 0);
        expect(result.stderr, isEmpty);
        final rows = (result.stdout as String).trimRight().split('\n');
        expect(rows, hasLength(listAgents().length));
        expect(
          [for (final row in rows) row.split(' ').first],
          [for (final agent in listAgents()) agent.name],
        );
        expect(result.stdout, contains('own CLI · not on PATH'));
        expect(result.stdout, isNot(contains('own CLI · found')));
        expect(result.stdout, isNot(contains('\x1b')));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('default startup with no runner exits one without a window', () async {
      final result = await invoke([]);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'chord: claude runs "npx", which is not on PATH; '
        'npx comes with Node.js: https://nodejs.org/en/download\n',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'unknown agents keep help on stdout and the refusal on stderr',
      () async {
        final result = await invoke(['tester-unknown']);
        expect(result.exitCode, 2);
        expect(result.stdout, startsWith('Usage: chord [agent]\n'));
        expect(
          result.stderr,
          '\n  error: Unknown agent "tester-unknown". '
          '`chord agents` lists them.\n\n',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'missing own CLI exits one with its executable and install URL',
      () async {
        final result = await invoke(['cursor']);
        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          'chord: cursor runs "agent", which is not on PATH; '
          'install it from https://cursor.com/docs/cli/installation\n',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
