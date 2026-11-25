// A task's ending that a session let go still says, as the conversation
// gives it, a RetiredUpdate: the window's reducer takes it to the retired
// or closing state that had the task's turn, as the original's
// `retired_heard` and `closing_heard` do, and `/cost` counts the task once,
// a live session of the same id winning over what was kept.
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/spend.dart';
import 'package:test/test.dart';

const _main = 1;
const _child = 2;
const _retired = -1000001;

const _start = TaskStart(
  id: 'task-1',
  name: 'Count the cost',
  runtime: 'fake',
  prompt: 'costwait',
);

/// The task's ending, with the $0.01 it spent, as its agent closing it
/// gives it.
final _ending = taskUpdate(
  'task-1',
  SubagentState.cancelled,
  spent: const TaskSpent(cost: (amount: 0.01, currency: 'USD')),
);

WindowedState _heard(WindowedState state, int key, ConversationEvent event) =>
    reduceWindowed(state, SessionHeard(key, event));

/// Session [key] up as [sessionId], its turn [turnId] over with its task
/// still at work.
WindowedState _working(
  WindowedState state,
  int key,
  String sessionId,
  String turnId,
) => [
  Connected(sessionId, AgentState.empty),
  Transcribed(PromptAction(turnId, 'taskcost', 0)),
  Transcribed(
    UpdateAction(
      turnId,
      taskUpdate('task-1', SubagentState.running, task: _start),
    ),
  ),
  Transcribed(ResultAction(turnId, const TurnAnswered('end_turn'))),
].fold(state, (state, event) => _heard(state, key, event));

/// Main, at work on its task, cleared: its old session held under
/// [_retired], the fresh one up as `new`.
WindowedState _cleared() {
  var state = _working(
    WindowedState.of(AppState.starting, _main),
    _main,
    'old',
    't1',
  );
  state = reduceWindowed(
    state,
    const SpendClosing(
      _retired,
      from: _main,
      name: 'main',
      runtime: 'fake',
      main: true,
    ),
  );
  state = _heard(state, _main, const Cleared());
  return _heard(state, _main, const Connected('new', AgentState.empty));
}

/// The window's agents: main alone, any child closed.
const _agents = WindowAgents<String>(
  main: MainAgent(_main, 'fake', 'fake', AgentWait()),
  children: [],
  picked: _main,
  opened: 1,
  nextKey: 10,
);

/// The window's spend as `/cost` reads it from [state]: the sessions open,
/// and those closed and closing, kept as their parts.
List<SpendPart> _spend(WindowedState state) => windowSpend(
  _agents,
  {
    for (final MapEntry(:key, :value) in state.sessions.entries)
      key: SpendSession(
        sessionId: value.start.sessionId,
        spent: value.spent,
        transcript: value.transcript,
      ),
  },
  [
    for (final kept in [
      ...state.kept,
      for (final closing in state.closing.values) keptOf(closing),
    ])
      KeptSpend(
        sessionId: kept.sessionId,
        part: SpendPart(
          name: kept.name,
          kind: kept.main ? SpendKind.main : SpendKind.agent,
          figure: sessionFigure(kept.spent),
          parts: taskParts(kept.tasks),
          ended: true,
        ),
      ),
  ],
);

/// The task rows of [parts], each by its name and whether it still works.
List<(String, bool, num?)> _taskRows(List<SpendPart> parts) => [
  for (final part in parts) ...[
    if (part.kind == SpendKind.task)
      (part.name, part.running, part.figure?.cost?.amount),
    ..._taskRows(part.parts),
  ],
];

void main() {
  test("a task of main's ending after /clear goes to main's retired state, "
      'the fresh session untouched, and counts once', () {
    final cleared = _cleared();
    final state = _heard(cleared, _main, RetiredUpdate('t1', _ending));
    expect(identical(state.sessions[_main], cleared.sessions[_main]), isTrue);
    final held = state.closing[_retired]!.session.transcript.entries
        .whereType<SubagentEntry>()
        .single
        .subagent;
    expect(held.state, SubagentState.cancelled);
    expect(held.task!.spent!.cost, (amount: 0.01, currency: 'USD'));

    final kept = reduceWindowed(state, const SpendClosed(_retired));
    expect(kept.kept.single.tasks.single.state, SubagentState.cancelled);
    expect(_taskRows(_spend(kept)), [('Count the cost', false, 0.01)]);
    expect(sum(_spend(kept)).cost, 0.01);
    // One no retired state had the turn of reaches no session.
    expect(
      identical(_heard(state, _main, RetiredUpdate('t9', _ending)), state),
      isTrue,
    );
  });

  test("a task of a child's ending as the person closes it goes to the "
      "child's closing state, and counts once", () {
    var state = reduceWindowed(
      WindowedState.of(AppState.starting, _main),
      const AgentOpened(_child),
    );
    state = _working(state, _child, 'parser-session', 'c1');
    state = reduceWindowed(
      state,
      const SpendClosing(_child, name: 'parser', runtime: 'fake'),
    );
    state = reduceWindowed(state, const SessionClosed(_child, _main));
    state = reduceWindowed(
      state,
      ClosingHeard(_child, RetiredUpdate('c1', _ending)),
    );
    state = reduceWindowed(state, const SpendClosed(_child));
    expect(state.kept.single.name, 'parser');
    expect(_taskRows(_spend(state)), [('Count the cost', false, 0.01)]);
    expect(sum(_spend(state)).cost, 0.01);
  });

  test("a cleared child's old task ending after the child closed too goes "
      'to the old launch, not the closed one', () {
    var state = reduceWindowed(
      WindowedState.of(AppState.starting, _main),
      const AgentOpened(_child),
    );
    state = _working(state, _child, 'old', 'c1');
    state = reduceWindowed(
      state,
      const SpendClosing(_retired, from: _child, name: 'parser'),
    );
    state = _heard(state, _child, const Cleared());
    state = _heard(state, _child, const Connected('new', AgentState.empty));
    state = reduceWindowed(
      state,
      const SpendClosing(_child, name: 'parser', runtime: 'fake'),
    );
    state = reduceWindowed(state, const SessionClosed(_child, _main));
    final closed = state.closing[_child];
    state = reduceWindowed(
      state,
      ClosingHeard(_child, RetiredUpdate('c1', _ending)),
    );
    expect(identical(state.closing[_child], closed), isTrue);
    final held = state.closing[_retired]!.session.transcript.entries
        .whereType<SubagentEntry>()
        .single
        .subagent;
    expect(held.state, SubagentState.cancelled);
  });

  test('the ended task counts once when the session it ran in is open '
      'again: the live part wins over the kept one', () {
    final kept = reduceWindowed(
      _heard(_cleared(), _main, RetiredUpdate('t1', _ending)),
      const SpendClosed(_retired),
    );
    // Kept, beside the fresh session, the old one's task counts there.
    expect(_taskRows(_spend(kept)), [('Count the cost', false, 0.01)]);
    expect(_spend(kept).where((part) => part.ended), hasLength(1));
    // Main resumed the old session, its record's task ended in it too.
    final resumed = [
      const Cleared(),
      const Connected('old', AgentState.empty),
      Transcribed(PromptAction('t1', 'taskcost', 0)),
      Transcribed(
        UpdateAction(
          't1',
          taskUpdate('task-1', SubagentState.running, task: _start),
        ),
      ),
      Transcribed(UpdateAction('t1', _ending)),
    ].fold(kept, (state, event) => _heard(state, _main, event));
    final spend = _spend(resumed);
    expect(_taskRows(spend), [('Count the cost', false, 0.01)]);
    expect(spend.where((part) => part.ended), isEmpty);
    expect(sum(spend).cost, 0.01);
  });
}
