// `chord -p` from the command line: its argument errors, and one turn on
// the original's fake agent in text and JSON, as the original's
// tests/headless_test.ts plays them.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show MemoryAgentProcess;
import 'package:chord/agents.dart' show findAgent;
import 'package:chord/session/prices.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake_harness.dart';

typedef _Call = ({int code, String stdout, String stderr});

late Directory _dir;

Future<_Call> _chord(
  List<String> args, {
  String? piped,
  List<String> fakeFlags = const [],
  bool fake = true,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final outcome = await runCli(
    [
      if (fake) ...[
        'fake',
        '--agent-command',
        fakeAgentCommand(null, fakeFlags).map(shellWord).join(' '),
      ],
      ...args,
    ],
    stdout: out,
    stderr: err,
    cwd: _dir.path,
    home: p.join(_dir.path, 'home'),
    environment: {'HOME': p.join(_dir.path, 'home')},
    stdinTTY: piped == null,
    readPiped: () async => piped ?? '',
    lookup: (command) async => '/bin/$command',
  );
  expect(outcome.launch, isNull);
  return (code: outcome.code, stdout: '$out', stderr: '$err');
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('chord-print-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('tester: CTUI-28 catalog pin override ownership', () {
    Future<({int code, String out, String err})> failStartup(
      List<String> args,
    ) async {
      final out = StringBuffer(), err = StringBuffer();
      late final MemoryAgentProcess process;
      process = MemoryAgentProcess(
        onSignal: (_) {
          if (process.exited) return;
          process.exit(const Exit(143, 'SIGTERM'));
          process.closeStdout();
          process.closeStderr();
        },
      );
      process.writeStderr('owned failure\n');
      process.closeStderr();
      process.exit(const Exit(99));
      process.closeStdout();
      final result = await runCli(
        args,
        stdout: out,
        stderr: err,
        cwd: _dir.path,
        home: p.join(_dir.path, 'home'),
        environment: {
          'HOME': p.join(_dir.path, 'home'),
          'XDG_CONFIG_HOME': p.join(_dir.path, 'config'),
          'XDG_STATE_HOME': p.join(_dir.path, 'state'),
        },
        stdinTTY: true,
        lookup: (_) async => '/bin/found',
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => connectAgent(
              process,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            ),
      );
      expect(process.exited, isTrue);
      expect(result.launch, isNull);
      return (code: result.code, out: '$out', err: '$err');
    }

    test(
      'only the catalog command reports its pinned package on failure',
      () async {
        final catalog = await failStartup(['claude', '-p', 'hi']);
        expect(catalog.code, 1);
        expect(catalog.out, isEmpty);
        expect(
          catalog.err,
          contains(
            'chord: chord ran ${findAgent('claude')!.pinned}, the version this chord pins.',
          ),
        );
        final flag = await failStartup([
          'claude',
          '--agent-command',
          'custom --acp',
          '-p',
          'hi',
        ]);
        expect(flag.code, 1);
        expect(flag.err, isNot(contains('chord ran')));
        expect(flag.err, contains('owned failure'));
      },
    );

    test(
      'settings string and argv commands suppress the catalog pin',
      () async {
        for (final command in [
          'custom --acp',
          ['custom', ''],
        ]) {
          File(p.join(_dir.path, '.chord', 'settings.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              jsonEncode({
                'agents': {
                  'claude': {'command': command},
                },
              }),
            );
          final call = await failStartup([
            'claude',
            '-p',
            'hi',
            '--output-format',
            'json',
          ]);
          expect(call.code, 1);
          expect(call.out, isEmpty);
          expect(call.err, isNot(contains('chord ran')));
          expect(call.err, contains('owned failure'));
        }
      },
    );
  });
  group('argument errors, as Cliffy words them', () {
    for (final (args, message) in [
      (
        ['-p', 'hi', '-m', 'x'],
        'Option "--model" conflicts with option "--print".',
      ),
      (
        ['-p', 'hi', '-c'],
        'Option "--print" conflicts with option "--continue".',
      ),
      (
        ['-p', 'hi', '-r', 'abc'],
        'Option "--print" conflicts with option "--resume".',
      ),
      (
        ['-p', 'hi', '--output-format', 'xml'],
        'Option "--output-format" must be of type "format", but got "xml". '
            'Expected values: "text", "json"',
      ),
      (
        ['--output-format', 'json'],
        'Option "--output-format" depends on option "--print".',
      ),
      (
        ['--dangerously-skip-permissions'],
        '--dangerously-skip-permissions works only with -p',
      ),
      (['-p'], 'Missing value for option "--print".'),
    ]) {
      test(args.join(' '), () async {
        final call = await _chord(args, fake: false);
        expect(call.code, 2);
        expect(call.stdout, '$chordHelp\n');
        expect(call.stderr, '\n  error: $message\n\n');
      });
    }

    test('the help names -p, its flags and its examples', () {
      for (final line in [
        '  -p, --print=<prompt>',
        'Send this prompt, print the reply and exit; piped input joins it.',
        '      --dangerously-skip-permissions',
        'Allow every permission the agent asks for. Only with -p.',
        '      --output-format=<format>',
        'How -p prints: the reply as it streams, or one JSON object at the end.',
        'One question, for a script',
        'git diff | chord -p "Review this" --output-format json',
      ]) {
        expect(chordHelp, contains(line));
      }
    });
  });

  group('one turn on the fake', skip: fakeAgentSkip, () {
    group('CTUI-69 tester: headless plan capability', () {
      for (final format in ['text', 'json']) {
        test(
          'capability-gated item plans leave reply output intact in $format',
          () async {
            final result = await _chord(
              ['-p', 'plan', '--output-format', format],
              fakeFlags: ['--plan-capability-only', '--step-ms', '1'],
            );
            expect(result.code, 0);
            expect(result.stderr, isEmpty);
            const expected = 'Planned. Step 2 done. Step 3 done.';
            if (format == 'text') {
              expect(result.stdout, '$expected\n');
            } else {
              expect(result.stdout.trimRight().split('\n'), hasLength(1));
              final json = jsonDecode(result.stdout) as Map<String, Object?>;
              expect(json['result'], expected);
              expect(json['is_error'], isFalse);
            }
          },
        );
      }
    });

    group('CTUI-68 tester: headless link diagnostics', () {
      test(
        'allow-all cancels links without skipped-question stderr in JSON',
        () async {
          final result = await _chord([
            '-p',
            'link',
            '--output-format',
            'json',
            '--dangerously-skip-permissions',
          ]);
          expect(result.code, 0);
          expect(result.stderr, isEmpty);
          expect(result.stdout.trimRight().split('\n'), hasLength(1));
          final json = jsonDecode(result.stdout) as Map<String, Object?>;
          expect(json['result'], 'Elicitation answer: cancel');
          expect(json['is_error'], isFalse);
        },
      );
    });

    test('-p prints the reply and exits 0', () async {
      expect(await _chord(['-p', 'text']), (
        code: 0,
        stdout: 'Hello, world. This reply came in chunks.\n',
        stderr: '',
      ));
    });

    test('a compaction adds nothing to stdout or stderr, as the '
        "original's -p, which declares compactions", () async {
      expect(await _chord(['-p', 'compact']), (
        code: 0,
        stdout: '',
        stderr: '',
      ));
    });

    test("a command's terminal output adds nothing to stdout: the reply "
        "alone, as the original's -p, which asks for it", () async {
      expect(await _chord(['-p', 'bash']), (
        code: 0,
        stdout: 'Two files changed.\n',
        stderr: '',
      ));
    });

    test("a form is declined, and stderr names it by its message; a link "
        "is cancelled", () async {
      expect(await _chord(['-p', 'form']), (
        code: 0,
        stdout: 'Elicitation answer: decline\n',
        stderr:
            'chord: fake asked: Set up the deploy target — skipped (no one '
            'to answer under -p)\n',
      ));
      expect(await _chord(['-p', 'link']), (
        code: 0,
        stdout: 'Elicitation answer: cancel\n',
        stderr: '',
      ));
    });

    test(
      'a form is declined, and stderr names each question it asked',
      () async {
        expect(await _chord(['-p', 'askcodex']), (
          code: 0,
          stdout: 'Elicitation answer: decline\n',
          stderr:
              'chord: fake asked: What would you like to focus on next? — '
              'skipped (no one to answer under -p)\n'
              'chord: fake asked: Paste the API token for the staging deploy. '
              '— skipped (no one to answer under -p)\n',
        ));
      },
    );

    group('CHD-1 tester: headless question diagnostics', () {
      const cases = [
        (
          'askclaude',
          [
            'Which language should helper scripts use?',
            'Which checks should run before a commit?',
          ],
        ),
        ('askclaudeone', ['Which language should helper scripts use?']),
        (
          'askcodex',
          [
            'What would you like to focus on next?',
            'Paste the API token for the staging deploy.',
          ],
        ),
        (
          'askcodexwait',
          [
            'What would you like to focus on next?',
            'Paste the API token for the staging deploy.',
          ],
        ),
        (
          'askdroid',
          [
            'Where should uploads be kept?',
            'Which formats should be accepted?',
            'What should the bucket be called?',
          ],
        ),
        ('askopencode', ['Where should the new tests go?']),
        ('askdimcode', ['Where should it deploy?']),
        ('form', ['Set up the deploy target']),
      ];
      for (final (scenario, questions) in cases) {
        test('$scenario: decline continues in text and JSON while stderr '
            'names every skipped question', () async {
          final expected = [
            for (final question in questions)
              'chord: fake asked: $question — skipped (no one to answer '
                  'under -p)\n',
          ].join();
          for (final format in ['text', 'json']) {
            final call = await _chord([
              '-p',
              scenario,
              '--output-format',
              format,
            ]);
            expect(call.code, 0);
            expect(call.stderr, expected);
            if (format == 'text') {
              expect(call.stdout, 'Elicitation answer: decline\n');
            } else {
              final lines = call.stdout.trimRight().split('\n');
              expect(lines, hasLength(1));
              final parsed = jsonDecode(lines.single) as Map<String, Object?>;
              expect(parsed['type'], 'result');
              expect(parsed['is_error'], false);
              expect(parsed['result'], 'Elicitation answer: decline');
              expect(parsed['stop_reason'], 'end_turn');
              expect(parsed.containsKey('questions'), isFalse);
            }
          }
        });
      }

      test('allow-all still skips questions', () async {
        expect(
          await _chord(['-p', 'askclaude', '--dangerously-skip-permissions']),
          await _chord(['-p', 'askclaude']),
        );
      });
    });

    test('a plan by id is the reply: stdout gets the first markdown and '
        'what later updates add to it, JSON the plans as last sent', () async {
      // The draft is rewritten from its start, which stdout cannot take
      // back, and then withdrawn, which JSON, written at the end, leaves
      // out; the file plan is no reply text.
      expect(await _chord(['-p', 'proposal'], fakeFlags: ['--step-ms', '1']), (
        code: 0,
        stdout:
            "I'll look first.1. Read the codePlan written. Draft dropped.\n",
        stderr: '',
      ));
      final call = await _chord(
        ['-p', 'proposal', '--output-format', 'json'],
        fakeFlags: ['--step-ms', '1'],
      );
      expect(call.code, 0);
      expect(
        (jsonDecode(call.stdout) as Map<String, Object?>)['result'],
        "I'll look first.Plan written. Draft dropped.",
      );
    });

    test('--output-format json prints one object with the usage', () async {
      final call = await _chord(['-p', 'status', '--output-format', 'json']);
      expect(call.code, 0);
      expect(call.stderr, '');
      final lines = call.stdout.trimRight().split('\n');
      expect(lines, hasLength(1));
      final result = jsonDecode(lines.single) as Map<String, Object?>;
      expect(result['session_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(
        {...result, 'session_id': 'id'},
        {
          'type': 'result',
          'is_error': false,
          'result': 'Status sent.',
          'session_id': 'id',
          'stop_reason': 'end_turn',
          'usage': {
            'input_tokens': 1000,
            'output_tokens': 200,
            'total_tokens': 1200,
          },
          'total_cost_usd': 0.01,
        },
      );
    });

    test('a cost chord worked out from the tokens is marked', () async {
      final call = await _chord(
        ['-p', 'text', '--output-format', 'json'],
        fakeFlags: const ['--tokens-only'],
      );
      final result = jsonDecode(call.stdout) as Map<String, Object?>;
      expect(call.code, 0);
      expect(result['usage'], {
        'input_tokens': 1000,
        'output_tokens': 200,
        'cache_read_input_tokens': 800,
        'total_tokens': 2000,
      });
      expect(
        result['total_cost_usd'],
        turnCost('gpt-5.3-codex', const {
          'inputTokens': 1000,
          'outputTokens': 200,
          'cachedReadTokens': 800,
          'totalTokens': 2000,
        }),
      );
      expect(result['cost_estimated'], isTrue);
    });

    test('a failing agent exits 1 with its error on stderr', () async {
      expect(await _chord(['-p', 'error']), (
        code: 1,
        stdout: 'About to fail.\n',
        stderr: 'chord: The fake agent failed on purpose.\n',
      ));
      final json = await _chord(['-p', 'error', '--output-format', 'json']);
      expect(json.code, 1);
      expect((jsonDecode(json.stdout) as Map)['is_error'], isTrue);
    });

    group('CTUI-161: notices on stderr', () {
      const fastOff =
          'chord: Fast mode turned off: Rate limit for fast mode reached; it '
          'comes back after the limit resets.\n';
      const reply = 'Running the lexer suite with coverage now. Done.';

      test("an agent's notice goes to stderr as a line of chord's, in text "
          'and JSON, and stdout keeps the reply alone', () async {
        expect(await _chord(['-p', 'notice']), (
          code: 0,
          stdout: '$reply\n',
          stderr: fastOff,
        ));
        final json = await _chord(['-p', 'notice', '--output-format', 'json']);
        expect(json.code, 0);
        expect(json.stderr, fastOff);
        expect((jsonDecode(json.stdout) as Map)['result'], reply);
      });

      for (final format in ['text', 'json']) {
        test('startup and turn notices reach stderr once in order, with '
            '$format stdout kept clean', () async {
          final call = await _chord(
            ['-p', 'notice', '--output-format', format],
            fakeFlags: ['--start-notice', 'Startup advice'],
          );
          expect(call.code, 0);
          expect(call.stderr, 'chord: Startup advice\n$fastOff');
          expect(
            format == 'json'
                ? (jsonDecode(call.stdout) as Map)['result']
                : call.stdout.trimRight(),
            reply,
          );
        });

        test('a failed prompt keeps its earlier notice and failure in '
            '$format', () async {
          final call = await _chord(
            ['-p', 'error', '--output-format', format],
            fakeFlags: ['--start-notice', 'Startup advice'],
          );
          expect(call.code, 1);
          expect(
            call.stderr,
            'chord: Startup advice\n'
            'chord: The fake agent failed on purpose.\n',
          );
          if (format == 'json') {
            expect((jsonDecode(call.stdout) as Map)['is_error'], isTrue);
          }
          expect(call.stdout, isNot(contains('Startup advice')));
        });
      }
    });

    test('a permission is refused, or allowed with '
        '--dangerously-skip-permissions', () async {
      expect(await _chord(['-p', 'permission']), (
        code: 0,
        stdout: 'Permission: deny.\n',
        stderr:
            'chord: refused Write notes.txt: -p cannot ask for permission.\n',
      ));
      expect(
        await _chord(['-p', 'permission', '--dangerously-skip-permissions']),
        (
          code: 0,
          stdout: 'Permission: allow.\n',
          stderr: 'chord: allowed Write notes.txt.\n',
        ),
      );
    });

    test('piped stdin joins the prompt on the command line', () async {
      expect(await _chord(['-p', '/echo one'], piped: 'two\n'), (
        code: 0,
        stdout: 'one\ntwo\n',
        stderr: '',
      ));
      final json = await _chord([
        '-p',
        '/echo one',
        '--output-format',
        'json',
      ], piped: 'two');
      expect(json.code, 0);
      expect((jsonDecode(json.stdout) as Map)['result'], 'one\ntwo');
    });

    test(
      'the mode comes from the project file, and the flag over it',
      () async {
        File(p.join(_dir.path, '.chord', 'settings.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode({
              'agents': {
                'fake': {'permissionMode': 'plan'},
              },
            }),
          );
        expect((await _chord(['-p', 'mode'])).stdout, 'Mode: plan.\n');
        expect(
          (await _chord([
            '-p',
            'mode',
            '--permission-mode',
            'acceptEdits',
          ])).stdout,
          'Mode: acceptEdits.\n',
        );
        final refused = await _chord([
          '-p',
          'permission',
          '--permission-mode',
          'nosuch',
        ]);
        expect(
          refused.stderr,
          'chord: could not start in nosuch mode, set by --permission-mode: '
          'the agent offers default, acceptEdits, plan\n'
          'chord: refused Write notes.txt: -p cannot ask for permission.\n',
        );
      },
    );

    test(
      'an effort asked of an agent with none is said, and the turn runs',
      () async {
        final call = await _chord(
          ['-p', 'text', '--effort', 'high'],
          fakeFlags: const ['--no-config'],
        );
        expect(call.code, 0);
        expect(
          call.stderr,
          'chord: could not start on high effort, set by --effort: the agent '
          'offers no efforts\n',
        );
      },
    );
  });

  group('MCP servers', () {
    final skip = fakeAgentSkip;
    List<Object?> sent(String stdout) =>
        jsonDecode(stdout.replaceAll(RegExp(r'^```json\n|\n```\n*$'), ''))
            as List<Object?>;

    test('-p gives the agent the directory\'s servers, and a wrong one is '
        'said on stderr', () async {
      File(p.join(_dir.path, '.mcp.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'files': {
              'command': 'files-mcp',
              'args': ['.'],
            },
            'broken': {'type': 'sse'},
          },
        }),
      );
      final result = await _chord(['-p', 'mcp']);
      expect(result.code, 0);
      expect(sent(result.stdout), [
        {
          'name': 'files',
          'command': 'files-mcp',
          'args': ['.'],
          'env': <Object?>[],
        },
      ]);
      expect(
        result.stderr,
        contains('"mcpServers.broken.url": missing; the server is ignored'),
      );
    }, skip: skip);

    test('-p --no-mcp-servers gives none', () async {
      File(p.join(_dir.path, '.mcp.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'files': {'command': 'files-mcp'},
          },
        }),
      );
      final result = await _chord(['-p', 'mcp', '--no-mcp-servers']);
      expect(result.code, 0);
      expect(sent(result.stdout), isEmpty);
    }, skip: skip);
  });
}
