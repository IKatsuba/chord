// How a child starts on the window's own agent, as the original's
// `startupOf` in src/settings.ts and `placeOf` in src/session/place.ts
// resolve it: the invoked agent with the command line's flags,
// `--agent-command` included, any other name from the files or the
// catalog alone; and the names a window offers children, as
// `knownAgents` lists them, through the launch a call to chord builds.
import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/servers.dart' show noMcpServersFlag;
import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _line = 'bun /fixtures/fake_agent/main.ts';
const _file = '/work/.chord/settings.json';

/// The window's own agent as `chord fake --agent-command <line>` invokes
/// it, with [model] when the call gives one.
({Startup invoked, Flags flags}) _fake({
  String? model,
  List<SettingsLayer> layers = const [],
}) {
  final flags = Flags(agent: 'fake', agentCommand: _line, model: model);
  return (invoked: resolveStartup(flags, layers, defaultAgent), flags: flags);
}

/// A temporary home with chord's user settings file in it.
final class _Home {
  _Home() {
    root = Directory.systemTemp.createTempSync('chord-child-start-');
    home = p.join(root.path, 'home');
    work = p.join(root.path, 'work');
    Directory(work).createSync(recursive: true);
  }

  late final Directory root;
  late final String home, work;

  void settings(Map<String, Object?> value) =>
      File(p.join(home, '.config', 'chord', 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(value));

  Future<Launch> launch(List<String> args) async {
    final outcome = await runCli(
      args,
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      cwd: work,
      home: home,
      environment: {'HOME': home},
      lookup: (command) async => '/bin/$command',
      readSessionRecords: () async => const [],
    );
    expect(outcome.code, 0);
    return outcome.launch!;
  }
}

void main() {
  _testerInvokedFlagIsolation();
  group('childStart for the invoked agent', () {
    test("carries --agent-command, where the name alone starts nothing", () {
      final (:invoked, :flags) = _fake();
      final start = childStart(
        'fake',
        const [],
        cwd: '/work',
        home: null,
        invoked: invoked,
        flags: flags,
      );
      expect(start?.command, _line);
      expect(start?.env, isEmpty);
      expect(start?.refused, isNull);
      // chord's own start fails with a version; the person's command does
      // not.
      expect(start?.pinned, isNull);
      expect(childStart('fake', const [], cwd: '/work', home: null), isNull);
    });

    test("takes the call's --model, and --no-mcp-servers, as main does", () {
      final (:invoked, :flags) = _fake(model: 'fake-small');
      final start = childStart(
        'fake',
        const [],
        cwd: '/work',
        home: null,
        invoked: invoked,
        flags: flags,
        noMcpServers: true,
      )!;
      expect(start.starting.model?.id, 'fake-small');
      expect(start.starting.model?.from, 'set by --model');
      expect(start.noMcpServers, isTrue);
      expect(start.noMcpServersFrom, noMcpServersFlag);
    });

    test('leaves a catalog agent as it was, the flags not its own', () {
      final (:invoked, :flags) = _fake(model: 'fake-small');
      final codex = childStart(
        'codex',
        const [],
        cwd: '/work',
        home: null,
        invoked: invoked,
        flags: flags,
        noMcpServers: true,
      )!;
      final alone = childStart('codex', const [], cwd: '/work', home: null)!;
      expect(codex.command, findAgent('codex')!.start.command);
      expect(codex.command, alone.command);
      expect(codex.env, alone.env);
      expect(codex.pinned, alone.pinned);
      expect(codex.starting.model, isNull);
      expect(codex.noMcpServers, alone.noMcpServers);
    });

    test('starts no name with neither a command nor a catalog entry', () {
      final (:invoked, :flags) = _fake();
      expect(
        childStart(
          'ghost',
          const [],
          cwd: '/work',
          home: null,
          invoked: invoked,
          flags: flags,
        ),
        isNull,
      );
    });

    test('starts a settings agent through its command', () {
      const layers = [
        SettingsLayer(
          _file,
          Settings(
            agents: {'mine': AgentSettings(command: CommandLine('mine --acp'))},
          ),
        ),
      ];
      final (:invoked, :flags) = _fake(layers: layers);
      final start = childStart(
        'mine',
        layers,
        cwd: '/work',
        home: null,
        invoked: invoked,
        flags: flags,
      );
      expect(start?.command, 'mine --acp');
    });

    test("is refused by the place's files unless a flag gave the command", () {
      const layers = [
        SettingsLayer(_file, Settings(), {'codex': 'expected a string'}),
      ];
      const flagged = Flags(agent: 'codex', agentCommand: _line);
      final given = childStart(
        'codex',
        layers,
        cwd: '/work',
        home: null,
        invoked: resolveStartup(flagged, const [], defaultAgent),
        flags: flagged,
      );
      expect(given?.refused, isNull);
      expect(given?.command, _line);
      const bare = Flags(agent: 'codex');
      final refused = childStart(
        'codex',
        layers,
        cwd: '/work',
        home: null,
        invoked: resolveStartup(bare, const [], defaultAgent),
        flags: bare,
      );
      expect(
        refused?.refused,
        'codex not started: agents.codex.command in '
        '.chord/settings.json: expected a string',
      );
    });
  });

  group('a launch on --agent-command', () {
    late _Home place;
    setUp(() => place = _Home());
    tearDown(() => place.root.deleteSync(recursive: true));

    test('starts children of its own agent on that command', () async {
      final launch = await place.launch(['fake', '--agent-command', _line]);
      final start = launch.childStart!('fake');
      expect(start?.command, _line);
      expect(start?.refused, isNull);
      expect(
        launch.childStart!('codex')?.command,
        findAgent('codex')!.start.command,
      );
      expect(launch.childStart!('ghost'), isNull);
    });

    test('offers its own agent first, then the files\' commands, then the '
        'catalog, each once', () async {
      place.settings({
        'agents': {
          'mine': {'command': 'mine --acp'},
          'claude': {'command': 'my-claude'},
          'codex': {'model': 'o3'},
        },
      });
      final launch = await place.launch(['fake', '--agent-command', _line]);
      final catalog = [for (final agent in listAgents()) agent.name];
      expect(launch.runtimeNames, [
        'fake',
        'mine',
        'claude',
        ...catalog.where((name) => name != 'claude'),
      ]);
      expect(launch.childStart!('mine')?.command, 'mine --acp');
    });

    test('a catalog agent invoked by name is listed once', () async {
      final launch = await place.launch(['codex']);
      expect(launch.runtimeNames, [
        'codex',
        for (final agent in listAgents())
          if (agent.name != 'codex') agent.name,
      ]);
    });
  });
}

void _testerInvokedFlagIsolation() {
  group('CTUI-35 tester: invoked runtime flag boundaries', () {
    test(
      'model, effort, mode and no-MCP flags affect only the invoked runtime',
      () {
        const flags = Flags(
          agent: 'fake',
          agentCommand: _line,
          model: 'flag-model',
          effort: 'high',
          permissionMode: 'acceptEdits',
        );
        const layers = [
          SettingsLayer(
            _file,
            Settings(
              agents: {
                'fake': AgentSettings(
                  model: 'file-model',
                  effort: 'low',
                  permissionMode: 'ask',
                  mcpServers: true,
                ),
                'helper': AgentSettings(
                  command: CommandLine('helper --acp'),
                  model: 'helper-model',
                  effort: 'medium',
                  permissionMode: 'plan',
                  mcpServers: false,
                ),
              },
            ),
          ),
        ];
        final invoked = resolveStartup(flags, layers, defaultAgent);
        final own = childStart(
          'fake',
          layers,
          cwd: '/work',
          home: null,
          invoked: invoked,
          flags: flags,
          noMcpServers: true,
        )!;
        expect(own.command, _line);
        expect(
          (
            own.starting.model?.id,
            own.starting.effort?.id,
            own.starting.mode?.id,
          ),
          ('flag-model', 'high', 'acceptEdits'),
        );
        expect(own.noMcpServersFrom, noMcpServersFlag);
        final other = childStart(
          'helper',
          layers,
          cwd: '/work',
          home: null,
          invoked: invoked,
          flags: flags,
          noMcpServers: true,
        )!;
        expect(other.command, 'helper --acp');
        expect(
          (
            other.starting.model?.id,
            other.starting.effort?.id,
            other.starting.mode?.id,
          ),
          ('helper-model', 'medium', 'plan'),
        );
        expect(other.noMcpServers, isTrue);
        expect(other.noMcpServersFrom, _file);
      },
    );

    test(
      'settings argv stays argv when that runtime was invoked without a command flag',
      () {
        const argv = ['bun', 'fixtures/fake agent.dart', '--label=界🙂'];
        const flags = Flags(agent: 'mine');
        final layers = [
          SettingsLayer(
            _file,
            Settings(
              agents: {'mine': AgentSettings(command: CommandArgv(argv))},
            ),
          ),
        ];
        final invoked = resolveStartup(flags, layers, defaultAgent);
        final start = childStart(
          'mine',
          layers,
          cwd: '/work',
          home: null,
          invoked: invoked,
          flags: flags,
        )!;
        expect(start.command, argv);
        expect(start.command, isA<List<String>>());
        expect(start.pinned, isNull);
      },
    );
  });
}
