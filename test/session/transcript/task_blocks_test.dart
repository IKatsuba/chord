// A task agent's block in its parent's transcript, as the original's
// session/transcript/subagents.ts, turn.ts, permissions.ts and chord.ts
// fold it: what chord says of the task, its spend and who stopped it; its
// asks outliving the parent's turn; a cancel of the parent's turn leaving
// the task to chord's own end; its own calls served among its work.
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _start = TaskStart(
  id: 'task-1',
  name: 'Fix it',
  runtime: 'fake',
  prompt: 'go',
  model: 'fake-small',
);

UpdateAction _task(
  SubagentState state, {
  TaskStart? task,
  TaskSpent? spent,
  TaskStop? stoppedWith,
}) => UpdateAction(
  't1',
  taskUpdate(
    'task-1',
    state,
    task: task,
    spent: spent,
    stoppedWith: stoppedWith,
  ),
);

Subagent _block(Transcript state) =>
    state.entries.whereType<SubagentEntry>().single.subagent;

void main() {
  test("a task's start says what it is; its effort comes later; its end "
      'what it spent and who stopped it', () {
    final state = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      _task(
        SubagentState.running,
        task: const TaskStart(
          id: 'task-1',
          name: 'Fix it',
          runtime: 'fake',
          prompt: 'go',
          model: 'fake-small',
          effort: 'high',
        ),
      ),
      _task(
        SubagentState.cancelled,
        spent: const TaskSpent(
          tokens: {'totalTokens': 2000},
          cost: (amount: 0.0125, currency: 'USD'),
          estimated: true,
        ),
        stoppedWith: TaskStop.esc,
      ),
    ]);
    final task = _block(state).task!;
    expect(
      (task.name, task.runtime, task.model, task.effort),
      ('Fix it', 'fake', 'fake-small', 'high'),
    );
    expect(task.spent!.tokens, {'totalTokens': 2000});
    expect(task.spent!.cost, (amount: 0.0125, currency: 'USD'));
    expect(task.spent!.estimated, isTrue);
    expect(task.stoppedWith, TaskStop.esc);
    expect(_block(state).state, SubagentState.cancelled);
  });

  test("a spend a record bent keeps what reads; `estimated` only with a "
      'cost', () {
    final state = fold([
      _task(SubagentState.running, task: _start),
      update('t1', {
        'sessionUpdate': 'subagent_update',
        'sessionId': 'task-1',
        'state': {'state': 'completed'},
        '_meta': {
          'chord/spent': {
            'tokens': {'inputTokens': -1, 'totalTokens': 5, 'other': 3},
            'cost': {'amount': 'a lot', 'currency': 'USD'},
            'estimated': true,
          },
          'chord/stopped': {'agent': 7},
        },
      }),
    ]);
    final task = _block(state).task!;
    expect(task.spent!.tokens, {'totalTokens': 5});
    expect(task.spent!.cost, isNull);
    expect(task.spent!.estimated, isFalse);
    expect(task.stoppedWith, isNull);
  });

  test("a cancel of the parent's turn leaves its task running, for chord to "
      'end, where it ends the adapters\' subagents', () {
    final state = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      update('t1', {
        'sessionUpdate': 'subagent_update',
        'sessionId': 'sub-1',
        'state': {'state': 'running'},
      }),
      const CancelAction('t1', 2),
      const ResultAction('t1', TurnAnswered('cancelled')),
    ]);
    final blocks = {
      for (final entry in state.entries.whereType<SubagentEntry>())
        entry.subagent.id: entry.subagent.state,
    };
    expect(blocks, {
      'task-1': SubagentState.running,
      'sub-1': SubagentState.cancelled,
    });
  });

  test("a running task's permission waits outside the turn: it outlives the "
      "turn's end, and is answered there", () {
    final asked = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      const ResultAction('t1', TurnAnswered('end_turn')),
      const PermissionRequestedAction(
        't1',
        PermissionWait('p1', subagentId: 'task-1'),
        at: 3,
      ),
    ]);
    final turn = asked.turn as AwaitingPermission;
    expect((turn.between, turn.permissions.single.id), (true, 'p1'));
    final answered = fold([
      const PermissionSettledAction('t1', 'p1', Chosen('allow')),
    ], asked);
    expect(answered.turn, isA<Idle>());
  });

  test("a task's form waits outside the turn, past its end, and its answer "
      'is kept', () {
    final asked = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      const ElicitationRequestedAction(
        't1',
        FormWait('e1', 'Name?', subagentId: 'task-1'),
      ),
      const ResultAction('t1', TurnAnswered('end_turn')),
    ]);
    final wait = asked.asking.single;
    expect((wait.id, wait.between, wait.subagentId), ('e1', false, 'task-1'));
    final answered = fold([
      const ElicitationSettledAction('t2', 'e1', ElicitationDeclined()),
    ], asked);
    expect(answered.asking, isEmpty);
    expect(answered.entries.whereType<ElicitationEntry>(), hasLength(1));
  });

  test("a task's own call served is tied among its work, not the "
      "parent's", () {
    const input = {'text': 'Found it.'};
    final state = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      UpdateAction(
        't1',
        update('t1', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'title': 'mcp__chord__send_message',
          'rawInput': input,
        }).update,
        subagentId: 'task-1',
      ),
      const ServedAction(
        't1',
        ChordCall(tool: ChordTool.sendMessage, input: input),
        subagentId: 'task-1',
      ),
    ]);
    final call = _block(state).entries.whereType<ToolEntry>().single.call;
    expect(call.chord?.input, input);
    expect(state.served, isEmpty);
  });

  test("a task's end after its turn draws no agent item line", () {
    final state = fold([
      PromptAction('t1', 'go', 1),
      _task(SubagentState.running, task: _start),
      const ResultAction('t1', TurnAnswered('end_turn')),
      _task(SubagentState.completed),
    ]);
    expect(state.entries.whereType<ItemEndedEntry>(), isEmpty);
  });
}
