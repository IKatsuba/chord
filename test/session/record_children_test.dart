// Records of the agents a session starts, and the parent's record read back
// with them, on fixture records: a task's work spliced after the line that
// started its block, a task whose record is gone kept bare, the served calls
// that draw chord's rows, messages by their senders, and the long-lived
// agents left open named last. From the original's
// tests/session/record_test.ts.
import 'dart:convert';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/tasks.dart'
    show TaskStart, taskUpdate, wrapMessage;
import 'package:chord/session/transcript/entries.dart' show replayTranscript;
import 'package:chord/session/transcript/subagents.dart' show subagentsIn;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/agents/agents.dart' show leftOpenLine;
import 'package:chord/ui/transcript/tools/chord.dart' show chordHeadline;
import 'package:test/test.dart';

/// A record's header; a child's with [more].
Map<String, Object?> header(String sessionId, [Map<String, Object?>? more]) => {
  'type': 'session',
  'version': 1,
  'sessionId': sessionId,
  'agent': 'fake',
  'cwd': 'fixture-project',
  'at': 0,
  ...?more,
};

Map<String, Object?> prompt(String turn, String text, [num at = 1]) => {
  'type': 'prompt',
  'turnId': turn,
  'at': at,
  'prompt': text,
  'images': 0,
};

Map<String, Object?> update(String turn, Map<String, Object?> update) => {
  'type': 'update',
  'turnId': turn,
  'update': update,
};

Map<String, Object?> said(String turn, String text) => update(turn, {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
});

Map<String, Object?> result(String turn) => {
  'type': 'result',
  'turnId': turn,
  'result': {'status': 'completed', 'stopReason': 'end_turn'},
};

Map<String, Object?> served(String turn, ChordCall call) => {
  'type': 'served',
  'turnId': turn,
  'call': call.toJson(),
};

const start = TaskStart(
  id: 'task-1',
  name: 'reader',
  runtime: 'fake',
  prompt: 'Read the parser.',
);

/// The parent's lines that start and end task [id]'s block.
Map<String, Object?> taskLine(String turn, SubagentState state) => update(
  turn,
  taskUpdate(
    start.id,
    state,
    task: state == SubagentState.running ? start : null,
  ).toJson(),
);

const listed = ChordCall(
  tool: ChordTool.listSessions,
  input: {'n': 1},
  answer: {'sessions': <Object?>[]},
);

/// Main's record: a turn that started task-1 and saw it end.
List<Object?> parent() => [
  header('main-1'),
  prompt('t1', 'hello'),
  taskLine('t1', SubagentState.running),
  taskLine('t1', SubagentState.completed),
  said('t1', 'done'),
  result('t1'),
];

/// task-1's own record: its prompt, its work, a call chord served it, a
/// subagent of its own, its end and what it spent.
List<Object?> task() => [
  header('task-s', {'parent': 'main-1', 'name': 'reader', 'task': 'task-1'}),
  {'type': 'opened', 'at': 1},
  prompt('tt', 'Read the parser.'),
  said('tt', 'Found it.'),
  served('tt', listed),
  {...said('tt', 'inner work'), 'subagentId': 'inner'},
  result('tt'),
  {
    'type': 'usage',
    'turnId': 'tt',
    'usage': {'inputTokens': 1},
  },
];

Transcript drawn(PreparedHistory history) => replayTranscript(history.actions);

void main() {
  group('tester team record boundaries', () {
    test('accepting a team header preserves unrelated omission reasons', () {
      final teamHeader = header('lead', {
        'parent': 'main',
        'name': 'bugfix',
        'id': 'lead-id',
        'team': 'bugfix',
      });
      final complete = recordActions([teamHeader]);
      final unknown = recordActions([
        teamHeader,
        {'type': 'future-team-event'},
      ]);
      final malformed = recordActions([teamHeader], malformed: true);
      for (final (history, omitted) in [
        (complete, false),
        (unknown, true),
        (malformed, true),
      ]) {
        final copied = PreparedHistory.fromJson(
          jsonDecode(jsonEncode(history.toJson())) as Map<String, Object?>,
        );
        expect(copied.omitted, omitted);
      }
    });
    test(
      'closed run IDs stay absent and a reopened member counts once through serialization',
      () {
        ChordCall ran(String id) => ChordCall(
          tool: ChordTool.runTeam,
          input: const {'team': 'bugfix', 'job': 'x'},
          answer: {
            'id': id,
            'name': 'bugfix',
            'team': 'bugfix',
            'agent': 'fake',
          },
        );
        ChordCall opened(String id) => ChordCall(
          tool: ChordTool.openAgent,
          input: const {'member': 'tester', 'prompt': 'x'},
          answer: {'id': id, 'name': 'tester', 'agent': 'fake'},
        );
        final history = recordActions(
          [
            header('main'),
            prompt('t1', 'job'),
            served('t1', ran('old-lead')),
            {'type': 'closed', 'agent': 'old-lead'},
            served('t1', ran('new-lead')),
            result('t1'),
          ],
          past: true,
          runs: {
            'old-lead': [
              header('old', {'id': 'old-lead', 'team': 'bugfix'}),
            ],
            'new-lead': [
              header('new', {'id': 'new-lead', 'team': 'bugfix'}),
              prompt('u1', 'job'),
              served('u1', opened('old-member')),
              {'type': 'closed', 'agent': 'old-member'},
              served('u1', opened('new-member')),
              result('u1'),
            ],
          },
        );
        final roundtrip = PreparedHistory.fromJson(
          jsonDecode(jsonEncode(history.toJson())) as Map<String, Object?>,
        );
        const expected = [
          (name: 'bugfix', runtime: 'fake', team: 'bugfix', agents: 2),
        ];
        expect((roundtrip.actions.last as LeftOpenAction).agents, expected);
        expect(
          drawn(roundtrip).entries.whereType<LeftOpenEntry>().single.agents,
          expected,
        );
        expect(roundtrip.past!.whereType<PastLeftOpen>().single.agents, [
          {'name': 'bugfix', 'runtime': 'fake', 'team': 'bugfix', 'agents': 2},
        ]);
      },
    );
  });
  _testerTaskRecordBurst();
  group('withTaskWork', () {
    test("puts a task's updates and served calls after its block's start, "
        "under the task's id and the parent's turn", () {
      final spliced = withTaskWork(parent(), taskPasts([task()]));
      expect(spliced.length, parent().length + 3);
      expect(spliced.sublist(0, 3), parent().sublist(0, 3));
      expect(spliced[3], {...said('t1', 'Found it.'), 'subagentId': 'task-1'});
      expect(spliced[4], {...served('t1', listed), 'subagentId': 'task-1'});
      // Its own subagent's keep their id.
      expect(spliced[5], {...said('t1', 'inner work'), 'subagentId': 'inner'});
      // The block's end is not spliced again; the rest is as it was.
      expect(spliced.sublist(6), parent().sublist(3));
    });

    test('drawn, the task block holds its work and the call chord served '
        'it', () {
      final spliced = withTaskWork(parent(), taskPasts([task()]));
      final transcript = drawn(recordActions(spliced));
      final block = subagentsIn(
        transcript.entries,
      ).singleWhere((each) => each.id == 'task-1');
      expect(block.task?.name, 'reader');
      expect(block.task?.workLost, isFalse);
      expect(
        block.entries.whereType<AssistantEntry>().map((e) => e.text.text),
        contains('Found it.'),
      );
      expect(
        transcript.entries.whereType<AssistantEntry>().map((e) => e.text.text),
        ['done'],
      );
    });

    test('a task whose record is gone keeps its bare block, marked so its '
        'work is said lost', () {
      final spliced = withTaskWork(parent(), const {});
      expect(spliced.length, parent().length);
      final start = spliced[2] as Map<String, Object?>;
      final meta =
          ((start['update'] as Map)['_meta'] as Map)['chord/task'] as Map;
      expect(meta['workLost'], isTrue);
      expect(meta['name'], 'reader');
      // Only the first line of its block is marked.
      expect(spliced[3], parent()[3]);
      final block = subagentsIn(drawn(recordActions(spliced)).entries).single;
      expect(block.task?.workLost, isTrue);
    });

    test('taskPasts keeps tasks alone, by their ids', () {
      final child = [
        header('c-s', {'parent': 'main-1', 'name': 'parser', 'id': 'c1'}),
      ];
      expect(taskPasts([task(), child]), {'task-1': task()});
    });
  });

  group('recordActions', () {
    const parser = ChordCall(
      tool: ChordTool.openAgent,
      input: {'agent': 'fake', 'prompt': 'Read.', 'name': 'parser'},
      answer: {'id': 'c1', 'name': 'parser', 'agent': 'fake'},
    );
    const docs = ChordCall(
      tool: ChordTool.openAgent,
      input: {'agent': 'codex', 'prompt': 'Write.', 'name': 'docs'},
      answer: {'id': 'c3', 'name': 'docs', 'agent': 'codex'},
    );
    const scratch = ChordCall(
      tool: ChordTool.openAgent,
      input: {'agent': 'fake', 'typed': '/new'},
      answer: {'id': 'c2', 'name': 'scratch', 'agent': 'fake'},
    );

    test('names the long-lived agents left open last: those served and '
        'those /new ran, but none closed while the session went on', () {
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'open them'),
        served('t1', parser),
        served('t1', docs),
        {'type': 'ran', 'turnId': 't1', 'call': scratch.toJson()},
        {'type': 'closed', 'agent': 'c3'},
        result('t1'),
      ]);
      expect(history.omitted, isFalse);
      final left = history.actions.last as LeftOpenAction;
      expect(left.turnId, 'history-left');
      expect(left.agents, [
        (name: 'parser', runtime: 'fake', team: null, agents: null),
        (name: 'scratch', runtime: 'fake', team: null, agents: null),
      ]);
      final note = drawn(history).entries.whereType<LeftOpenEntry>().single;
      expect(
        leftOpenLine(note.agents),
        'parser (fake) and scratch (fake) were open when this session was '
        'left and are not reopened · /resume lists them',
      );
    });

    test("a team run counts as one, with its lead and the members its lead's "
        'record had open; its lead alone once that record has gone', () {
      ChordCall ran(String id, String name) => ChordCall(
        tool: ChordTool.runTeam,
        input: const {'team': 'bugfix', 'job': 'x'},
        answer: {'id': id, 'name': name, 'team': 'bugfix', 'agent': 'fake'},
      );
      ChordCall member(String id, String name) => ChordCall(
        tool: ChordTool.openAgent,
        input: {'member': name, 'prompt': 'x'},
        answer: {'id': id, 'name': name, 'agent': 'fake'},
      );
      final history = recordActions(
        [
          header('main-1'),
          prompt('t1', 'run them'),
          served('t1', ran('l1', 'bugfix')),
          {
            'type': 'ran',
            'turnId': 't1',
            'call': ran('l2', 'bugfix 2').toJson(),
          },
          result('t1'),
        ],
        runs: {
          'l1': [
            header('lead-1', {
              'parent': 'main-1',
              'id': 'l1',
              'team': 'bugfix',
            }),
            prompt('u1', 'job'),
            served('u1', member('m1', 'tester')),
            served('u1', member('m2', 'coder')),
            served('u1', member('m3', 'reviewer')),
            {'type': 'closed', 'agent': 'm3'},
            result('u1'),
          ],
        },
      );
      final left = history.actions.last as LeftOpenAction;
      expect(left.agents, [
        (name: 'bugfix', runtime: 'fake', team: 'bugfix', agents: 3),
        (name: 'bugfix 2', runtime: 'fake', team: 'bugfix', agents: 1),
      ]);
      expect(
        leftOpenLine(left.agents),
        'team bugfix (3 agents) and team bugfix 2 (1 agent) were open when '
        'this session was left and are not reopened · /resume lists them · '
        '/team run bugfix starts the team again',
      );
      expect(
        runPasts([
          [
            header('lead-1', {'id': 'l1', 'team': 'bugfix'}),
          ],
          [
            header('child-1', {'id': 'c1'}),
          ],
        ]).keys,
        ['l1'],
      );
    });

    test("a team lead's own record replays as any session's, not "
        'omitted', () {
      final history = recordActions([
        header('lead-1', {
          'parent': 'main-1',
          'name': 'bugfix 2',
          'id': 'l1',
          'team': 'bugfix',
        }),
        prompt('t1', 'Fix issue 214.'),
        said('t1', 'On it.'),
        result('t1'),
      ]);
      expect(history.omitted, isFalse);
      expect(
        [
          for (final entry in drawn(history).entries)
            if (entry is AssistantEntry) entry.text.text,
        ],
        ['On it.'],
      );
    });

    test('the ran line of /new draws no row of its own', () {
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'hi'),
        {'type': 'ran', 'turnId': 't1', 'call': scratch.toJson()},
        result('t1'),
      ]);
      expect(history.omitted, isFalse);
      expect(history.actions.whereType<ServedAction>(), isEmpty);
      expect(
        leftOpenLine(
          drawn(history).entries.whereType<LeftOpenEntry>().single.agents,
        ),
        'scratch (fake) was open when this session was left and is not '
        'reopened · /resume lists it',
      );
    });

    test('no note when every agent opened was closed', () {
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'hi'),
        served('t1', docs),
        {'type': 'closed', 'agent': 'c3'},
        result('t1'),
      ]);
      expect(history.actions.whereType<LeftOpenAction>(), isEmpty);
    });

    test("a served send_message ties to the agent's call, so its → row "
        'names the recipient and says it was queued', () {
      const sent = ChordCall(
        tool: ChordTool.sendMessage,
        input: {'to': 'c1', 'text': 'Look again.'},
        answer: {'delivered': 'queued', 'to': 'parser'},
        queued: true,
      );
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'tell parser'),
        update('t1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'mcp__chord__send_message',
          'status': 'completed',
          'rawInput': {'to': 'c1', 'text': 'Look again.'},
        }),
        served('t1', sent),
        result('t1'),
      ]);
      expect(history.omitted, isFalse);
      final tool = drawn(history).entries.whereType<ToolEntry>().single;
      final chord = tool.call.chord!;
      expect(chord.toJson(), sent.toJson());
      final headline = chordHeadline(chord);
      expect(
        (headline.name, headline.sent, headline.note),
        ('parser', true, ' · queued'),
      );
    });

    test("messages draw from their lines' senders, a steered one into the "
        'turn it went into', () {
      const from = MessageFrom('parser', runtime: 'fake', reachable: true);
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'hi'),
        {
          ...prompt('t2', wrapMessage(from, 'While you work: the lexer too.')),
          'from': from.toJson(),
          'into': 't1',
        },
        result('t1'),
        {...prompt('t3', wrapMessage(from, 'Done.')), 'from': from.toJson()},
        result('t3'),
      ]);
      expect(history.omitted, isFalse);
      final prompts = history.actions.whereType<PromptAction>().toList();
      expect(
        [for (final p in prompts) (p.turnId, p.text, p.from, p.into)],
        [
          ('history-t1', 'hi', null, null),
          ('history-t2', 'While you work: the lexer too.', from, 'history-t1'),
          ('history-t3', 'Done.', from, null),
        ],
      );
      expect(drawn(history).entries.whereType<UserEntry>().last.from, from);
    });

    test("a message's line written before senders were kept reads its "
        "wrapper, @ only for a name the record's open_agent answered", () {
      final history = recordActions([
        header('main-1'),
        prompt('t1', 'hi'),
        served('t1', parser),
        result('t1'),
        prompt('t2', wrapMessage(const MessageFrom('parser'), 'one')),
        result('t2'),
        prompt('t3', wrapMessage(const MessageFrom('reader'), 'two')),
        result('t3'),
      ]);
      expect(
        [
          for (final p in history.actions.whereType<PromptAction>())
            if (p.from case final from?) (from.name, from.reachable),
        ],
        [('parser', true), ('reader', false)],
      );
    });
  });

  group("a child's record", () {
    Future<List<Map<String, Object?>>> written(
      void Function(FileRecording recording) work, {
      RecordChild? child,
    }) async {
      final text = StringBuffer();
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'fixture',
        append: (_, line) async => text.write(line),
        child: child,
      );
      recording.opened(
        const RecordingSession(
          sessionId: 'task-s',
          agent: 'fake',
          cwd: 'fixture-project',
        ),
      );
      recording.sent('t', 'Read the parser.', 0, const [], 1);
      work(recording);
      await recording.flushed();
      return parseRecord(text.toString()).cast<Map<String, Object?>>();
    }

    test("a task's header names its parent, its name and its task id; a "
        "long-lived agent's its id", () async {
      var parentId = 'main-1';
      final task = await written(
        (_) {},
        child: RecordChild(
          parent: () => parentId,
          name: 'reader',
          task: 'task-1',
        ),
      );
      expect(task.first, {
        'type': 'session',
        'version': 1,
        'sessionId': 'task-s',
        'agent': 'fake',
        'cwd': 'fixture-project',
        'at': task.first['at'],
        'parent': 'main-1',
        'name': 'reader',
        'task': 'task-1',
      });
      parentId = 'main-2';
      final child = await written(
        (_) {},
        child: RecordChild(parent: () => parentId, name: 'parser', id: 'c1'),
      );
      expect(
        [child.first['parent'], child.first['name'], child.first['id']],
        ['main-2', 'parser', 'c1'],
      );
      expect(child.first.containsKey('task'), isFalse);
      expect(child.first.containsKey('team'), isFalse);
      // A team's lead's names the team it runs; a member's names none.
      final lead = await written(
        (_) {},
        child: RecordChild(
          parent: () => parentId,
          name: 'bugfix 2',
          id: 'l1',
          team: 'bugfix',
        ),
      );
      expect(
        [lead.first['name'], lead.first['id'], lead.first['team']],
        ['bugfix 2', 'l1', 'bugfix'],
      );
      // Main's own names no parent.
      final main = await written((_) {});
      expect(
        main.first.keys.where(
          (key) => const {'parent', 'name', 'task', 'id'}.contains(key),
        ),
        isEmpty,
      );
    });

    test('served, ran and closed lines, and a self-started turn with its '
        'sender', () async {
      const from = MessageFrom('main', reachable: true);
      final lines = await written((recording) {
        recording.heard(Transcribed(ServedAction('t', listed)));
        recording.heard(
          Transcribed(ServedAction('t', listed, subagentId: 'inner')),
        );
        recording.heard(
          RanTyped(
            't',
            const ChordCall(
              tool: ChordTool.openAgent,
              input: {'agent': 'fake', 'typed': '/new'},
              answer: {'id': 'c2', 'name': 'scratch', 'agent': 'fake'},
            ),
          ),
        );
        recording.heard(const AgentClosed('c1'));
        recording.heard(const Transcribed(SelfStartedAction('s', from: from)));
      });
      expect(lines.skipWhile((line) => line['type'] != 'prompt').skip(1), [
        {'type': 'served', 'turnId': 't', 'call': listed.toJson()},
        {
          'type': 'served',
          'turnId': 't',
          'call': listed.toJson(),
          'subagentId': 'inner',
        },
        {
          'type': 'ran',
          'turnId': 't',
          'call': {
            'tool': 'open_agent',
            'input': {'agent': 'fake', 'typed': '/new'},
            'answer': {'id': 'c2', 'name': 'scratch', 'agent': 'fake'},
          },
        },
        {'type': 'closed', 'agent': 'c1'},
        {
          'type': 'self_started',
          'turnId': 's',
          'from': {'name': 'main', 'reachable': true},
        },
      ]);
      // Read back as they were written.
      final history = recordActions(lines);
      expect(history.omitted, isFalse);
      expect(
        [
          for (final s in history.actions.whereType<ServedAction>())
            {...s.call.toJson(), 'by': s.subagentId},
        ],
        [
          {...listed.toJson(), 'by': null},
          {...listed.toJson(), 'by': 'inner'},
        ],
      );
      expect(history.actions.whereType<SelfStartedAction>().single.from, from);
    });

    test('a call keeps every field through its JSON; a tool chord does not '
        'serve reads as none', () {
      const call = ChordCall(
        tool: ChordTool.spawnTask,
        input: {'agent': 'fake', 'prompt': 'x'},
        answer: {'id': 'task-1'},
        error: 'refused',
        task: 'task-1',
        queued: true,
        asked: 'a1',
      );
      final back = ChordCall.fromJson(jsonDecode(jsonEncode(call.toJson())))!;
      expect(back.tool, call.tool);
      expect(back.toJson(), call.toJson());
      expect((back.queued, back.asked), (true, 'a1'));
      expect(
        ChordCall.fromJson({
          'tool': 'no_such_tool',
          'input': <String, Object?>{},
        }),
        isNull,
      );
      expect(
        recordActions([
          header('main-1'),
          {
            'type': 'served',
            'turnId': 't',
            'call': {'tool': 'no_such_tool', 'input': <String, Object?>{}},
          },
        ]).omitted,
        isTrue,
      );
    });
  });

  test('a past for chord acp ends with the agents left open', () {
    final history = recordActions([
      header('main-1'),
      prompt('t1', 'hi'),
      served(
        't1',
        const ChordCall(
          tool: ChordTool.openAgent,
          input: {'agent': 'fake', 'prompt': 'Read.'},
          answer: {'id': 'c1', 'name': 'parser', 'agent': 'fake'},
        ),
      ),
      result('t1'),
    ], past: true);
    expect(history.past!.last.toJson(), {
      'type': 'left_open',
      'agents': [
        {'name': 'parser', 'runtime': 'fake'},
      ],
    });
  });

  test('an update under a task id that never started a block is left as '
      'it was', () {
    final lines = [
      header('main-1'),
      prompt('t1', 'hi'),
      update(
        't1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'subagent_update',
          'sessionId': 'own-sub',
          'state': {'state': 'running'},
        }).toJson(),
      ),
    ];
    expect(withTaskWork(lines, taskPasts([task()])), lines);
  });
}

void _testerTaskRecordBurst() {
  group('CTUI-35 tester: task replay burst', () {
    test(
      'a thousand updates splice once despite repeated task metadata without mutating records',
      () {
        final own = [
          header('task-s', {'task': start.id}),
          for (var i = 0; i < 1000; i++) said('task-turn', '界🙂e\u0301 $i'),
          result('task-turn'),
        ];
        final main = [
          header('main-1'),
          prompt('t1', 'read'),
          taskLine('t1', SubagentState.running),
          taskLine('t1', SubagentState.running),
          taskLine('t1', SubagentState.completed),
          result('t1'),
        ];
        final before = jsonEncode([main, own]);
        final spliced = withTaskWork(main, {start.id: own});
        final work = spliced
            .whereType<Map<String, Object?>>()
            .where((entry) => entry['subagentId'] == start.id)
            .toList();
        expect(work, hasLength(1000));
        expect(work.map((entry) => entry['turnId']).toSet(), {'t1'});
        expect(
          work.map(
            (entry) => ((entry['update'] as Map)['content'] as Map)['text'],
          ),
          [for (var i = 0; i < 1000; i++) '界🙂e\u0301 $i'],
        );
        expect(spliced.length, main.length + 1000);
        expect(jsonEncode([main, own]), before);
      },
    );
  });
}
