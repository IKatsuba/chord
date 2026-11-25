// `chord upgrade`'s parts: install detection, the managers' argv, the
// version list, the registry read over loopback, the flow's texts and the
// runner on real processes. Cases of the original's tests/upgrade_test.ts
// keep its names.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/upgrade.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _bin = 'node_modules/@chorded/chord-darwin-arm64/bin/chord';

/// A [VersionSource] answering [versions], counting its reads.
class FakeSource implements VersionSource {
  FakeSource(this.versions);

  /// What each read answers, or a [RegistryError] to throw.
  final Object versions;
  int reads = 0;
  bool closed = false;

  @override
  Future<Versions> read() async {
    reads++;
    return switch (versions) {
      final Versions versions => versions,
      final Object error => throw error,
    };
  }

  @override
  void close() => closed = true;
}

/// A [Runner] that records what it is asked to run and answers [fail].
class RecordingRunner implements Runner {
  RecordingRunner([this.fail]);

  final RunFailure? fail;
  final ran = <List<String>>[];
  final envs = <Map<String, String>>[];

  @override
  Future<void> inherit(List<String> argv, Map<String, String> env) async {
    ran.add(argv);
    envs.add(env);
    if (fail case final failure?) throw failure;
  }

  @override
  Future<String> capture(List<String> argv, Map<String, String> env) =>
      throw UnimplementedError();
}

/// One run of the flow, with what it printed.
typedef Ran = ({int code, String stdout, String stderr});

Future<Ran> upgradeWith(
  UpgradeRequest request, {
  required VersionSource source,
  Runner? runner,
  String running = '0.54.0',
  String path = '/var/u/.bun/install/global/$_bin',
  Map<String, String> env = const {},
  bool official = false,
  String machine = 'darwin-arm64',
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runUpgrade(
    request,
    running: running,
    realPath: () => path,
    env: env,
    runner: runner ?? RecordingRunner(),
    source: source,
    stdout: out,
    stderr: err,
    official: official,
    machine: () => machine,
  );
  return (code: code, stdout: '$out', stderr: '$err');
}

const _forced = UpgradeRequest(force: true, to: '0.55.0', verbose: true);

/// The original's channel document.
const _document = {
  'dist-tags': {
    'latest': '0.67.0',
    'next': '1.0.0-next.4',
    'beta': '1.0.0-beta.1',
  },
  'versions': {'0.67.0': {}, '1.0.0-beta.1': {}, '1.0.0-next.4': {}},
};

/// A loopback registry: [answer] serves each request, [paths] records them.
class Registry {
  Registry._(this.server, this.client);

  final HttpServer server;
  final http.Client client;
  final paths = <String>[];
  late Future<void> Function(HttpRequest request) answer;

  static Future<Registry> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final registry = Registry._(server, IOClient(HttpClient()));
    registry.answer = (request) => registry.json(request, _document);
    server.listen((request) {
      registry.paths.add(request.uri.path);
      registry.answer(request);
    });
    return registry;
  }

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}/');

  Future<void> json(HttpRequest request, Object? body, [int status = 200]) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(body is String ? body : jsonEncode(body));
    return request.response.close();
  }

  RegistryReader reader(String running) =>
      RegistryReader(client: client, running: running, base: base);

  Future<void> close() async {
    client.close();
    await server.close(force: true);
  }
}

void main() {
  group('tester: CTUI-153 official refusal boundaries', () {
    for (final machine in [
      'darwin-arm64',
      'darwin-x64',
      'linux-arm64',
      'linux-x64',
    ]) {
      test('$machine keeps channel target and manager ordering', () async {
        const target = '1.0.0-next.7';
        final source = FakeSource(StateError('forced target must not read'));
        final runner = RecordingRunner();
        final ran = await upgradeWith(
          const UpgradeRequest(force: true, to: target),
          source: source,
          runner: runner,
          path: '/fixture/bin/chord',
          official: true,
          machine: machine,
        );
        expect((ran.code, source.reads), (1, 0));
        expect(runner.ran, isEmpty);
        expect(ran.stdout, isEmpty);
        expect(
          ran.stderr,
          'Failed to upgrade chord from version 0.54.0 to $target.\n'
          'Install chord through npm (npm install -g @chorded/chord) or '
          'Homebrew (brew install ikatsuba/tap/chord) and upgrade it there, '
          'or replace this binary by chord-$machine.tar.gz from '
          'https://github.com/IKatsuba/chord/releases/tag/v$target, '
          'checked against its SHA256SUMS.\n',
        );
      });
    }
  });

  test('the manager is read off where a global install puts the binary', () {
    final rows = <(String, Manager?)>[
      ('/var/u/.bun/install/global/$_bin', Manager.bun),
      (
        '/var/u/Library/pnpm/global/5/node_modules/.pnpm/'
            '@chorded+chord-darwin-arm64@0.54.0/$_bin',
        Manager.pnpm,
      ),
      (
        '/var/u/.local/share/pnpm/global/v11/abc-1/node_modules/.pnpm/'
            '@chorded+chord-linux-x64@0.54.0/node_modules/@chorded/'
            'chord-linux-x64/bin/chord',
        Manager.pnpm,
      ),
      ('/var/u/.config/yarn/global/$_bin', Manager.yarn),
      ('/opt/homebrew/lib/node_modules/@chorded/chord/$_bin', Manager.npm),
      (
        '/usr/lib/node_modules/@chorded/chord/node_modules/@chorded/'
            'chord-linux-arm64/bin/chord',
        Manager.npm,
      ),
      // Caches, a build from source and a local install are no global
      // install.
      ('/var/u/.npm/_npx/1a2b/$_bin', null),
      ('/private/tmp/bunx-501-@chorded/chord@latest/$_bin', null),
      ('/var/u/.local/bin/chord', null),
      ('/opt/homebrew/bin/bun', null),
      ('/var/u/src/app/$_bin', null),
      // A Homebrew keg is no row of this unit.
      ('/opt/homebrew/Cellar/chord/0.54.0/bin/chord', null),
    ];
    for (final (path, manager) in rows) {
      expect(detectManager(path), manager, reason: path);
    }
  });

  test('each manager installs the exact version globally', () {
    expect(installArgv(Manager.npm, '0.55.0'), [
      'npm',
      'install',
      '--global',
      '@chorded/chord@0.55.0',
    ]);
    expect(installArgv(Manager.bun, '0.55.0'), [
      'bun',
      'add',
      '--global',
      '@chorded/chord@0.55.0',
    ]);
    expect(installArgv(Manager.pnpm, '0.55.0'), [
      'pnpm',
      'add',
      '--global',
      '@chorded/chord@0.55.0',
    ]);
    expect(installArgv(Manager.yarn, '0.55.0'), [
      'yarn',
      'global',
      'add',
      '@chorded/chord@0.55.0',
    ]);
  });

  test('the upgrade runs the manager that installed chord', () async {
    final runner = RecordingRunner();
    final source = FakeSource(StateError('no read'));
    final ran = await upgradeWith(
      _forced,
      source: source,
      runner: runner,
      env: const {'PATH': '/fixture/bin'},
    );
    expect(ran.code, 0);
    expect(runner.ran, [
      ['bun', 'add', '--global', '@chorded/chord@0.55.0'],
    ]);
    expect(runner.envs, [
      {'PATH': '/fixture/bin'},
    ]);
    expect(source.reads, 0);
    expect(
      ran.stdout,
      'Upgrading chord to version 0.55.0\n'
      'Upgrading chord:\n'
      '  - current version: 0.54.0\n'
      '  - target version: 0.55.0\n'
      '\$ bun add --global @chorded/chord@0.55.0\n'
      'A chord already running keeps 0.54.0 until it is started again.\n'
      'Successfully upgraded chord from version 0.54.0 to 0.55.0! '
      '(https://npmjs.org/package/@chorded/chord/v/0.55.0)\n',
    );
    expect(ran.stderr, isEmpty);
  });

  test(
    'a chord no manager installed is refused with how to upgrade it',
    () async {
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        _forced,
        source: FakeSource(StateError('no read')),
        runner: runner,
        path: '/var/u/.local/bin/chord',
      );
      expect(ran.code, 1);
      expect(runner.ran, isEmpty);
      expect(
        ran.stderr,
        'Failed to upgrade chord from version 0.54.0 to 0.55.0.\n'
        'chord cannot tell which package manager installed '
        '/var/u/.local/bin/chord. If one did, upgrade with it: npm install '
        '--global @chorded/chord@0.55.0, bun add --global '
        '@chorded/chord@0.55.0, pnpm add --global @chorded/chord@0.55.0, yarn '
        'global add @chorded/chord@0.55.0. Homebrew upgrades with brew '
        'upgrade ikatsuba/tap/chord. A release binary is replaced by '
        'chord-darwin-arm64.tar.gz from '
        'https://github.com/IKatsuba/chord/releases/tag/v0.55.0, checked '
        'against its SHA256SUMS. A build from source upgrades with git pull '
        'and dart compile exe bin/chord.dart -o <path of your '
        'chord>.\n',
      );
      // No `$` line: nothing was going to run.
      expect(ran.stdout, isNot(contains('\$')));
    },
  );

  test('a manager missing from PATH is said by name', () async {
    final argv = installArgv(Manager.pnpm, '0.55.0');
    final ran = await upgradeWith(
      _forced,
      source: FakeSource(StateError('no read')),
      runner: RecordingRunner(RunNotFound(argv)),
      path:
          '/var/u/Library/pnpm/global/5/node_modules/.pnpm/'
          '@chorded+chord-darwin-arm64@0.54.0/$_bin',
    );
    expect(ran.code, 1);
    expect(
      ran.stderr,
      'Failed to upgrade chord from version 0.54.0 to 0.55.0.\n'
      'pnpm is not on PATH. Install pnpm, or upgrade chord with the manager '
      'that installed it.\n',
    );
    expect(
      ran.stdout,
      endsWith('\$ pnpm add --global @chorded/chord@0.55.0\n'),
    );
  });

  test('a failed or killed manager is said with its argv', () async {
    final argv = installArgv(Manager.bun, '0.55.0');
    for (final (failure, line) in [
      (
        RunExited(argv, 3),
        'bun add --global @chorded/chord@0.55.0 exited with status 3.',
      ),
      (
        RunKilled(argv, 'SIGTERM'),
        'bun add --global @chorded/chord@0.55.0 was killed by SIGTERM.',
      ),
    ]) {
      final ran = await upgradeWith(
        _forced,
        source: FakeSource(StateError('no read')),
        runner: RecordingRunner(failure),
      );
      expect(ran.code, 1);
      expect(
        ran.stderr,
        'Failed to upgrade chord from version 0.54.0 to 0.55.0.\n$line\n',
      );
      expect(ran.stdout, isNot(contains('Successfully')));
    }
  });

  test('latest is resolved to an exact version for the manager', () async {
    final runner = RecordingRunner();
    final source = FakeSource(
      const Versions(latest: '0.56.0', versions: ['0.56.0', '0.55.0']),
    );
    final ran = await upgradeWith(
      const UpgradeRequest(force: true),
      source: source,
      runner: runner,
    );
    expect(ran.code, 0);
    expect(source.reads, 1);
    expect(runner.ran, [installArgv(Manager.bun, '0.56.0')]);
    expect(
      ran.stdout,
      'A chord already running keeps 0.54.0 until it is started again.\n'
      'Successfully upgraded chord from version 0.54.0 to 0.56.0! '
      '(https://npmjs.org/package/@chorded/chord/v/0.56.0)\n',
    );
  });

  group('the texts of the truth table', () {
    const listed = Versions(
      latest: '0.55.0',
      versions: ['0.55.0', '0.54.0', '0.53.0'],
    );

    test('already latest: one read, said on stderr, exit 0', () async {
      final source = FakeSource(listed);
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        const UpgradeRequest(),
        source: source,
        runner: runner,
        running: '0.55.0',
      );
      expect((ran.code, source.reads, runner.ran.length), (0, 1, 0));
      expect(
        ran.stderr,
        "You're already using the latest available version 0.55.0 of "
        'chord.\n',
      );
      expect(ran.stdout, isEmpty);
    });

    test('a newer one: two reads, then the manager', () async {
      final source = FakeSource(listed);
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        const UpgradeRequest(verbose: true),
        source: source,
        runner: runner,
      );
      expect((ran.code, source.reads), (0, 2));
      expect(runner.ran, [installArgv(Manager.bun, '0.55.0')]);
      expect(ran.stdout, startsWith('Upgrading chord to the latest version\n'));
    });

    test('a version not listed: the latest named', () async {
      final source = FakeSource(listed);
      final ran = await upgradeWith(
        const UpgradeRequest(to: '9.9.9'),
        source: source,
      );
      expect((ran.code, source.reads), (1, 1));
      expect(
        ran.stderr,
        'The provided version 9.9.9 is not found. The latest version is '
        '0.55.0.\n\n'
        '    Visit https://npmjs.org/package/@chorded/chord for available '
        'releases or run again with the -l or --list-versions command.\n',
      );
    });

    test('a near miss is suggested instead', () async {
      final ran = await upgradeWith(
        const UpgradeRequest(to: 'v0.55.0'),
        source: FakeSource(listed),
      );
      expect(
        ran.stderr,
        startsWith(
          'The provided version v0.55.0 is not found. Did you mean '
          '0.55.0?\n\n    Visit',
        ),
      );
    });

    test('the running version named: said on stderr, exit 0', () async {
      final source = FakeSource(listed);
      final ran = await upgradeWith(
        const UpgradeRequest(to: '0.54.0'),
        source: source,
      );
      expect((ran.code, source.reads), (0, 1));
      expect(ran.stderr, "You're already using version 0.54.0 of chord.\n");
    });

    test('a failed read stops it before anything runs', () async {
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        const UpgradeRequest(verbose: true),
        source: FakeSource(RegistryError('the registry answered 503')),
        runner: runner,
      );
      expect(ran.code, 1);
      expect(runner.ran, isEmpty);
      // Under -v too, the message alone.
      expect(
        ran.stderr,
        'chord could not read the versions of @chorded/chord from the npm '
        'registry: the registry answered 503\n',
      );
    });

    test('-l lists the versions; a failed read is said, exit 1', () async {
      final ran = await upgradeWith(
        const UpgradeRequest(list: true),
        source: FakeSource(listed),
      );
      expect(ran.code, 0);
      expect(ran.stdout, '  0.55.0\n* 0.54.0\n  0.53.0\n');
      final failed = await upgradeWith(
        const UpgradeRequest(list: true),
        source: FakeSource(RegistryError('the registry answered 503')),
      );
      expect(failed.code, 1);
      expect(failed.stdout, isEmpty);
      expect(
        failed.stderr,
        'chord could not read the versions of @chorded/chord from the npm '
        'registry: the registry answered 503\n',
      );
    });
  });

  group('an official build', () {
    test('a plain run is not official', () {
      expect(officialBuild, isFalse);
      expect(const bool.fromEnvironment('chord.official'), isFalse);
    });

    test('the machine as the archives name it', () {
      expect(
        machineOf('3.12.0 (stable) (Tue) on "macos_arm64"'),
        'darwin-arm64',
      );
      expect(machineOf('3.12.0 (stable) on "macos_x64"'), 'darwin-x64');
      expect(machineOf('3.12.0 (stable) on "linux_arm64"'), 'linux-arm64');
      expect(machineOf('3.12.0 (stable) on "linux_x64"'), 'linux-x64');
      expect(
        runningMachine(),
        matches(RegExp(r'^(darwin|linux)-(arm64|x64)$')),
      );
    });

    test(
      'no row identifies it: replaced from the release, nothing run',
      () async {
        final runner = RecordingRunner();
        final source = FakeSource(
          const Versions(latest: '0.55.0', versions: ['0.55.0', '0.54.0']),
        );
        final ran = await upgradeWith(
          const UpgradeRequest(),
          source: source,
          runner: runner,
          path: '/usr/local/bin/chord',
          official: true,
          machine: 'linux-x64',
        );
        expect((ran.code, source.reads, runner.ran.length), (1, 2, 0));
        expect(
          ran.stderr,
          'Failed to upgrade chord from version 0.54.0 to 0.55.0.\n'
          'Install chord through npm (npm install -g @chorded/chord) or '
          'Homebrew (brew install ikatsuba/tap/chord) and upgrade it there, '
          'or replace this binary by chord-linux-x64.tar.gz from '
          'https://github.com/IKatsuba/chord/releases/tag/v0.55.0, checked '
          'against its SHA256SUMS.\n',
        );
      },
    );

    test('the path rows win over the stamp', () async {
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        _forced,
        source: FakeSource(StateError('no read')),
        runner: runner,
        path: '/usr/lib/node_modules/@chorded/chord/$_bin',
        official: true,
      );
      expect(ran.code, 0);
      expect(runner.ran, [installArgv(Manager.npm, '0.55.0')]);
    });

    test('an unofficial one keeps the managers and the source build', () async {
      final ran = await upgradeWith(
        _forced,
        source: FakeSource(StateError('no read')),
        path: '/usr/local/bin/chord',
      );
      expect(ran.stderr, contains('chord cannot tell which package manager'));
      expect(ran.stderr, contains('git pull and dart compile exe'));
      // The release is named as one source among the others.
      expect(ran.stderr, contains('Homebrew upgrades with'));
    });
  });

  group('formatVersions, as cliffy prints them', () {
    test('a short list, newest first, the running one marked', () {
      expect(
        formatVersions([
          '0.9.0',
          '1.0.0-next.4',
          '1.0.0',
          '1.0.0-beta.1',
          '0.10.0',
        ], '0.10.0'),
        '  1.0.0\n'
        '  1.0.0-next.4\n'
        '  1.0.0-beta.1\n'
        '* 0.10.0\n'
        '  0.9.0',
      );
    });

    test('unparseable versions last, in string order', () {
      expect(
        formatVersions(['b', '0.1.0', 'a', '1.0.0'], null),
        '  1.0.0\n  0.1.0\n  a\n  b',
      );
    });

    test('nothing for no versions', () {
      expect(formatVersions([], '0.1.0'), '');
    });

    test('25 still one per line', () {
      final versions = [for (var i = 1; i <= 25; i++) '0.0.$i'];
      expect(formatVersions(versions, null).split('\n'), hasLength(25));
    });

    test('more than 25 in eight columns filled column by column', () {
      final versions = [for (var i = 1; i <= 26; i++) '0.0.$i'];
      expect(
        formatVersions(versions, '0.0.20'),
        [
          '  0.0.26   0.0.22   0.0.18   0.0.14   0.0.10   0.0.6   0.0.2 ',
          '  0.0.25   0.0.21   0.0.17   0.0.13   0.0.9    0.0.5   0.0.1 ',
          '  0.0.24 * 0.0.20   0.0.16   0.0.12   0.0.8    0.0.4         ',
          '  0.0.23   0.0.19   0.0.15   0.0.11   0.0.7    0.0.3         ',
        ].join('\n'),
      );
    });

    test('forty fill every column, each as wide as its widest cell', () {
      final versions = [
        for (var i = 1; i <= 39; i++) '1.$i.0',
        '1.0.0-beta.10',
      ];
      expect(
        formatVersions(versions, '1.3.0'),
        [
          '  1.39.0   1.34.0   1.29.0   1.24.0   1.19.0   1.14.0   1.9.0 '
              '  1.4.0        ',
          '  1.38.0   1.33.0   1.28.0   1.23.0   1.18.0   1.13.0   1.8.0 '
              '* 1.3.0        ',
          '  1.37.0   1.32.0   1.27.0   1.22.0   1.17.0   1.12.0   1.7.0 '
              '  1.2.0        ',
          '  1.36.0   1.31.0   1.26.0   1.21.0   1.16.0   1.11.0   1.6.0 '
              '  1.1.0        ',
          '  1.35.0   1.30.0   1.25.0   1.20.0   1.15.0   1.10.0   1.5.0 '
              '  1.0.0-beta.10',
        ].join('\n'),
      );
    });
  });

  group('the tag chord upgrade follows', () {
    late Registry registry;
    setUp(() async => registry = await Registry.start());
    tearDown(() => registry.close());

    for (final (running, latest) in [
      ('0.66.0', '0.67.0'),
      ('1.0.0', '0.67.0'),
      ('1.0.0-next.3', '1.0.0-next.4'),
      ('1.0.0-next.4', '1.0.0-next.4'),
      ('1.0.0-beta.0', '1.0.0-beta.1'),
    ]) {
      test('a build of $running follows $latest', () async {
        expect((await registry.reader(running).read()).latest, latest);
        expect(registry.paths, ['/@chorded/chord']);
      });
    }

    test('a channel lists every version, as a stable build does', () async {
      final channel = await registry.reader('1.0.0-next.3').read();
      final stable = await registry.reader('0.66.0').read();
      expect(channel.versions, stable.versions);
      expect(channel.versions, ['1.0.0-next.4', '1.0.0-beta.1', '0.67.0']);
    });

    test(
      'a channel with no tag fails naming it, and never falls back to latest',
      () async {
        await expectLater(
          registry.reader('1.0.0-rc.0').read(),
          throwsA(
            isA<RegistryError>().having(
              (error) => error.message,
              'message',
              'chord could not read the versions of @chorded/chord from the npm '
                  'registry: it has no tag rc, the channel this chord is on',
            ),
          ),
        );
        expect(registry.paths, hasLength(1));
      },
    );

    test('a failed read on a channel says so', () async {
      registry.answer = (request) => registry.json(request, '', 503);
      await expectLater(
        registry.reader('1.0.0-next.3').read(),
        _fails('the registry answered 503'),
      );
    });

    test('a failed read on a stable build says it as cliffy does', () async {
      registry.answer = (request) => registry.json(request, '', 503);
      await expectLater(
        registry.reader('0.66.0').read(),
        _fails("couldn't fetch the latest version - try again after sometime"),
      );
    });

    test('an answer that is no package document is said so', () async {
      for (final body in [
        '{not json',
        '[]',
        {'versions': {}},
        {'dist-tags': {}, 'versions': {}},
        {
          'dist-tags': {'latest': 1},
          'versions': {},
        },
      ]) {
        registry.answer = (request) => registry.json(request, body);
        await expectLater(
          registry.reader('0.66.0').read(),
          _fails("the registry's answer is not a package document"),
          reason: '$body',
        );
      }
    });

    test('a closed port is said in the exception\'s own words', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final reader = RegistryReader(
        client: registry.client,
        running: '0.66.0',
        base: Uri.parse('http://127.0.0.1:$port/'),
      );
      await expectLater(
        reader.read(),
        throwsA(
          isA<RegistryError>().having(
            (error) => error.message,
            'message',
            startsWith(
              'chord could not read the versions of @chorded/chord from the '
              'npm registry: ',
            ),
          ),
        ),
      );
    });

    test(
      'a version no channel can have stops the upgrade, not the command',
      () async {
        await expectLater(
          registry.reader('1.0.0-next').read(),
          throwsA(
            isA<RegistryError>().having(
              (error) => error.message,
              'message',
              contains('a pre-release is written <x.y.z>-<channel>.<n>'),
            ),
          ),
        );
        expect(registry.paths, isEmpty);
      },
    );

    test('a version named is taken as it is, on any build', () async {
      final runner = RecordingRunner();
      final ran = await upgradeWith(
        const UpgradeRequest(force: true, to: '0.67.0'),
        source: registry.reader('1.0.0-next.3'),
        runner: runner,
        running: '1.0.0-next.3',
      );
      expect(ran.code, 0);
      expect(runner.ran, [installArgv(Manager.bun, '0.67.0')]);
      expect(registry.paths, isEmpty);
    });

    test('the flow gives the reader the running version', () async {
      final runner = RecordingRunner();
      await upgradeWith(
        const UpgradeRequest(force: true),
        source: registry.reader('1.0.0-beta.0'),
        runner: runner,
        running: '1.0.0-beta.0',
      );
      expect(runner.ran, [installArgv(Manager.bun, '1.0.0-beta.1')]);
    });
  });

  group('tester: CHD-577 upgrade channel boundaries', () {
    late Registry registry;
    setUp(() async => registry = await Registry.start());
    tearDown(() => registry.close());

    const document = {
      'dist-tags': {
        'latest': '0.67.0',
        'next': '1.0.0-next.10',
        'beta': '1.0.0-beta.3',
      },
      'versions': {'0.67.0': {}, '1.0.0-next.10': {}, '1.0.0-beta.3': {}},
    };

    test(
      'simultaneous builds keep their tags when registry answers arrive in reverse order',
      () async {
        final pending = <HttpRequest>[];
        final all = Completer<void>();
        registry.answer = (request) async {
          pending.add(request);
          if (pending.length == 3) all.complete();
        };
        final reads = [
          for (final running in ['0.66.0', '1.0.0-next.9', '1.0.0-beta.2'])
            registry.reader(running).read(),
        ];
        await all.future;
        for (final request in pending.reversed) {
          await registry.json(request, document);
        }
        expect(
          [for (final read in await Future.wait(reads)) read.latest],
          ['0.67.0', '1.0.0-next.10', '1.0.0-beta.3'],
        );
      },
    );

    test(
      'a rejected registry read makes one request and never falls back',
      () async {
        registry.answer = (request) async {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
        };
        await expectLater(
          registry.reader('1.0.0-next.9').read(),
          throwsA(isA<RegistryError>()),
        );
        expect(registry.paths, hasLength(1));
      },
    );

    test(
      'each manager receives the exact channel version resolved from the registry',
      () async {
        registry.answer = (request) => registry.json(request, document);
        for (final (manager, path) in [
          (Manager.npm, '/usr/lib/node_modules/@chorded/chord/$_bin'),
          (Manager.bun, '/var/u/.bun/install/global/$_bin'),
          (
            Manager.pnpm,
            '/var/u/Library/pnpm/global/5/node_modules/.pnpm/'
                '@chorded+chord-darwin-arm64@0.54.0/$_bin',
          ),
          (Manager.yarn, '/var/u/.config/yarn/global/$_bin'),
        ]) {
          final runner = RecordingRunner();
          await upgradeWith(
            const UpgradeRequest(),
            source: registry.reader('1.0.0-beta.2'),
            runner: runner,
            running: '1.0.0-beta.2',
            path: path,
          );
          expect(runner.ran, [installArgv(manager, '1.0.0-beta.3')]);
        }
      },
    );
  });

  group('the runner on real processes', () {
    late Directory dir;
    late Directory bin;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('chord_upgrade_runner_');
      bin = await Directory(p.join(dir.path, 'bin')).create();
    });
    tearDown(() => dir.delete(recursive: true));

    Future<void> script(String name, String body) async {
      final file = File(p.join(bin.path, name));
      await file.writeAsString('#!/bin/sh\n$body\n');
      await Process.run('/bin/chmod', ['+x', file.path]);
    }

    Map<String, String> env([Map<String, String> more = const {}]) => {
      'PATH': bin.path,
      ...more,
    };

    test(
      'a manager exiting 0 succeeds, in exactly the given environment',
      () async {
        final marker = p.join(dir.path, 'env');
        await script('npm', '/usr/bin/env > "\$CHORD_MARKER"');
        await const ProcessRunner().inherit([
          'npm',
          'install',
          '--global',
          '@chorded/chord@0.55.0',
        ], env({'CHORD_MARKER': marker, 'CHORD_FIXTURE': 'one'}));
        final seen = {
          for (final line in await File(marker).readAsLines())
            line.substring(0, line.indexOf('=')): line.substring(
              line.indexOf('=') + 1,
            ),
        };
        // What the shell itself sets is no inherited variable.
        for (final own in ['PWD', 'SHLVL', '_', 'OLDPWD']) {
          seen.remove(own);
        }
        expect(seen, env({'CHORD_MARKER': marker, 'CHORD_FIXTURE': 'one'}));
      },
    );

    test('an exit status is a RunExited', () async {
      await script('bun', 'exit 3');
      await expectLater(
        const ProcessRunner().inherit(['bun', 'add'], env()),
        throwsA(
          isA<RunExited>()
              .having((e) => e.status, 'status', 3)
              .having(
                (e) => e.message,
                'message',
                'bun add exited with status 3.',
              ),
        ),
      );
    });

    test('a signal is a RunKilled', () async {
      await script('bun', r'kill -TERM $$');
      await expectLater(
        const ProcessRunner().inherit(['bun', 'add'], env()),
        throwsA(
          isA<RunKilled>().having(
            (e) => e.message,
            'message',
            'bun add was killed by SIGTERM.',
          ),
        ),
      );
    });

    test('a program missing from PATH is a RunNotFound', () async {
      await expectLater(
        const ProcessRunner().inherit(['npm', 'install'], env()),
        throwsA(isA<RunNotFound>()),
      );
    });

    test('capture gives stdout and the same failures', () async {
      await script('npm', 'echo captured; echo noise >&2');
      expect(
        await const ProcessRunner().capture(['npm', 'view'], env()),
        'captured\n',
      );
      await script('bun', 'exit 4');
      await expectLater(
        const ProcessRunner().capture(['bun'], env()),
        throwsA(isA<RunExited>().having((e) => e.status, 'status', 4)),
      );
    });
  });

  group('a TLS failure is the read\'s failure', () {
    RegistryReader tls() => RegistryReader(
      client: MockClient(
        (_) async => throw const HandshakeException('bad certificate'),
      ),
      running: '0.54.0',
    );

    test('as -l says it, exit 1', () async {
      final ran = await upgradeWith(
        const UpgradeRequest(list: true),
        source: tls(),
      );
      expect(ran.code, 1);
      expect(
        ran.stderr,
        'chord could not read the versions of @chorded/chord from the npm '
        'registry: bad certificate\n',
      );
    });

    test('as the upgrade says it, exit 1', () async {
      final ran = await upgradeWith(const UpgradeRequest(), source: tls());
      expect(ran.code, 1);
      expect(
        ran.stderr,
        'chord could not read the versions of @chorded/chord from the npm '
        'registry: bad certificate\n',
      );
    });
  });

  group('tester: npm upgrade read and list boundaries', () {
    test(
      'a failed second read runs no manager and reports no success',
      () async {
        var reads = 0;
        final source = RegistryReader(
          running: '0.54.0',
          client: MockClient((_) async {
            if (++reads == 1) {
              return http.Response(
                jsonEncode({
                  'dist-tags': {'latest': '0.55.0'},
                  'versions': {'0.54.0': {}, '0.55.0': {}},
                }),
                200,
              );
            }
            throw http.ClientException('second read failed');
          }),
        );
        addTearDown(source.close);
        final runner = RecordingRunner();
        final ran = await upgradeWith(
          const UpgradeRequest(verbose: true),
          source: source,
          runner: runner,
        );
        expect((ran.code, reads), (1, 2));
        expect(runner.ran, isEmpty);
        expect(ran.stderr, contains('registry: second read failed'));
        expect(ran.stdout, isNot(contains('Successfully upgraded')));
      },
    );

    test(
      'an I/O read failure is normalised into the registry diagnostic',
      () async {
        final source = RegistryReader(
          running: '0.54.0',
          client: MockClient(
            (_) async => throw const FileSystemException('fixture I/O failure'),
          ),
        );
        addTearDown(source.close);
        final ran = await upgradeWith(
          const UpgradeRequest(list: true),
          source: source,
        );
        expect(ran.code, 1);
        expect(
          ran.stderr,
          startsWith(
            'chord could not read the versions of @chorded/chord from the npm registry: ',
          ),
        );
        expect(ran.stderr, contains('fixture I/O failure'));
      },
    );

    test('list sorting is stable for metadata ties and keeps its input', () {
      final versions = ['1.0.0+z', '1.0.0+a', '1.0.1', 'bad'];
      final before = List.of(versions);
      expect(
        formatVersions(versions, '1.0.0+a'),
        '  1.0.1\n  1.0.0+z\n* 1.0.0+a\n  bad',
      );
      expect(versions, before);
    });
  });
}

Matcher _fails(String reason) => throwsA(
  isA<RegistryError>().having(
    (error) => error.message,
    'message',
    'chord could not read the versions of @chorded/chord from the npm '
        'registry: $reason',
  ),
);
