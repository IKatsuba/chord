import 'dart:io';

import 'package:chord/acp/process.dart' show commandArgv;
import 'package:chord/version.dart' as chord;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart';
import '../fixtures/fake.dart';
import '../fixtures/fake_harness.dart' show fakeAgentSkip;

void expectCall(
  DevChord? call, {
  required bool fake,
  required List<String> args,
  String? qa,
}) {
  expect(call?.fake, fake);
  expect(call?.qa, qa);
  expect(call?.args, args);
}

void main() {
  group('parseDev', () {
    test('reads chord and its arguments', () {
      expectCall(
        parseDev(['chord', 'codex', '-p', 'hi']),
        fake: false,
        args: ['codex', '-p', 'hi'],
      );
    });

    test('--fake before chord\'s words is the runner\'s', () {
      expectCall(
        parseDev(['chord', '--fake', '-p', 'hi']),
        fake: true,
        args: ['-p', 'hi'],
      );
    });

    test('from chord\'s first word on, every word is chord\'s', () {
      expectCall(
        parseDev(['chord', 'codex', '--fake']),
        fake: false,
        args: ['codex', '--fake'],
      );
    });

    test('after --, words go to chord as they are, empty ones too', () {
      expectCall(
        parseDev(['chord', '--fake', '--', '--help', '']),
        fake: true,
        args: ['--help', ''],
      );
      expectCall(
        parseDev(['chord', '-p', '', 'x', '--', '']),
        fake: false,
        args: ['-p', 'x', ''],
      );
    });

    // What the original's Cliffy command gives for the same words.
    test('an empty first word ends the runner'
        's options and is dropped', () {
      expectCall(
        parseDev(['chord', '', '--fake']),
        fake: false,
        args: ['--fake'],
      );
    });

    test('an option it does not know is chord'
        's', () {
      expectCall(
        parseDev(['chord', '--fake', '--unknown', 'x']),
        fake: true,
        args: ['--unknown', 'x'],
      );
    });

    test('--qa <name> runs chord in /tmp/chord-qa.<name>, before its own '
        'arguments', () {
      expectCall(
        parseDev(['chord', '--qa', 'tabs', '--fake', '-p', 'hi']),
        fake: true,
        qa: '/tmp/chord-qa.tabs',
        args: ['-p', 'hi'],
      );
      expectCall(
        parseDev(['chord', '--fake', '--qa=tabs', 'codex']),
        fake: true,
        qa: '/tmp/chord-qa.tabs',
        args: ['codex'],
      );
      // Bare, the default place, before chord's own options.
      expectCall(
        parseDev(['chord', '--qa', '--fake']),
        fake: true,
        qa: '/tmp/chord-qa',
        args: [],
      );
      expectCall(
        parseDev(['chord', '--qa']),
        fake: false,
        qa: '/tmp/chord-qa',
        args: [],
      );
      expectCall(
        parseDev(['chord', '--qa', '-p', 'hi']),
        fake: false,
        qa: '/tmp/chord-qa',
        args: ['-p', 'hi'],
      );
      // An empty name is dropped: a run as with no --qa.
      expectCall(parseDev(['chord', '--qa', '']), fake: false, args: []);
      expectCall(parseDev(['chord', '--qa=']), fake: false, args: []);
      for (final name in ['../home', 'a/b', '..', '.', 'with space']) {
        expect(
          () => parseDev(['chord', '--qa', name]),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              '--qa takes letters, digits, . _ and -, not "$name"',
            ),
          ),
          reason: name,
        );
      }
    });

    test('anything but chord is not a call it knows', () {
      expect(parseDev([]), isNull);
      expect(parseDev(['test']), isNull);
    });
  });

  group('chordArgv', () {
    const fake = ['/sdk/dart', '/src/my chord/fake.dill', '--scenario', 'text'];

    test('runs the port from source with chord\'s arguments', () {
      expect(chordArgv(dart: '/sdk/dart', portDir: '/repo', args: ['codex']), [
        '/sdk/dart',
        'run',
        '/repo/bin/chord.dart',
        'codex',
      ]);
    });

    test("on the fake, as chord fake --agent-command with the Dart fake's "
        'argv', () {
      final argv = chordArgv(
        dart: '/sdk/dart',
        portDir: '/repo',
        args: ['-p', 'hi'],
        fake: fake,
      );
      expect(argv, [
        '/sdk/dart',
        'run',
        fixtureDefine,
        fakeRuntimesDefine,
        '/repo/bin/chord.dart',
        'fake',
        '--agent-command',
        "/sdk/dart '/src/my chord/fake.dill' --scenario text",
        '-p',
        'hi',
      ]);
      // chord splits the command back into the very argv.
      expect(commandArgv(argv[7]), fake);
    });

    test('any path survives the split, operators and quotes included', () {
      for (final path in [
        "/it's here",
        r'/a\b',
        '/a"b',
        r'/a$b',
        r'/a`b',
        '/a b',
        for (final c in ';|&<>()*?#!~{}[]^'.split('')) '/a${c}b',
        '#/a',
        '/界😀é',
      ]) {
        final argv = chordArgv(
          dart: '/sdk/dart',
          portDir: '/repo',
          args: const [],
          fake: [path, p.join(path, 'fake.dill')],
        );
        expect(commandArgv(argv[7]), [
          path,
          p.join(path, 'fake.dill'),
        ], reason: path);
      }
    });

    test('a capture isolates resource sources even for a real agent', () {
      final argv = chordArgv(
        dart: '/sdk/dart',
        portDir: '/repo',
        args: ['codex'],
        fixtureResources: true,
      );
      expect(argv, [
        '/sdk/dart',
        'run',
        fixtureDefine,
        '/repo/bin/chord.dart',
        'codex',
      ]);
    });

    test('a plain word is left as it is', () {
      expect(shellWord('/opt/bun-1.2/bin/bun'), '/opt/bun-1.2/bin/bun');
      expect(shellWord("it's"), r"'it'\''s'");
    });
  });

  test('stateEnv makes the state directory and names it', () {
    final dir = Directory.systemTemp.createTempSync('chord-dev-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = p.join(dir.path, 'state', 'fake');
    expect(stateEnv(state), {'XDG_STATE_HOME': state});
    expect(Directory(state).existsSync(), isTrue);
    expect(stateEnv(null), isEmpty);
    expect(stateEnv(state, config: '/c'), {
      'XDG_STATE_HOME': state,
      'XDG_CONFIG_HOME': '/c',
    });
  });

  group('CTUI-117: a --fake run starts only the fake', () {
    test('builds chord with fake runtimes on the fake alone', () {
      const fake = ['/sdk/dart', '/fake.dill'];
      List<String> argv({List<String>? fake, bool fixture = false}) =>
          chordArgv(
            dart: '/sdk/dart',
            portDir: '/repo',
            args: const ['codex'],
            fake: fake,
            fixtureResources: fixture,
          );
      expect(argv(fake: fake), contains(fakeRuntimesDefine));
      expect(
        argv(fake: fake).indexOf(fakeRuntimesDefine),
        lessThan(argv(fake: fake).indexOf('/repo/bin/chord.dart')),
      );
      expect(argv(), isNot(contains(fakeRuntimesDefine)));
      expect(argv(fixture: true), isNot(contains(fakeRuntimesDefine)));
    });

    test("gives the fake's children the fake runtime on --fake alone", () {
      final dir = Directory.systemTemp.createTempSync('chord-dev-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final qa = p.join(dir.path, 'chord-qa.x');
      expect(chordEnv((fake: true, qa: qa, args: const [])), {
        'XDG_STATE_HOME': qaState(qa),
        'XDG_CONFIG_HOME': qaConfig(qa),
        'CHORD_FAKE_CHILD_RUNTIME': 'fake',
      });
      expect(chordEnv((fake: false, qa: qa, args: const [])), {
        'XDG_STATE_HOME': qaState(qa),
        'XDG_CONFIG_HOME': qaConfig(qa),
      });
      expect(chordEnv((fake: false, qa: null, args: const [])), isEmpty);
    });

    // The define's build of chord, the probe in place of bin/chord.dart.
    test('the define reaches the build, and the environment never does', () {
      final probe = p.join(
        portPackageDir(),
        'test',
        'fixtures',
        'fake_runtimes_probe.dart',
      );
      String built(List<String>? fake) {
        final argv = chordArgv(
          dart: Platform.resolvedExecutable,
          portDir: portPackageDir(),
          args: const [],
          fake: fake,
        );
        final at = argv.indexWhere((word) => word.endsWith('chord.dart'));
        final result = Process.runSync(
          argv.first,
          [...argv.sublist(1, at), probe],
          environment: {'CHORD_FAKE_RUNTIMES': 'true'},
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return (result.stdout as String).trim();
      }

      expect(built(const ['/sdk/dart', '/fake.dill']), 'fake runtimes true');
      expect(built(null), 'fake runtimes false');
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  test('CTUI-91: a capture passes its directory as -C first, as given', () {
    expect(
      chordArgs((fake: true, qa: '/tmp/chord-qa.x', args: const ['-p', 'hi'])),
      ['-C', '/tmp/chord-qa.x', '-p', 'hi'],
    );
    expect(chordArgs((fake: false, qa: null, args: const ['codex'])), [
      'codex',
    ]);
  });

  test('qaPlace makes a capture directory and its places afresh', () {
    final dir = Directory.systemTemp.createTempSync('chord-dev-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final qa = p.join(dir.path, 'chord-qa.x');
    final places = [qa, qaState(qa), qaConfig(qa)];
    expect(places.skip(1), ['$qa.state', '$qa.config']);
    qaPlace(places);
    for (final place in places) {
      File(p.join(place, 'left')).writeAsStringSync('from before');
    }
    qaPlace(places);
    for (final place in places) {
      expect(Directory(place).listSync(), isEmpty, reason: place);
    }
  });

  group('the dev route reads fixture resources', () {
    final probe = p.join(
      portPackageDir(),
      'test',
      'fixtures',
      'resource_fixture_probe.dart',
    );
    const fake = ['/sdk/dart', '/fake.dill'];

    // chordArgv's build of chord, the probe in place of bin/chord.dart.
    String built(
      List<String> argv, [
      Map<String, String>? env,
      String? instead,
    ]) {
      final at = argv.indexWhere((word) => word.endsWith('chord.dart'));
      final result = Process.runSync(argv.first, [
        ...argv.sublist(1, at),
        instead ?? probe,
      ], environment: env);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    List<String> argv({List<String>? fake, bool fixture = false}) => chordArgv(
      dart: Platform.resolvedExecutable,
      portDir: portPackageDir(),
      args: const [],
      fake: fake,
      fixtureResources: fixture,
    );

    test('--fake and --qa build chord on fixtures, never official', () {
      expect(built(argv(fake: fake)), 'fixture normal');
      expect(
        built(argv(fixture: true), {'CHORD_FAKE_RESOURCE_CASE': 'partial'}),
        'fixture partial',
      );
    });

    test('without them, and never from the environment, it is official', () {
      expect(
        built(argv(), {'CHORD_RESOURCE_FIXTURE': 'true'}),
        'official normal',
      );
    });

    // The launch's own read, an official reader that says so standing by:
    // the dev route's build reads the fixture windows and never reaches it.
    final route = p.join(
      portPackageDir(),
      'test',
      'fixtures',
      'resource_route_probe.dart',
    );

    test('the --fake route reads fixture windows and never resolves an '
        'official reader', () {
      expect(
        built(argv(fake: fake), null, route),
        'claude 12.345\ncodex 12.345',
      );
      expect(
        built(argv(fixture: true), {
          'CHORD_FAKE_RESOURCE_CASE': 'unavailable',
        }, route),
        'claude Scripted unavailable provider.\n'
        'codex Scripted unavailable provider.',
      );
    });

    test('a build for no capture reaches the official reader', () {
      expect(
        built(argv(), {'CHORD_RESOURCE_FIXTURE': 'true'}, route),
        allOf(
          contains('official resolved claude'),
          contains('official resolved codex'),
        ),
      );
    });
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a signal is 128 and its number, as a shell says it', () {
    expect(shellStatus(0), 0);
    expect(shellStatus(3), 3);
    expect(shellStatus(-15), 143);
  });

  group('the runner', () {
    final script = p.join(portPackageDir(), 'tool', 'dev.dart');

    ProcessResult dev(List<String> args, [Map<String, String>? env]) =>
        Process.runSync(
          Platform.resolvedExecutable,
          ['run', script, ...args],
          environment: env,
          workingDirectory: portPackageDir(),
        );

    test('without chord prints its usage and exits 2', () {
      final result = dev([]);
      expect(result.exitCode, 2);
      expect(result.stderr, startsWith('Usage: dart run tool/dev.dart chord'));
    });

    test('--fake runs the Dart fake, with no bun on PATH', () {
      final person = Directory.systemTemp.createTempSync('chord-person-');
      final qa = qaDir('dev-test-nobun-$pid');
      addTearDown(() {
        person.deleteSync(recursive: true);
        for (final place in [qa, qaState(qa), qaConfig(qa)]) {
          if (Directory(place).existsSync()) {
            Directory(place).deleteSync(recursive: true);
          }
        }
      });
      final path = [
        for (final dir in (Platform.environment['PATH'] ?? '').split(':'))
          if (!File(p.join(dir, 'bun')).existsSync()) dir,
      ].join(':');
      final result = dev(
        ['chord', '--qa', 'dev-test-nobun-$pid', '--fake', '-p', 'hi'],
        {
          'PATH': path,
          'XDG_STATE_HOME': p.join(person.path, 'state'),
          'XDG_CONFIG_HOME': p.join(person.path, 'config'),
        },
      );
      expect(
        result.stdout,
        contains('Hello, world.'),
        reason: '${result.stderr}',
      );
      expect(result.exitCode, 0);
    }, skip: fakeAgentSkip);

    test("runs chord from source and exits with chord's status", () {
      final version = dev(['chord', '--', '--version']);
      expect(version.stdout, 'chord ${chord.version}\n');
      expect(version.exitCode, 0);
      expect(dev(['chord', 'nosuch']).exitCode, 2);
    });

    test('refuses a --qa name that is not a plain word', () {
      final result = dev(['chord', '--qa', 'a/b']);
      expect(result.exitCode, 2);
      expect(
        result.stderr,
        endsWith(
          '\n\nerror: --qa takes letters, digits, . _ and -, not "a/b"\n',
        ),
      );
    });

    test(
      "--qa leaves the person's state and its own directory nothing",
      skip: fakeAgentSkip,
      () {
        final person = Directory.systemTemp.createTempSync('chord-person-');
        final qa = qaDir('dev-test-$pid');
        addTearDown(() {
          person.deleteSync(recursive: true);
          for (final place in [qa, qaState(qa), qaConfig(qa)]) {
            if (Directory(place).existsSync()) {
              Directory(place).deleteSync(recursive: true);
            }
          }
        });
        final result = dev(
          ['chord', '--qa', 'dev-test-$pid', '--fake', '-p', 'hi'],
          {
            'XDG_STATE_HOME': p.join(person.path, 'state'),
            'XDG_CONFIG_HOME': p.join(person.path, 'config'),
          },
        );
        expect(result.stdout, contains('Hello, world.'));
        expect(result.exitCode, 0);
        expect(person.listSync(recursive: true), isEmpty);
        // Nothing in the run's own directory, where @ would list it.
        expect(Directory(qa).listSync(), isEmpty);
      },
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  group('tester runner boundaries', () {
    test('fake plus capture defines fixtures once before the entry point', () {
      const source = ['/sdk/dart', '/src/chord/fake.dill'];
      final argv = chordArgv(
        dart: '/sdk/dart',
        portDir: '/repo',
        args: [fixtureDefine, '--', ''],
        fake: source,
        fixtureResources: true,
      );
      final entryAt = argv.indexOf('/repo/bin/chord.dart');
      expect(argv.sublist(1, entryAt), [
        'run',
        fixtureDefine,
        fakeRuntimesDefine,
      ]);
      final commandAt = argv.indexOf('--agent-command') + 1;
      expect(commandArgv(argv[commandAt]), source);
      expect(argv.sublist(commandAt + 1), [fixtureDefine, '--', '']);
    });

    test(
      'fake command quoting preserves shell metacharacters as path text',
      () {
        for (final path in [
          '/workspace/a;b',
          '/workspace/a&b',
          '/workspace/a(b)',
          '/workspace/a#b',
          r'/workspace/a`b',
          '/workspace/界😀é',
        ]) {
          final source = ['$path/dart', '$path/fake.dill'];
          final argv = chordArgv(
            dart: '/sdk/dart',
            portDir: '/repo',
            args: ['--', ''],
            fake: source,
          );
          final commandAt = argv.indexOf('--agent-command') + 1;
          expect(commandArgv(argv[commandAt]), source, reason: path);
          expect(argv.sublist(commandAt + 1), ['--', '']);
        }
      },
    );

    test('repeated state setup preserves existing contents', () {
      final dir = Directory.systemTemp.createTempSync('chord-dev-tester-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = p.join(dir.path, 'nested', 'state');
      stateEnv(state);
      final marker = File(p.join(state, 'marker'))..writeAsStringSync('keep');
      expect(stateEnv(state), {'XDG_STATE_HOME': state});
      expect(marker.readAsStringSync(), 'keep');
    });

    test(
      'runner ignores obsolete Bun overrides and uses the Dart fake',
      () async {
        final person = Directory.systemTemp.createTempSync('chord-dev-no-bun-');
        final qa = qaDir('tester-obsolete-bun-$pid');
        addTearDown(() {
          person.deleteSync(recursive: true);
          for (final place in [qa, qaState(qa), qaConfig(qa)]) {
            if (Directory(place).existsSync()) {
              Directory(place).deleteSync(recursive: true);
            }
          }
        });
        final child = await Process.start(
          Platform.resolvedExecutable,
          [
            'run',
            p.join(portPackageDir(), 'tool', 'dev.dart'),
            'chord',
            '--qa',
            'tester-obsolete-bun-$pid',
            '--fake',
            '-p',
            'hi',
          ],
          workingDirectory: portPackageDir(),
          environment: {
            'HOME': person.path,
            'XDG_CONFIG_HOME': p.join(person.path, 'config'),
            'XDG_STATE_HOME': p.join(person.path, 'state'),
          },
        );
        final out = child.stdout.toList();
        final err = child.stderr.toList();
        addTearDown(() async {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        });
        // Headless mode reads piped input until EOF before starting the turn.
        await child.stdin.close();
        expect(await child.exitCode.timeout(const Duration(seconds: 60)), 0);
        expect(
          String.fromCharCodes((await out).expand((b) => b)),
          contains('Hello, world.'),
        );
        expect(await err, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
