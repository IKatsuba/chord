import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/upgrade.dart';
import 'package:test/test.dart';

const cellar = '/opt/homebrew/Cellar/chord/0.54.0/bin/chord';

/// Homebrew as an upgrade meets it: brew's run fails with [fail], and
/// `brew list --versions` answers [listed] or fails with [listFails].
final class Brew implements Runner {
  Brew({this.fail, this.listed = 'chord 0.55.0 0.54.0\n', this.listFails});

  final RunFailure? fail;
  final String listed;
  final RunFailure? listFails;
  final ran = <List<String>>[];

  @override
  Future<void> inherit(List<String> argv, Map<String, String> env) async {
    ran.add(argv);
    if (fail case final failure?) throw failure;
  }

  @override
  Future<String> capture(List<String> argv, Map<String, String> env) async {
    ran.add(argv);
    if (listFails case final failure?) throw failure;
    return listed;
  }
}

/// A source no Homebrew run may read.
final class NoRead implements VersionSource {
  @override
  Future<Versions> read() => throw StateError('the registry was read');

  @override
  void close() {}
}

typedef Ran = ({int code, String stdout, String stderr});

Future<Ran> brewUpgrade(
  UpgradeRequest request, {
  Brew? runner,
  String path = cellar,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runUpgrade(
    request,
    running: '0.54.0',
    realPath: () => path,
    env: const {'PATH': '/fixture/bin'},
    runner: runner ?? Brew(),
    source: NoRead(),
    stdout: out,
    stderr: err,
    machine: () => 'darwin-arm64',
  );
  return (code: code, stdout: '$out', stderr: '$err');
}

void main() {
  test('the Cellar of chord\'s formula is Homebrew, under any prefix', () {
    for (final path in [
      cellar,
      '/usr/local/Cellar/chord/1.2.3/bin/chord',
      '/home/linuxbrew/.linuxbrew/Cellar/chord/1.2.3_1/bin/chord',
    ]) {
      expect(homebrewFormulaOf(path), 'chord', reason: path);
    }
    for (final path in [
      '/opt/homebrew/Cellar/other/1.0.0/bin/chord',
      '/opt/homebrew/bin/chord',
      '/opt/homebrew/Cellar/chord/0.54.0/libexec/chord',
    ]) {
      expect(homebrewFormulaOf(path), isNull, reason: path);
    }
  });

  test(
    'an upgrade runs brew, reads no registry, and says the new version',
    () async {
      final runner = Brew();
      final ran = await brewUpgrade(const UpgradeRequest(), runner: runner);
      expect(ran.code, 0);
      expect(runner.ran, [
        ['brew', 'upgrade', 'ikatsuba/tap/chord'],
        ['brew', 'list', '--versions', 'chord'],
      ]);
      expect(
        ran.stdout,
        'A chord already running keeps 0.54.0 until it is started again.\n'
        'Successfully upgraded chord from version 0.54.0 to 0.55.0! '
        '(https://github.com/IKatsuba/chord/releases/tag/v0.55.0)\n',
      );
      expect(ran.stderr, isEmpty);
    },
  );

  test('-v says it is upgrading to the latest, and the command', () async {
    final ran = await brewUpgrade(const UpgradeRequest(verbose: true));
    expect(
      ran.stdout,
      startsWith(
        'Upgrading chord to the latest version\n'
        '\$ brew upgrade ikatsuba/tap/chord\n',
      ),
    );
  });

  test('-f reinstalls', () async {
    final runner = Brew(listed: 'chord 0.54.0\n');
    await brewUpgrade(const UpgradeRequest(force: true), runner: runner);
    expect(runner.ran.first, ['brew', 'reinstall', 'ikatsuba/tap/chord']);
  });

  test('nothing newer: already the latest, exit 0', () async {
    final ran = await brewUpgrade(
      const UpgradeRequest(),
      runner: Brew(listed: 'chord 0.54.0\n'),
    );
    expect(ran.code, 0);
    expect(
      ran.stderr,
      "You're already using the latest available version 0.54.0 of chord.\n",
    );
    expect(ran.stdout, isEmpty);
  });

  group('what brew installed cannot be told', () {
    for (final (name, brew, reason) in [
      (
        'brew list fails',
        Brew(listFails: const RunExited(['brew', 'list'], 1)),
        'brew list exited with status 1.',
      ),
      ('brew lists nothing', Brew(listed: ''), 'brew lists no chord'),
      (
        'brew lists no version',
        Brew(listed: 'chord HEAD\n'),
        'brew listed "chord HEAD", which names no version',
      ),
    ]) {
      test('$name: the upgrade may have happened, exit 1', () async {
        final ran = await brewUpgrade(const UpgradeRequest(), runner: brew);
        expect(ran.code, 1);
        expect(
          ran.stderr,
          'brew upgrade ikatsuba/tap/chord finished, but chord could not '
          'tell which version is installed now: $reason. Run brew list '
          '--versions chord.\n',
        );
      });
    }
  });

  test('brew failing says so, with its words', () async {
    final ran = await brewUpgrade(
      const UpgradeRequest(),
      runner: Brew(fail: const RunExited(['brew', 'upgrade', 'x'], 1)),
    );
    expect(ran.code, 1);
    expect(
      ran.stderr,
      'Failed to upgrade chord from version 0.54.0 to latest.\n'
      'brew upgrade x exited with status 1.\n',
    );
  });

  test('brew missing from PATH is said by name', () async {
    final ran = await brewUpgrade(
      const UpgradeRequest(),
      runner: Brew(fail: const RunNotFound(['brew'])),
    );
    expect(
      ran.stderr,
      'Failed to upgrade chord from version 0.54.0 to latest.\n'
      'brew is not on PATH. Install brew, or upgrade chord with the manager '
      'that installed it.\n',
    );
  });

  test(
    '--version is refused with no read, naming npm and the releases',
    () async {
      final runner = Brew();
      final ran = await brewUpgrade(
        const UpgradeRequest(to: '0.50.0'),
        runner: runner,
      );
      expect(ran.code, 1);
      expect(runner.ran, isEmpty);
      expect(
        ran.stderr,
        'Homebrew installs only the version its formula names: brew upgrade '
        'ikatsuba/tap/chord. For another version, install chord with npm (npm '
        'install --global @chorded/chord@0.50.0) or from '
        'https://github.com/IKatsuba/chord/releases.\n',
      );
    },
  );

  test('-l is refused with no read, saying where the versions are', () async {
    final runner = Brew();
    final ran = await brewUpgrade(
      const UpgradeRequest(list: true),
      runner: runner,
    );
    expect(ran.code, 1);
    expect(runner.ran, isEmpty);
    expect(
      ran.stderr,
      'Homebrew installs only the version its formula names: brew upgrade '
      'ikatsuba/tap/chord. For the versions there are, run npm view '
      '@chorded/chord versions or see '
      'https://github.com/IKatsuba/chord/releases.\n',
    );
  });

  // Only chord's own row of brew's listing counts.
  test('a listing without chord\'s row is no observation, whatever else it '
      'names', () async {
    final ran = await brewUpgrade(
      const UpgradeRequest(),
      runner: Brew(listed: 'other 9.0.0\n'),
    );
    expect(ran.code, 1);
    expect(ran.stdout, isEmpty);
    expect(
      ran.stderr,
      contains(
        'could not tell which version is installed now: brew lists '
        'no chord.',
      ),
    );
  });

  test("chord's row is found among others", () async {
    final ran = await brewUpgrade(
      const UpgradeRequest(),
      runner: Brew(listed: 'other 9.0.0\nchord 0.55.0 0.54.0\n'),
    );
    expect(ran.code, 0);
    expect(ran.stdout, contains('to 0.55.0!'));
  });

  group('a binary whose path cannot be resolved', () {
    Future<(int, String, String, List<List<String>>)> cli(
      List<String> args,
    ) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = Brew();
      final outcome = await runCli(
        args,
        stdout: out,
        stderr: err,
        cwd: '/work',
        home: '/home/x',
        environment: const {'PATH': '/fixture/bin'},
        executablePath: () =>
            throw const FileSystemException('No such file', '/gone/chord'),
        runner: runner,
        openVersions: (_) => Listed(),
      );
      return (outcome.code, '$out', '$err', runner.ran);
    }

    test('-l still lists the versions', () async {
      final (code, out, _, ran) = await cli(['upgrade', '-l']);
      expect(code, 0);
      expect(out, contains('0.0.2'));
      expect(ran, isEmpty);
    });

    test('an upgrade says why, exit 1, running nothing', () async {
      final (code, _, err, ran) = await cli(['upgrade', '--force']);
      expect(code, 1);
      expect(err, contains('No such file: /gone/chord'));
      expect(ran, isEmpty);
    });
  });

  group('tester: Homebrew observation and ownership boundaries', () {
    test(
      'the newest numeric version wins within a whitespace-padded chord row',
      () async {
        final ran = await brewUpgrade(
          const UpgradeRequest(),
          runner: Brew(listed: 'other 99.0.0\n  chord\t1.9.9 1.10.0 HEAD\r\n'),
        );
        expect(ran.code, 0);
        expect(ran.stdout, contains('to 1.10.0!'));
        expect(ran.stderr, isEmpty);
      },
    );

    test(
      'a signalled upgrade never asks which version was installed',
      () async {
        final runner = Brew(
          fail: const RunKilled([
            'brew',
            'upgrade',
            'ikatsuba/tap/chord',
          ], 'SIGTERM'),
        );
        final ran = await brewUpgrade(const UpgradeRequest(), runner: runner);
        expect(ran.code, 1);
        expect(runner.ran, hasLength(1));
        expect(ran.stdout, isEmpty);
        expect(ran.stderr, contains('was killed by SIGTERM'));
      },
    );

    test(
      'CLI resolves once, forwards both environments and closes its unread source',
      () async {
        final source = _TesterUnreadSource();
        final runner = _TesterBrewRunner();
        var resolutions = 0;
        const env = {'PATH': '/fixture/bin', 'MARK': 'kept'};
        final outcome = await runCli(
          ['upgrade'],
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: '/fixture',
          home: '/fixture',
          environment: env,
          executablePath: () {
            resolutions++;
            return cellar;
          },
          runner: runner,
          openVersions: (_) => source,
        );
        expect(outcome.code, 0);
        expect(resolutions, 1);
        expect(runner.envs, [env, env]);
        expect(source.reads, 0);
        expect(source.closed, isTrue);
      },
    );
  });
}

/// A registry answer of two versions, latest 0.0.2.
final class Listed implements VersionSource {
  @override
  Future<Versions> read() async =>
      const Versions(latest: '0.0.2', versions: ['0.0.2', '0.0.1']);

  @override
  void close() {}
}

final class _TesterUnreadSource implements VersionSource {
  var reads = 0;
  var closed = false;
  @override
  Future<Versions> read() {
    reads++;
    throw StateError('registry read');
  }

  @override
  void close() => closed = true;
}

final class _TesterBrewRunner implements Runner {
  final inner = Brew();
  final envs = <Map<String, String>>[];
  @override
  Future<void> inherit(List<String> argv, Map<String, String> env) {
    envs.add(Map.of(env));
    return inner.inherit(argv, env);
  }

  @override
  Future<String> capture(List<String> argv, Map<String, String> env) {
    envs.add(Map.of(env));
    return inner.capture(argv, env);
  }
}
