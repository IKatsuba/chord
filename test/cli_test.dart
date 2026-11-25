import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/version.dart';
import 'package:test/test.dart';

/// A call to chord, with what it printed.
class Call {
  Call(this.outcome, this.stdout, this.stderr);

  final CliOutcome outcome;
  final String stdout;
  final String stderr;
}

/// A lookup that finds only [commands].
Lookup has(Iterable<String> commands) =>
    (command) async => commands.contains(command) ? '/bin/$command' : null;

Future<Call> chord(
  List<String> args, {
  Lookup? lookup,
  String cwd = '/home/me/src/app',
  int? columns,
}) async {
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final outcome = await runCli(
    args,
    stdout: stdout,
    stderr: stderr,
    cwd: cwd,
    home: '/home/me',
    columns: columns,
    lookup: lookup ?? has(['npx', 'uvx']),
  );

  return Call(outcome, '$stdout', '$stderr');
}

/// Expects [call] refused as the original's Cliffy refuses: [help] on stdout,
/// [message] on stderr between blank lines, exit 2.
void refused(Call call, String message, {String? help}) {
  expect(call.outcome.code, 2);
  expect(call.outcome.launch, isNull);
  expect(call.stdout, '${help ?? chordHelp}\n');
  expect(call.stderr, '\n  error: $message\n\n');
}

void main() {
  group('tester CTUI-45: agentStart boundaries', () {
    Launch launch({KnownAgent? agent, String? override}) => Launch(
      name: agent?.name ?? 'fixture-unknown',
      agent: agent,
      agentCommand: override,
      version: 'test',
      directory: '.',
    );

    test('unknown launch without an override fails with its name', () {
      expect(
        () => agentStart(launch()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Unknown agent "fixture-unknown".',
          ),
        ),
      );
    });

    test('unknown launch accepts a literal override including empty text', () {
      for (final command in [
        '',
        r'fixture "two words" $LITERAL é界😀',
        'fixture\x1b[31m --acp',
      ]) {
        final start = agentStart(launch(override: command));
        expect(start.command, command);
        expect(start.env, isEmpty);
      }
    });

    test('every catalog launch retains whole argv and its own environment', () {
      for (final agent in listAgents()) {
        final start = agentStart(launch(agent: agent));
        expect(start.command, same(agent.start.command), reason: agent.name);
        expect(start.env, same(agent.start.env), reason: agent.name);
      }
    });

    test('an override does not contaminate a later catalog launch', () {
      final agent = findAgent('auggie')!;
      final before = Map<String, String>.of(agent.start.env);
      final overridden = agentStart(launch(agent: agent, override: 'fixture'));
      expect(overridden.env, isEmpty);
      final catalog = agentStart(launch(agent: agent));
      expect(catalog.command, same(agent.start.command));
      expect(catalog.env, before);
      expect(catalog.env, {'AUGMENT_DISABLE_AUTO_UPDATE': '1'});
    });
  });

  group('agentStart', () {
    final agent = findAgent('auggie')!;
    Launch launch([String? override]) => Launch(
      name: agent.name,
      agent: agent,
      agentCommand: override,
      version: 'test',
      directory: '.',
    );

    test('override wins unchanged with no catalog environment', () {
      const override = 'fixture "two words" --acp';
      final start = agentStart(launch(override));
      expect(start.command, override);
      expect(start.env, isEmpty);
    });

    test('catalog argv and environment come through unchanged', () {
      final start = agentStart(launch());
      expect(start.command, same(agent.start.command));
      expect(start.command, [
        'npx',
        '-y',
        '@augmentcode/auggie@0.37.0',
        '--acp',
      ]);
      expect(start.env, same(agent.start.env));
      expect(start.env, {'AUGMENT_DISABLE_AUTO_UPDATE': '1'});
    });
  });

  test(
    'chord with no name opens the default agent in the directory, ~ for home',
    () async {
      final call = await chord([]);

      expect(call.outcome.code, 0);
      expect(call.outcome.launch?.agent?.name, defaultAgent);
      expect(call.outcome.launch?.version, version);
      expect(call.outcome.launch?.directory, '~/src/app');
      expect(call.stdout, isEmpty);
      expect(call.stderr, isEmpty);
    },
  );

  test('chord <agent> opens that agent', () async {
    final call = await chord(
      ['goose'],
      lookup: has(['goose']),
      cwd: '/srv/app',
    );

    expect(call.outcome.code, 0);
    expect(call.outcome.launch?.agent?.title, 'goose');
    expect(call.outcome.launch?.directory, '/srv/app');
  });

  test('an unknown agent is refused with the help', () async {
    refused(
      await chord(['nosuch']),
      'Unknown agent "nosuch". `chord agents` lists them.',
    );
  });

  test(
    'a start command missing from PATH is refused on stderr alone, exit 1',
    () async {
      final call = await chord(['cursor'], lookup: has(['npx']));

      expect(call.outcome.code, 1);
      expect(call.outcome.launch, isNull);
      expect(call.stdout, isEmpty);
      expect(
        call.stderr,
        'chord: cursor runs "agent", which is not on PATH; '
        'install it from https://cursor.com/docs/cli/installation\n',
      );
    },
  );

  test('no name and no npx refuses the default agent for its runner', () async {
    final call = await chord([], lookup: has([]));

    expect(call.outcome.code, 1);
    expect(
      call.stderr,
      startsWith(
        'chord: claude runs "npx", which is not on PATH; npx comes with Node.js',
      ),
    );
  });

  test('an unknown option is refused in Cliffy\'s words', () async {
    refused(await chord(['--nope']), 'Unknown option "--nope".');
    refused(await chord(['-x']), 'Unknown option "-x".');
    refused(await chord(['--no-help']), 'Unknown option "--no-help".');
    refused(await chord(['claude', '--nope']), 'Unknown option "--nope".');
  });

  test('more than one argument is refused', () async {
    refused(await chord(['a', 'b']), 'Too many arguments: b');
    refused(await chord(['a', 'b', 'c']), 'Too many arguments: b c');
    refused(await chord(['claude', 'agents']), 'Too many arguments: agents');
  });

  test('--help and -h print the help, with the original\'s words', () async {
    for (final flag in ['--help', '-h']) {
      final call = await chord([flag]);

      expect(call.outcome.code, 0);
      expect(call.outcome.launch, isNull);
      expect(call.stdout, '$chordHelp\n');
      expect(call.stderr, isEmpty);
    }
    expect(chordHelp, startsWith('Usage: chord [agent]\nVersion: $version\n'));
    expect(
      chordHelp,
      contains(
        'A full-screen terminal client for ACP coding agents. A new unnamed '
        'interactive start asks which agent to use for this invocation; explicit '
        'commands, headless and resume routes keep their existing behavior.',
      ),
    );
    expect(chordHelp, contains(RegExp(r'-h, --help +Show this help\.')));
    expect(
      chordHelp,
      contains(
        RegExp(r'-V, --version +Show the version number for this program\.'),
      ),
    );
    expect(
      chordHelp,
      contains(
        RegExp(
          r'agents +List the agents chord can start: name, title, command, and '
          r'for those started by their own CLI whether PATH has it\.',
        ),
      ),
    );
    expect(chordHelp, contains(RegExp(r'Claude Code +chord claude')));
    expect(chordHelp, contains('-C, --cwd=<dir>'));
  });

  test('--version names the program, -V prints the bare version', () async {
    final long = await chord(['--version']);
    final short = await chord(['-V']);

    expect(long.outcome.code, 0);
    expect(long.stdout, 'chord $version\n');
    expect(short.outcome.code, 0);
    expect(short.stdout, '$version\n');
    expect(long.outcome.launch, isNull);
  });

  test('chord agents prints the table, one line each when piped', () async {
    final call = await chord(['agents'], lookup: has(['goose']));

    expect(call.outcome.code, 0);
    expect(call.outcome.launch, isNull);
    expect(call.stdout, '${agentTable(await listedAgents(has(['goose'])))}\n');
    expect(call.stdout.trimRight().split('\n'), hasLength(listAgents().length));
    expect(
      call.stdout,
      contains(
        RegExp(r'^goose +goose +own CLI · found +goose acp$', multiLine: true),
      ),
    );
    expect(call.stderr, isEmpty);
  });

  test('on a terminal, chord agents wraps to its width', () async {
    final call = await chord(['agents'], columns: 80);

    expect(
      call.stdout,
      '${agentTable(await listedAgents(has(['npx', 'uvx'])), 80)}\n',
    );
    expect(
      call.stdout.trimRight().split('\n').length,
      greaterThan(listAgents().length),
    );
  });

  test('chord agents --help prints its own help', () async {
    final call = await chord(['agents', '-h']);

    expect(call.outcome.code, 0);
    expect(call.stdout, '$agentsHelp\n');
    expect(agentsHelp, startsWith('Usage: chord agents\n'));
    expect(
      agentsHelp,
      contains(
        'List the agents chord can start: name, title, command, and for those '
        'started by their own CLI whether PATH has it.',
      ),
    );
  });

  test(
    'chord agents refuses arguments and unknown options with its own help',
    () async {
      refused(
        await chord(['agents', 'x']),
        'No arguments allowed for command "chord agents".',
        help: agentsHelp,
      );
      refused(
        await chord(['agents', '--nope']),
        'Unknown option "--nope". Did you mean option "--help"?',
        help: agentsHelp,
      );
    },
  );

  test(
    "a flag of chord's own before agents is chord's, after it is unknown",
    () async {
      refused(
        await chord(['agents', '-V']),
        'Unknown option "-V". Did you mean option "-h"?',
        help: agentsHelp,
      );
      refused(
        await chord(['agents', '--version']),
        'Unknown option "--version". Did you mean option "--json"?',
        help: agentsHelp,
      );
      refused(
        await chord(['agents', '--no-mcp-servers']),
        'Unknown option "--no-mcp-servers". Did you mean option "--help"?',
        help: agentsHelp,
      );
      expect((await chord(['-V', 'agents'])).stdout, '$version\n');
      expect((await chord(['-h', 'agents'])).stdout, '$chordHelp\n');
      expect((await chord(['-V', 'claude'])).stdout, '$version\n');
    },
  );

  test(
    'after --, agents takes nothing as an option or an argument, as Cliffy',
    () async {
      final call = await chord(['agents', '--', '--version', 'x']);

      expect(call.outcome.code, 0);
      expect(
        call.stdout,
        '${agentTable(await listedAgents(has(['npx', 'uvx'])))}\n',
      );
      expect(call.stderr, isEmpty);
      refused(
        await chord(['agents', 'x', '--', 'y']),
        'No arguments allowed for command "chord agents".',
        help: agentsHelp,
      );
    },
  );

  test(
    '-V names the program when --version is anywhere, -- or not, as Cliffy',
    () async {
      expect(
        (await chord(['-V', '--', '--version'])).stdout,
        'chord $version\n',
      );
      expect(
        (await chord(['--version', '--', 'x'])).stdout,
        'chord $version\n',
      );
    },
  );

  group('tester: CLI isolation and boundaries', () {
    test('help and version never probe or launch an agent', () async {
      for (final args in [
        ['-h'],
        ['--help'],
        ['-V'],
        ['--version'],
        ['agents', '--help'],
        ['claude', '--help'],
        ['claude', '--version'],
      ]) {
        final call = await chord(
          args,
          lookup: (_) =>
              throw StateError('informational calls must not query PATH'),
        );
        expect(call.outcome.code, 0, reason: '$args');
        expect(call.outcome.launch, isNull);
        expect(call.stderr, isEmpty);
      }
    });

    test('invalid calls stop before any PATH lookup', () async {
      for (final args in [
        ['Claude'],
        ['claude '],
        ['claude-acp'],
        ['--nope'],
        ['a', 'b'],
        ['agents', 'x'],
        ['agents', '--version'],
      ]) {
        final call = await chord(
          args,
          lookup: (_) => throw StateError('invalid calls must not query PATH'),
        );
        expect(call.outcome.code, 2, reason: '$args');
        expect(call.outcome.launch, isNull);
        expect(call.stderr, startsWith('\n  error: '));
      }
    });

    test(
      'every public catalog name launches with its own executable',
      () async {
        for (final agent in listAgents()) {
          final calls = <String>[];
          final call = await chord(
            [agent.name],
            lookup: (command) async {
              calls.add(command);
              return 'fixture-found';
            },
          );
          expect(call.outcome.code, 0, reason: agent.name);
          expect(call.outcome.launch?.agent?.name, agent.name);
          expect(calls, [agent.start.command.first]);
          expect(call.stdout, isEmpty);
          expect(call.stderr, isEmpty);
        }
      },
    );

    test('concurrent calls keep their agent and directory separate', () async {
      final calls = await Future.wait([
        chord(['claude'], cwd: '/workspace/first'),
        chord(['fast-agent'], cwd: '/workspace/second'),
        chord(['cursor'], cwd: '/workspace/third', lookup: has(['agent'])),
      ]);
      expect(
        [for (final call in calls) call.outcome.launch?.agent?.name],
        ['claude', 'fast-agent', 'cursor'],
      );
      expect(
        [for (final call in calls) call.outcome.launch?.directory],
        ['/workspace/first', '/workspace/second', '/workspace/third'],
      );
    });

    test(
      'agents honors a 120-column terminal and keeps its output separate',
      () async {
        final call = await chord(
          ['agents'],
          columns: 120,
          lookup: has(['agent']),
        );
        expect(call.outcome.code, 0);
        expect(call.outcome.launch, isNull);
        expect(
          call.stdout,
          '${agentTable(await listedAgents(has(['agent'])), 120)}\n',
        );
        expect(call.stderr, isEmpty);
      },
    );

    test(
      'the main command treats flags after the terminator as names',
      () async {
        refused(
          await chord(['--', '--help']),
          'Unknown agent "--help". `chord agents` lists them.',
        );
        final call = await chord(['--', 'claude']);
        expect(call.outcome.launch?.agent?.name, 'claude');
        expect(call.stdout, isEmpty);
      },
    );
  });

  group('--agent-command', () {
    test('is in the help, with the original'
        's words and example', () {
      expect(
        chordHelp,
        contains(
          RegExp(
            r"--agent-command=<command> +Start this ACP agent command instead "
            r"of chord's own; \[agent\] only names it\.",
          ),
        ),
      );
      expect(
        chordHelp,
        contains(
          RegExp(
            r'An agent chord does not know +'
            r'chord my-agent --agent-command "my-agent --acp"',
          ),
        ),
      );
    });

    test('starts a name outside the catalog, with no PATH check', () async {
      final asked = <String>[];
      final call = await chord(
        ['my-agent', '--agent-command', 'my-agent --acp'],
        lookup: (command) async {
          asked.add(command);
          return null;
        },
      );

      expect(call.outcome.code, 0);
      expect(call.outcome.launch?.name, 'my-agent');
      expect(call.outcome.launch?.agent, isNull);
      expect(call.outcome.launch?.agentCommand, 'my-agent --acp');
      expect(call.outcome.launch?.directory, '~/src/app');
      expect(asked, isEmpty);
      expect(call.stdout, isEmpty);
      expect(call.stderr, isEmpty);
    });

    test("overrides a known agent's command, whose CLI need not be on "
        'PATH', () async {
      final call = await chord([
        'goose',
        '--agent-command=/opt/goose acp',
      ], lookup: has([]));

      expect(call.outcome.code, 0);
      expect(call.outcome.launch?.agent?.title, 'goose');
      expect(call.outcome.launch?.agentCommand, '/opt/goose acp');
      expect(call.stderr, isEmpty);
    });

    test('with no name goes with the default agent', () async {
      final call = await chord(['--agent-command', 'x --acp']);

      expect(call.outcome.launch?.name, defaultAgent);
      expect(call.outcome.launch?.agentCommand, 'x --acp');
    });

    test('without it, launches carry no command', () async {
      expect((await chord([])).outcome.launch?.agentCommand, isNull);
    });

    test('without a value is refused as Cliffy refuses it', () async {
      refused(
        await chord(['--agent-command']),
        'Missing value for option "--agent-command".',
      );
    });

    test('is not an option of chord agents', () async {
      refused(
        await chord(['agents', '--agent-command', 'x']),
        'Unknown option "--agent-command". Did you mean option "--cwd"?',
        help: agentsHelp,
      );
    });
  });

  group('tester command override boundaries', () {
    test(
      'an override before agents keeps the accepted subcommand behavior',
      () async {
        final call = await chord(['--agent-command', 'x', 'agents']);
        expect(call.outcome.code, 0);
        expect(call.outcome.launch, isNull);
        expect(
          call.stdout,
          '${agentTable(await listedAgents(has(['npx', 'uvx'])))}\n',
        );
        expect(call.stderr, isEmpty);
      },
    );

    test(
      'informational calls combined with an override refuse before lookup',
      () async {
        for (final flag in ['--help', '--version']) {
          final call = await chord(
            ['custom', '--agent-command', 'missing --acp', flag],
            lookup: (_) => throw StateError('information must not query PATH'),
          );
          refused(
            call,
            'Option "$flag" cannot be combined with other options.',
          );
        }
      },
    );

    test(
      'the CLI preserves command quotes escapes and unicode literally',
      () async {
        const command = r'executable "two words" é界😀 $LITERAL --acp';
        final call = await chord([
          'custom',
          '--agent-command',
          command,
        ], lookup: (_) => throw StateError('override must not query PATH'));
        expect(call.outcome.launch?.name, 'custom');
        expect(call.outcome.launch?.agentCommand, command);
        expect(call.stdout, isEmpty);
        expect(call.stderr, isEmpty);
      },
    );

    test('what /new lists is read only when the launcher asks, through the '
        'same PATH lookup', () async {
      final cursor = findAgent('cursor')!.start.command.first;
      var looked = 0;
      final call = await chord(
        ['custom', '--agent-command', 'run'],
        lookup: (command) async {
          looked++;
          return command == cursor ? command : null;
        },
      );
      expect(looked, 0);
      final listed = await call.outcome.launch!.readListed!();
      expect(looked, greaterThan(0));
      final found = {
        for (final agent in listed)
          if (agent.found != null) agent.name: agent.found,
      };
      expect(found['cursor'], isTrue);
      expect(found.values.where((each) => each == true), hasLength(1));
    });
  });
}
