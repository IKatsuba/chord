import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/context.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/tasks.dart' show wrapTeamMessage, wrapMessage;
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/subagents.dart' show subagentsIn;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/transcript/tools/tools.dart' as tools;
import 'package:path/path.dart' as p;
import 'package:chord/session/subagents.dart' show Heard;
import 'package:test/test.dart';

Map<String, Object?> prompt(String id, String text, [num at = 1]) => {
  'type': 'prompt',
  'turnId': id,
  'at': at,
  'prompt': text,
  'images': 0,
};
Map<String, Object?> update(
  String kind, [
  Map<String, Object?> more = const {},
]) => {
  'type': 'update',
  'turnId': 't',
  'update': {'sessionUpdate': kind, ...more},
};
acp.SessionUpdate chunk(String kind, Map<String, Object?> content) =>
    acp.SessionUpdate.fromJson({'sessionUpdate': kind, 'content': content});
Transcript fold(List<TranscriptAction> actions) =>
    actions.fold(Transcript.empty, reduceTranscript);

Object? normalize(Object? value) {
  if (value is List) return value.map(normalize).toList();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.value != null &&
            entry.key != 'running' &&
            !(value.containsKey('command') &&
                entry.value == false &&
                {'stopped', 'truncated'}.contains(entry.key)))
          entry.key as String: normalize(entry.value),
    };
  }
  return value;
}

/// [updates], each the session's own as it heard them.
List<Heard> own(List<acp.SessionUpdate> updates) => [
  for (final update in updates) (update: update, subagentId: null),
];

void main() {
  group('tester CTUI-160: sign-in account privacy in records', () {
    for (final account in <AccountState?>[
      null,
      noAccount,
      const AccountPending(),
      const AccountFailed(),
      const AccountHeard({'state': 'unauthenticated'}),
      const AccountHeard({
        'state': 'authenticated',
        'accounts': [
          {
            'label': 'private-label',
            'email': 'private@example.test',
            'organization': 'private-organization',
            'active': true,
          },
        ],
      }),
    ]) {
      test(
        '${account.runtimeType} is excluded through the complete result round trip',
        () {
          final signIn = SignIn('refused', [
            (name: null, description: 'Browser'),
          ], account: account);
          final written =
              jsonDecode(
                    jsonEncode(
                      recordResult(
                        TurnFailed('refused', code: -32000, signIn: signIn),
                      ),
                    ),
                  )
                  as Map<String, Object?>;
          expect(jsonEncode(written), isNot(contains('account')));
          expect(jsonEncode(written), isNot(contains('private')));
          final past = recordActions([
            prompt('t', 'hello'),
            {'type': 'result', 'turnId': 't', 'result': written},
          ]);
          final entry = fold(
            PreparedHistory.fromJson(past.toJson()).actions,
          ).entries.whereType<ErrorEntry>().single;
          expect(entry.signIn!.message, 'refused');
          expect(entry.signIn!.ways, [(name: null, description: 'Browser')]);
          expect(entry.signIn!.account, isNull);
          expect(signIn.account, same(account));
        },
      );
    }

    test('a raw legacy record cannot restore account facts through signIn', () {
      final raw = {
        'message': 'refused',
        'ways': <Object?>[],
        'account': {
          'phase': 'heard',
          'status': {
            'state': 'authenticated',
            'accounts': [
              {'email': 'private@example.test'},
            ],
          },
        },
      };
      expect(recordSignIn(raw)!.account, isNull);
      final past = recordActions([
        prompt('t', 'hello'),
        {
          'type': 'result',
          'turnId': 't',
          'result': {
            'status': 'failed',
            'error': {'message': 'refused', 'code': '-32000', 'signIn': raw},
          },
        },
      ]);
      for (final actions in [
        past.actions,
        PreparedHistory.fromJson(past.toJson()).actions,
      ]) {
        expect(
          fold(actions).entries.whereType<ErrorEntry>().single.signIn!.account,
          isNull,
        );
      }
    });
  });
  group('tester: CTUI-65 legacy sender roundtrip', () {
    Map<String, Object?> served(String tool, String name) => {
      'type': 'served',
      'turnId': tool,
      'at': 0,
      'call': {
        'tool': tool,
        'args': <String, Object?>{},
        'answer': {'id': 'child', 'name': name},
      },
    };
    PreparedHistory copied(List<Object?> entries) => PreparedHistory.fromJson(
      jsonDecode(jsonEncode(recordActions(entries).toJson()))
          as Map<String, Object?>,
    );

    test('reachable monitor metadata survives JSON and transcript folding', () {
      const name = 'parser "界🙂e\u0301"';
      final past = copied([
        served('open_agent', name),
        prompt(
          'legacy',
          wrapMessage(
            const MessageFrom(name, monitor: (id: 'm-界🙂', end: null)),
            'body\n\x1b[31mred\x1b[0m',
          ),
        ),
      ]);
      const expected = MessageFrom(
        name,
        monitor: (id: 'm-界🙂', end: null),
        reachable: true,
      );
      final action = past.actions.whereType<PromptAction>().single;
      expect(action.from, expected);
      final entry = fold(past.actions).entries.whereType<UserEntry>().single;
      expect(entry.from, expected);
      expect(entry.text, 'body\n\x1b[31mred\x1b[0m');
      final restored = copied(historyEntries(past.actions));
      // The original's historyEntries writes bare prompt text, without from.
      expect(restored.actions.whereType<PromptAction>().single.from, isNull);
    });

    test(
      'a task name overrides child reachability regardless of answer order',
      () {
        for (final reverse in [false, true]) {
          final answers = [
            served('open_agent', 'worker'),
            served('spawn_task', 'worker'),
          ];
          final past = copied([
            ...reverse ? answers.reversed : answers,
            prompt(
              'legacy',
              wrapMessage(
                const MessageFrom('worker', monitor: (id: 'm1', end: null)),
                'task-named monitor',
              ),
            ),
          ]);
          expect(
            past.actions.whereType<PromptAction>().single.from,
            const MessageFrom('worker', monitor: (id: 'm1', end: null)),
          );
        }
      },
    );

    for (final note in MessageNote.values) {
      test('legacy task ${note.name} cannot inherit an open child address', () {
        final past = copied([
          served('open_agent', 'worker'),
          prompt(
            'legacy',
            wrapMessage(
              MessageFrom('worker', runtime: 'codex', note: note),
              'done',
            ),
          ),
        ]);
        expect(
          past.actions.whereType<PromptAction>().single.from,
          MessageFrom('worker', runtime: 'codex', note: note),
        );
      });
    }
  });

  group('CTUI-37 tester: team prompt serialization', () {
    test(
      'PreparedHistory roundtrip preserves instruction boundaries and Unicode',
      () {
        const part = (
          team: 'bugfix',
          member: 'tester',
          text: '界🙂é\n\x1b[31mred\x1b[0m\n',
        );
        const from = MessageFrom('bugfix', reachable: true);
        final history = recordActions([
          {
            'type': 'session',
            'version': 1,
            'sessionId': 's',
            'agent': 'fake',
            'cwd': '/w',
            'at': 0,
          },
          {
            ...prompt('t1', wrapTeamMessage(part, from, 'job')),
            'from': from.toJson(),
          },
          {
            'type': 'result',
            'turnId': 't1',
            'result': {'status': 'completed', 'stopReason': 'end_turn'},
          },
        ]);
        final copied = PreparedHistory.fromJson(
          jsonDecode(jsonEncode(history.toJson())) as Map<String, Object?>,
        );
        final state = fold(copied.actions);
        expect(state.entries.whereType<TeamPartEntry>().single.part, part);
        expect(state.entries.whereType<UserEntry>().single.text, 'job');
        expect(
          state.entries.whereType<UserEntry>().single.from?.name,
          'bugfix',
        );
        expect(copied.actions.whereType<PromptAction>().single.team, part);
      },
    );
  });
  test("a team agent's first message replays with the team part that went "
      'ahead of it, drawn before it', () {
    const from = MessageFrom('bugfix', reachable: true);
    const part = (team: 'bugfix', member: 'tester', text: 'You are tester.');
    final history = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'fake',
        'cwd': '/w',
        'at': 0,
      },
      {
        'type': 'prompt',
        'turnId': 't1',
        'prompt': wrapTeamMessage(part, from, 'Write the test.'),
        'images': 0,
        'at': 1,
        'from': from.toJson(),
      },
      {
        'type': 'result',
        'turnId': 't1',
        'result': {'status': 'completed', 'stopReason': 'end_turn'},
      },
    ]);
    expect(history.omitted, isFalse);
    final prompt = history.actions.whereType<PromptAction>().single;
    expect((prompt.text, prompt.team), ('Write the test.', part));
    final state = history.actions.fold(Transcript.empty, reduceTranscript);
    final [teamPart, message, ...] = state.entries;
    expect((teamPart as TeamPartEntry).part, part);
    expect((message as UserEntry).from?.name, 'bugfix');
  });
  test("a replayed past's title is the session's own, not a subagent's", () {
    Heard titled(String title, [String? from]) => (
      update: acp.SessionUpdate.fromJson({
        'sessionUpdate': 'session_info_update',
        'title': title,
      }),
      subagentId: from,
    );
    final past = pastActions([
      titled('Main'),
      titled('Child', 'c'),
      titled('Grandchild', 'g'),
    ], 1);
    expect(past.title, 'Main');
  });

  test("a session's replayed past keeps its subagents' work under them, "
      "nested, and they end disconnected", () {
    Heard said(String text, [String? from]) => (
      update: acp.SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
      }),
      subagentId: from,
    );
    Heard spawned(String id, [String? from]) => (
      update: acp.SessionUpdate.fromJson({
        'sessionUpdate': 'subagent_update',
        'sessionId': id,
        'title': 'Agent $id',
      }),
      subagentId: from,
    );
    final past = pastActions([
      (
        update: acp.SessionUpdate.fromJson({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'look'},
        }),
        subagentId: null,
      ),
      said('started'),
      spawned('c'),
      said('child work', 'c'),
      spawned('g', 'c'),
      said('grandchild work', 'g'),
    ], 1);
    expect(past.actions.last, isA<DisconnectedAction>());
    final transcript = past.actions.fold(Transcript.empty, reduceTranscript);
    final agents = subagentsIn(transcript.entries);
    expect([for (final a in agents) a.id], ['c', 'g']);
    String words(Subagent a) => [
      for (final e in a.entries)
        if (e is AssistantEntry) e.text.text,
    ].join();
    expect(words(agents[0]), 'child work');
    expect(words(agents[1]), 'grandchild work');
    expect(
      [for (final a in agents) a.state],
      [SubagentState.disconnected, SubagentState.disconnected],
    );
  });

  for (final agentLoad in [false, true]) {
    for (final unknown in [false, true]) {
      test(
        '${agentLoad ? 'agent-load' : 'local'} mixed tool content keeps supported parts, unknown=$unknown',
        () {
          final report = <String, Object?>{
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tool',
            'title': 'kept title',
            'status': 'completed',
            '_meta': {
              'future': {'extra': true},
              'terminal_output': {
                'terminal_id': 'terminal',
                'data': 'terminal output',
              },
            },
            'content': [
              {
                'type': 'content',
                'content': {
                  'type': 'text',
                  'text': 'supported text',
                  'future': true,
                },
                'future': true,
              },
              {
                'type': 'diff',
                'path': 'fixture.dart',
                'oldText': 'old',
                'newText': 'new',
                'future': true,
              },
              {'type': 'terminal', 'terminalId': 'terminal', 'future': true},
              for (final kind in [
                'image',
                'audio',
                'resource',
                'resource_link',
              ])
                {
                  'type': 'content',
                  'content': {'type': kind, 'future': true},
                },
              if (unknown)
                {'type': 'future_content', 'text': 'saved unknown output'},
            ],
          };
          final past = agentLoad
              ? pastActions(own([acp.SessionUpdate.fromJson(report)]), 1)
              : recordActions([
                  {'type': 'update', 'turnId': 't', 'update': report},
                ]);
          expect(past.omitted, unknown);
          final call = fold(
            past.actions,
          ).entries.whereType<ToolEntry>().single.call;
          expect(call.title, 'kept title');
          final drawn = tools.summary(call, false);
          expect(
            drawn.lines,
            containsAll([
              'supported text',
              '[image]',
              '[audio]',
              '[resource]',
              '[resource_link]',
            ]),
          );
          expect(drawn.diffs, hasLength(1));
          expect(call.terminals!.single.output, 'terminal output');
          expect(call.content, hasLength(unknown ? 8 : 7));
        },
      );
    }
    test(
      '${agentLoad ? 'agent-load' : 'local'} unknown inner block is flagged and metadata-only update is harmless',
      () {
        final unknown = {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tool',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'future_block', 'text': 'unknown'},
            },
          ],
        };
        final metadata = {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'tool',
          '_meta': {'future': true},
        };
        PreparedHistory prepare(Map<String, Object?> report) => agentLoad
            ? pastActions(own([acp.SessionUpdate.fromJson(report)]), 1)
            : recordActions([
                {'type': 'update', 'turnId': 't', 'update': report},
              ]);
        expect(prepare(unknown).omitted, isTrue);
        expect(prepare(metadata).omitted, isFalse);
        expect(
          prepare(unknown).actions.whereType<UpdateAction>(),
          hasLength(1),
        );
      },
    );
  }

  test(
    'recall retains supported nondrawing metadata in original report order',
    () {
      final past = recordActions([
        update('current_mode_update', {'currentModeId': 'A'}),
        update('config_option_update', {'configOptions': <Object?>[]}),
        update('session_info_update', {'title': 'named'}),
        update('current_mode_update', {'currentModeId': 'C'}),
        {
          ...update('tool_call', {'toolCallId': 'child'}),
          'subagentId': 'child',
        },
      ]);
      final copied = PreparedHistory.fromJson(past.toJson());
      expect(copied.recalled.map((u) => u.kind), [
        'current_mode_update',
        'config_option_update',
        'session_info_update',
        'current_mode_update',
      ]);
      // A subagent's update is drawn under it, never recalled as the
      // session's own.
      expect(
        [
          for (final a in copied.actions.whereType<UpdateAction>())
            a.subagentId,
        ],
        [null, null, 'child'],
      );
      expect(
        () => copied.recalled.add(acp.SessionUpdate.fromJson({})),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'base plan, context and mode replay preserve reported numeric facts',
    () {
      final past = recordActions([
        prompt('t', 'work'),
        update('plan', {
          'entries': [
            {
              'content': 'finished',
              'priority': 'medium',
              'status': 'completed',
            },
          ],
        }),
        update('usage_update', {'used': 1.25, 'size': 8.5}),
        update('current_mode_update', {'currentModeId': 'plan'}),
      ]);
      expect(past.omitted, isFalse);
      final transcript = fold(past.actions);
      expect(transcript.usage!.used, 1.25);
      expect(transcript.usage!.size, 8.5);
      expect(transcript.mode, 'plan');
      expect(
        transcript.entries
            .whereType<FinishedPlanEntry>()
            .single
            .entries
            .single
            .content,
        'finished',
      );
      // A legacy `plan` update carrying a planId replays as the live reducer
      // draws it, its id ignored, as the original's recordActions passes
      // every update to its reducer (CTUI-167).
      final legacy = recordActions([
        update('plan', {
          'planId': 'legacy',
          'entries': [
            {'content': 'drawn', 'priority': 'medium', 'status': 'in_progress'},
          ],
        }),
      ]);
      expect(legacy.omitted, isFalse);
      final drawn = fold(legacy.actions);
      expect(drawn.plan.single.content, 'drawn');
      expect(drawn.planId, isNull);
      expect(
        recordActions([
          {
            ...update('agent_message_chunk', {
              'content': {'type': 'text', 'text': 'bad time'},
            }),
            'at': 'wrong',
          },
        ]).omitted,
        isTrue,
      );
      expect(
        recordActions([
          {...prompt('t', 'bad images'), 'images': double.infinity},
        ]).omitted,
        isTrue,
      );
    },
  );

  test(
    'supported local projection matches retained original actions and endings',
    () async {
      final text = await File(
        'test/fixtures/records/replay_supported.jsonl',
      ).readAsString();
      final original = jsonDecode(
        await File('test/fixtures/records/replay_oracle.json').readAsString(),
      );
      final past = recordActions(parseRecord(text));
      expect(past.rawHasPast, isTrue);
      expect(past.omitted, isFalse);
      expect(normalize(past.toJson()['actions']), normalize(original));
      final transcript = fold(past.actions);
      expect(
        transcript.entries.whereType<StoppedEntry>().single.reason,
        'cancelled',
      );
      expect(transcript.entries.whereType<CancelledEntry>(), hasLength(1));
      expect(transcript.turn, isA<Idle>());
      expect(
        transcript.entries.whereType<UserEntry>().first.text,
        'ask [Image #8] [Image #2]',
      );
      expect(
        transcript.entries.whereType<ToolEntry>().single.call.guardian,
        'approved',
      );
    },
  );

  test(
    'parsed presence stays separate from supported history and malformed lines',
    () async {
      expect(
        recordActions([
          {
            'type': 'session',
            'version': 1,
            'sessionId': 'id',
            'agent': 'fake',
            'cwd': 'project',
            'at': 0,
          },
        ]).rawHasPast,
        isTrue,
      );
      final opaque = recordActions([
        {'type': 'future', 'opaque': true},
      ]);
      expect(opaque.rawHasPast, isTrue);
      expect(opaque.actions, isEmpty);
      expect(opaque.omitted, isTrue);
      final malformed = recordActions(parseRecord('not JSON'), malformed: true);
      expect(malformed.rawHasPast, isFalse);
      expect(malformed.omitted, isTrue);
      expect(
        recordActions([
          {'type': 'prompt', 'at': 1},
        ]).rawHasPast,
        isTrue,
      );
    },
  );

  test(
    'unsupported versions refuse preparation and preserve exact bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chord-replay-version-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File(p.join(dir.path, 'record.jsonl'));
      for (final version in [2, 'future']) {
        final text =
            '${encodeRecord({'type': 'session', 'version': version})}${encodeRecord(prompt('t', 'hello'))}';
        await file.writeAsString(text);
        await expectLater(
          readRecordedHistory(file.path),
          throwsA(
            isA<UnsupportedRecordVersion>().having(
              (e) => e.toString(),
              'version line',
              'Unsupported session record version: $version.',
            ),
          ),
        );
        expect(await file.readAsString(), text);
      }
    },
  );

  test(
    'selected preparation accepts UTF-8 replacement, torn tail and final valid JSON',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chord-replay-prepare-',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File(p.join(dir.path, 'record.jsonl'));
      await file.writeAsBytes([
        ...utf8.encode(
          '{"type":"prompt","turnId":"t","at":1.25,"images":0,"prompt":"',
        ),
        255,
        ...utf8.encode(
          '"}\nnot JSON\n{"type":"result","turnId":"t","result":{"status":"completed","stopReason":"end_turn"}}',
        ),
      ]);
      final past = await readRecordedHistory(file.path);
      expect(past.rawHasPast, isTrue);
      expect(past.omitted, isTrue);
      expect(past.actions.whereType<PromptAction>().single.text, '\uFFFD');
      expect(past.actions.whereType<PromptAction>().single.at, 1.25);
      expect(
        (await readRecordedHistory(p.join(dir.path, 'missing'))).rawHasPast,
        isFalse,
      );
      final token = CancellationToken()..cancel();
      await expectLater(
        readRecordedHistory(file.path, cancellationToken: token),
        throwsA(isA<CancelledException>()),
      );
      await dir.delete(recursive: true);
      expect(await dir.exists(), isFalse);
    },
  );

  test(
    'unsupported meaningful entries set one fact while metadata and extra keys do not',
    () {
      final supported = recordActions([
        {
          'type': 'session',
          'version': 1,
          'sessionId': 'id',
          'agent': 'fake',
          'cwd': 'p',
          'at': 0,
          'future': true,
        },
        {'type': 'state', 'options': <String, Object?>{}},
        {'type': 'renamed', 'title': 'named', 'at': 1},
        update('session_info_update', {'title': null}),
        update('user_message_chunk'),
        update('config_option_update'),
        update('available_commands_update'),
        prompt('t', 'hello'),
        update('agent_message_chunk', {
          'content': {'type': 'text', 'text': 'answer'},
          'future': true,
        }),
      ]);
      expect(supported.omitted, isFalse);
      expect(supported.actions.whereType<PromptAction>(), hasLength(1));
      for (final kind in [
        'usage',
        'served',
        'ran',
        'closed',
        'asked',
        'answered',
        'plan_asked',
        'plan_answered',
        'stopping',
        'self_started',
        'forked',
        'unknown',
      ]) {
        expect(
          recordActions([
            {'type': kind},
          ]).omitted,
          isTrue,
          reason: kind,
        );
      }
      // A child's header draws as any session's, a team's lead's too.
      Map<String, Object?> header(Map<String, Object?> more) => {
        'type': 'session',
        'version': 1,
        'sessionId': 'id',
        'agent': 'fake',
        'cwd': 'p',
        'at': 0,
        ...more,
      };
      expect(
        recordActions([
          header({'parent': 'parent', 'name': 'parser', 'id': 'c1'}),
        ]).omitted,
        isFalse,
      );
      expect(
        recordActions([
          header({'parent': 'parent', 'name': 'fix', 'task': 't1'}),
        ]).omitted,
        isFalse,
      );
      expect(
        recordActions([
          header({'parent': 'parent', 'id': 'l1', 'team': 'ship'}),
        ]).omitted,
        isFalse,
      );
    },
  );

  test(
    'foreign/subagent prompts and malformed updates stay omitted beside steering',
    () {
      final past = recordActions([
        {
          ...prompt('foreign', 'not the person'),
          'from': {'name': 'other'},
        },
        {...prompt('steered', 'not an ordinary turn'), 'into': 't'},
        prompt('legacy', '<message from="main">\nlegacy sender\n</message>'),
        {
          ...update('agent_message_chunk', {
            'content': {'type': 'text', 'text': 'child'},
          }),
          'subagentId': 'child',
        },
        update('agent_message_chunk', {
          'content': {'type': 'image', 'data': 'not copied'},
        }),
        update('tool_call'),
        update('plan', {'entries': 'wrong'}),
        update('future'),
        prompt('good', 'survives'),
        update('agent_message_chunk', {
          'content': {'type': 'text', 'text': 'okay'},
        }),
      ]);
      expect(past.omitted, isTrue);
      final transcript = fold(past.actions);
      // A message whose line has no sender is read from its wrapper, as
      // the original's legacy records are.
      expect(transcript.entries.whereType<UserEntry>().map((e) => e.text), [
        'not an ordinary turn',
        'legacy sender',
        'survives',
      ]);
      expect(
        transcript.entries.whereType<UserEntry>().elementAt(1).from,
        const MessageFrom('main', reachable: true),
      );
      expect(
        transcript.entries.whereType<AssistantEntry>().single.text.toString(),
        'okay',
      );
    },
  );

  test(
    'saved raw string errors retain messages and representable numeric display codes',
    () {
      for (final code in ['-32000', 'reason/text']) {
        final past = recordActions([
          prompt('t', 'hello'),
          {
            'type': 'result',
            'turnId': 't',
            'result': {
              'status': 'failed',
              'error': {'message': 'refused', 'code': code},
            },
          },
        ]);
        final result =
            past.actions.whereType<ResultAction>().single.result as TurnFailed;
        expect(result.recordedCode, code);
        expect(result.code, code == '-32000' ? -32000 : null);
        expect(past.omitted, code == 'reason/text');
        expect(recordResult(result), {
          'status': 'failed',
          'error': {'message': 'refused', 'code': code},
        });
        expect(
          fold(past.actions).entries.whereType<ErrorEntry>().single.message,
          'refused',
        );
      }
    },
  );

  test(
    'fractional prompt, update, cancel and disconnect times survive JSON/actions/state',
    () {
      final past = recordActions([
        prompt('t', 'hello', 1.25),
        {
          ...update('agent_message_chunk', {
            'content': {'type': 'text', 'text': 'x'},
          }),
          'at': 1.5,
        },
        {'type': 'cancel', 'turnId': 't', 'at': 1.75},
        {'type': 'disconnected', 'at': 1.875},
      ]);
      final copied = PreparedHistory.fromJson(past.toJson());
      expect(copied.actions.whereType<PromptAction>().single.at, 1.25);
      expect(copied.actions.whereType<UpdateAction>().single.at, 1.5);
      expect(copied.actions.whereType<CancelAction>().single.at, 1.75);
      expect(copied.actions.whereType<DisconnectedAction>().single.at, 1.875);
      final active = fold(copied.actions.take(3).toList()).turn as Cancelling;
      expect(active.since, 1.25);
      expect(active.cancelledAt, 1.75);
      expect(
        () => copied.actions.add(const DisconnectedAction('other')),
        throwsUnsupportedError,
      );
    },
  );

  test('unfinished turns settle at next prompt, opened boundary and EOF', () {
    final past = recordActions([
      prompt('a', 'one'),
      prompt('b', 'two'),
      {'type': 'opened', 'at': 2},
      prompt('c', 'three'),
    ]);
    expect(past.actions.whereType<ResultAction>().map((a) => a.turnId), [
      'history-a',
      'history-b',
      'history-c',
    ]);
    expect(fold(past.actions).turn, isA<Idle>());
  });

  test(
    'agent history groups contiguous user chunks and holds converted shell/images once',
    () {
      final context = shellContext([
        const ShellRun(command: 'pwd', stdout: 'fixture', running: false),
      ]);
      final past = pastActions(
        own([
          chunk('user_message_chunk', {
            'type': 'text',
            'text': '$context\n\nask ',
          }),
          chunk('user_message_chunk', {'type': 'text', 'text': '[Image #9]'}),
          chunk('user_message_chunk', {
            'type': 'image',
            'data': 'payload not recorded',
          }),
          chunk('user_message_chunk', {
            'type': 'resource_link',
            'uri': 'file:fixture',
          }),
          chunk('agent_message_chunk', {'type': 'text', 'text': 'answer'}),
          chunk('user_message_chunk', {'type': 'text', 'text': 'second'}),
        ]),
        4.25,
      );
      expect(past.omitted, isFalse);
      expect(past.actions.whereType<PromptAction>().map((a) => a.text), [
        'ask [Image #9]',
        'second',
      ]);
      expect(
        past.actions.whereType<PromptAction>().every((a) => a.at == 4.25),
        isTrue,
      );
      final converted = historyEntries(past.actions);
      expect(
        converted
            .where((e) => e['type'] == 'prompt')
            .every((e) => e['images'] == 0),
        isTrue,
      );
      expect(jsonEncode(converted), isNot(contains('payload not recorded')));
      final replayed = fold(recordActions(converted).actions);
      expect(replayed.entries.whereType<UserEntry>().map((e) => e.text), [
        'ask [Image #9]',
        'second',
      ]);
      expect(replayed.entries.whereType<ShellEntry>(), hasLength(1));
      expect(withImages('[Image #8]', 2), '[Image #8] [Image #2]');
    },
  );

  test('a legacy message is said by its wrapper\'s sender in the window, '
      'reachable as the record\'s answers say, as the original\'s '
      'legacyFrom', () {
    final served = [('open_agent', 'parser'), ('spawn_task', 'fix')].indexed
        .map(
          (each) => {
            'type': 'served',
            'turnId': 's${each.$1}',
            'at': 1,
            'call': {
              'tool': each.$2.$1,
              'args': <String, Object?>{},
              'answer': {'id': 'c${each.$1}', 'name': each.$2.$2},
            },
          },
        );
    final past = recordActions([
      ...served,
      prompt('a', '<message from="parser · codex">\nfrom a child\n</message>'),
      prompt(
        'b',
        '<message from="tester · codex · report">\nDone.\n</message>',
      ),
      prompt('c', '<message from="fix · claude">\nfrom a task\n</message>'),
      prompt(
        'd',
        '<message from="watch" monitor="m1">\nBuild red.\n</message>',
      ),
      {
        ...prompt('e', '<message from="main">\nsteered\n</message>'),
        'into': 'd',
      },
      prompt(
        'g',
        '<message from="parser" monitor="m2">\nnamed as a child\n</message>',
      ),
      {
        ...prompt('f', '<message from="parser · codex">\nkept\n</message>'),
        'from': {'name': 'kept'},
      },
    ]);
    expect(
      [
        for (final action in past.actions)
          if (action is PromptAction) (action.text, action.from, action.into),
      ],
      [
        (
          'from a child',
          const MessageFrom('parser', runtime: 'codex', reachable: true),
          null,
        ),
        (
          'Done.',
          const MessageFrom(
            'tester',
            runtime: 'codex',
            note: MessageNote.report,
          ),
          null,
        ),
        ('from a task', const MessageFrom('fix', runtime: 'claude'), null),
        (
          'Build red.',
          const MessageFrom('watch', monitor: (id: 'm1', end: null)),
          null,
        ),
        ('steered', const MessageFrom('main', reachable: true), 'history-d'),
        (
          'named as a child',
          const MessageFrom(
            'parser',
            monitor: (id: 'm2', end: null),
            reachable: true,
          ),
          null,
        ),
        ('kept', const MessageFrom('kept'), null),
      ],
    );
  });

  group('CTUI-160: a failed turn\'s sign-in in the record', () {
    const written = {
      'status': 'failed',
      'error': {
        'message': 'Authentication required',
        'code': '-32000',
        'signIn': {
          'message': 'Authentication required',
          'ways': [
            {'name': 'Log in', 'description': 'with a browser'},
            {'name': 'API key'},
            {'description': 'Only words'},
          ],
        },
      },
    };

    test('is written as the original writes it, its account left out', () {
      expect(
        jsonDecode(
          jsonEncode(
            recordResult(
              const TurnFailed(
                'Authentication required',
                code: -32000,
                signIn: SignIn('Authentication required', [
                  (name: 'Log in', description: 'with a browser'),
                  (name: 'API key', description: null),
                  (name: null, description: 'Only words'),
                ], account: AccountHeard({'state': 'unauthenticated'})),
              ),
            ),
          ),
        ),
        written,
      );
      expect(RecordedResult.view(written)!.toJson(), written);
    });

    test('replays to the error entry\'s sign-in, with no account', () {
      final past = recordActions([
        prompt('t', 'hello'),
        {'type': 'result', 'turnId': 't', 'result': written},
      ]);
      for (final actions in [
        past.actions,
        PreparedHistory.fromJson(past.toJson()).actions,
      ]) {
        final entry = fold(actions).entries.whereType<ErrorEntry>().single;
        expect(entry.message, 'Authentication required');
        expect(entry.code, -32000);
        expect(entry.signIn!.message, 'Authentication required');
        expect(entry.signIn!.ways, [
          (name: 'Log in', description: 'with a browser'),
          (name: 'API key', description: null),
          (name: null, description: 'Only words'),
        ]);
        expect(entry.signIn!.account, isNull);
      }
    });

    test('a record without one, or a malformed one, replays without it', () {
      for (final signIn in <Object?>[
        null,
        'text',
        {'message': 'no ways'},
        {
          'message': 'm',
          'ways': [3],
        },
        {
          'message': 'm',
          'ways': [
            {'name': 4},
          ],
        },
      ]) {
        final past = recordActions([
          prompt('t', 'hello'),
          {
            'type': 'result',
            'turnId': 't',
            'result': {
              'status': 'failed',
              'error': {'message': 'refused', 'signIn': ?signIn},
            },
          },
        ]);
        expect(
          fold(past.actions).entries.whereType<ErrorEntry>().single.signIn,
          isNull,
        );
      }
    });
  });
}
