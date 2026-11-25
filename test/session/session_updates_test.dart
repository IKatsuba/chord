// What a session hears from the original's fake agent in a turn: the
// original's tests/session/session_updates_test.ts, the cases M1 covers,
// plans by id and proposals included.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permissions.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/terminal_text.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';
import 'transcript/fold.dart';

/// What the `shell` scenario's command writes, piece by piece.
const _shellOutput = [
  'Task test deno test\n',
  'running 3 tests\n1/3',
  '\r2/3\r3/3\n\x1b[3',
  '2mok\x1b[0m | 2 passed\n\x1b]8;;https://example.com/failed',
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed\n',
];

/// What the `bash` scenario's command writes, whole.
const _bashOutput = ' M src/main.tsx\n?? notes.md\n';

/// What the `compact` scenario streams as its compaction's summary.
const _compactSummary = [
  '## Summary\n\n',
  'The person asked for a README section on install, ',
  'then for the tests to run.\n\n',
  '- Read `README.md` and `deno.json`\n',
  '- Wrote the install section with `bun install`\n',
  '- Ran `bun dev test`: 3 passed\n\n',
  'Next: commit the change.',
];

/// The fake's `markdownwrap` reply, the original's MARKDOWN_WRAP.
const _markdownWrap =
    '## A heading long enough that at eighty columns it has to wrap onto a second row of its own\n'
    '\n'
    '- package.json:3: the package @chorded/chord at version 0.54.1 needs Bun 1.4.2 or newer. check runs check:static and then the tests.\n'
    '  - a nested item long enough to wrap at eighty columns, whose wrapped lines should hang under its own text\n'
    '    1. deeper still, a numbered item that also runs past the edge of the window so its hang shows too\n'
    '- a short item\n'
    '\n'
    '> A quote whose paragraph is long enough to wrap inside its bar at eighty columns, and at a hundred and twenty too, once it runs on.\n'
    '\n'
    '8. eight\n'
    '9. nine\n'
    '10. ten, with a two-digit marker and text long enough to wrap so the hang under a wider marker shows\n'
    '\n'
    '- [ ] open task\n'
    '- [x] done task\n'
    '\n'
    'Soft\n'
    'break and a hard  \n'
    'break here.';

/// Each failed call's status, text and terminal exit, as the last of its
/// updates left them.
List<Map<String, Object?>> _endsOf(List<acp.SessionUpdate> updates) => [
  for (final update in calls(updates))
    if (update['status'] == 'failed')
      {
        'status': update['status'],
        'text': switch (update['content']) {
          final List<Object?> blocks => [
            for (final block in blocks.cast<Map<String, Object?>>())
              if (block['type'] == 'content' &&
                  (block['content'] as Map)['type'] == 'text')
                (block['content'] as Map)['text'] as String,
          ],
          _ => null,
        },
        'exit': (update['_meta'] as Map?)?['terminal_exit'],
      },
];

const _editOld =
    'export function greet(name: string): string {\n'
    '  return "hello " + name;\n'
    '}\n';

const _editNew =
    '/** Greets someone by name. */\n'
    'export function greet(name: string): string {\n'
    r'  return `hello, ${name}`;'
    '\n}\n';

/// Plays `permission`, answering its request with [answer] a moment after
/// it is asked, as a key press would, never inside the callback.
Future<
  ({
    List<Map<String, Object?>> calls,
    List<String> said,
    PendingPermission request,
  })
>
_answerPermission(
  Session session,
  void Function(PendingPermission) answer,
) async {
  PendingPermission? request;

  session.permissions.subscribe((pending) {
    request = pending;
    expect(session.permissions.pending(), [pending]);
    Timer(const Duration(milliseconds: 10), () => answer(pending));
  });

  final updates = await collect(session, 'permission');

  expect(request, isNotNull);
  expect(session.permissions.pending(), isEmpty);

  return (calls: calls(updates), said: said(updates), request: request!);
}

void main() {
  group('CTUI-69 tester: concurrent proposal cancellation', () {
    test(
      'cancelling one proposal leaves a simultaneous session complete and independent',
      () async {
        await withSession(
          capabilities: windowCapabilities(),
          flags: ['--step-ms', '1'],
          (first, _) async {
            await withSession(
              capabilities: windowCapabilities(),
              flags: ['--step-ms', '1'],
              (second, _) async {
                Future<void>? cancelled;
                final results = await Future.wait([
                  run(
                    first,
                    'proposal',
                    onUpdate: (updates, turn) {
                      if (updates.any(
                        (update) => update.kind == 'plan_update',
                      )) {
                        cancelled ??= turn.cancel();
                      }
                    },
                  ),
                  run(second, 'proposal'),
                ]);
                expect(cancelled, isNotNull);
                await cancelled;
                expect(
                  results.first.result,
                  isA<TurnAnswered>().having(
                    (result) => result.cancelled,
                    'cancelled',
                    isTrue,
                  ),
                );
                expect(
                  results.last.result,
                  isA<TurnAnswered>().having(
                    (result) => result.cancelled,
                    'cancelled',
                    isFalse,
                  ),
                );
                expect(
                  said(results.last.updates).join(),
                  "I'll look first.Plan written. Draft dropped.",
                );
                expect(
                  results.last.updates.any(
                    (update) => update.kind == 'plan_removed',
                  ),
                  isTrue,
                );
              },
            );
          },
        );
      },
      skip: fakeAgentSkip,
    );
  });

  final skip = fakeAgentSkip;

  test('a plain reply streams in several chunks and completes', () async {
    await withSession((session, _) async {
      final (:turn, :updates, :result) = await run(session, 'text');

      expect(said(updates), [
        'Hello',
        ', world',
        '. This reply',
        ' came in chunks.',
      ]);
      expect((result as TurnAnswered).stopReason, 'end_turn');
      expect(turn.id, isNotEmpty);
    });
  }, skip: skip);

  test('thought chunks arrive on their own stream before the reply', () async {
    await withSession((session, _) async {
      final updates = await collect(session, 'thought');

      expect(said(updates, 'agent_thought_chunk'), [
        'Considering',
        ' the question.',
      ]);
      expect(said(updates), ['Here is', ' the answer.']);

      final first = updates.indexWhere((u) => u.kind == 'agent_message_chunk');

      expect(
        updates.skip(first).where((u) => u.kind == 'agent_thought_chunk'),
        isEmpty,
      );
    });
  }, skip: skip);

  test(
    'a tool call goes pending, in progress, completed under one id',
    () async {
      await withSession((session, _) async {
        final tools = calls(await collect(session, 'tools'));

        expect(
          [for (final c in tools) (c['toolCallId'], c['status'])],
          [
            ('read-1', 'pending'),
            ('read-1', 'in_progress'),
            ('read-1', 'completed'),
          ],
        );
        expect(tools.first['title'], 'Read README.md');
        expect(tools.first['kind'], 'read');
        expect(tools.last['content'], [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': '# chord'},
          },
        ]);
        // The enrichers carried the call's title and kind onto its updates.
        expect(tools.last['title'], 'Read README.md');
      });
    },
    skip: skip,
  );

  test('an edit carries its diff', () async {
    await withSession((session, _) async {
      final edits = calls(await collect(session, 'edit'));

      expect(edits.first['kind'], 'edit');
      expect(edits.last['content'], [
        {
          'type': 'diff',
          'path': 'src/greeting.ts',
          'oldText': _editOld,
          'newText': _editNew,
        },
      ]);
    });
  }, skip: skip);

  test('a permission request waits for the answer and gets the chosen '
      'option', () async {
    await withSession((session, _) async {
      final (:calls, :said, :request) = await _answerPermission(
        session,
        (r) => r.resolve('always'),
      );

      expect(request.toolCall.toolCallId, 'write-1');
      expect(request.options.map((o) => o.optionId), [
        'allow',
        'always',
        'deny',
      ]);
      // The enrichers named the call before the bridge saw it.
      expect(waitFor(request).title, 'Write notes.txt');
      expect(said, ['Permission: always.']);
      expect(calls.last['status'], 'completed');
    });
  }, skip: skip);

  test('a rejected permission request reaches the agent as its reject '
      'option', () async {
    await withSession((session, _) async {
      final (:calls, :said, request: _) = await _answerPermission(
        session,
        (r) => r.reject(),
      );

      expect(said, ['Permission: deny.']);
      expect(calls.last['status'], 'failed');
    });
  }, skip: skip);

  test('cancelling a turn withdraws its pending permission request', () async {
    await withSession((session, _) async {
      final asked = Completer<PendingPermission>();

      session.permissions.subscribe(asked.complete);

      final turn = session.prompt('permission');
      final request = await asked.future;

      await turn.cancel();
      expect(request.withdrawn.isCancelled, isTrue);
      expect(session.permissions.pending(), isEmpty);
      expect((await turn.result as TurnAnswered).cancelled, isTrue);
    });
  }, skip: skip);

  test('a plan update carries its entries', () async {
    await withSession((session, _) async {
      final plan = (await collect(
        session,
        'plan',
      )).firstWhere((u) => u.kind == 'plan');

      expect(plan.toJson()['entries'], [
        {'content': 'Read the code', 'priority': 'high', 'status': 'completed'},
        {
          'content': 'Write the change',
          'priority': 'medium',
          'status': 'in_progress',
        },
        {'content': 'Run the tests', 'priority': 'low', 'status': 'pending'},
      ]);
    });
  }, skip: skip);

  // Codex's adapter sends its plan by id only to a client that declares
  // `clientCapabilities.plan`, and to any other as reply text.
  test(
    'an agent that sends plans by id only on request sends chord one',
    () async {
      await withSession(
        capabilities: windowCapabilities(),
        flags: ['--plan-capability-only'],
        (session, _) async {
          final updates = await collect(session, 'plan');
          final plan = updates.firstWhere((u) => u.kind == 'plan_update');
          expect(said(updates), ['Planned.', ' Step 2 done.', ' Step 3 done.']);
          final content = plan.toJson()['plan']! as Map<String, Object?>;
          expect(content['type'], 'items');
          expect(
            [for (final e in content['entries']! as List) (e as Map)['status']],
            ['completed', 'in_progress', 'pending'],
          );
        },
      );
    },
    skip: skip,
  );

  // Codex's plan mode proposes its plan as markdown, the whole text each
  // time, and may withdraw it by id; `--step-ms 1` keeps the fake's pace,
  // set for a person watching, short.
  test('a proposed plan rewritten and withdrawn leaves the rest of the '
      'reply, and a second proposal leaves the first in place', () async {
    await withSession(
      capabilities: windowCapabilities(),
      flags: ['--step-ms', '1'],
      (session, _) async {
        var transcript = Transcript.empty;
        for (final turnId in ['t1', 't2']) {
          final updates = await collect(session, 'proposal');
          if (turnId == 't1') {
            expect(
              [
                for (final u in updates)
                  if (u.kind == 'plan_update')
                    if (u.toJson()['plan'] case {
                      'type': 'markdown',
                      'content': final String content,
                    })
                      content,
              ],
              [
                '1. Read the code',
                '1. Inspect the code',
                '1. Inspect the code\n2. Write the change',
              ],
            );
          }
          transcript = fold([
            PromptAction(turnId, 'proposal', 0),
            for (final u in updates) UpdateAction(turnId, u),
          ], transcript);
        }
        const run = [
          "I'll look first.",
          'file:///plans/proposal.md',
          'Plan written. Draft dropped.',
        ];
        expect(
          [
            for (final e in transcript.entries)
              if (e is AssistantEntry) e.text.text,
          ],
          [...run, ...run],
        );
      },
    );
  }, skip: skip);

  // Codex's adapter streams a command's output to any client as it comes,
  // under `_meta`, whatever chord declared.
  test("a command's output streams into its terminal as Codex's adapter "
      'sends it, and its failing exit ends it', () async {
    await withSession((session, _) async {
      final watch = Stopwatch()..start();
      final arrived = <int>[];
      final (turn: _, :updates, result: _) = await run(
        session,
        'shell',
        onUpdate: (_, _) => arrived.add(watch.elapsedMilliseconds),
      );
      final seen = states([
        const PromptAction('t1', 'shell', 0),
        for (final update in updates) UpdateAction('t1', update),
      ]);
      List<Terminal> terminalsIn(Transcript state) => [
        for (final entry in state.entries)
          if (entry is ToolEntry) ...?entry.call.terminals,
      ];
      final outputs = <String>{
        for (final state in seen)
          for (final terminal in terminalsIn(state).take(1))
            if (!terminal.exited) terminal.output,
      };
      final terminal = terminalsIn(seen.last).single;

      // Each piece was there before the command ended, and they came apart.
      expect(outputs.toList(), [
        for (var index = 0; index < _shellOutput.length - 1; index++)
          plainText(_shellOutput.take(index).join()),
        plainText(_shellOutput.take(_shellOutput.length - 1).join()),
      ]);
      expect(arrived.last - arrived.first, greaterThanOrEqualTo(1500));
      expect(terminal.output, plainText(_shellOutput.join()));
      expect(terminal.exited, isTrue);
      expect(terminal.exitCode, 1);
      // The session's own directory, which the command ran in.
      expect(terminal.cwd, contains('chord-session-'));

      final call = seen.last.entries.whereType<ToolEntry>().single.call;

      expect(describedCall(call), {
        'id': calls(updates).first['toolCallId'],
        'title': 'Run bun dev test',
        'kind': 'execute',
        'status': 'failed',
        'content': [
          {'type': 'terminal', 'terminalId': terminal.id},
        ],
        'rawInput': {
          'command': ['deno', 'task', 'test'],
        },
        'terminals': [describedTerminal(terminal)],
      });
    });
  }, skip: skip);

  /// [updates] folded under a prompt of [prompt], each state on the way.
  List<Transcript> foldedEach(String prompt, List<acp.SessionUpdate> updates) =>
      states([
        PromptAction('t1', prompt, 0),
        for (final update in updates) UpdateAction('t1', update),
      ]);

  List<Map<String, Object?>> terminalsIn(Transcript state) => [
    for (final entry in state.entries)
      if (entry is ToolEntry)
        for (final terminal in entry.call.terminals ?? const <Terminal>[])
          describedTerminal(terminal),
  ];

  // Claude's adapter sends a command's terminal and output as `_meta` only
  // to a client that declares `terminal_output_delta`, which the window
  // does.
  test("a command's output comes whole at its end as Claude's adapter sends "
      'it to chord', () async {
    await withSession(capabilities: windowCapabilities(), (session, _) async {
      final updates = await collect(session, 'bash');
      final seen = foldedEach('bash', updates);
      final before = seen.take(seen.length - 1).expand(terminalsIn).toList();

      expect(before, isNotEmpty, reason: 'the terminal is named up front');
      expect(
        before
            .where((terminal) => terminal['output'] != '')
            .every((terminal) => terminal['output'] == _bashOutput),
        isTrue,
      );
      expect(
        calls(updates).where(
          (update) =>
              (update['_meta'] as Map?)?['terminal_output_delta'] != null,
        ),
        hasLength(1),
      );
      expect(terminalsIn(seen.last), [
        {
          'id': calls(updates).first['toolCallId'],
          'output': _bashOutput,
          'exited': true,
          'exitCode': 0,
        },
      ]);
    });
  }, skip: skip);

  test('a client that declares no terminal output gets the command as text '
      'and no terminal', () async {
    await withSession((session, _) async {
      final updates = await collect(session, 'bash');
      expect(terminalsIn(foldedEach('bash', updates).last), isEmpty);
      expect([
        for (final update in calls(updates))
          for (final key in ((update['_meta'] as Map?) ?? const {}).keys)
            if ((key as String).startsWith('terminal_')) key,
      ], isEmpty);
    });
  }, skip: skip);

  // Claude's adapter ends a call the turn leaves without a result `failed`,
  // with a line saying why, and a command's terminal with no exit code.
  test('a cancel ends a running command and a call that never ran failed, '
      "as Claude's adapter sends them", () async {
    await withSession(capabilities: windowCapabilities(), (session, _) async {
      final (turn: _, :updates, :result) = await run(
        session,
        'bashcut',
        onUpdate: (updates, turn) {
          if (calls(updates).length == 3) turn.cancel().ignore();
        },
      );
      final command = calls(updates).first['toolCallId'];

      expect(
        result,
        isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', isTrue),
      );
      expect(_endsOf(updates), [
        {
          'status': 'failed',
          'text': [
            'The turn was cancelled before this tool call returned a result.',
          ],
          'exit': {'terminal_id': command, 'exit_code': null, 'signal': null},
        },
        {
          'status': 'failed',
          'text': ['Claude stopped this tool call before it ran.'],
          'exit': null,
        },
      ]);
    });
  }, skip: skip);

  test('a turn that ends on its own leaves its command failed with '
      "Claude's line for no result", () async {
    await withSession(
      capabilities: windowCapabilities(),
      flags: const ['--step-ms', '1'],
      (session, _) async {
        final (turn: _, :updates, :result) = await run(session, 'bashcut');

        expect(
          result,
          isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', isFalse),
        );
        expect(
          [for (final end in _endsOf(updates)) end['text']],
          [
            ['Claude ended the turn without returning a result for this tool.'],
            ['Claude stopped this tool call before it ran.'],
          ],
        );
      },
    );
  }, skip: skip);

  List<Compaction> compactionsIn(Transcript state) => [
    for (final entry in state.entries)
      if (entry is CompactionEntry) entry.compaction,
  ];

  // Both adapters send compactions by id only to a client that declares
  // `session.compaction`, which chord does.
  test('a compaction runs, its summary streaming in, and completes as '
      "Claude's adapter sends it to chord", () async {
    await withSession(capabilities: windowCapabilities(), (session, _) async {
      final watch = Stopwatch()..start();
      final arrived = <int>[];
      final (turn: _, :updates, result: _) = await run(
        session,
        'compact',
        onUpdate: (_, _) => arrived.add(watch.elapsedMilliseconds),
      );
      final seen = foldedEach('compact', updates);
      final summaries = <String>{
        for (final state in seen)
          for (final compaction in compactionsIn(state))
            if (compaction.status == 'in_progress') compaction.summary,
      };

      expect(calls(updates), isEmpty);
      expect(summaries.toList(), [
        for (var index = 0; index <= _compactSummary.length; index++)
          _compactSummary.take(index).join(),
      ]);
      expect(arrived.last - arrived.first, greaterThanOrEqualTo(1500));
      expect(
        [for (final c in compactionsIn(seen.last)) describedCompaction(c)],
        [
          {
            'id': updates
                .firstWhere((update) => update.kind == 'compaction_update')
                .toJson()['compactionId'],
            'status': 'completed',
            'summary': _compactSummary.join(),
          },
        ],
      );
    });
  }, skip: skip);

  test(
    "a compaction completes with no summary as Codex's adapter sends it",
    () async {
      await withSession(capabilities: windowCapabilities(), (session, _) async {
        final updates = await collect(session, 'codexcompact');
        expect(
          [
            for (final c in compactionsIn(
              foldedEach('codexcompact', updates).last,
            ))
              (c.status, c.summary),
          ],
          [('completed', '')],
        );
      });
    },
    skip: skip,
  );

  test('a compaction that fails says why', () async {
    await withSession(capabilities: windowCapabilities(), (session, _) async {
      final updates = await collect(session, 'compactfail');
      expect(
        [
          for (final c in compactionsIn(
            foldedEach('compactfail', updates).last,
          ))
            (c.status, c.error),
        ],
        [('failed', 'Not enough messages to compact.')],
      );
    });
  }, skip: skip);

  test('a compaction its turn was cancelled under is cancelled', () async {
    await withSession(capabilities: windowCapabilities(), (session, _) async {
      final (turn: _, :updates, result: _) = await run(
        session,
        'compact',
        onUpdate: (updates, turn) {
          if (updates.length == 2) turn.cancel().ignore();
        },
      );
      expect(
        compactionsIn(foldedEach('compact', updates).last).first.status,
        'cancelled',
      );
    });
  }, skip: skip);

  test('a client that declares no compaction gets it as a tool call', () async {
    await withSession((session, _) async {
      final updates = await collect(session, 'codexcompact');
      expect(compactionsIn(foldedEach('codexcompact', updates).last), isEmpty);
      expect(calls(updates).first['title'], 'Compact conversation');
    });
  }, skip: skip);

  test('the markdownwrap reply is the exact sample, with no tool or thought, '
      'and the next turn still answers', () async {
    await withSession((session, _) async {
      final (turn: _, :updates, :result) = await run(session, 'markdownwrap');

      expect(said(updates), [_markdownWrap]);
      expect(said(updates, 'agent_thought_chunk'), isEmpty);
      expect(calls(updates), isEmpty);
      expect(
        said(updates).join(),
        contains('Soft\nbreak and a hard  \nbreak here.'),
      );
      expect(
        result,
        isA<TurnAnswered>().having(
          (r) => r.stopReason,
          'stopReason',
          'end_turn',
        ),
      );

      final next = await run(session, 'text');
      expect(
        said(next.updates).join(),
        'Hello, world. This reply came in chunks.',
      );
      expect(next.result, isA<TurnAnswered>());
    });
  }, skip: skip);

  test('the agent starts with the task list tools turned on', () async {
    await withSession((session, _) async {
      final own = Platform.environment['CLAUDE_CODE_ENABLE_TODO_TOOLS'] ?? '1';

      expect(said(await collect(session, 'todos')), ['todo tools: $own']);
    });
  }, skip: skip);

  test('the task list tools stay off when the person turned them off', () {
    expect(agentEnv({'CLAUDE_CODE_ENABLE_TODO_TOOLS': '0'}), isEmpty);
    expect(agentEnv({'CLAUDE_CODE_ENABLE_TODO_TOOLS': ''}), isEmpty);
    expect(agentEnv({}), {'CLAUDE_CODE_ENABLE_TODO_TOOLS': '1'});
  });

  test('usage and mode updates come through as the agent sent them', () async {
    await withSession((session, _) async {
      final (turn: _, :updates, :result) = await run(session, 'status');
      final mode = updates.firstWhere((u) => u.kind == 'current_mode_update');
      final usage = updates.firstWhere((u) => u.kind == 'usage_update');

      expect(mode.toJson()['currentModeId'], 'plan');
      expect([usage.toJson()['used'], usage.toJson()['size']], [1200, 200000]);
      expect(usage.toJson()['cost'], {'amount': 0.01, 'currency': 'USD'});
      expect(result, isA<TurnAnswered>());
      // The mode the agent moved to by the update alone is the one it is in.
      final modes = session.state.modes;
      final options = session.state.configOptions;
      expect(
        modes?['currentModeId'] ??
            options.firstWhere((o) => o['id'] == 'mode')['currentValue'],
        'plan',
      );
    });
  }, skip: skip);
}
