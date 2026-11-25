import 'dart:async';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/clis.dart';
import 'package:chord/registry.dart';
import 'package:test/test.dart';

import 'fixtures/fake.dart';

/// A lookup that finds only [commands].
Lookup has(Iterable<String> commands) =>
    (command) async => commands.contains(command) ? '/bin/$command' : null;

RegistryAgent registered(String id) =>
    registryAgents.firstWhere((agent) => agent.id == id);

void main() {
  test('recorded fast options use original registry adapter ids', () {
    expect(findAgent('claude')!.fastOption, 'fast');
    expect(findAgent('codex')!.fastOption, 'fast-mode');
    expect(findAgent('gemini')!.fastOption, isNull);
  });

  test(
    'default offering omits only missing own CLIs and preserves catalog order',
    () async {
      final missing = await listedAgents((_) async => null);
      final offered = offeredAgents(missing);
      expect(offered.map((agent) => agent.name), [
        for (final agent in missing)
          if (agent.from != AgentRunner.cli) agent.name,
      ]);
      expect(offered.every((agent) => agent.found == null), isTrue);
      final present = await listedAgents((command) async => '/bin/$command');
      expect(offeredAgents(present), present);
      expect(offeredAgents([]), isEmpty);
    },
  );
  test('the default agent is one chord knows', () {
    expect(findAgent(defaultAgent), isNotNull);
  });

  test(
    "a registry agent says the package and version npx or uvx runs, one of chord's table none",
    () {
      final agoragentic = registered('agoragentic-acp');

      expect(
        findAgent('agoragentic-acp')?.pinned,
        '${agoragentic.package}@${agoragentic.version}',
      );
      expect(findAgent('zeroclaw')?.pinned, isNull);
    },
  );

  test('claude and codex are the short names of the registry ids', () {
    final names = [for (final agent in listAgents()) agent.name];

    expect(names, containsAll(['claude', 'codex']));
    expect(names, isNot(contains('claude-acp')));
    expect(names, isNot(contains('codex-acp')));
    expect(
      findAgent('claude')!.start.command[2],
      '@agentclientprotocol/claude-agent-acp@${registered('claude-acp').version}',
    );
    expect(findAgent('codex')?.title, 'Codex');
  });

  test('kimi is the one name of the registry\'s Kimi Code', () {
    final kimi = registered('kimi-code');
    final names = [for (final agent in listAgents()) agent.name];

    expect(names.where((name) => name == 'kimi'), hasLength(1));
    expect(names, isNot(contains('kimi-code')));
    expect(findAgent('kimi')!.start.command, [
      'npx',
      '-y',
      '${kimi.package}@${kimi.version}',
      ...kimi.args,
    ]);
  });

  test('every other agent is known by its registry id', () {
    final gemini = registered('gemini');

    expect(findAgent('gemini')!.start.command, [
      'npx',
      '-y',
      '@google/gemini-cli@${gemini.version}',
      ...gemini.args,
    ]);
  });

  test('an agent starts through npx at its exact version, with its env', () {
    final droid = registered('factory-droid');
    final start = findAgent('factory-droid')!.start;

    expect(start.env, droid.env);
    expect(
      startLine(start),
      [
        for (final MapEntry(:key, :value) in droid.env.entries) '$key=$value',
        'npx',
        '-y',
        'droid@${droid.version}',
        ...droid.args,
      ].join(' '),
    );

    for (final agent in listAgents()) {
      if (agent.runner == AgentRunner.npx) {
        expect(agent.start.command.take(2), ['npx', '-y'], reason: agent.name);
      }
    }
  });

  test('a uvx agent starts through uvx at its exact version, with its env', () {
    final fast = registered('fast-agent');
    final agent = findAgent('fast-agent')!;

    expect(agent.runner, AgentRunner.uvx);
    expect(agent.start.command, [
      'uvx',
      '${fast.package}@${fast.version}',
      ...fast.args,
    ]);
    expect(agent.start.env, fast.env);
    expect(agent.install, fast.website);
  });

  test('a table agent starts by its own CLI, with no env', () {
    final cursor = findAgent('cursor')!;

    expect(cursor.start.command, ['agent', 'acp']);
    expect(cursor.start.env, isEmpty);
    expect(cursor.runner, AgentRunner.cli);
    expect(cursor.install, 'https://cursor.com/docs/cli/installation');
  });

  test('a name in the registry and the table starts as the registry says', () {
    for (final CliAgent(:name) in cliAgents) {
      final inRegistry = registryAgents.any((agent) => agent.id == name);

      expect(
        findAgent(name)?.runner == AgentRunner.cli,
        !inRegistry,
        reason: name,
      );
    }
  });

  test('the registry lists each agent once', () {
    final names = [for (final agent in listAgents()) agent.name];

    expect(names.toSet(), hasLength(names.length));
  });

  test(
    "cursor-cloud sits among the npx agents in name order, right after codex, given no MCP servers",
    () {
      final names = [for (final agent in listAgents()) agent.name];
      final agent = findAgent('cursor-cloud')!;

      expect(names.indexOf('cursor-cloud'), names.indexOf('codex') + 1);
      expect(agent.title, 'Cursor Cloud Agents');
      expect(agent.runner, AgentRunner.npx);
      expect(agent.pinned, '@chorded/cursor-cloud-acp@0.2.0');
      expect(agent.mcpServers, isFalse);
      expect(agent.start.command, [
        'npx',
        '-y',
        '@chorded/cursor-cloud-acp@0.2.0',
      ]);
      expect(findAgent('openclaw')?.mcpServers, isFalse);
      expect(findAgent('codex')?.mcpServers, isNull);
    },
  );

  test(
    'kiro selects engine v3 and Copilot keeps its id with its full title',
    () {
      expect(findAgent('kiro')!.start.command, [
        'kiro-cli',
        'acp',
        '--agent-engine=v3',
      ]);
      expect(findAgent('github-copilot-cli')?.title, 'GitHub Copilot');
    },
  );

  test('an unknown name is not known', () {
    expect(findAgent('no-such-agent'), isNull);
  });

  test(
    'a command missing from PATH refuses with where to install it',
    () async {
      expect(
        await missingCommand('cursor', has(['npx'])),
        'chord: cursor runs "agent", which is not on PATH; '
        'install it from https://cursor.com/docs/cli/installation',
      );
      expect(await missingCommand('claude', has(['npx'])), isNull);
    },
  );

  test('a missing npx points at Node.js, not at the agent', () async {
    expect(
      await missingCommand('claude', has(['uvx'])),
      'chord: claude runs "npx", which is not on PATH; '
      'npx comes with Node.js: https://nodejs.org/en/download',
    );
  });

  test('a missing uvx points at uv, not at the agent', () async {
    expect(
      await missingCommand('fast-agent', has(['npx'])),
      'chord: fast-agent runs "uvx", which is not on PATH; '
      'uvx comes with uv: https://docs.astral.sh/uv/getting-started/installation/',
    );
  });

  test(
    'a command on PATH, or a name chord does not know, is not refused',
    () async {
      expect(await missingCommand('cursor', has(['agent'])), isNull);
      expect(await missingCommand('no-such-agent', has([])), isNull);
    },
  );

  test('chord agents marks the own CLIs PATH has', () async {
    final listed = await listedAgents(has(['goose']));
    ListedAgent named(String name) =>
        listed.firstWhere((agent) => agent.name == name);

    expect(named('goose').title, 'goose');
    expect(named('goose').start, 'goose acp');
    expect(named('goose').from, AgentRunner.cli);
    expect(named('goose').found, isTrue);
    expect(named('cursor').found, isFalse);
    expect(named('claude').from, AgentRunner.npx);
    expect(named('claude').found, isNull);
    expect(
      named('cursor-cloud').start,
      'npx -y @chorded/cursor-cloud-acp@0.2.0',
    );
    expect(
      [for (final agent in listed) agent.name],
      [for (final agent in listAgents()) agent.name],
    );
  });

  for (final found in [false, true]) {
    test('autohand is listed once, found as PATH says: $found', () async {
      final listed = await listedAgents(has(found ? ['autohand'] : []));
      final rows = listed.where((agent) => agent.name == 'autohand');

      expect(rows, hasLength(1));
      expect(rows.single.title, 'Autohand Code');
      expect(rows.single.start, 'autohand --acp');
      expect(rows.single.from, AgentRunner.cli);
      expect(rows.single.found, found);
    });
  }

  test('chord agents writes name, title, mark and start in columns', () {
    expect(
      agentTable(const [
        ListedAgent(
          name: 'goose',
          title: 'goose',
          start: 'goose acp',
          from: AgentRunner.cli,
          found: true,
        ),
        ListedAgent(
          name: 'cursor',
          title: 'Cursor',
          start: 'agent acp',
          from: AgentRunner.cli,
          found: false,
        ),
        ListedAgent(
          name: 'claude',
          title: 'Claude Agent',
          start: 'npx -y c@1',
          from: AgentRunner.npx,
        ),
        ListedAgent(
          name: 'fast',
          title: 'fast-agent',
          start: 'uvx f@1',
          from: AgentRunner.uvx,
        ),
      ]),
      [
        'goose   goose         own CLI · found        goose acp',
        'cursor  Cursor        own CLI · not on PATH  agent acp',
        'claude  Claude Agent  npx                    npx -y c@1',
        'fast    fast-agent    uvx                    uvx f@1',
      ].join('\n'),
    );
  });

  test('on a terminal, chord agents wraps a long start inside its column', () {
    const listed = [
      ListedAgent(
        name: 'qwen',
        title: 'Qwen Code',
        start: 'npx -y @qwen-code/qwen-code@0.25.0 --acp --experimental-skills',
        from: AgentRunner.npx,
      ),
      ListedAgent(
        name: 'goose',
        title: 'goose',
        start: 'goose acp',
        from: AgentRunner.cli,
        found: true,
      ),
    ];

    expect(
      agentTable(listed, 60),
      [
        'qwen   Qwen Code  npx              npx -y @qwen-code/qwen-co',
        '                                   de@0.25.0 --acp',
        '                                   --experimental-skills',
        'goose  goose      own CLI · found  goose acp',
      ].join('\n'),
    );
    // Piped, one line each, for grep and awk.
    expect(agentTable(listed).split('\n'), hasLength(2));
  });

  test(
    'a narrow terminal leaves the start column no narrower than 20 cells',
    () {
      const listed = [
        ListedAgent(
          name: 'qwen',
          title: 'Qwen Code',
          start: 'npx -y @qwen-code/qwen-code@0.25.0',
          from: AgentRunner.npx,
        ),
      ];

      expect(
        agentTable(listed, 10),
        [
          'qwen  Qwen Code  npx  npx -y @qwen-code/qw',
          '                      en-code@0.25.0',
        ].join('\n'),
      );
    },
  );

  test(
    "chord's own agent is one line, as the original's table gives it",
    () async {
      final row = (await listedAgents(
        has([]),
      )).firstWhere((agent) => agent.name == 'cursor-cloud');

      expect(
        agentTable([row]),
        'cursor-cloud  Cursor Cloud Agents  npx  npx -y @chorded/cursor-cloud-acp@0.2.0',
      );
    },
  );

  group('onPath', () {
    late Directory temp;
    // Each lookup ran the fixture with `dart run`, compiling it again, a
    // few times a case; it is compiled once, and kept, in setUpAll, which
    // is bounded by the test runner's own setUpAll limit, not by a case's.
    late List<String> lookupFixture;
    setUpAll(() {
      lookupFixture = fixtureCommand('test/fixtures/lookup.dart');
    });

    setUp(() => temp = Directory.systemTemp.createTempSync('chord-path-'));
    tearDown(() => temp.deleteSync(recursive: true));

    Directory bin(String name, List<String> commands) {
      final dir = Directory('${temp.path}/$name')..createSync();
      for (final command in commands) {
        File('${dir.path}/$command').writeAsStringSync('#!/bin/sh\n');
        Process.runSync('chmod', ['755', '${dir.path}/$command']);
      }
      return dir;
    }

    Future<String> lookup(
      String how,
      String command,
      Map<String, String> env,
    ) async {
      final result = await Process.run(lookupFixture.first, [
        ...lookupFixture.skip(1),
        how,
        command,
      ], environment: env);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    test(
      'reads the real PATH alone, never process_run\'s own env file',
      () async {
        final path = bin('path', ['chord-fixture-on-path']);
        final elsewhere = bin('elsewhere', ['chord-fixture-elsewhere']);
        final envFile = File('${temp.path}/env.yaml')
          ..writeAsStringSync('path:\n  - ${elsewhere.path}\n');
        final env = {
          'PATH': path.path,
          'TEKARTIK_PROCESS_RUN_USER_ENV_FILE_PATH': envFile.path,
        };

        expect(
          await lookup('ours', 'chord-fixture-on-path', env),
          '${path.path}/chord-fixture-on-path',
        );
        expect(await lookup('ours', 'chord-fixture-elsewhere', env), 'null');
        // process_run's defaults do read the file, so the one above is a real
        // test of it.
        expect(
          await lookup('package', 'chord-fixture-elsewhere', env),
          '${elsewhere.path}/chord-fixture-elsewhere',
        );
      },
    );

    test('passes over a file that is not executable', () async {
      final path = bin('path', []);
      File('${path.path}/chord-fixture-plain').writeAsStringSync('');

      expect(
        await lookup('ours', 'chord-fixture-plain', {'PATH': path.path}),
        'null',
      );
    });
  });

  group('tester: catalog boundaries', () {
    test('unknown and nonexact names never query PATH', () async {
      for (final name in [
        '',
        'Claude',
        'claude ',
        'claude-acp',
        'kimi-code',
        '__proto__',
        'constructor',
        'riff',
      ]) {
        expect(findAgent(name), isNull, reason: name);
        expect(
          await missingCommand(
            name,
            (_) => throw StateError('unknown names must not query PATH'),
          ),
          isNull,
        );
      }
    });

    test(
      'missing command queries the executable rather than the agent name',
      () async {
        for (final entry in {
          'cursor': 'agent',
          'poolside': 'pool',
          'kiro': 'kiro-cli',
          'claude': 'npx',
          'minion-code': 'uvx',
        }.entries) {
          final calls = <String>[];
          expect(
            await missingCommand(entry.key, (command) async {
              calls.add(command);
              return 'fixture-found';
            }),
            isNull,
          );
          expect(calls, [entry.value]);
        }
      },
    );

    test(
      'late PATH answers preserve catalog order and only inspect own CLIs',
      () async {
        final pending = <String, Completer<String?>>{};
        final result = listedAgents((command) {
          final answer = Completer<String?>();
          pending[command] = answer;
          return answer.future;
        });
        final own = listAgents()
            .where((agent) => agent.runner == AgentRunner.cli)
            .toList();
        expect(pending.keys, [
          for (final agent in own) agent.start.command.first,
        ]);
        for (final entry in pending.entries.toList().reversed) {
          entry.value.complete(entry.key == 'agent' ? 'fixture-found' : null);
        }
        final rows = await result;
        expect(
          [for (final row in rows) row.name],
          [for (final agent in listAgents()) agent.name],
        );
        expect(rows.where((row) => row.found == true).map((row) => row.name), [
          'cursor',
        ]);
        expect(
          rows
              .where((row) => row.from != AgentRunner.cli)
              .every((row) => row.found == null),
          isTrue,
        );
      },
    );

    test('availability is looked up afresh on each listing', () async {
      final absent = await listedAgents(has([]));
      final present = await listedAgents((_) async => 'fixture-found');
      expect(
        absent
            .where((row) => row.from == AgentRunner.cli)
            .every((row) => row.found == false),
        isTrue,
      );
      expect(
        present
            .where((row) => row.from == AgentRunner.cli)
            .every((row) => row.found == true),
        isTrue,
      );
    });

    test(
      'empty tables and zero or one column retain the narrow table contract',
      () {
        for (final width in [null, 0, 1, 80, 120]) {
          expect(agentTable([], width), '');
        }
        const rows = [
          ListedAgent(
            name: 'fixture',
            title: 'Fixture',
            start: 'abcdefghijklmnopqrstuvw',
            from: AgentRunner.npx,
          ),
        ];
        expect(agentTable(rows, 0), agentTable(rows, 1));
        expect(agentTable(rows, 0).split('\n'), hasLength(2));
        expect(agentTable(rows, 80), agentTable(rows));
        expect(agentTable(rows, 120), agentTable(rows));
      },
    );
  });
}
