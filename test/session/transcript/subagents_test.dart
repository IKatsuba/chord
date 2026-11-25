// The original's tests/session/subagents_test.ts for the transcript's fold
// of subagents: where each stands, its own work, nesting, times, states,
// cancels, the agent's going, end lines and messages between agents.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/subagents.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _turn = 't1';
const _prompt = PromptAction(_turn, 'look', 1);

UpdateAction up(Map<String, Object?> json, {String? from, num? at}) =>
    UpdateAction(
      _turn,
      acp.SessionUpdate.fromJson(json),
      subagentId: from,
      at: at,
    );

UpdateAction sayIn(String text, [String? from]) => up({
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
}, from: from);

UpdateAction call(String id, String status, [String? from]) => up(
  status == 'in_progress'
      ? {
          'sessionUpdate': 'tool_call',
          'toolCallId': id,
          'title': 'Read $id',
          'kind': 'read',
          'status': status,
        }
      : {
          'sessionUpdate': 'tool_call_update',
          'toolCallId': id,
          'status': status,
        },
  from: from,
);

UpdateAction spawned(String id, String title, {String? from, num? at}) => up(
  {
    'sessionUpdate': 'subagent_update',
    'sessionId': id,
    'title': title,
    'description': '$title, in full.',
  },
  from: from,
  at: at,
);

UpdateAction ended(String id, String state, {String? from, num? at}) => up(
  {
    'sessionUpdate': 'subagent_update',
    'sessionId': id,
    'state': {'state': state},
  },
  from: from,
  at: at,
);

UpdateAction stood(String id, Map<String, Object?> state, [num? at]) => up({
  'sessionUpdate': 'subagent_update',
  'sessionId': id,
  'state': state,
}, at: at);

List<Object?> shape(List<Entry> entries) => [
  for (final entry in entries)
    switch (entry) {
      UserEntry(:final text) => 'user: $text',
      AssistantEntry(:final text) => 'assistant: ${text.text}',
      ToolEntry(:final call) => 'tool: ${call.title} ${call.status}',
      SubagentEntry(:final subagent) => {
        '${subagent.title} ${subagent.state.name}': shape(subagent.entries),
      },
      ItemEndedEntry(:final name, :final end) => 'ended: $name ${end.name}',
      ChildMessageEntry(:final text) => 'message: $text',
      AgentMessageEntry(:final toSubagent, :final title, :final text) =>
        '${toSubagent ? '→' : '←'} $title: $text',
      _ => '$entry',
    },
];

Subagent only(Transcript transcript, String id) =>
    subagentsIn(transcript.entries).firstWhere((each) => each.id == id);

void main() {
  stoppingTests();
  testerStoppingLifecycle();
  test("a subagent stands where its spawn came, among its parent's entries, "
      'and changes there', () {
    final transcript = fold([
      _prompt,
      sayIn('I will send two.'),
      spawned('a', 'Find the layer'),
      spawned('b', 'Find the drawing'),
      sayIn('Reading', 'a'),
      call('c1', 'in_progress', 'b'),
      sayIn('Both are out.'),
      call('c1', 'failed', 'b'),
      ended('b', 'failed'),
      sayIn(' Done.', 'a'),
    ]);
    expect(shape(transcript.entries), [
      'user: look',
      'assistant: I will send two.',
      {
        'Find the layer running': ['assistant: Reading Done.'],
      },
      {
        'Find the drawing failed': ['tool: Read c1 failed'],
      },
      'assistant: Both are out.',
    ]);
    expect(only(transcript, 'b').description, 'Find the drawing, in full.');
  });

  test("a subagent's words, calls and plan are its own, and never its "
      "parent's", () {
    final transcript = fold([
      _prompt,
      spawned('a', 'Find the layer'),
      call('c1', 'in_progress', 'a'),
      up({
        'sessionUpdate': 'plan',
        'entries': [
          {'content': 'Find it', 'priority': 'medium', 'status': 'in_progress'},
        ],
      }, from: 'a'),
      up({'sessionUpdate': 'usage_update', 'used': 5, 'size': 10}, from: 'a'),
      up({
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      }, from: 'a'),
      sayIn('Found it.', 'a'),
    ]);
    final child = only(transcript, 'a');
    expect(transcript.plan, isEmpty);
    expect(transcript.usage, isNull);
    expect(transcript.mode, isNull);
    expect([for (final step in child.plan) step.content], ['Find it']);
    // The plan came after its first call: that is where it is drawn.
    expect(child.planAt, 1);
    expect(shape(child.entries), [
      'tool: Read c1 in_progress',
      'assistant: Found it.',
    ]);
    expect(transcript.entries.whereType<AssistantEntry>(), isEmpty);
  });

  test('an update for a subagent the transcript does not hold is dropped', () {
    expect(shape(fold([_prompt, sayIn('Hello', 'stranger')]).entries), [
      'user: look',
    ]);
  });

  test("a subagent's own subagent nests under it, and the way down is "
      'named', () {
    final transcript = fold([
      _prompt,
      spawned('a', 'Find the layer'),
      spawned('g', 'Read the tests', from: 'a'),
      call('c1', 'in_progress', 'g'),
      sayIn('Read.', 'g'),
      ended('g', 'completed', from: 'a'),
      sayIn('Back.', 'a'),
    ]);
    expect(shape(transcript.entries), [
      'user: look',
      {
        'Find the layer running': [
          {
            'Read the tests completed': [
              'tool: Read c1 in_progress',
              'assistant: Read.',
            ],
          },
          'assistant: Back.',
        ],
      },
    ]);
    expect(
      [for (final s in subagentPath(transcript.entries, 'g')) s.title],
      ['Find the layer', 'Read the tests'],
    );
    expect(subagentPath(transcript.entries, 'nobody'), isEmpty);
  });

  test('a subagent reopened under a new id is a new one, where it came', () {
    expect(
      shape(
        fold([
          _prompt,
          spawned('a', 'Find the layer'),
          ended('a', 'completed'),
          sayIn('Asking again.'),
          spawned('a:generation:2', 'Find the layer'),
        ]).entries,
      ),
      [
        'user: look',
        {'Find the layer completed': <Object?>[]},
        'assistant: Asking again.',
        {'Find the layer running': <Object?>[]},
      ],
    );
  });

  test("a subagent's times are when its spawn and its end reached chord, and "
      'none is made up', () {
    final timed = fold([
      _prompt,
      spawned('a', 'Find', at: 100),
      ended('a', 'completed', at: 141),
      // A word that repeats the ending keeps the time it ended at.
      ended('a', 'completed', at: 150),
    ]);
    final untimed = fold([_prompt, spawned('a', 'Find'), ended('a', 'failed')]);
    expect((only(timed, 'a').startedAt, only(timed, 'a').endedAt), (100, 141));
    expect(
      (only(untimed, 'a').startedAt, only(untimed, 'a').endedAt),
      (null, null),
    );
  });

  test("ACP's states read as chord's: idle by its stop reason, unknown as "
      'untracked until a later state, requires_action still running', () {
    for (final (state, read) in [
      ({'state': 'idle', 'stopReason': 'end_turn'}, SubagentState.completed),
      ({'state': 'idle', 'stopReason': 'cancelled'}, SubagentState.cancelled),
      ({'state': 'idle', 'stopReason': 'max_tokens'}, SubagentState.ended),
      ({'state': 'idle'}, SubagentState.ended),
      ({'state': 'unknown'}, SubagentState.untracked),
      ({'state': 'requires_action'}, SubagentState.running),
      ({'state': 'disconnected'}, SubagentState.disconnected),
    ]) {
      expect(subagentStateOf(state), read, reason: '$state');
    }
    expect(subagentStateOf({'state': 'dreaming'}), isNull);
    final failed = fold([
      _prompt,
      spawned('a', 'Find'),
      stood('a', {
        'state': 'idle',
        'stopReason': 'error',
        'error': {'message': 'Out of tokens'},
      }),
    ]);
    expect(
      (only(failed, 'a').state, only(failed, 'a').error),
      (SubagentState.failed, 'Out of tokens'),
    );
    final waiting = fold([
      _prompt,
      spawned('a', 'Find'),
      stood('a', {'state': 'requires_action'}, 7),
    ]);
    expect(only(waiting, 'a').waiting, (since: 7));
    // A patch with null clears; one left out keeps.
    final retitled = fold([
      _prompt,
      spawned('a', 'Find'),
      up({'sessionUpdate': 'subagent_update', 'sessionId': 'a', 'title': null}),
    ]);
    expect(only(retitled, 'a').title, isNull);
    expect(only(retitled, 'a').description, 'Find, in full.');
  });

  test('a cancelled turn leaves a subagent that can be cancelled alone to its '
      'agent, and ends the rest', () {
    UpdateAction own(String id, [String? from]) => up({
      'sessionUpdate': 'subagent_update',
      'sessionId': id,
      'title': id,
      'capabilities': {'cancel': <String, Object?>{}},
      'state': {'state': 'running'},
    }, from: from);
    final cut = fold([
      _prompt,
      own('a'),
      own('g', 'a'),
      spawned('b', 'Draw'),
      const CancelAction(_turn, 12),
      const ResultAction(_turn, TurnAnswered('cancelled')),
    ]);
    expect(
      [
        for (final s in subagentsIn(cut.entries))
          (s.id, s.state.name, s.endedAt),
      ],
      [('a', 'running', null), ('g', 'running', null), ('b', 'cancelled', 12)],
    );
    expect(runningSubagents(cut), 2);
    final later = fold([
      stood('a', {'state': 'idle', 'stopReason': 'end_turn'}, 20),
      up({
        'sessionUpdate': 'subagent_update',
        'sessionId': 'g',
        'capabilities': null,
      }, from: 'a'),
    ], cut);
    expect(only(later, 'a').state, SubagentState.completed);
    expect(only(later, 'g').cancellable, isFalse);
  });

  test('a turn that ends on its own leaves its subagents running; one that '
      'ends after it is said once', () {
    final answered = fold([
      _prompt,
      spawned('a', 'Run the tests', at: 1000),
      spawned('b', 'Read'),
      ended('b', 'completed'),
      const ResultAction(_turn, TurnAnswered('end_turn')),
    ]);
    expect(answered.turn, isA<Idle>());
    expect(runningSubagents(answered), 1);
    // Ended while its turn ran: its own block says it.
    expect(answered.entries.whereType<ItemEndedEntry>(), isEmpty);
    final later = fold([
      sayIn('All passed.', 'a'),
      ended('a', 'completed', at: 4000),
    ], answered);
    expect(runningSubagents(later), 0);
    expect(shape(only(later, 'a').entries), ['assistant: All passed.']);
    final [line] = later.entries.whereType<ItemEndedEntry>().toList();
    expect(
      (line.name, line.end, line.startedAt, line.endedAt, line.turnId),
      ('Run the tests, in full.', ItemEnd.done, 1000, 4000, _turn),
    );
  });

  test("the agent's going disconnects the subagents still running or "
      'untracked, at any depth', () {
    final transcript = fold([
      _prompt,
      spawned('a', 'Find'),
      spawned('g', 'Read', from: 'a'),
      spawned('b', 'Draw'),
      ended('b', 'completed'),
      spawned('u', 'Watch'),
      stood('u', {'state': 'unknown'}, 20),
      const DisconnectedAction(_turn, at: 30),
    ]);
    expect(
      [
        for (final s in subagentsIn(transcript.entries))
          (s.state.name, s.endedAt),
      ],
      [
        ('disconnected', 30),
        ('disconnected', 30),
        ('completed', null),
        ('disconnected', 30),
      ],
    );
  });

  test("Claude's subagent is named by its title, others by their task", () {
    final claude = fold([
      _prompt,
      up({
        'sessionUpdate': 'subagent_update',
        'sessionId': 'a',
        'title': 'explorer',
        'description': 'a role',
        '_meta': {'chord/named_by_title': true},
      }),
    ]);
    expect(agentItemName(only(claude, 'a')), 'explorer');
    expect(
      agentItemName(only(fold([_prompt, spawned('b', 'Find')]), 'b')),
      'Find, in full.',
    );
    expect(agentItemName(const Subagent('x')), 'agent');
  });

  test('messages between the agent and its subagents: a launch above the '
      'block, a reply after, an upsert by id and an empty one gone', () {
    UpdateAction message(
      String id, {
      String? to,
      String? from,
      Object? text = '',
      String? on,
    }) => up({
      'sessionUpdate': 'session_message',
      'messageId': id,
      'recipientSessionId': ?to,
      'senderSessionId': ?from,
      if (text != '')
        'content': text == null
            ? null
            : [
                {'type': 'text', 'text': text},
              ],
    }, from: on);
    final transcript = fold([
      _prompt,
      spawned('a', 'Find'),
      spawned('b', 'Draw'),
      message('m1', to: 'b', text: 'Draw it.'),
      message('m2', from: 'a', text: 'Found it.'),
      message('m2', text: 'Found it, here.'),
      message('m3', to: 'nobody', text: 'Lost'),
      // On the child's own session: its task, then a later message.
      message('p1', on: 'a', text: 'Your task.'),
      message('p2', on: 'a', text: 'More.'),
    ]);
    // A launch stands above the run of blocks it stands in.
    expect(shape(transcript.entries), [
      'user: look',
      '→ Draw: Draw it.',
      {
        'Find running': ['message: More.'],
      },
      {'Draw running': <Object?>[]},
      '← Find: Found it, here.',
    ]);
    expect(only(transcript, 'b').addressed, isTrue);
    expect(only(transcript, 'a').prompt, 'Your task.');
    final child = only(transcript, 'a').entries.single as ChildMessageEntry;
    expect((child.text, child.byAgent), ('More.', true));
    final gone = fold([message('m2', text: null)], transcript);
    expect(gone.entries.whereType<AgentMessageEntry>(), hasLength(1));
  });

  test("a subagent's answered permission is part of its work, not its "
      "parent's; the session's own stays in its entries", () {
    final transcript = fold([
      _prompt,
      spawned('a', 'Find the layer'),
      call('c1', 'in_progress', 'a'),
      const PermissionRequestedAction(
        _turn,
        PermissionWait(
          'p1',
          toolCallId: 'c1',
          title: 'Write a',
          subagentId: 'a',
        ),
      ),
      const PermissionSettledAction(_turn, 'p1', Chosen('allow')),
      const PermissionRequestedAction(
        _turn,
        PermissionWait('p2', title: 'Write main'),
      ),
      const PermissionSettledAction(_turn, 'p2', Chosen('allow')),
    ]);
    expect(
      [for (final entry in only(transcript, 'a').entries) entry.runtimeType],
      [ToolEntry, PermissionEntry],
    );
    expect(
      [
        for (final entry in transcript.entries.whereType<PermissionEntry>())
          entry.title,
      ],
      ['Write main'],
    );
  });

  test("a subagent's review marks its own call, not its parent's of the "
      "same id, and its ask counts from when it came", () {
    const review = PermissionReview('caution', 'Writes outside the project.');
    final transcript = fold([
      _prompt,
      call('c1', 'in_progress'),
      spawned('a', 'Find the layer'),
      call('c1', 'in_progress', 'a'),
      const PermissionRequestedAction(
        _turn,
        PermissionWait(
          'p1',
          toolCallId: 'c1',
          title: 'Write a',
          review: review,
          subagentId: 'a',
        ),
        at: 42,
      ),
    ]);
    final own = transcript.entries.whereType<ToolEntry>().single;
    final child = only(transcript, 'a').entries.whereType<ToolEntry>().single;
    expect(own.call.review, isNull);
    expect(child.call.review, same(review));
    final turn = transcript.turn as AwaitingPermission;
    expect(turn.permissions.single.at, 42);
  });
}

/// A subagent the person stopped alone: the original's CHD-479 and CHD-2
/// cases.
void stoppingTests() {
  SubagentStoppingAction stop(bool stopping, [String id = 'a']) =>
      SubagentStoppingAction('stop', id, stopping);

  test('a subagent stopped alone reads stopping until its agent tells a '
      'state it is not at work in, or the stop could not go', () {
    UpdateAction told(String state) => stood('a', {'state': state});
    final stopped = fold([_prompt, spawned('a', 'explorer'), stop(true)]);
    expect(only(stopped, 'a').stopping, isTrue);
    expect(only(fold([told('running')], stopped), 'a').stopping, isTrue);
    expect(only(fold([told('idle')], stopped), 'a').stopping, isFalse);
    expect(only(fold([told('unknown')], stopped), 'a').stopping, isFalse);
    expect(only(fold([stop(false)], stopped), 'a').stopping, isFalse);
    // An ended one is not marked.
    expect(
      only(fold([told('idle'), stop(true)], stopped), 'a').stopping,
      isFalse,
    );
    // Nothing to stop: the transcript is the same one.
    expect(fold([stop(true, 'none')], stopped), same(stopped));
  });

  test('completion stays done after a late rollback, and a second run can '
      'be stopped on its own', () {
    UpdateAction state(String word, num at) => stood(
      'a',
      word == 'running'
          ? {'state': 'running'}
          : {'state': 'idle', 'stopReason': 'end_turn'},
      at,
    );
    final done = fold([
      _prompt,
      spawned('a', 'A'),
      stop(true),
      state('idle', 20),
      stop(false),
    ]);
    expect(only(done, 'a').state, SubagentState.completed);
    expect(only(done, 'a').endedAt, 20);
    expect(only(done, 'a').stopping, isFalse);
    final again = fold([state('running', 30), stop(true)], done);
    expect(only(again, 'a').state, SubagentState.running);
    expect(only(again, 'a').stopping, isTrue);
    expect(only(again, 'a').endedAt, isNull);
  });

  test("an end line carries its agent's reason, a stop the person's x, a "
      "gone agent its disconnect", () {
    final failed = fold([
      _prompt,
      spawned('a', 'Find a'),
      spawned('b', 'Find b'),
      spawned('c', 'Find c'),
      const ResultAction(_turn, TurnAnswered('end_turn')),
      stood('a', {
        'state': 'idle',
        'stopReason': 'error',
        'error': {'message': 'tsc exited 2'},
      }, 9),
      stop(true, 'b'),
      stood('b', {'state': 'cancelled'}, 10),
      const DisconnectedAction(_turn, at: 11),
    ]);
    expect(
      [
        for (final line in failed.entries.whereType<ItemEndedEntry>())
          (line.name, line.end, line.byPerson, line.error),
      ],
      [
        ('Find a, in full.', ItemEnd.failed, false, 'tsc exited 2'),
        ('Find b, in full.', ItemEnd.stopped, true, null),
        ('Find c, in full.', ItemEnd.disconnected, false, null),
      ],
    );
  });
}

void testerStoppingLifecycle() {
  group('CTUI-83 tester: stopping lifecycle', () {
    test(
      'nested stopping targets only its id and repeated marks are inert',
      () {
        final base = fold([
          _prompt,
          spawned('parent', 'Parent'),
          spawned('nested', 'Nested', from: 'parent'),
          spawned('sibling', 'Sibling'),
        ]);
        const stop = SubagentStoppingAction(_turn, 'nested', true);
        final marked = fold([stop], base);
        expect(only(marked, 'nested').stopping, isTrue);
        expect(only(marked, 'parent').stopping, isFalse);
        expect(only(marked, 'sibling').stopping, isFalse);
        expect(fold([stop], marked), same(marked));
        final renamed = fold([
          spawned('nested', 'Renamed', from: 'parent'),
        ], marked);
        expect(only(renamed, 'nested').stopping, isTrue);
        final rolledBack = fold([
          const SubagentStoppingAction(_turn, 'nested', false),
        ], renamed);
        expect(only(rolledBack, 'nested').stopping, isFalse);
        expect(only(rolledBack, 'nested').state, SubagentState.running);
        expect(
          fold([
            const SubagentStoppingAction(_turn, 'nested', false),
          ], rolledBack),
          same(rolledBack),
        );
      },
    );

    for (final (state, expected, byPerson) in [
      ({'state': 'cancelled'}, ItemEnd.stopped, true),
      ({'state': 'idle'}, ItemEnd.ended, true),
      ({'state': 'idle', 'stopReason': 'end_turn'}, ItemEnd.done, false),
      ({'state': 'idle', 'stopReason': 'error'}, ItemEnd.failed, false),
    ]) {
      test('pending stop preserves terminal reason $expected', () {
        final result = fold([
          _prompt,
          spawned('a', 'Worker'),
          const ResultAction(_turn, TurnAnswered('end_turn')),
          const SubagentStoppingAction(_turn, 'a', true),
          stood('a', state, 12),
        ]);
        expect(only(result, 'a').stopping, isFalse);
        final line = result.entries.whereType<ItemEndedEntry>().single;
        expect(line.end, expected);
        expect(line.byPerson, byPerson);
        final late = fold([
          const SubagentStoppingAction(_turn, 'a', false),
          const SubagentStoppingAction(_turn, 'a', true),
        ], result);
        expect(late, same(result));
      });
    }
  });
}
