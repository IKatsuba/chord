// The ACP client against the original's fake agent, the agent the
// original's own client is checked against. Expectations are the original's
// tests' (tests/acp/connection_test.ts, tests/session/session_test.ts,
// tests/session/session_updates_test.ts) where they have one, else what the
// fake's scenario sends (tests/fixtures/fake_agent/scenarios/).
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/schema.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';

/// What `crash`'s agent leaves on stderr before it exits mid-turn.
const crashWords =
    'fatal: out of memory reading tests/parse/fixtures/huge.json';

/// The last line of `--start-fails traceback`'s traceback.
const tracebackError =
    "ImportError: cannot import name 'AuthMethod' from 'acp.schema'";

const editOld =
    'export function greet(name: string): string {\n'
    '  return "hello " + name;\n'
    '}\n';

const editNew =
    '/** Greets someone by name. */\n'
    'export function greet(name: string): string {\n'
    r'  return `hello, ${name}`;'
    '\n}\n';

/// A started fake with one session open.
typedef Opened = ({FakeAgentRun run, Agent agent, String sessionId});

Future<Opened> open({
  List<String> flags = const [],
  Map<String, String>? env,
  PermissionHandler? onPermission,
  ClientCapabilities? capabilities,
  StopBounds stop = fakeStopBounds,
}) async {
  final run = startFake(
    flags: flags,
    env: env,
    onPermission: onPermission,
    capabilities: capabilities,
    stop: stop,
  );
  final agent = await run.agent;
  final opened = await agent.newSession(
    NewSessionRequest(cwd: run.cwd, mcpServers: const []),
  );
  return (run: run, agent: agent, sessionId: opened.sessionId);
}

/// Plays [scenario], chosen as the original chooses it: the prompt's text.
Future<PromptResponse> play(
  Opened opened,
  String scenario, {
  CancellationToken? token,
}) => opened.agent.prompt(
  PromptRequest(
    sessionId: opened.sessionId,
    prompt: [ContentBlock.text(scenario)],
  ),
  cancellationToken: token,
);

/// Every tool call and its updates, as `[id, status]`, in order.
List<List<Object?>> callStatuses(TrafficRecorder traffic) => [
  for (final update in traffic.updates)
    if (update case {
      'sessionUpdate': 'tool_call' || 'tool_call_update',
      'toolCallId': final id,
      'status': final status,
    })
      [id, status],
];

/// The methods chord sent, requests and notifications alike.
List<Object?> sent(TrafficRecorder traffic) => [
  for (final traffic in traffic.heard)
    if (traffic case ChordTraffic(message: {'method': final method})) method,
];

/// The results chord answered the agent's requests with.
List<Object?> answered(TrafficRecorder traffic) => [
  for (final traffic in traffic.heard)
    if (traffic case ChordTraffic(message: {'result': final result})) result,
];

/// Until [check] holds, or five seconds pass.
Future<void> eventually(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) fail('it never happened');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Whether [future] is still pending after a moment.
Future<bool> pending(Future<Object?> future) async {
  var done = false;
  future.then((_) => done = true, onError: (_) => done = true);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return !done;
}

bool alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  group('the fake agent', skip: fakeAgentSkip, () {
    group('connect', () {
      test(
        'initialize answers, and a session opens in its directory',
        () async {
          final opened = await open();
          expect(opened.agent.init.protocolVersion, 1);
          expect(opened.sessionId, isNotEmpty);
          expect(sent(opened.run.traffic), ['initialize', 'session/new']);
        },
      );

      test('a close ends the agent with code 0', () async {
        final opened = await open(stop: fakeCloseBounds);
        await opened.agent.close();
        expect(await opened.agent.exited, const Exit(0));
        expect(alive(opened.agent.pid), isFalse);
      });

      test('a close ends with code 0 an agent held 150 ms across stdin\'s '
          'end, as a loaded machine holds it', () async {
        final opened = await open(stop: fakeCloseBounds);
        final pid = opened.agent.pid;
        Process.killPid(pid, ProcessSignal.sigstop);
        // Let go even if the close fails, so no stopped fake is left.
        final held = Timer(
          const Duration(milliseconds: 150),
          () => Process.killPid(pid, ProcessSignal.sigcont),
        );
        addTearDown(() {
          held.cancel();
          Process.killPid(pid, ProcessSignal.sigcont);
        });
        await opened.agent.close();
        expect(await opened.agent.exited, const Exit(0));
      });

      test('a broken one exits 1 before initialize, its traceback on '
          'stderr', () async {
        final run = startFake(flags: ['--start-fails', 'traceback']);
        await expectLater(
          run.agent,
          throwsA(
            isA<AgentGone>()
                .having(
                  (e) => e.message,
                  'message',
                  startsWith('The agent exited: '),
                )
                .having((e) => e.message, 'message', contains(tracebackError)),
          ),
        );
        expect(run.traffic.stderr, contains(tracebackError));
      });

      test('one that prints a line on stdout and exits 0 before initialize '
          'leaves chord nothing of it', () async {
        final run = startFake(flags: ['--start-fails', 'stdout']);
        await expectLater(
          run.agent,
          throwsA(
            isA<AgentGone>().having(
              (e) => e.message,
              'message',
              'The agent exited.',
            ),
          ),
        );
      });

      test('one that is not an ACP agent answers initialize and no session '
          'request', () async {
        final run = startFake(flags: ['--start-fails', 'notacp']);
        final agent = await run.agent;
        await expectLater(
          agent.newSession(
            NewSessionRequest(cwd: run.cwd, mcpServers: const []),
          ),
          throwsA(
            isA<RpcException>()
                .having((e) => e.code, 'code', -32601)
                .having(
                  (e) => e.message,
                  'message',
                  'Method not found: session/new',
                )
                .having((e) => e.data, 'data', isNull),
          ),
        );
      });

      test('one that needs an agent alias refuses session/new -32602 with no '
          'data', () async {
        final run = startFake(flags: ['--start-fails', 'alias']);
        final agent = await run.agent;
        await expectLater(
          agent.newSession(
            NewSessionRequest(cwd: run.cwd, mcpServers: const []),
          ),
          throwsA(
            isA<RpcException>()
                .having((e) => e.code, 'code', -32602)
                .having(
                  (e) => e.message,
                  'message',
                  'session/new requires `agentAlias` (alias of a configured '
                      '[agents.<alias>] entry)',
                )
                .having((e) => e.data, 'data', isNull),
          ),
        );
      });
    });

    group('prompt', () {
      test("a turn's updates reach the subscriber, in order, before its "
          'answer settles', () async {
        final opened = await open();
        final traffic = opened.run.traffic;
        final answer = await play(opened, 'text');
        final heard = traffic.heard;
        final response = heard.lastIndexWhere(
          (t) => t is AgentTraffic && t.message.containsKey('result'),
        );
        final lastUpdate = heard.lastIndexWhere(
          (t) => t is AgentTraffic && t.message['method'] == 'session/update',
        );
        expect(traffic.said, 'Hello, world. This reply came in chunks.');
        expect(answer.stopReason, StopReason.endTurn);
        expect(answer.usage?['totalTokens'], 2000);
        expect(response, greaterThan(lastUpdate));
        expect(traffic.updates.last['sessionUpdate'], 'usage_update');
      });

      test('--no-usage reports none', () async {
        final opened = await open(flags: ['--no-usage']);
        final answer = await play(opened, 'text');
        expect(
          opened.run.traffic.said,
          'Hello, world. This reply came in chunks.',
        );
        expect(answer.usage, isNull);
        expect(
          opened.run.traffic.updates.map((u) => u['sessionUpdate']),
          isNot(contains('usage_update')),
        );
      });

      test(
        'thought chunks arrive on their own stream before the reply',
        () async {
          final opened = await open();
          await play(opened, 'thought');
          final kinds = [
            for (final u in opened.run.traffic.updates) u['sessionUpdate'],
          ];
          final thoughts = [
            for (final u in opened.run.traffic.updates)
              if (u case {
                'sessionUpdate': 'agent_thought_chunk',
                'content': {'text': final String text},
              })
                text,
          ];
          expect(thoughts, ['Considering', ' the question.']);
          expect(opened.run.traffic.said, 'Here is the answer.');
          expect(
            kinds.lastIndexOf('agent_thought_chunk'),
            lessThan(kinds.indexOf('agent_message_chunk')),
          );
        },
      );

      test('the environment given reaches the agent', () async {
        final opened = await open(env: {'CLAUDE_CODE_ENABLE_TODO_TOOLS': '1'});
        await play(opened, 'todos');
        expect(opened.run.traffic.said, 'todo tools: 1');
      });

      test(
        'a tool call goes pending, in progress, completed under one id',
        () async {
          final opened = await open();
          await play(opened, 'tools');
          expect(callStatuses(opened.run.traffic), [
            ['read-1', 'pending'],
            ['read-1', 'in_progress'],
            ['read-1', 'completed'],
          ]);
          final calls = opened.run.traffic.updates
              .where((u) => u['toolCallId'] == 'read-1')
              .toList();
          expect(calls.first['title'], 'Read README.md');
          expect(calls.first['kind'], 'read');
          expect(calls.last['content'], [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': '# chord'},
            },
          ]);
          expect(opened.run.traffic.said, 'Read it.');
        },
      );

      test('calls end completed and failed', () async {
        final opened = await open();
        await play(opened, 'calls');
        expect(callStatuses(opened.run.traffic), [
          ['read-1', 'in_progress'],
          ['read-1', 'completed'],
          ['bash-2', 'in_progress'],
          ['bash-2', 'completed'],
          ['read-3', 'in_progress'],
          ['read-3', 'failed'],
        ]);
        expect(opened.run.traffic.said, 'Two calls worked, one failed.');
      });

      test('an edit carries its diff', () async {
        final opened = await open();
        await play(opened, 'edit');
        final edits = opened.run.traffic.updates
            .where((u) => u['toolCallId'] == 'edit-1')
            .toList();
        expect(edits.first['kind'], 'edit');
        expect(edits.last['content'], [
          {
            'type': 'diff',
            'path': 'src/greeting.ts',
            'oldText': editOld,
            'newText': editNew,
          },
        ]);
        expect(opened.run.traffic.said, 'Edited.');
      });

      test('a rewrite carries a diff of the whole table', () async {
        final opened = await open();
        await play(opened, 'rewrite');
        final last = opened.run.traffic.updates.lastWhere(
          (u) => u['toolCallId'] == 'rewrite-1',
        );
        expect(last['status'], 'completed');
        expect(last['content'], [
          isA<Map<String, Object?>>()
              .having((d) => d['type'], 'type', 'diff')
              .having((d) => d['path'], 'path', 'src/table.ts')
              .having(
                (d) => d['oldText'],
                'oldText',
                contains("{ id: 60, name: 'row 60' }"),
              ),
        ]);
        expect(opened.run.traffic.said, 'Rewrote the table.');
      });

      test('markdown streams line by line, whole', () async {
        final opened = await open();
        await play(opened, 'markdown');
        final said = opened.run.traffic.said;
        expect(said, startsWith('# Reading the session layer\n\n'));
        expect(said, endsWith('do echo "built \$bin"; done\n```'));
        final chunks = opened.run.traffic.updates
            .where((u) => u['sessionUpdate'] == 'agent_message_chunk')
            .length;
        expect(chunks, '\n'.allMatches(said).length + 1);
      });

      test('long streams its numbered lines until cancelled', () async {
        final opened = await open();
        final turn = play(opened, 'long');
        await eventually(
          () => opened.run.traffic.said.contains('2. Line 2 of 200'),
        );
        expect(
          opened.run.traffic.said,
          startsWith('1. Line 1 of 200, streamed one at a time.'),
        );
        await opened.agent.cancel(opened.sessionId);
        expect((await turn).stopReason, StopReason.cancelled);
        expect(opened.run.traffic.said, isNot(contains('200. Line 200')));
      });

      test('an update the agent sends after answering still reaches the '
          'subscriber', () async {
        final opened = await open();
        await play(opened, 'late');
        expect(opened.run.traffic.said, 'Answered.');
        await eventually(
          () => opened.run.traffic.said == 'Answered. Late, after the answer.',
        );
      });

      test('an update or notification of a kind no schema knows comes '
          'through raw', () async {
        final opened = await open();
        await play(opened, 'unknown');
        expect(
          opened.run.traffic.updates,
          contains(
            equals({'sessionUpdate': 'future_update', 'detail': 'from later'}),
          ),
        );
        expect(
          [
            for (final t in opened.run.traffic.heard)
              if (t case AgentTraffic(
                message: {'method': '_fake/notice', 'params': final params},
              ))
                params,
          ],
          [
            {'text': 'an extension'},
          ],
        );
        expect(opened.run.traffic.said, 'Sent the unknown.');
      });

      test("Claude's sign-in notifications are dropped and the turn "
          'completes', () async {
        final opened = await open();
        final answer = await play(opened, 'authstatus');
        const status = {
          'state': 'authenticated',
          'accounts': [
            {'label': 'Claude Max', 'active': true},
          ],
        };
        expect(answer.stopReason, StopReason.endTurn);
        for (final method in ['_auth/status_update', 'auth/status_update']) {
          expect(
            [
              for (final t in opened.run.traffic.heard)
                if (t case AgentTraffic(
                  message: {'method': final m, 'params': final p},
                ) when m == method)
                  p,
            ],
            [status],
          );
        }
        expect(opened.run.traffic.said, 'Sent the sign-in state.');
      });

      test(
        'a failed turn says why, and the session takes the next prompt',
        () async {
          final opened = await open();
          await expectLater(
            play(opened, 'error'),
            throwsA(
              isA<RpcException>()
                  .having((e) => e.code, 'code', -32603)
                  .having(
                    (e) => e.message,
                    'message',
                    'The fake agent failed on purpose.',
                  ),
            ),
          );
          expect(opened.run.traffic.said, 'About to fail.');
          expect((await play(opened, 'text')).stopReason, StopReason.endTurn);
          expect(opened.agent.gone(), isNull);
        },
      );

      test("a turn failed on the model's error carries its reason", () async {
        final opened = await open();
        await expectLater(
          play(opened, 'turnfailed'),
          throwsA(
            isA<RpcException>()
                .having((e) => e.code, 'code', -32603)
                .having(
                  (e) => e.message,
                  'message',
                  'Request failed: the model is overloaded.',
                )
                .having((e) => e.data, 'data', {'reason': 'turn_failed'}),
          ),
        );
        expect(opened.run.traffic.said, 'Reading the tests.');
        expect(opened.agent.gone(), isNull);
      });
    });

    group('permission', () {
      test(
        'a permission waits for the answer and gets the option chosen',
        () async {
          final asked = <RequestPermissionRequest>[];
          final opened = await open(
            onPermission: (request, token) async {
              asked.add(request);
              return RequestPermissionResponse.selected('always');
            },
          );
          await play(opened, 'permission');
          expect(asked.single.toolCall.toolCallId, 'write-1');
          expect(asked.single.options.map((o) => o.optionId), [
            'allow',
            'always',
            'deny',
          ]);
          expect(opened.run.traffic.said, 'Permission: always.');
          expect(callStatuses(opened.run.traffic).last, [
            'write-1',
            'completed',
          ]);
        },
      );

      test(
        'a rejected permission reaches the agent as its reject option',
        () async {
          final opened = await open(
            onPermission: (request, token) async =>
                RequestPermissionResponse.selected('deny'),
          );
          await play(opened, 'permission');
          expect(opened.run.traffic.said, 'Permission: deny.');
          expect(callStatuses(opened.run.traffic).last, ['write-1', 'failed']);
        },
      );

      test('a permission is answered by the exact option picked, even among '
          'two of one kind', () async {
        final asked = <RequestPermissionRequest>[];
        final opened = await open(
          onPermission: (request, token) async {
            asked.add(request);
            return RequestPermissionResponse.selected('allow-here');
          },
        );
        await play(opened, 'twins');
        expect(opened.run.traffic.said, 'Permission: allow-here.');
        expect(asked.single.options.map((o) => o.kind), [
          'allow_once',
          'allow_once',
          'reject_once',
        ]);
      });

      test('a permission asked while another call stays open', () async {
        final opened = await open(
          onPermission: (request, token) async =>
              RequestPermissionResponse.selected('allow'),
        );
        await play(opened, 'overlapask');
        expect(callStatuses(opened.run.traffic), [
          ['overlapask-a', 'in_progress'],
          ['write-1', 'pending'],
          ['write-1', 'completed'],
          ['overlapask-a', 'completed'],
        ]);
        expect(opened.run.traffic.said, 'Permission: allow.');
      });

      test(
        'a permission left open as the turn ends is still answered',
        () async {
          final asking = Completer<void>();
          final answer = Completer<RequestPermissionResponse>();
          final opened = await open(
            onPermission: (request, token) {
              asking.complete();
              return answer.future;
            },
          );
          final turn = play(opened, 'leftask');
          await asking.future;
          expect((await turn).stopReason, StopReason.endTurn);
          expect(
            opened.run.traffic.said,
            'I asked; the turn ends with it open.',
          );
          answer.complete(RequestPermissionResponse.selected('allow'));
          await eventually(
            () => opened.run.traffic.said.endsWith('Permission: allow.'),
          );
        },
      );

      test('a permission asked between turns is answered', () async {
        final asking = Completer<RequestPermissionRequest>();
        final opened = await open(
          onPermission: (request, token) async {
            asking.complete(request);
            return RequestPermissionResponse.selected('allow');
          },
        );
        expect(
          (await play(opened, 'mainbetween')).stopReason,
          StopReason.endTurn,
        );
        expect(asking.isCompleted, isFalse);
        expect((await asking.future).toolCall.toolCallId, 'write-1');
        await eventually(
          () =>
              opened.run.traffic.said ==
              'I will write the report once the build is done.'
                  'Permission: allow.',
        );
      });
    });

    group('cancel', () {
      test('a cancel ends a slow turn early, and the agent answers it '
          'cancelled', () async {
        final opened = await open();
        final turn = play(opened, 'slow');
        await eventually(() => opened.run.traffic.said.startsWith('Working'));
        await opened.agent.cancel(opened.sessionId);
        expect((await turn).stopReason, StopReason.cancelled);
        // The turn is a thousand chunks long; stopping early is the agent
        // honouring cancel.
        expect(opened.run.traffic.said.length, lessThan(1000));
      });

      test("a prompt's token stops the wait and cancels the turn", () async {
        final opened = await open();
        final token = CancellationToken();
        final turn = play(opened, 'slow', token: token);
        await eventually(() => opened.run.traffic.said.startsWith('Working'));
        token.cancel();
        await expectLater(turn, throwsA(isA<CancelledException>()));
        expect(sent(opened.run.traffic), contains('session/cancel'));
      });

      test('a cancel answers a permission still waiting on the person as '
          'cancelled', () async {
        CancellationToken? withdrawn;
        final opened = await open(
          onPermission: (request, token) {
            withdrawn = token;
            return Completer<RequestPermissionResponse>().future;
          },
        );
        final turn = play(opened, 'permission');
        await eventually(() => withdrawn != null);
        await opened.agent.cancel(opened.sessionId);
        expect((await turn).stopReason, StopReason.cancelled);
        expect(withdrawn!.isCancelled, isTrue);
        expect(answered(opened.run.traffic), [
          {
            'outcome': {'outcome': 'cancelled'},
          },
        ]);
      });

      test('a cancel with no turn reaches the agent', () async {
        final opened = await open();
        await opened.agent.cancel(opened.sessionId);
        await play(opened, 'cancels');
        expect(opened.run.traffic.said, 'Cancels with no turn: 1.');
      });

      test(
        'a cancel during a turn is not counted as one with no turn',
        () async {
          final opened = await open();
          final turn = play(opened, 'slow');
          await eventually(() => opened.run.traffic.said.startsWith('Working'));
          await opened.agent.cancel(opened.sessionId);
          await turn;
          opened.run.traffic.heard.clear();
          await play(opened, 'cancels');
          expect(opened.run.traffic.said, 'Cancels with no turn: 0.');
        },
      );

      test('a stopped subagent ends alone, its parent turn going on, and '
          'the agent is reusable', () async {
        // Subagents go only to a client that declares it takes them.
        final opened = await open(capabilities: windowCapabilities());
        final turn = play(opened, 'codexsubagentstop');
        Map<String, Object?>? offered() => opened.run.traffic.updates
            .where(
              (u) =>
                  u['sessionUpdate'] == 'subagent_update' &&
                  (u['capabilities'] as Map?)?['cancel'] != null,
            )
            .firstOrNull;
        await eventually(() => offered() != null);
        final child = offered()!['sessionId'] as String;
        await opened.agent.stopSubagent(child);
        expect((await turn).stopReason, StopReason.endTurn);
        expect(
          opened.run.traffic.updates.where(
            (u) =>
                u['sessionUpdate'] == 'subagent_update' &&
                (u['state'] as Map?)?['state'] == 'idle' &&
                (u['state'] as Map?)?['stopReason'] == 'cancelled',
          ),
          hasLength(1),
        );
        expect(
          [
            for (final traffic in opened.run.traffic.heard)
              if (traffic case ChordTraffic(
                message: {'method': 'session/cancel', 'params': final params},
              ))
                params,
          ],
          [
            {'sessionId': child},
          ],
        );
        opened.run.traffic.heard.clear();
        await play(opened, 'text');
        expect(opened.run.traffic.said, contains('Hello, world.'));
      });
    });

    group('exit', () {
      test('an agent that exits mid-turn fails the turn, and its last words '
          'are what it left on stderr', () async {
        final opened = await open();
        expect(opened.agent.gone(), isNull);
        await expectLater(
          play(opened, 'crash'),
          throwsA(
            isA<AgentGone>().having(
              (e) => e.message,
              'message',
              'The agent exited: $crashWords',
            ),
          ),
        );
        expect(opened.agent.gone(), crashWords);
        expect(await opened.agent.exited, const Exit(1));
      });
    });

    group('hang', () {
      test('one that ignores cancel keeps its prompt until close, which '
          'fails it as gone', () async {
        final opened = await open();
        final turn = play(opened, 'ignorescancel');
        await eventually(() => opened.run.traffic.said == 'Holding on.');
        await opened.agent.cancel(opened.sessionId);
        expect(await pending(turn), isTrue);
        final closing = opened.agent.close();
        await expectLater(turn, throwsA(isA<AgentGone>()));
        await closing;
        expect(alive(opened.agent.pid), isFalse);
      });

      test('a turn that never ends is failed as gone by close, which goes '
          'to SIGKILL', () async {
        final opened = await open(flags: ['--hang', 'turn']);
        final turn = play(opened, 'text');
        await opened.agent.cancel(opened.sessionId);
        expect(await pending(turn), isTrue);
        final watch = Stopwatch()..start();
        final closing = opened.agent.close();
        await expectLater(turn, throwsA(isA<AgentGone>()));
        await closing;
        // It ignores stdin's end and SIGTERM: both bounds run out first.
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(fakeStopBounds.exit + fakeStopBounds.term),
        );
        expect((await opened.agent.exited).signal, 'SIGKILL');
      });

      test('a start that never answers initialize waits until given up, '
          'then the whole ladder ends it', () async {
        final run = startFake(flags: ['--hang', 'start', '--say-wedged']);
        final process = await run.process;
        await run.traffic.next(
          (t) => t is ChordTraffic && t.message['method'] == 'initialize',
        );
        // Chord's initialize can go out before the fake's VM reaches main,
        // where SIGTERM would still end it: the ladder is timed from its
        // word that SIGTERM is ignored.
        await run.traffic.next(
          (t) => t is StderrTraffic && t.text.contains('wedged'),
        );
        expect(await pending(run.agent), isTrue);
        final watch = Stopwatch()..start();
        run.opening.cancel();
        await expectLater(run.agent, throwsA(isA<CancelledException>()));
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(fakeStopBounds.exit + fakeStopBounds.term),
        );
        expect((await process.status).signal, 'SIGKILL');
        expect(alive(process.pid), isFalse);
      });
    });
  });

  group('tester session boundaries', skip: fakeAgentSkip, () {
    test(
      'concurrent sign-in notifications preserve each session update',
      () async {
        final opened = await open(stop: fakeCloseBounds);
        final second = await opened.agent.newSession(
          NewSessionRequest(cwd: opened.run.cwd, mcpServers: const []),
        );
        final ids = [opened.sessionId, second.sessionId];
        expect(ids.toSet(), hasLength(2));
        final answers = await Future.wait([
          for (final id in ids)
            opened.agent.prompt(
              PromptRequest(
                sessionId: id,
                prompt: [ContentBlock.text('authstatus')],
              ),
            ),
        ]);
        expect(
          answers.map((a) => a.stopReason),
          everyElement(StopReason.endTurn),
        );
        for (final method in ['_auth/status_update', 'auth/status_update']) {
          expect(
            opened.run.traffic.heard.where(
              (t) => t is AgentTraffic && t.message['method'] == method,
            ),
            hasLength(2),
          );
        }
        for (final id in ids) {
          final updates = [
            for (final t in opened.run.traffic.heard)
              if (t
                  case AgentTraffic(
                    message: {
                      'method': 'session/update',
                      'params': {
                        'sessionId': final String session,
                        'update': final Map<String, Object?> update,
                      },
                    },
                  )
                  when session == id &&
                      update['sessionUpdate'] != 'available_commands_update' &&
                      update['sessionUpdate'] != 'usage_update')
                update,
          ];
          expect(updates, [
            {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'Sent the sign-in state.'},
            },
          ]);
        }
        await opened.agent.close();
        expect(opened.run.traffic.stderr, isEmpty);
        expect(await opened.agent.exited, const Exit(0));
      },
    );

    test(
      'cancelling one session leaves another turn live and both reusable',
      () async {
        final opened = await open();
        final second = await opened.agent.newSession(
          NewSessionRequest(cwd: opened.run.cwd, mcpServers: const []),
        );
        final other = (
          run: opened.run,
          agent: opened.agent,
          sessionId: second.sessionId,
        );
        final firstTurn = play(opened, 'slow');
        final secondTurn = play(other, 'slow');
        for (final id in [opened.sessionId, second.sessionId]) {
          await opened.run.traffic.next((t) {
            if (t case AgentTraffic(
              message: {
                'method': 'session/update',
                'params': {
                  'sessionId': final String session,
                  'update': {
                    'sessionUpdate': 'agent_message_chunk',
                    'content': {'text': 'Working'},
                  },
                },
              },
            )) {
              return session == id;
            }
            return false;
          });
        }
        await opened.agent.cancel(opened.sessionId);
        expect((await firstTurn).stopReason, StopReason.cancelled);
        expect(await pending(secondTurn), isTrue);
        await opened.agent.cancel(second.sessionId);
        expect((await secondTurn).stopReason, StopReason.cancelled);
        expect(
          (await play(opened, 'authstatus')).stopReason,
          StopReason.endTurn,
        );
        expect((await play(other, 'text')).stopReason, StopReason.endTurn);
        expect(opened.run.traffic.said, contains('Hello, world.'));
        await opened.agent.close();
        expect(opened.run.traffic.stderr, isEmpty);
      },
    );
  });

  // After every test above, nothing of the fake is left.
  tearDownAll(() {
    expect(
      [
        for (final pid in fakeAgentPids)
          if (alive(pid)) pid,
      ],
      isEmpty,
      reason: 'fake agents left running',
    );
  });
}
