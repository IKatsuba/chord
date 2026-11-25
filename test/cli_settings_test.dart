// The settings files as a call to chord reads them: problems, the default
// agent, settings commands, starting values and refusals, all in temporary
// directories with an injected environment.
import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/notify.dart' show NotifChannel;
import 'package:chord/session/sessions.dart';
import 'package:chord/settings.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A temporary home with chord's config under it and a project directory.
class _Place {
  _Place() {
    root = Directory.systemTemp.createTempSync('chord-cli-settings-');
    home = p.join(root.path, 'home');
    work = p.join(home, 'src', 'app');
    Directory(work).createSync(recursive: true);
  }

  late final Directory root;
  late final String home, work;

  String get userFile => p.join(home, '.config', 'chord', 'settings.json');
  String projectFile([String? dir]) =>
      p.join(dir ?? work, '.chord', 'settings.json');

  void write(String file, Object? value) => File(file)
    ..createSync(recursive: true)
    ..writeAsStringSync(value is String ? value : jsonEncode(value));

  final stdout = StringBuffer(), stderr = StringBuffer();
  List<ListedAgent>? catalog;
  List<String>? offeredSetting;
  String? preferred;

  Future<CliOutcome> call(
    List<String> args, {
    bool tty = false,
    String? pick,
    List<SessionRecord> records = const [],
    void Function(Settings)? onSettings,
  }) => runCli(
    args,
    stdout: stdout,
    stderr: stderr,
    cwd: work,
    home: home,
    environment: {'HOME': home},
    stdinTTY: tty,
    stdoutTTY: tty,
    lookup: (command) async => '/bin/$command',
    readSessionRecords: () async => records,
    onSettings: onSettings,
    pickAgent:
        ({
          required agents,
          required version,
          required directory,
          required preferred,
          required offered,
        }) async {
          catalog = agents;
          offeredSetting = offered;
          this.preferred = preferred;
          return pick;
        },
  );
}

void main() {
  late _Place place;
  setUp(() => place = _Place());
  tearDown(() => place.root.deleteSync(recursive: true));

  group('tester: CTUI-29 CLI settings boundaries', () {
    test(
      'XDG config overrides HOME and command argv bypasses PATH discovery',
      () async {
        final config = p.join(place.root.path, 'xdg');
        place.write(place.userFile, {
          'agents': {
            'custom': {'command': 'wrong'},
          },
        });
        place.write(p.join(config, 'chord', 'settings.json'), {
          'agents': {
            'custom': {
              'command': ['界😀é agent', '', r'$HOME'],
              'model': 'kept',
            },
          },
        });
        var looked = 0;
        final outcome = await runCli(
          ['custom'],
          stdout: place.stdout,
          stderr: place.stderr,
          cwd: place.work,
          home: place.home,
          environment: {
            'HOME': place.home,
            'XDG_CONFIG_HOME': config,
            'XDG_STATE_HOME': p.join(place.root.path, 'state'),
          },
          lookup: (_) async {
            looked++;
            return null;
          },
        );
        expect(outcome.code, 0);
        expect(agentStart(outcome.launch!).command, [
          '界😀é agent',
          '',
          r'$HOME',
        ]);
        expect(outcome.launch!.starting.model!.id, 'kept');
        expect(looked, 0);
      },
    );

    test(
      'resume preserves the invoking command but reads target model and deduplicates user warnings',
      () async {
        final other = p.join(place.root.path, 'elsewhere');
        place.write(place.userFile, {'unknown': true});
        place.write(place.projectFile(), {
          'agents': {
            'custom': {
              'command': ['here', ''],
              'model': 'here',
            },
          },
        });
        place.write(place.projectFile(other), {
          'agents': {
            'custom': {
              'command': ['there'],
              'model': 'there',
            },
          },
          'unexpected': true,
        });
        final launch = (await place.call(
          ['--resume', 'saved'],
          records: [
            SessionRecord(
              path: 'records/saved.jsonl',
              sessionId: 'saved',
              prompt: 'saved prompt',
              agent: 'custom',
              cwd: other,
              lastUsedAt: 1,
            ),
          ],
        )).launch!;
        expect(agentStart(launch).command, ['here', '']);
        expect(launch.starting.model!.id, 'there');
        expect(launch.starting.model!.from, 'set in .chord/settings.json');
        expect(
          launch.warnings.where(
            (warning) => warning.contains('unknown key "unknown"'),
          ),
          hasLength(1),
        );
        expect(
          launch.warnings.where(
            (warning) => warning.contains('unknown key "unexpected"'),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'help and invalid syntax do not read or report settings problems',
      () async {
        place.write(place.userFile, '{');
        expect((await place.call(['--help'])).code, 0);
        expect(place.stderr.toString(), isEmpty);
        expect((await place.call(['--not-an-option'])).code, 2);
        expect(place.stderr.toString(), isNot(contains('not valid JSON')));
      },
    );
  });
  test('problems go to stderr naming the file, and to the window from ~ or '
      'the directory', () async {
    place.write(place.userFile, {'colour': 'red'});
    place.write(place.projectFile(), {'theme': 'dark'});
    final launch = (await place.call(['claude'])).launch!;
    expect(place.stderr.toString().split('\n').where((l) => l.isNotEmpty), [
      'chord: ${place.userFile}: unknown key "colour", ignored',
      'chord: ${place.projectFile()}: "theme" is read only from '
          '~/.config/chord/settings.json, ignored',
    ]);
    expect(launch.warnings, [
      '~/.config/chord/settings.json: unknown key "colour", ignored',
      '.chord/settings.json: "theme" is read only from '
          '~/.config/chord/settings.json, ignored',
    ]);
  });

  test('the keybindings file is read for the window: its problems on stderr '
      'and in the transcript, counted for the status line', () async {
    final none = (await place.call(['claude'])).launch!;
    expect(none.keysFailed, isNull);
    expect(none.keymap, defaultKeymap);

    final file = p.join(place.home, '.config', 'chord', 'keybindings.json');
    place.write(file, {
      'bindings': [
        {'context': 'Nope', 'bindings': {}},
        {
          'context': 'Chat',
          'bindings': {'ctrl+s': 'chat:submit', 'ctrl+c': null},
        },
      ],
    });
    place.stderr.clear();
    final launch = (await place.call(['claude'])).launch!;
    expect(place.stderr.toString().split('\n').where((l) => l.isNotEmpty), [
      'chord: $file: unknown context "Nope", ignored',
      'chord: $file: ctrl+c cannot be rebound, ignored',
    ]);
    expect(launch.warnings, [
      '~/.config/chord/keybindings.json: unknown context "Nope", ignored',
      '~/.config/chord/keybindings.json: ctrl+c cannot be rebound, ignored',
    ]);
    expect(
      launch.keysFailed,
      'keybindings.json: 2 problems · unknown context "Nope", ignored',
    );
    expect(
      bound(launch.keymap!, 'chat:submit', parseSequence('ctrl+s').value),
      isTrue,
    );
  });

  test('the keybindings file is read once, before the start picker, and '
      'the window takes the same keymap', () async {
    final file = p.join(place.home, '.config', 'chord', 'keybindings.json');
    place.write(file, {
      'bindings': [
        {
          'context': 'Select',
          'bindings': {'q': 'select:cancel'},
        },
      ],
    });
    final seen = <Keybindings>[];
    var picked = false;
    final outcome = await runCli(
      const [],
      stdout: place.stdout,
      stderr: place.stderr,
      cwd: place.work,
      home: place.home,
      environment: {'HOME': place.home},
      stdinTTY: true,
      stdoutTTY: true,
      lookup: (command) async => '/bin/$command',
      readSessionRecords: () async => const [],
      onKeymap: (keymap) {
        expect(picked, isFalse, reason: 'the keymap comes before the picker');
        seen.add(keymap);
      },
      pickAgent:
          ({
            required agents,
            required version,
            required directory,
            required preferred,
            required offered,
          }) async {
            picked = true;
            return 'claude';
          },
    );
    expect(picked, isTrue);
    expect(seen, isNotEmpty);
    expect(seen.every((each) => identical(each, seen.first)), isTrue);
    expect(outcome.launch?.keymap, same(seen.first));
    expect(
      bound(seen.first, 'select:cancel', parseSequence('q').value),
      isTrue,
    );
  });

  test('"mouse": false is read from the user\'s file alone, before any '
      'picker takes the terminal', () async {
    Settings? seen;
    await place.call(['claude'], onSettings: (s) => seen = s);
    expect(seen?.mouse, isNull);
    place.write(place.projectFile(), {'mouse': false});
    await place.call(['claude'], onSettings: (s) => seen = s);
    expect(seen?.mouse, isNull);
    place.write(place.userFile, {'mouse': false});
    var picked = false;
    final picking = runCli(
      const [],
      stdout: place.stdout,
      stderr: place.stderr,
      cwd: place.work,
      home: place.home,
      environment: {'HOME': place.home},
      stdinTTY: true,
      stdoutTTY: true,
      lookup: (command) async => '/bin/$command',
      readSessionRecords: () async => const [],
      onSettings: (s) {
        seen = s;
        expect(picked, isFalse);
      },
      pickAgent:
          ({
            required agents,
            required version,
            required directory,
            required preferred,
            required offered,
          }) async {
            picked = true;
            return null;
          },
    );
    await picking;
    expect(picked, isTrue);
    expect(seen?.mouse, isFalse);
  });

  test(
    "vim mode starts as the user's file keeps it, and /vim saves there",
    () async {
      final off = (await place.call(['claude'])).launch!;
      expect(off.vim, isFalse);
      expect(off.settingsFile, place.userFile);
      expect(off.shownSettingsFile, '~/.config/chord/settings.json');
      expect(off.theme, isNull);
      place.write(place.userFile, {'editorMode': 'vim', 'theme': 'light'});
      final on = (await place.call(['claude'])).launch!;
      expect(on.vim, isTrue);
      expect(on.theme, 'light');
    },
  );

  test('the agent setting is the default and the picker\'s first highlight; '
      'the project\'s wins', () async {
    place.write(place.userFile, {'agent': 'codex'});
    expect((await place.call([])).launch!.name, 'codex');
    place.write(place.projectFile(), {'agent': 'gemini'});
    expect((await place.call([])).launch!.name, 'gemini');
    final picked = await place.call([], tty: true, pick: 'claude');
    expect(place.preferred, 'gemini');
    expect(picked.launch!.name, 'claude');
    expect((await place.call(['claude'])).launch!.name, 'claude');
  });

  test('a settings command starts its agent, and names only settings define '
      'are listed and startable', () async {
    place.write(place.userFile, {
      'agents': {
        'claude': {'command': 'my-claude --acp'},
        'mine': {
          'command': ['my agent', '--acp', ''],
        },
      },
    });
    final claude = (await place.call(['claude'])).launch!;
    expect(claude.command, const CommandLine('my-claude --acp'));
    expect(agentStart(claude).command, 'my-claude --acp');
    expect(agentStart(claude).env, isEmpty);
    final mine = (await place.call(['mine'])).launch!;
    expect(mine.agent, isNull);
    expect(agentStart(mine).command, ['my agent', '--acp', '']);
    await place.call([], tty: true);
    expect(
      place.catalog!.map((a) => (a.name, a.title, a.start, a.from)),
      containsAll([
        ('claude', 'Claude Agent', 'my-claude --acp', AgentRunner.settings),
        ('mine', null, "'my agent' --acp ''", AgentRunner.settings),
      ]),
    );
    place.stdout.clear();
    await place.call(['agents']);
    final rows = place.stdout.toString().split('\n');
    expect(
      rows.firstWhere((row) => row.startsWith('mine ')),
      matches(RegExp(r"^mine +from settings +settings +'my agent' --acp ''$")),
    );
    expect(
      rows.firstWhere((row) => row.startsWith('claude ')),
      matches(RegExp(r'^claude +Claude Agent +settings +my-claude --acp$')),
    );
  });

  test('starting values: a flag beats the project, which beats the user, '
      'each with where it was set', () async {
    place.write(place.userFile, {
      'agents': {
        'claude': {'model': 'opus', 'effort': 'low'},
      },
    });
    place.write(place.projectFile(), {
      'agents': {
        'claude': {'effort': 'high', 'permissionMode': 'acceptEdits'},
      },
    });
    final launch = (await place.call([
      'claude',
      '--permission-mode',
      'plan',
    ])).launch!;
    final s = launch.starting;
    expect(
      (s.model!.id, s.model!.from),
      ('opus', 'set in ~/.config/chord/settings.json'),
    );
    expect(
      (s.effort!.id, s.effort!.from),
      ('high', 'set in .chord/settings.json'),
    );
    expect((s.mode!.id, s.mode!.from), ('plan', 'set by --permission-mode'));
    final flagged = (await place.call([
      'claude',
      '-m',
      'sonnet',
      '--effort',
      'max',
    ])).launch!.starting;
    expect(
      (flagged.model!.id, flagged.model!.from),
      ('sonnet', 'set by --model'),
    );
    expect(flagged.effort!.from, 'set by --effort');
    // Another agent's settings are not this one's.
    expect((await place.call(['codex'])).launch!.starting.model, isNull);
  });

  test('a refused command stops its agent with the original line, unless '
      '--agent-command gives one', () async {
    place.write(place.projectFile(), {
      'agents': {
        'claude': {'command': 1},
      },
    });
    final call = await place.call(['claude']);
    expect(call.code, 1);
    expect(call.launch, isNull);
    expect(
      place.stderr.toString().trim().split('\n').last,
      'chord: claude not started: agents.claude.command in '
      '.chord/settings.json: expected a string, got a number',
    );
    final flagged = await place.call(['claude', '--agent-command', 'x --acp']);
    expect(flagged.launch!.command, const CommandLine('x --acp'));
    expect(flagged.launch!.agentCommand, 'x --acp');
  });

  test(
    'a resumed session\'s directory gives its own settings and refusals',
    () async {
      final other = p.join(place.home, 'elsewhere');
      place.write(place.projectFile(other), {
        'agents': {
          'claude': {'model': 'there', 'command': false},
        },
      });
      final records = [
        SessionRecord(
          path: 'records/s1.jsonl',
          sessionId: 's1',
          agent: 'claude',
          cwd: other,
          lastUsedAt: 1,
          prompt: 'saved',
        ),
      ];
      final refused = await place.call(['--resume', 's1'], records: records);
      expect(refused.code, 1);
      expect(
        place.stderr.toString().trim().split('\n').last,
        'chord: claude not started: agents.claude.command in '
        '.chord/settings.json: expected a string, got a boolean',
      );
      place.write(place.projectFile(other), {
        'agents': {
          'claude': {'model': 'there'},
        },
      });
      final launch = (await place.call([
        '--resume',
        's1',
      ], records: records)).launch!;
      expect(launch.directory, '~/elsewhere');
      expect(
        (launch.starting.model!.id, launch.starting.model!.from),
        ('there', 'set in .chord/settings.json'),
      );
    },
  );

  test('preferredNotifChannel comes from the settings files, auto by '
      'default', () async {
    expect(
      (await place.call(['claude'])).launch!.notifChannel,
      NotifChannel.auto,
    );
    place.write(place.userFile, {'preferredNotifChannel': 'osc777'});
    expect(
      (await place.call(['claude'])).launch!.notifChannel,
      NotifChannel.osc777,
    );
    place.write(place.projectFile(), {'preferredNotifChannel': 'off'});
    expect(
      (await place.call(['claude'])).launch!.notifChannel,
      NotifChannel.off,
    );
  });

  test('copyOnSelect comes from the user file alone, on by default', () async {
    expect((await place.call(['claude'])).launch!.copyOnSelect, isTrue);
    place.write(place.projectFile(), {'copyOnSelect': false});
    expect((await place.call(['claude'])).launch!.copyOnSelect, isTrue);
    place.write(place.userFile, {'copyOnSelect': false});
    expect((await place.call(['claude'])).launch!.copyOnSelect, isFalse);
  });

  test('the starting flags are the window\'s, in the original words, and '
      '`agents` takes none of them', () async {
    // The columns widen with the longest option; the words stay.
    for (final (option, words) in [
      ('  -m, --model=<model>', "on this model, by its id for it."),
      ('      --effort=<effort>', 'on this effort, by its id for it.'),
      ('      --permission-mode=<mode>', 'in this mode, by its id for it.'),
    ]) {
      expect(
        chordHelp.split('\n'),
        contains(
          matches(
            RegExp(
              '^${RegExp.escape(option)} +'
              "${RegExp.escape("Start each of [agent]'s sessions $words")}\$",
            ),
          ),
        ),
      );
    }
    // The nearest option of agents' own, as the original's Cliffy says.
    const nearest = {
      '-m': '-h',
      '--model': '--help',
      '--effort': '--json',
      '--permission-mode': '--json',
    };
    for (final flag in nearest.keys) {
      place.stderr.clear();
      final call = await place.call(['agents', flag, 'x']);
      expect(call.code, 2);
      expect(
        place.stderr.toString(),
        '\n  error: Unknown option "$flag". '
        'Did you mean option "${nearest[flag]}"?\n\n',
      );
    }
  });
  test('offeredAgents goes to the picker, and a name chord lacks is a '
      'problem of the user\'s file', () async {
    place.write(place.userFile, {
      'offeredAgents': ['codex', 'nope', 'claude'],
    });
    final call = await place.call([], tty: true, pick: 'codex');
    expect(place.offeredSetting, ['codex', 'nope', 'claude']);
    expect(
      place.stderr.toString().trim(),
      'chord: ${place.userFile}: "offeredAgents": no agent named nope, left '
      'out',
    );
    expect(call.launch!.warnings, [
      '~/.config/chord/settings.json: "offeredAgents": no agent named nope, '
          'left out',
    ]);
    place.root.deleteSync(recursive: true);
    place = _Place();
    place.write(place.projectFile(), {
      'offeredAgents': ['nope'],
    });
    await place.call([], tty: true, pick: 'codex');
    expect(place.offeredSetting, isNull);
  });

  test(
    'the window takes the directory\'s MCP servers, shown from ~ or the '
    'directory, what the files lost, and whether its agent takes none',
    () async {
      place.write(place.userFile, {
        'mcpServers': {
          'docs': {'type': 'http', 'url': 'https://docs.example/mcp'},
        },
        'agents': {
          'claude': {'mcpServers': false},
        },
      });
      place.write(p.join(place.work, '.mcp.json'), {
        'mcpServers': {
          'files': {'command': 'files-mcp'},
          'broken': {'command': 3},
        },
      });
      final launch = (await place.call(['claude'])).launch!;
      expect(
        [for (final d in launch.mcpServers) '${d.server['name']} ${d.from}'],
        ['docs ~/.config/chord/settings.json', 'files .mcp.json'],
      );
      expect(launch.mcpIgnored.single.from, '.mcp.json');
      expect(launch.mcpIgnored.single.servers, 1);
      expect(launch.noMcpServers, isTrue);
      expect(launch.noMcpServersFrom, place.userFile);
      expect(launch.warnings, [
        '.mcp.json: "mcpServers.broken.command": invalid input: expected '
            'string, received number; the server is ignored',
      ]);
      expect(place.stderr.toString(), contains('mcpServers.broken.command'));

      final flagged = (await place.call(['codex', '--no-mcp-servers'])).launch!;
      expect(flagged.noMcpServers, isTrue);
      expect(flagged.noMcpServersFrom, '--no-mcp-servers');
      final takes = (await place.call(['codex'])).launch!;
      expect(takes.noMcpServers, isFalse);
    },
  );
}
