// The runtime catalog starts only the fake or a scripted opener: a real
// runtime's name never reaches a process.
@Tags(['fake_agent'])
library;

import 'package:chord/session/session.dart';
import 'package:chord/session/start_failure.dart' show StartFailed;
import 'package:test/test.dart';

import 'fake_harness.dart';
import 'runtimes.dart';

void main() {
  testerRuntimeCatalogTests();
  test(
    'a real runtime is refused by name, and its command never starts',
    () async {
      final pids = <int>[];
      final runtimes = TestRuntimes(onPid: pids.add);
      addTearDown(runtimes.dispose);
      expect(
        () => runtimes.commandOf('codex'),
        throwsA(isA<NotATestRuntime>()),
      );
      await expectLater(
        openSession(
          agent: 'codex',
          command: ['npx', '@zed-industries/codex-acp'],
          cwd: runtimes.home.path,
          open: runtimes.opener,
        ),
        // The session says its start failed, in the catalog's words.
        throwsA(
          isA<StartFailed>().having(
            (e) => '$e',
            'words',
            contains('npx is not a test runtime'),
          ),
        ),
      );
      expect(pids, isEmpty);
    },
  );

  test('an issued command cannot be changed into another program', () {
    final runtimes = TestRuntimes();
    addTearDown(runtimes.dispose);
    final argv = runtimes.commandOf('fake') as List<String>;
    expect(argv.clear, throwsUnsupportedError);
    expect(() => argv[0] = 'npx', throwsUnsupportedError);
  }, skip: fakeAgentSkip);

  test('every runtime runs at home in a directory of its own, its children on '
      'the fake', () {
    final runtimes = TestRuntimes();
    addTearDown(runtimes.dispose);
    final env = runtimes.env;
    expect(env['HOME'], runtimes.home.path);
    for (final name in [
      'XDG_CONFIG_HOME',
      'XDG_STATE_HOME',
      'XDG_CACHE_HOME',
    ]) {
      expect(env[name], startsWith(runtimes.home.path));
    }
    expect(env['CHORD_FAKE_CHILD_RUNTIME'], 'fake');
  });

  test('a scripted runtime opens through its own opener, given the '
      "catalog's environment", () async {
    Map<String, String>? given;
    final runtimes = TestRuntimes(
      scripted: {
        'scripted':
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) {
              given = env;
              throw StateError('scripted, not started');
            },
      },
    );
    addTearDown(runtimes.dispose);
    await expectLater(
      runtimes.opener(
        command: runtimes.commandOf('scripted'),
        cwd: runtimes.home.path,
        onTraffic: (_) {},
        onPermission: (_, _) => throw UnimplementedError(),
      ),
      throwsStateError,
    );
    expect(given, containsPair('CHORD_FAKE_CHILD_RUNTIME', 'fake'));
  });

  test('the fake starts from the catalog, and closes', () async {
    final pids = <int>[];
    final runtimes = TestRuntimes(onPid: pids.add);
    addTearDown(runtimes.dispose);
    final session = await openSession(
      agent: 'fake',
      command: runtimes.commandOf('fake'),
      cwd: runtimes.home.path,
      open: runtimes.opener,
    );
    expect(pids, hasLength(1));
    await session.close();
  }, skip: fakeAgentSkip);
}

void testerRuntimeCatalogTests() {
  group('tester: catalog provenance and environment isolation', () {
    test(
      'equal argv copies and another catalog commands never reach inner opener',
      () async {
        var opened = 0;
        final scripted = <String, SessionOpener>{
          'scripted':
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) {
                opened++;
                throw StateError('inner reached');
              },
        };
        final first = TestRuntimes(scripted: scripted);
        final second = TestRuntimes(scripted: scripted);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final issued = first.commandOf('scripted') as List<String>;
        for (final command in <Object>[
          [...issued],
          second.commandOf('scripted'),
          'scripted',
        ]) {
          await expectLater(
            first.opener(
              command: command,
              cwd: first.home.path,
              onTraffic: (_) {},
              onPermission: (_, _) => throw UnimplementedError(),
            ),
            throwsA(isA<NotATestRuntime>()),
          );
        }
        expect(opened, 0);
        await expectLater(
          first.opener(
            command: issued,
            cwd: first.home.path,
            onTraffic: (_) {},
            onPermission: (_, _) => throw UnimplementedError(),
          ),
          throwsStateError,
        );
        expect(opened, 1);
      },
    );

    test(
      'inner gets immutable trusted argv and protected environment over supplied values',
      () async {
        List<String>? trusted;
        Map<String, String>? received;
        final catalog = TestRuntimes(
          scripted: {
            'scripted':
                ({
                  required command,
                  env,
                  required cwd,
                  required onTraffic,
                  required onPermission,
                  relay,
                  cancellationToken,
                }) {
                  trusted = command as List<String>;
                  received = env;
                  throw StateError('scripted, no process');
                },
          },
        );
        addTearDown(catalog.dispose);
        final issued = catalog.commandOf('scripted');
        final supplied = <String, String>{
          for (final key in catalog.env.keys) key: 'untrusted',
          'SCRIPTED_FIXTURE': 'kept',
        };
        await expectLater(
          catalog.opener(
            command: issued,
            env: supplied,
            cwd: catalog.home.path,
            onTraffic: (_) {},
            onPermission: (_, _) => throw UnimplementedError(),
          ),
          throwsStateError,
        );
        expect(trusted, ['scripted', 'scripted']);
        expect(identical(trusted, issued), isFalse);
        expect(() => trusted![0] = 'npx', throwsUnsupportedError);
        for (final entry in catalog.env.entries) {
          expect(received, containsPair(entry.key, entry.value));
        }
        expect(received, containsPair('SCRIPTED_FIXTURE', 'kept'));
        expect(supplied['CHORD_FAKE_CHILD_RUNTIME'], 'untrusted');
        catalog.dispose();
        expect(catalog.home.existsSync(), isFalse);
      },
    );
  });
}
