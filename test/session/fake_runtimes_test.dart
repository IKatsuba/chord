// A dev build on the fake (CTUI-117): with the compile-time flag, every
// runtime a window or `chord acp` starts, the main agent, children, team
// leads and members, `/new` and forks, is the command line's
// `--agent-command`, the fake, under its own name; without one nothing
// starts. Without the flag nothing changes.
import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/place.dart';
import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _line = 'bun /fixtures/fake_agent/main.ts';
const _fakeFlags = Flags(agent: 'fake', agentCommand: _line);
final _invoked = resolveStartup(_fakeFlags, const [], defaultAgent);

/// A directory whose `.chord/settings.json` holds [settings].
String _project(Map<String, Object?> settings) {
  final dir = Directory.systemTemp.createTempSync('chord-fake-runtimes-');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, '.chord', 'settings.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(settings));
  return dir.path;
}

SessionStart? _child(
  String runtime, {
  required bool fake,
  List<SettingsLayer> layers = const [],
  Startup? invoked,
  Flags flags = _fakeFlags,
}) => childStart(
  runtime,
  layers,
  cwd: '/work',
  home: null,
  invoked: invoked ?? _invoked,
  flags: flags,
  fakeRuntimes: fake,
);

void main() {
  _testerFakeRuntimeIsolation();
  group('childStart with fake runtimes', () {
    test('starts claude, codex and any catalog runtime as the fake', () {
      for (final agent in listAgents()) {
        final start = _child(agent.name, fake: true)!;
        expect(start.command, _line, reason: agent.name);
        expect(start.env, isEmpty, reason: agent.name);
        expect(start.refused, isNull, reason: agent.name);
        expect(start.pinned, isNull, reason: agent.name);
      }
    });

    test(
      'starts a runtime only a team or the files name as the fake',
      () async {
        final dir = _project({
          'agents': {
            'opus-lead': {'command': 'claude-agent-acp --model opus'},
            'codex': {'command': 'codex-acp --profile real'},
          },
        });
        final layers = (await loadSettings(configHome: null, cwd: dir)).layers;
        for (final runtime in ['opus-lead', 'codex', 'claude', 'unknown']) {
          final start = _child(runtime, fake: true, layers: layers)!;
          expect(start.command, _line, reason: runtime);
        }
        // Without the flag the files' commands stand.
        expect(
          _child('opus-lead', fake: false, layers: layers)!.command,
          'claude-agent-acp --model opus',
        );
      },
    );

    test('without --agent-command refuses every runtime, its own too', () {
      const flags = Flags(agent: 'claude');
      final invoked = resolveStartup(flags, const [], defaultAgent);
      for (final runtime in ['claude', 'codex', 'fake']) {
        final start = _child(
          runtime,
          fake: true,
          invoked: invoked,
          flags: flags,
        )!;
        expect(start.command, isNull, reason: runtime);
        expect(start.refused, fakeRuntimesRefusal(runtime), reason: runtime);
      }
      expect(
        childStart(
          'codex',
          const [],
          cwd: '/work',
          home: null,
          fakeRuntimes: true,
        )!.refused,
        fakeRuntimesRefusal('codex'),
      );
    });

    test('without the flag a catalog runtime keeps its own command', () {
      for (final name in ['claude', 'codex']) {
        expect(
          _child(name, fake: false)!.command,
          findAgent(name)!.start.command,
        );
      }
      expect(_child('fake', fake: false)!.command, _line);
    });

    test('a normal build carries no flag', () {
      expect(fakeRuntimesFlag, isFalse);
    });
  });

  group('chord acp with fake runtimes', () {
    test(
      'its children and its main start as the fake, or are refused',
      () async {
        final dir = _project({});
        final launched = await loadSettings(configHome: null, cwd: dir);
        final children = await childrenReader(
          agent: 'fake',
          launchDir: dir,
          launched: launched,
          flags: _fakeFlags,
          configHome: null,
          home: null,
          fakeRuntimes: true,
        )(dir);
        expect(children.startOf('claude')!.command, _line);
        expect(children.startOf('codex')!.command, _line);

        final place = await placeReader(
          agent: 'codex',
          launchDir: dir,
          launched: launched,
          flags: const Flags(agent: 'codex'),
          configHome: null,
          home: null,
          fakeRuntimes: true,
        )(dir);
        expect(place.start!.command, isNull);
        expect(place.start!.refused, fakeRuntimesRefusal('codex'));
      },
    );
  });

  group('runCli with fake runtimes', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-fake-runtimes-cli-');
      Directory(p.join(root.path, 'work')).createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<(CliOutcome, String)> run(List<String> args, bool fake) async {
      final err = StringBuffer();
      final outcome = await runCli(
        args,
        stdout: StringBuffer(),
        stderr: err,
        cwd: p.join(root.path, 'work'),
        home: p.join(root.path, 'home'),
        environment: {'XDG_CONFIG_HOME': p.join(root.path, 'config')},
        lookup: (command) async => '/bin/$command',
        readSessionRecords: () async => const [],
        fakeRuntimes: fake,
      );
      return (outcome, err.toString());
    }

    test('refuses a real agent, in a window and with -p', () async {
      for (final args in [
        ['codex'],
        ['claude', '-p', 'hi'],
      ]) {
        final (outcome, err) = await run(args, true);
        expect(outcome.code, 1, reason: '$args');
        expect(outcome.launch, isNull, reason: '$args');
        expect(err, 'chord: ${fakeRuntimesRefusal(args.first)}\n');
      }
    });

    test("starts the fake, and every child on the fake's command", () async {
      final (outcome, _) = await run(['fake', '--agent-command', _line], true);
      final launch = outcome.launch!;
      expect(launch.command, isNotNull);
      for (final runtime in ['claude', 'codex', 'fake']) {
        expect(launch.childStart!(runtime)!.command, _line, reason: runtime);
      }
    });

    test('without the flag a real agent starts as before', () async {
      final (outcome, _) = await run(['codex'], false);
      expect(outcome.code, 0);
      expect(
        outcome.launch!.childStart!('claude')!.command,
        findAgent('claude')!.start.command,
      );
    });
  });
}

void _testerFakeRuntimeIsolation() {
  group('tester CTUI-117: fake runtime reader isolation', () {
    test('concurrent places and children keep each launch command', () async {
      final dirs = [
        _project({
          'agents': {
            'codex': {'command': 'forbidden-first-runtime'},
          },
        }),
        _project({
          'agents': {
            'codex': {'command': 'forbidden-second-runtime'},
          },
        }),
      ];
      final loaded = await loadSettings(configHome: null, cwd: dirs.first);
      await Future.wait([
        for (final command in ['fake-first', 'fake-second'])
          () async {
            final flags = Flags(agent: 'fake', agentCommand: command);
            final places = placeReader(
              agent: 'fake',
              launchDir: dirs.first,
              launched: loaded,
              flags: flags,
              configHome: null,
              home: null,
              fakeRuntimes: true,
            );
            final children = childrenReader(
              agent: 'fake',
              launchDir: dirs.first,
              launched: loaded,
              flags: flags,
              configHome: null,
              home: null,
              fakeRuntimes: true,
            );
            for (final dir in dirs) {
              expect((await places(dir)).start!.command, command);
              final start = (await children(dir)).startOf('codex')!;
              expect(start.command, command);
              expect(start.agentCommand, command);
              expect(start.env, isEmpty);
              expect(start.pinned, isNull);
              expect(start.refused, isNull);
            }
          }(),
      ]);
    });

    test('directory commands cannot bypass a missing fake command', () async {
      final dir = _project({
        'agents': {
          'codex': {'command': 'forbidden-runtime'},
        },
      });
      final loaded = await loadSettings(configHome: null, cwd: dir);
      final children = await childrenReader(
        agent: 'codex',
        launchDir: dir,
        launched: loaded,
        flags: const Flags(agent: 'codex'),
        configHome: null,
        home: null,
        fakeRuntimes: true,
      )(dir);
      for (final runtime in ['codex', 'claude', 'unknown']) {
        final start = children.startOf(runtime)!;
        expect(start.command, isNull);
        expect(start.agentCommand, isNull);
        expect(start.refused, fakeRuntimesRefusal(runtime));
      }
    });
  });
}
