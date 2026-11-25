// `chord acp` up to serving: its help, its usage errors on stderr alone
// with stdout empty, a refused or unknown agent, and what it serves.
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_test.dart' show Call, chord;

void main() {
  /// A usage error: exit 2, stdout empty, [line] alone on stderr.
  void usage(Call call, String line) {
    expect(call.outcome.code, 2);
    expect(call.outcome.acp, isNull);
    expect(call.outcome.launch, isNull);
    expect(call.stdout, isEmpty);
    expect(call.stderr, '$line\n');
  }

  test('--help describes it on stdout, its flags too', () async {
    final call = await chord(['acp', '--help']);
    expect(call.outcome.code, 0);
    expect(call.stdout, '$acpHelp\n');
    expect(acpHelp, startsWith('Usage: chord acp [agent]\n'));
    expect(
      acpHelp,
      contains(
        'Serve ACP on stdin and stdout, for a client that starts chord as its '
        'agent; draws nothing.',
      ),
    );
    for (final line in [
      RegExp(r'--agent-command=<command> +Start this ACP agent command'),
      RegExp(r'-m, --model=<model> +Start each of \[agent\]'),
      RegExp(r'--effort=<effort> +Start each'),
      RegExp(r'--permission-mode=<mode> +Start each'),
      RegExp(r'--no-mcp-servers +Start each of \[agent\]'),
    ]) {
      expect(acpHelp, contains(line));
    }
    expect(call.stderr, isEmpty);
  });

  test('chord\'s own help lists it after agents', () {
    expect(
      chordHelp,
      contains(
        RegExp(
          r'Commands:\n  agents +List the agents[^\n]*\n  acp +Serve ACP on '
          r'stdin and stdout',
        ),
      ),
    );
  });

  test('an unknown agent', () async {
    usage(
      await chord(['acp', 'no-such-agent']),
      'chord: Unknown agent "no-such-agent". `chord agents` lists them.',
    );
  });

  test(
    'an unknown option, with --agent-command too, in args\' words',
    () async {
      for (final args in [
        ['acp', '--nope'],
        ['acp', '--nope', '--agent-command', 'x'],
      ]) {
        usage(
          await chord(args),
          'chord: Could not find an option named "--nope".',
        );
      }
    },
  );

  test('an option without its value, in Cliffy\'s words, and a second '
      'agent', () async {
    for (final (args, option) in [
      (['acp', '--agent-command'], '--agent-command'),
      (['acp', '-m'], '--model'),
      (['acp', '--model'], '--model'),
      (['acp', '--effort'], '--effort'),
      (['acp', '--permission-mode'], '--permission-mode'),
    ]) {
      usage(await chord(args), 'chord: Missing value for option "$option".');
    }
    usage(
      await chord(['acp', 'claude', 'codex']),
      'chord: Too many arguments: codex',
    );
  });

  test('a command the launch directory refuses: exit 1, the original\'s '
      'line, stdout empty; --agent-command passes it', () async {
    final dir = Directory.systemTemp.createTempSync('chord-acp-cli-');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, '.chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'agents': {
            'claude': {'command': 1},
          },
        }),
      );
    final refused = await chord(['acp', 'claude'], cwd: dir.path);
    expect(refused.outcome.code, 1);
    expect(refused.outcome.acp, isNull);
    expect(refused.stdout, isEmpty);
    expect(
      refused.stderr.trim().split('\n').last,
      'claude not started: agents.claude.command in .chord/settings.json: '
      'expected a string, got a number',
    );
    final given = await chord([
      'acp',
      'claude',
      '--agent-command',
      'x --acp',
    ], cwd: dir.path);
    expect(given.outcome.acp?.flags.agentCommand, 'x --acp');
  });

  test(
    'a call it serves: the agent as named, its flags, nothing printed',
    () async {
      final call = await chord([
        'acp',
        'codex',
        '-m',
        'gpt',
        '--effort',
        'high',
        '--permission-mode',
        'plan',
        '--no-mcp-servers',
      ]);
      expect(call.outcome.code, 0);
      expect(call.outcome.launch, isNull);
      final start = call.outcome.acp!;
      expect(start.agent, 'codex');
      expect(
        (
          start.flags.model,
          start.flags.effort,
          start.flags.permissionMode,
          start.noMcpServers,
        ),
        ('gpt', 'high', 'plan', true),
      );
      expect(start.cwd, '/home/me/src/app');
      expect(call.stdout, isEmpty);
      expect(call.stderr, isEmpty);
      // A name only --agent-command starts, and no name at all: the default.
      expect(
        (await chord([
          'acp',
          'mine',
          '--agent-command',
          'mine --acp',
        ])).outcome.acp?.agent,
        'mine',
      );
      expect((await chord(['acp'])).outcome.acp?.noMcpServers, isFalse);
    },
  );

  test('acp anywhere but first is the window\'s agent of that name', () async {
    final call = await chord(['--agent-command', 'x', 'acp']);
    expect(call.outcome.acp, isNull);
    expect(call.outcome.launch?.name, 'acp');
  });
}
