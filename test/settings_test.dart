import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('home is ~, a path under it starts from ~, any other is whole', () {
    expect(homePath('/home/me', '/home/me'), '~');
    expect(homePath('/home/me/', '/home/me'), '~');
    expect(homePath('/home/me/src/app', '/home/me'), '~/src/app');
    expect(homePath('/home/meow', '/home/me'), '/home/meow');
    expect(homePath('/srv/app', '/home/me'), '/srv/app');
    expect(homePath('/srv/app', null), '/srv/app');
  });

  group('tester: home path boundaries', () {
    test('normalizes parent segments before deciding home containment', () {
      expect(
        homePath('/workspace/home/project/../app', '/workspace/home'),
        '~/app',
      );
      expect(
        homePath('/workspace/home/../outside', '/workspace/home'),
        '/workspace/home/../outside',
      );
      expect(homePath('/workspace/home/app', '/workspace/home/'), '~/app');
    });

    test('preserves unicode and the original dot-dot prefix behavior', () {
      expect(homePath('/workspace/home/界😀é', '/workspace/home'), '~/界😀é');
      expect(
        homePath('/workspace/home/..cache', '/workspace/home'),
        '/workspace/home/..cache',
      );
      expect(
        homePath('/workspace/home/..cache', null),
        '/workspace/home/..cache',
      );
    });
  });

  group('tester: CTUI-29 settings recovery and isolation', () {
    SettingsLayer layer(String file, Map<String, Object?> agents) {
      final parsed = parseSettings(file, jsonEncode({'agents': agents}));
      return SettingsLayer(file, parsed.settings, parsed.refused);
    }

    test(
      'model-only overrides preserve a refusal and other agents stay independent',
      () {
        final layers = [
          layer('user', {
            'custom': {'command': null, 'effort': 'low'},
            'other': {
              'command': ['other', ''],
              'model': 'other-model',
            },
          }),
          layer('project', {
            'custom': {'model': 'project-model'},
          }),
        ];
        expect(refusedAgents(layers), {'custom'});
        expect(
          resolveStartup(const Flags(agent: 'custom'), layers, 'fallback'),
          const Startup(
            agent: 'custom',
            refused: Refusal('user', 'expected a string, got null'),
            model: Sourced('project-model', 'project'),
            effort: Sourced('low', 'user'),
          ),
        );
        final other = resolveStartup(
          const Flags(agent: 'other'),
          layers,
          'fallback',
        );
        expect(other.agentCommand, CommandArgv(['other', '']));
        expect(other.model, const Sourced('other-model', 'user'));
        expect(other.refused, isNull);
        expect(
          resolveStartup(
            const Flags(agent: 'custom', agentCommand: 'override'),
            layers,
            'fallback',
          ).refused,
          isNull,
        );
        expect(refusedAgents(layers), {'custom'});
      },
    );

    test(
      'a resumed command survives a local refusal without losing local values',
      () {
        final layers = [
          layer('here', {
            'custom': {'command': false, 'model': 'local'},
          }),
        ];
        final found = Startup(
          agent: 'custom',
          agentCommand: CommandArgv(['saved', '']),
        );
        expect(
          resumedStartup(
            found,
            const Flags(
              agent: 'other',
              agentCommand: 'override',
              effort: 'high',
            ),
            layers,
          ),
          Startup(
            agent: 'custom',
            agentCommand: CommandArgv(['saved', '']),
            model: const Sourced('local', 'here'),
            effort: const Sourced('high', '--effort'),
          ),
        );
      },
    );

    test('many invalid offered names cost only that key', () {
      final parsed = parseSettings(
        'f',
        jsonEncode({
          'offeredAgents': List.filled(1000, null),
          'agent': '界😀é',
          'copyOnSelect': false,
          'agents': {
            '界😀é': {'model': 'kept'},
          },
        }),
      );
      expect(parsed.problems, hasLength(1));
      expect(parsed.problems.single.key, ['offeredAgents']);
      expect(parsed.settings.offeredAgents, isNull);
      expect(parsed.settings.agent, '界😀é');
      expect(parsed.settings.copyOnSelect, isFalse);
      expect(parsed.settings.agents!['界😀é']!.model, 'kept');
    });

    test(
      'file repair, project scoping and deletion are fresh on every read',
      () async {
        final root = Directory.systemTemp.createTempSync('settings-tester-');
        addTearDown(() => root.deleteSync(recursive: true));
        final home = p.join(root.path, 'home');
        final config = p.join(home, 'config');
        final cwd = p.join(root.path, 'work');
        final user = File(userSettingsFile(config)!)
          ..createSync(recursive: true);
        final project = File(p.join(cwd, '.chord', 'settings.json'))
          ..createSync(recursive: true);
        Future<LoadedSettings> load() =>
            loadSettings(configHome: config, cwd: cwd, home: home);
        user.writeAsStringSync(
          jsonEncode({
            'offeredAgents': ['mine', null],
            'copyOnSelect': false,
          }),
        );
        project.writeAsStringSync(
          jsonEncode({
            'offeredAgents': ['project'],
            'agent': 'project',
          }),
        );
        final bad = await load();
        expect(bad.settings.offeredAgents, isNull);
        expect(bad.settings.copyOnSelect, isFalse);
        expect(bad.settings.agent, 'project');
        expect(bad.problems.map((problem) => problem.kind), [
          SettingsProblemKind.validation,
          SettingsProblemKind.scope,
        ]);
        user.writeAsStringSync(
          jsonEncode({
            'offeredAgents': ['b', 'a', 'b'],
            'copyOnSelect': false,
          }),
        );
        project.writeAsStringSync(
          jsonEncode({
            'offeredAgents': [null],
            'agent': 'project',
          }),
        );
        final repaired = await load();
        expect(repaired.settings.offeredAgents, ['b', 'a', 'b']);
        expect(repaired.problems.single.kind, SettingsProblemKind.validation);
        expect(repaired.layers.last.settings.offeredAgents, isNull);
        user.deleteSync();
        project.deleteSync();
        final removed = await load();
        expect(removed.layers, isEmpty);
        expect(removed.problems, isEmpty);
        expect(removed.settings.offeredAgents, isNull);
        expect(removed.settings.copyOnSelect, isNull);
      },
    );

    test(
      'diagnostic deduplication uses file and message even when metadata changes',
      () {
        const old = SettingsProblem(
          'user',
          'same',
          kind: SettingsProblemKind.validation,
          key: ['a'],
        );
        const reread = SettingsProblem(
          'user',
          'same',
          kind: SettingsProblemKind.scope,
          key: ['b'],
        );
        const elsewhere = SettingsProblem('project', 'same');
        const changed = SettingsProblem('user', 'different');
        expect(unseenProblems([old], [reread, elsewhere, changed]), [
          elsewhere,
          changed,
        ]);
      },
    );
  });
  group('files', () {
    test('the config home is XDG_CONFIG_HOME, else ~/.config, else none', () {
      expect(configHome({'XDG_CONFIG_HOME': '/x', 'HOME': '/h'}), '/x');
      expect(configHome({'XDG_CONFIG_HOME': '', 'HOME': '/h'}), '/h/.config');
      expect(configHome({}), isNull);
    });

    test('the user file is under the config home, the project file under '
        'the directory', () {
      expect(settingsFiles(configHome: '/c', cwd: '/w'), [
        '/c/chord/settings.json',
        '/w/.chord/settings.json',
      ]);
      expect(settingsFiles(configHome: null, cwd: '/w'), [
        '/w/.chord/settings.json',
      ]);
    });
  });

  group('parseSettings', () {
    List<String> said(Object? value) => parseSettings(
      'f',
      jsonEncode(value),
    ).problems.map((problem) => problem.message).toList();

    test('each wrong value is named in the original words, and ignored', () {
      final cases = <Object?, List<String>>{
        {'agent': 1}: [
          '"agent": invalid input: expected string, received number, ignored',
        ],
        {'agent': ''}: [
          '"agent": too small: expected string to have >=1 characters, '
              'ignored',
        ],
        // The original adds a zod artifact here; only this line is kept.
        {'agent': []}: [
          '"agent": invalid input: expected string, received array, ignored',
        ],
        {'agent': null}: [
          '"agent": invalid input: expected string, received null, ignored',
        ],
        {'agents': 1}: [
          '"agents": invalid input: expected record, received number, ignored',
        ],
        {'agents': []}: [
          '"agents": invalid input: expected record, received array, ignored',
        ],
        {
          'agents': {'codex': 1},
        }: [
          '"agents.codex": invalid input: expected object, received number, '
              'ignored',
        ],
        {
          'agents': {
            'codex': {'model': true, 'effort': '', 'foo': 1},
          },
        }: [
          '"agents.codex.model": invalid input: expected string, received '
              'boolean, ignored',
          '"agents.codex.effort": too small: expected string to have >=1 '
              'characters, ignored',
          'unknown key "agents.codex.foo", ignored',
        ],
        {
          'agents': {
            'codex': {'mcpServers': 'x'},
          },
        }: [
          '"agents.codex.mcpServers": invalid input: expected boolean, '
              'received string, ignored',
        ],
        {'copyOnSelect': 'x'}: [
          '"copyOnSelect": invalid input: expected boolean, received string, '
              'ignored',
        ],
        {'mouse': 1}: [
          '"mouse": invalid input: expected boolean, received number, ignored',
        ],
        {'theme': 1}: [
          '"theme": invalid option: expected one of "auto"|"dark"|"light"|'
              '"dark-daltonized"|"light-daltonized"|"dark-ansi"|"light-ansi", '
              'ignored',
        ],
        {'editorMode': 'x'}: [
          '"editorMode": invalid option: expected one of "normal"|"vim", '
              'ignored',
        ],
        {'preferredNotifChannel': 'x'}: [
          '"preferredNotifChannel": invalid option: expected one of '
              '"auto"|"bell"|"osc9"|"osc777"|"off", ignored',
        ],
        for (final offered in [
          [],
          'x',
          [1],
          [''],
        ])
          {'offeredAgents': offered}: [
            '"offeredAgents": expected a list of one or more agent names, '
                'ignored',
          ],
        {'mcpServers': []}: [
          '"mcpServers": invalid input: expected record, received array, '
              'ignored',
        ],
        {'teamSelection': 1}: [
          '"teamSelection": invalid input: expected object, received number, '
              'ignored',
        ],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(said(key), value, reason: jsonEncode(key));
      }
    });

    test('problems come in the schema order, unknown keys last as written', () {
      expect(
        said({
          'zz': 1,
          'offeredAgents': 1,
          'agent': 1,
          'mouse': 'x',
          'aa': 2,
          'agents': {
            'b': {'foo': 1, 'model': 1, 'command': 2},
            'a': {'effort': 1},
          },
        }),
        [
          '"agent": invalid input: expected string, received number, ignored',
          '"agents.b.command": expected a string, got a number · b will not '
              'start',
          '"agents.b.model": invalid input: expected string, received number, '
              'ignored',
          'unknown key "agents.b.foo", ignored',
          '"agents.a.effort": invalid input: expected string, received '
              'number, ignored',
          '"mouse": invalid input: expected boolean, received string, ignored',
          '"offeredAgents": expected a list of one or more agent names, '
              'ignored',
          'unknown key "zz", ignored',
          'unknown key "aa", ignored',
        ],
      );
    });

    test('known keys with no effect yet are read without a problem', () {
      final parsed = parseSettings(
        'f',
        jsonEncode({
          'theme': 'dark',
          'editorMode': 'vim',
          'mouse': false,
          'preferredNotifChannel': 'bell',
          'mcpServers': {'x': {}},
          'teamSelection': {'intent': 'balanced'},
          'agents': {
            'codex': {'mcpServers': false},
          },
        }),
      );
      expect(parsed.problems, isEmpty);
      expect(parsed.settings.theme, 'dark');
      expect(parsed.settings.agents!['codex']!.mcpServers, isFalse);
    });

    test('a refused command names why and that its agent will not start', () {
      final cases = <Object?, String>{
        1: 'a number',
        true: 'a boolean',
        null: 'null',
        '': 'an empty string',
        <Object?>[]: 'an empty list',
        ['']: 'a list whose program is empty',
        ['', 'x']: 'a list whose program is empty',
        ['a', 1]: 'a list with something not a string',
        [<Object?>[]]: 'a list with something not a string',
        <String, Object?>{}: 'an object',
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final parsed = parseSettings(
          'f',
          jsonEncode({
            'agents': {
              'codex': {'command': key, 'model': 'm'},
            },
          }),
        );
        expect(parsed.refused, {'codex': 'expected a string, got $value'});
        expect(parsed.problems.map((problem) => problem.message), [
          '"agents.codex.command": expected a string, got $value · codex '
              'will not start',
        ]);
        expect(parsed.settings.agents, {
          'codex': const AgentSettings(model: 'm'),
        });
      }
    });

    test('a command is a line or the program and its arguments', () {
      final parsed = parseSettings(
        'f',
        jsonEncode({
          'agents': {
            'a': {'command': 'a --acp'},
            'b': {
              'command': ['b', ''],
            },
          },
          'offeredAgents': ['a', 'a'],
          'copyOnSelect': false,
        }),
      );
      expect(parsed.problems, isEmpty);
      expect(parsed.refused, isEmpty);
      expect(parsed.settings.agents, {
        'a': const AgentSettings(command: CommandLine('a --acp')),
        'b': AgentSettings(command: CommandArgv(['b', ''])),
      });
      expect(parsed.settings.offeredAgents, ['a', 'a']);
      expect(parsed.settings.copyOnSelect, isFalse);
    });

    test('text that is not a JSON object counts for nothing', () {
      for (final text in ['[]', '1', '"x"', 'null']) {
        final parsed = parseSettings('f', text);
        expect(_isEmpty(parsed.settings), isTrue);
        expect(parsed.problems, [
          const SettingsProblem(
            'f',
            'not a JSON object; the file is ignored',
            kind: SettingsProblemKind.parse,
          ),
        ]);
      }
      final broken = parseSettings('f', '{').problems.single;
      expect(broken.kind, SettingsProblemKind.parse);
      expect(broken.message, startsWith('not valid JSON ('));
      expect(broken.message, endsWith('); the file is ignored'));
    });
  });

  test('later settings win key by key, agent by agent, server by server', () {
    final merged = mergeSettings([
      Settings(
        agent: 'codex',
        agents: {
          'fake': AgentSettings(
            command: const CommandLine('fake --acp'),
            model: 'large',
            effort: 'low',
          ),
        },
        mcpServers: {'a': 1, 'b': 1},
        offeredAgents: const ['a', 'b'],
        copyOnSelect: false,
      ),
      Settings(
        agent: 'fake',
        agents: {'fake': const AgentSettings(effort: 'high')},
        mcpServers: {'b': 2},
        offeredAgents: const ['c'],
      ),
    ]);
    expect(merged.agent, 'fake');
    expect(merged.agents, {
      'fake': const AgentSettings(
        command: CommandLine('fake --acp'),
        model: 'large',
        effort: 'high',
      ),
    });
    expect(merged.mcpServers, {'a': 1, 'b': 2});
    expect(merged.offeredAgents, ['c']);
    expect(merged.copyOnSelect, isFalse);
  });

  group('loadSettings', () {
    late Directory root;
    late String config, cwd, home;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-settings-');
      home = p.join(root.path, 'home');
      config = p.join(home, '.config');
      cwd = p.join(root.path, 'work');
    });
    tearDown(() => root.deleteSync(recursive: true));

    void place({Object? user, Object? project}) {
      for (final (file, value) in [
        (p.join(config, 'chord', 'settings.json'), user),
        (p.join(cwd, '.chord', 'settings.json'), project),
      ]) {
        if (value == null) continue;
        File(file)
          ..createSync(recursive: true)
          ..writeAsStringSync(value is String ? value : jsonEncode(value));
      }
    }

    Future<LoadedSettings> load() =>
        loadSettings(configHome: config, cwd: cwd, home: home);

    test(
      'a missing file is no problem, and no file leaves the defaults',
      () async {
        final loaded = await load();
        expect(_isEmpty(loaded.settings), isTrue);
        expect(loaded.layers, isEmpty);
        expect(loaded.problems, isEmpty);
        place(project: {'agent': 'fake'});
        expect((await load()).settings.agent, 'fake');
        expect(
          (await loadSettings(configHome: null, cwd: cwd)).settings.agent,
          'fake',
        );
      },
    );

    test('the project file overrides the user file, and a flag both', () async {
      place(
        user: {
          'agent': 'codex',
          'agents': {
            'fake': {
              'command': 'fake --acp',
              'model': 'large',
              'effort': 'low',
              'permissionMode': 'acceptEdits',
            },
          },
        },
        project: {
          'agent': 'fake',
          'agents': {
            'fake': {'effort': 'high', 'permissionMode': 'plan'},
          },
        },
      );
      final loaded = await load();
      final [user, project] = settingsFiles(configHome: config, cwd: cwd);
      expect(loaded.problems, isEmpty);
      expect(loaded.settings.agents, {
        'fake': const AgentSettings(
          command: CommandLine('fake --acp'),
          model: 'large',
          effort: 'high',
          permissionMode: 'plan',
        ),
      });
      expect(
        resolveStartup(const Flags(), loaded.layers, 'claude'),
        Startup(
          agent: 'fake',
          agentCommand: const CommandLine('fake --acp'),
          model: Sourced('large', user),
          effort: Sourced('high', project),
          permissionMode: Sourced('plan', project),
        ),
      );
      expect(
        resolveStartup(
          const Flags(
            permissionMode: 'default',
            model: 'small',
            effort: 'max',
            agentCommand: 'other',
          ),
          loaded.layers,
          'claude',
        ),
        const Startup(
          agent: 'fake',
          agentCommand: CommandLine('other'),
          model: Sourced('small', '--model'),
          effort: Sourced('max', '--effort'),
          permissionMode: Sourced('default', '--permission-mode'),
        ),
      );
    });

    test(
      "user-only keys in the project's file are problems, left out",
      () async {
        place(
          user: {'theme': 'dark'},
          project: {
            'theme': 'light',
            'editorMode': 'vim',
            'mouse': false,
            'copyOnSelect': false,
            'offeredAgents': ['codex'],
            'agent': 'codex',
          },
        );
        final loaded = await load();
        expect(loaded.settings.theme, 'dark');
        expect(loaded.settings.copyOnSelect, isNull);
        expect(loaded.settings.offeredAgents, isNull);
        expect(loaded.settings.agent, 'codex');
        expect(
          loaded.problems.map((problem) => (problem.kind, problem.message)),
          [
            for (final key in [
              'theme',
              'editorMode',
              'mouse',
              'copyOnSelect',
              'offeredAgents',
            ])
              (
                SettingsProblemKind.scope,
                '"$key" is read only from ~/.config/chord/settings.json, '
                    'ignored',
              ),
          ],
        );
        final none = await loadSettings(configHome: null, cwd: cwd);
        expect(
          none.problems.first.message,
          '"theme" is read only from the user\'s settings file, ignored',
        );
      },
    );

    test(
      'a malformed byte is replaced, and the other file still counts',
      () async {
        final user = File(p.join(config, 'chord', 'settings.json'))
          ..createSync(recursive: true);
        user.writeAsBytesSync([
          ...utf8.encode('{"agent": "co'),
          0xff,
          ...utf8.encode('dex"}'),
        ]);
        place(
          project: {
            'agents': {
              'fake': {'model': 'm'},
            },
          },
        );
        final loaded = await load();
        expect(loaded.settings.agent, 'co\uFFFDdex');
        expect(loaded.settings.agents!['fake']!.model, 'm');
        expect(loaded.layers, hasLength(2));
      },
    );

    test('a malformed or unreadable file is named and ignored, the other '
        'still counts', () async {
      place(user: '{', project: {'agent': 'fake'});
      final loaded = await load();
      expect(loaded.settings.agent, 'fake');
      expect(loaded.problems.single.message, startsWith('not valid JSON ('));
      File(p.join(cwd, '.chord', 'settings.json')).deleteSync();
      Directory(p.join(cwd, '.chord', 'settings.json')).createSync();
      final unreadable = (await load()).problems.last;
      expect(unreadable.kind, SettingsProblemKind.read);
      expect(unreadable.message, startsWith('cannot be read ('));
      expect(unreadable.message, endsWith('); the file is ignored'));
    });
  });

  group('startup', () {
    test("an agent named on the command line takes that agent's settings", () {
      const layers = [
        SettingsLayer(
          'f',
          Settings(
            agent: 'fake',
            agents: {
              'fake': AgentSettings(permissionMode: 'plan'),
              'codex': AgentSettings(model: 'o3'),
            },
          ),
        ),
      ];
      expect(
        resolveStartup(const Flags(agent: 'codex'), layers, 'claude'),
        const Startup(agent: 'codex', model: Sourced('o3', 'f')),
      );
      expect(
        resolveStartup(const Flags(), const [], 'claude'),
        const Startup(agent: 'claude'),
      );
    });

    test('a refused command refuses its agent unless a later file or a flag '
        'gives one', () {
      const refusedIn = SettingsLayer(
        'p',
        Settings(agents: {'codex': AgentSettings()}),
        {'codex': 'expected a string, got a number'},
      );
      const good = SettingsLayer(
        'u',
        Settings(agents: {'codex': AgentSettings(command: CommandLine('c'))}),
      );
      expect(
        resolveStartup(const Flags(agent: 'codex'), const [
          good,
          refusedIn,
        ], 'claude'),
        const Startup(
          agent: 'codex',
          refused: Refusal('p', 'expected a string, got a number'),
        ),
      );
      expect(refusedAgents(const [good, refusedIn]), {'codex'});
      expect(refusedAgents(const [refusedIn, good]), isEmpty);
      expect(
        resolveStartup(const Flags(agent: 'codex'), const [
          refusedIn,
          good,
        ], 'claude'),
        const Startup(agent: 'codex', agentCommand: CommandLine('c')),
      );
      expect(
        resolveStartup(
          const Flags(agent: 'codex', agentCommand: 'mine'),
          const [refusedIn],
          'claude',
        ),
        const Startup(agent: 'codex', agentCommand: CommandLine('mine')),
      );
      expect(
        refusalLine(
          'codex',
          const Refusal(
            '/w/.chord/settings.json',
            'expected a string, got a number',
          ),
          cwd: '/w',
          home: '/h',
        ),
        'codex not started: agents.codex.command in .chord/settings.json: '
        'expected a string, got a number',
      );
    });

    test('a resumed session keeps its agent and command, the files here '
        'give the rest', () {
      final found = Startup(
        agent: 'fake',
        agentCommand: CommandArgv(['fake', '--acp']),
      );
      const here = [
        SettingsLayer(
          'p',
          Settings(
            agent: 'codex',
            agents: {
              'fake': AgentSettings(
                command: CommandLine('other'),
                model: 'm',
                effort: 'e',
              ),
            },
          ),
        ),
      ];
      expect(
        resumedStartup(found, const Flags(effort: 'max'), here),
        Startup(
          agent: 'fake',
          agentCommand: CommandArgv(['fake', '--acp']),
          model: const Sourced('m', 'p'),
          effort: const Sourced('max', '--effort'),
        ),
      );
    });

    test('the agents a window can open: its own, the files\' commands, then '
        'the registry\'s, each once', () {
      const layers = [
        SettingsLayer(
          'u',
          Settings(agents: {'mine': AgentSettings(command: CommandLine('a'))}),
        ),
        SettingsLayer(
          'f',
          Settings(
            agents: {
              'mine': AgentSettings(command: CommandLine('b')),
              'fake2': AgentSettings(command: CommandLine('fake2 --acp')),
              'claude': AgentSettings(command: CommandLine('my-claude')),
              'codex': AgentSettings(model: 'o3'),
            },
          ),
        ),
      ];
      expect(agentCommands(layers), {
        'mine': const CommandLine('b'),
        'fake2': const CommandLine('fake2 --acp'),
        'claude': const CommandLine('my-claude'),
      });
      expect(
        knownAgents(const Startup(agent: 'fake'), layers, ['claude', 'codex']),
        ['fake', 'mine', 'fake2', 'claude', 'codex'],
      );
    });
  });

  test('commands and startups compare by their shape, not their display', () {
    expect(CommandArgv(['a, b']), isNot(CommandArgv(['a', 'b'])));
    expect(CommandArgv(['a', 'b']), CommandArgv(['a', 'b']));
    expect(const CommandLine('a b'), isNot(CommandArgv(['a b'])));
    expect(
      Startup(agent: 'x', agentCommand: CommandArgv(['a, b'])),
      isNot(Startup(agent: 'x', agentCommand: CommandArgv(['a', 'b']))),
    );
    expect(
      const SettingsProblem('f', 'm', key: ['a.b']),
      isNot(const SettingsProblem('f', 'm', key: ['a', 'b'])),
    );
  });

  group('lines', () {
    test('paths show from the directory or ~, never the home path', () {
      expect(
        shownPath('/w/.chord/settings.json', cwd: '/w', home: '/h'),
        '.chord/settings.json',
      );
      expect(
        shownPath('/h/.config/chord/settings.json', cwd: '/w', home: '/h'),
        '~/.config/chord/settings.json',
      );
      expect(shownPath('/etc/x', cwd: '/w', home: '/h'), '/etc/x');
      expect(setWhere('--model', cwd: '/w', home: '/h'), 'set by --model');
      expect(
        setWhere('/h/.config/chord/settings.json', cwd: '/w', home: '/h'),
        'set in ~/.config/chord/settings.json',
      );
    });

    test('a problem as the transcript and stderr say it, each once', () {
      const problem = SettingsProblem(
        '/h/.config/chord/settings.json',
        'unknown key "colour", ignored',
      );
      expect(
        problemNote(problem, cwd: '/w', home: '/h'),
        '~/.config/chord/settings.json: unknown key "colour", ignored',
      );
      expect(
        problemLine(problem),
        'chord: /h/.config/chord/settings.json: unknown key "colour", ignored',
      );
      const project = SettingsProblem('p', 'unknown key "y", ignored');
      expect(unseenProblems(const [problem], const [problem, project]), [
        project,
      ]);
      expect(unknownOffered('u', ['cdex', 'codx']).map((p) => p.message), [
        '"offeredAgents": no agent named cdex, left out',
        '"offeredAgents": no agent named codx, left out',
      ]);
    });
  });
}

bool _isEmpty(Settings s) =>
    s.agent == null &&
    s.agents == null &&
    s.teamSelection == null &&
    s.mcpServers == null &&
    s.preferredNotifChannel == null &&
    s.theme == null &&
    s.editorMode == null &&
    s.mouse == null &&
    s.copyOnSelect == null &&
    s.offeredAgents == null;
