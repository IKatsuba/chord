// `chord upgrade` through runCli: its help and usage errors, which open no
// registry client, and each row of the design's truth table with a fake
// version source and a recording runner.
import 'package:chord/cli.dart';
import 'package:chord/upgrade.dart';
import 'package:chord/version.dart';
import 'package:pub_semver/pub_semver.dart' show Version;
import 'package:test/test.dart';

import 'upgrade_test.dart' show FakeSource, RecordingRunner;

const _npmPath =
    '/usr/lib/node_modules/@chorded/chord/node_modules/@chorded/'
    'chord-linux-x64/bin/chord';

/// A call, with what it printed and what it read and ran.
class Upgraded {
  Upgraded(this.code, this.stdout, this.stderr, this.source, this.runner);

  final int code;
  final String stdout;
  final String stderr;
  final FakeSource? source;
  final RecordingRunner runner;
}

/// Runs chord with [args]; without [versions] nothing may open a source,
/// run a command or resolve the executable.
Future<Upgraded> chord(
  List<String> args, {
  Object? versions,
  RunFailure? fail,
  String path = _npmPath,
  bool official = false,
}) async {
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final runner = RecordingRunner(fail);
  FakeSource? source;
  final outcome = await runCli(
    args,
    stdout: stdout,
    stderr: stderr,
    cwd: '/home/me/src/app',
    home: '/home/me',
    environment: const {'PATH': '/fixture/bin'},
    executablePath: versions == null
        ? () => throw StateError('executable resolved')
        : () => path,
    runner: versions == null ? _Refusing() : runner,
    openVersions: (running) {
      if (versions == null) throw StateError('registry client built');
      expect(running, version);
      return source = FakeSource(versions);
    },
    official: official,
  );
  if (source != null) expect(source!.closed, isTrue);
  return Upgraded(outcome.code, '$stdout', '$stderr', source, runner);
}

class _Refusing implements Runner {
  @override
  Future<void> inherit(List<String> argv, Map<String, String> env) =>
      throw StateError('ran $argv');

  @override
  Future<String> capture(List<String> argv, Map<String, String> env) =>
      throw StateError('ran $argv');
}

/// Refused as the port's other refusals: help on stdout, the message on
/// stderr between blank lines, exit 2.
void refused(Upgraded call, String message) {
  expect(call.code, 2);
  expect(call.stdout, '$upgradeHelp\n');
  expect(call.stderr, '\n  error: $message\n\n');
}

// The running chord is version.dart's; these are around it.
// Past the running version, a release or a channel's, so it sorts above
// it: the next patch, or the release a prerelease leads to.
final _newer = Version.parse(version).nextPatch.toString();
const _older = '0.0.0';

Versions _listed({String? latest}) =>
    Versions(latest: latest ?? _newer, versions: [_newer, version, _older]);

String _argv(String to) => 'npm install --global @chorded/chord@$to';

void main() {
  test('--help in args\' layout with the original\'s words', () async {
    for (final help in ['--help', '-h']) {
      final call = await chord(['upgrade', help]);
      expect(call.code, 0);
      expect(call.stderr, isEmpty);
      expect(
        call.stdout,
        'Usage: chord upgrade\n'
        'Version: $version\n'
        '\n'
        'Upgrade chord executable to latest or given version.\n'
        '\n'
        'Options:\n'
        '  -h, --help                 Show this help.\n'
        '  -l, --list-versions        Show available versions.\n'
        '      --version=<version>    The version to upgrade to.\n'
        '                             (defaults to "latest")\n'
        '  -f, --force                Replace current installation even if '
        'not out-of-date.\n'
        '  -v, --verbose              Log verbose output.\n',
      );
    }
  });

  test(
    'chord\'s own help, version and help of agents build no client',
    () async {
      for (final args in [
        ['--help'],
        ['-h'],
        ['--version'],
        ['-V'],
        ['agents', '--help'],
        ['acp', '--help'],
      ]) {
        final call = await chord(args);
        expect(call.code, 0, reason: '$args');
      }
    },
  );

  test('chord\'s help lists upgrade after acp', () {
    expect(
      chordHelp,
      contains(
        'Commands:\n'
        '  agents   List the agents chord can start',
      ),
    );
    expect(
      chordHelp,
      contains(
        'draws nothing.\n'
        '  upgrade  Upgrade chord executable to latest or given version.\n'
        '\nExamples:',
      ),
    );
  });

  group('usage errors, with no client', () {
    test('an unknown option, with the nearest one', () async {
      refused(
        await chord(['upgrade', '-V']),
        'Unknown option "-V". Did you mean option "-v"?',
      );
      refused(
        await chord(['upgrade', '--lst-versions']),
        'Unknown option "--lst-versions". Did you mean option '
        '"--list-versions"?',
      );
      refused(
        await chord(['upgrade', '-lV']),
        'Unknown option "-V". Did you mean option "-v"?',
      );
      refused(
        await chord(['upgrade', '--no-force']),
        'Unknown option "--no-force". Did you mean option "--force"?',
      );
    });

    test('chord\'s own options are not upgrade\'s', () async {
      refused(
        await chord(['upgrade', '--cwd', 'x']),
        'Unknown option "--cwd". Did you mean option "--help"?',
      );
    });

    test('--version without its value', () async {
      refused(
        await chord(['upgrade', '--version']),
        'Missing value for option "--version".',
      );
    });

    test('a flag given a value', () async {
      refused(
        await chord(['upgrade', '--force=yes']),
        'Option "--force" doesn\'t take a value, but got "yes".',
      );
    });

    test('an option given twice, as typed the second time', () async {
      refused(
        await chord(['upgrade', '-v', '--verbose']),
        'Option "--verbose" can only occur once, but was found several '
        'times.',
      );
      refused(
        await chord(['upgrade', '-fv', '-f']),
        'Option "-f" can only occur once, but was found several times.',
      );
      refused(
        await chord(['upgrade', '--version', '1', '--version=2']),
        'Option "--version" can only occur once, but was found several '
        'times.',
      );
      // Read in order: the twice-given option comes before the unknown one.
      refused(
        await chord(['upgrade', '-v', '-v', '--nope']),
        'Option "-v" can only occur once, but was found several times.',
      );
    });

    test('help stands alone', () async {
      refused(
        await chord(['upgrade', '-h', '-f']),
        'Option "--help" cannot be combined with other options.',
      );
    });

    test('an argument', () async {
      refused(
        await chord(['upgrade', 'now']),
        'No arguments allowed for command "chord upgrade".',
      );
    });
  });

  group('the truth table', () {
    test('-l: one read, the versions, the running one marked', () async {
      final call = await chord(['upgrade', '-l'], versions: _listed());
      expect((call.code, call.source!.reads), (0, 1));
      expect(call.stdout, '  $_newer\n* $version\n  $_older\n');
      expect(call.runner.ran, isEmpty);
    });

    test('-l on a failed read: the message, exit 1', () async {
      final call = await chord([
        'upgrade',
        '--list-versions',
      ], versions: RegistryError('the registry answered 503'));
      expect((call.code, call.source!.reads), (1, 1));
      expect(call.stdout, isEmpty);
      expect(
        call.stderr,
        'chord could not read the versions of @chorded/chord from the npm '
        'registry: the registry answered 503\n',
      );
    });

    test('bare, already latest: one read, exit 0', () async {
      final call = await chord(['upgrade'], versions: _listed(latest: version));
      expect((call.code, call.source!.reads), (0, 1));
      expect(
        call.stderr,
        "You're already using the latest available version $version of "
        'chord.\n',
      );
      expect(call.runner.ran, isEmpty);
    });

    test('bare, a newer one: two reads, the manager run', () async {
      final call = await chord(['upgrade'], versions: _listed());
      expect((call.code, call.source!.reads), (0, 2));
      expect(call.runner.ran, [installArgv(Manager.npm, _newer)]);
      expect(call.runner.envs, [
        {'PATH': '/fixture/bin'},
      ]);
      expect(
        call.stdout,
        'A chord already running keeps $version until it is started again.\n'
        'Successfully upgraded chord from version $version to $_newer! '
        '(https://npmjs.org/package/@chorded/chord/v/$_newer)\n',
      );
      expect(call.stderr, isEmpty);
    });

    test('-v says each step', () async {
      final call = await chord(['upgrade', '-v'], versions: _listed());
      expect(
        call.stdout,
        'Upgrading chord to the latest version\n'
        'Upgrading chord:\n'
        '  - current version: $version\n'
        '  - target version: $_newer\n'
        '\$ ${_argv(_newer)}\n'
        'A chord already running keeps $version until it is started again.\n'
        'Successfully upgraded chord from version $version to $_newer! '
        '(https://npmjs.org/package/@chorded/chord/v/$_newer)\n',
      );
    });

    test('--version not listed: one read, not found, exit 1', () async {
      final call = await chord([
        'upgrade',
        '--version',
        '9.9.9',
      ], versions: _listed());
      expect((call.code, call.source!.reads), (1, 1));
      expect(
        call.stderr,
        'The provided version 9.9.9 is not found. The latest version is '
        '$_newer.\n\n'
        '    Visit https://npmjs.org/package/@chorded/chord for available '
        'releases or run again with the -l or --list-versions command.\n',
      );
      expect(call.runner.ran, isEmpty);
    });

    test('--version the running one: one read, exit 0', () async {
      final call = await chord([
        'upgrade',
        '--version=$version',
      ], versions: _listed());
      expect((call.code, call.source!.reads), (0, 1));
      expect(call.stderr, "You're already using version $version of chord.\n");
      expect(call.runner.ran, isEmpty);
    });

    test('--version listed: one read, the manager run', () async {
      final call = await chord([
        'upgrade',
        '--version',
        _older,
      ], versions: _listed());
      expect((call.code, call.source!.reads), (0, 1));
      expect(call.runner.ran, [installArgv(Manager.npm, _older)]);
    });

    test('--force: one read to resolve latest', () async {
      final call = await chord([
        'upgrade',
        '--force',
      ], versions: _listed(latest: version));
      expect((call.code, call.source!.reads), (0, 1));
      expect(call.runner.ran, [installArgv(Manager.npm, version)]);
    });

    test('--force --version: no read', () async {
      final call = await chord([
        'upgrade',
        '-f',
        '--version',
        '7.0.0',
      ], versions: _listed());
      expect((call.code, call.source!.reads), (0, 0));
      expect(call.runner.ran, [installArgv(Manager.npm, '7.0.0')]);
    });

    test('what follows -- is no argument', () async {
      final call = await chord([
        'upgrade',
        '-f',
        '--',
        'ignored',
      ], versions: _listed());
      expect(call.code, 0);
      expect(call.runner.ran, [installArgv(Manager.npm, _newer)]);
    });

    test('unidentified: refused after the reads, nothing run', () async {
      final call = await chord(
        ['upgrade'],
        versions: _listed(),
        path: '/home/me/bin/chord',
      );
      expect((call.code, call.source!.reads), (1, 2));
      expect(call.runner.ran, isEmpty);
      expect(
        call.stderr,
        'Failed to upgrade chord from version $version to $_newer.\n'
        '${unidentifiedText('/home/me/bin/chord', _newer, machine: runningMachine())}\n',
      );
    });

    test('official and unidentified: replaced from the release', () async {
      final call = await chord(
        ['upgrade'],
        versions: _listed(),
        path: '/home/me/bin/chord',
        official: true,
      );
      expect((call.code, call.source!.reads), (1, 2));
      expect(call.runner.ran, isEmpty);
      expect(
        call.stderr,
        'Failed to upgrade chord from version $version to $_newer.\n'
        'Install chord through npm (npm install -g @chorded/chord) or '
        'Homebrew (brew install ikatsuba/tap/chord) and upgrade it there, '
        'or replace this binary by chord-${runningMachine()}.tar.gz '
        'from https://github.com/IKatsuba/chord/releases/tag/v$_newer, '
        'checked against its SHA256SUMS.\n',
      );
    });

    test('official on an npm path: the npm flow', () async {
      final call = await chord(
        ['upgrade'],
        versions: _listed(),
        official: true,
      );
      expect(call.code, 0);
      expect(call.runner.ran, [installArgv(Manager.npm, _newer)]);
    });

    test('the manager\'s failures', () async {
      final argv = installArgv(Manager.npm, _newer);
      for (final (failure, line) in [
        (RunExited(argv, 3), '${_argv(_newer)} exited with status 3.'),
        (RunKilled(argv, 'SIGINT'), '${_argv(_newer)} was killed by SIGINT.'),
        (
          RunNotFound(argv),
          'npm is not on PATH. Install npm, or upgrade chord with the '
              'manager that installed it.',
        ),
      ]) {
        final call = await chord(
          ['upgrade'],
          versions: _listed(),
          fail: failure,
        );
        expect(call.code, 1);
        expect(
          call.stderr,
          'Failed to upgrade chord from version $version to $_newer.\n'
          '$line\n',
        );
        expect(call.stdout, isEmpty);
      }
    });
  });
}
