// The status notice's task variant, as the original's ui/status/status.ts
// `waitsNotice` and ui/app/sessions.ts `taskOf` give it: an agent not shown
// that waits on a task of its own is named by the task, as the task's box
// names it, and where that does not fit by whose task it is.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart' show Connected, Transcribed;
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/transcript/agents/subagents.dart' show taskAsking;
import 'package:test/test.dart';

/// main's transcript: the task `Fix the tokenizer` and a subagent of the
/// runtime's own.
List<Entry> _entries() => [
  PromptAction('t1', 'task', 0),
  UpdateAction(
    't1',
    taskUpdate(
      'task-1',
      SubagentState.running,
      task: const TaskStart(
        id: 'task-1',
        name: 'Fix the tokenizer',
        runtime: 'fake',
        prompt: 'taskchild',
        model: 'fake-small',
      ),
    ),
  ),
  UpdateAction(
    't1',
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'subagent_update',
      'sessionId': 'own',
      'title': 'Look',
      'state': {'state': 'running'},
    }),
  ),
].fold(Transcript.empty, reduceTranscript).entries;

AgentWaiting _asking(String name, AskingWait on) =>
    (name: name, wait: AgentWait(asking: (on: on, since: 5)));

void main() {
  test("a task's request is named as its box names it, by its runtime", () {
    final entries = _entries();
    expect(
      taskAsking(entries, const PermissionAsk(subagentId: 'task-1')),
      'Agent(Fix the tokenizer) · fake',
    );
    expect(
      taskAsking(entries, const InputAsk('Name it', subagentId: 'task-1')),
      'Agent(Fix the tokenizer) · fake',
    );
    // The session's own agent, or a subagent of the runtime's, is no task.
    expect(taskAsking(entries, const PermissionAsk()), isNull);
    expect(taskAsking(entries, const PermissionAsk(subagentId: 'own')), isNull);
    expect(
      taskAsking(entries, const PermissionAsk(subagentId: 'gone')),
      isNull,
    );
  });

  test('the notice names the task, and whose task it is where that does '
      'not fit', () {
    final notice = agentsWaitsNotice(
      [_asking('main', const PermissionAsk(subagentId: 'task-1'))],
      'ctrl+x a',
      taskOf: (agent) => taskAsking(_entries(), agent.wait.asking?.on),
    )!;
    expect(
      notice.text,
      '● Agent(Fix the tokenizer) · fake needs your permission',
    );
    expect(notice.short, "● main's task needs your permission");
    expect(notice.key, 'ctrl+x a');
    expect(notice.tone, StatusTone.waits);
    final input = agentsWaitsNotice(
      [_asking('main', const InputAsk('Name it', subagentId: 'task-1'))],
      null,
      taskOf: (agent) => taskAsking(_entries(), agent.wait.asking?.on),
    )!;
    expect(input.text, '● Agent(Fix the tokenizer) · fake asks for input');
    expect(input.short, "● main's task asks for input");
  });

  test('an agent asking for itself is named by its own name', () {
    final notice = agentsWaitsNotice(
      [_asking('docs', const PermissionAsk())],
      'ctrl+x a',
      taskOf: (agent) => taskAsking(_entries(), agent.wait.asking?.on),
    )!;
    expect(notice.text, '● docs needs your permission');
    expect(notice.short, '● docs needs your permission');
  });

  test("a relayed request's wait keeps which task asks, as the notice "
      'reads it', () {
    // Up, as a session must be for its requests to wait on the person.
    final up = heardWait(
      const AgentWait(),
      const Connected('m', AgentState.empty),
      1,
      front: false,
    ).wait;
    final permission = heardWait(
      up,
      Transcribed(
        PermissionRequestedAction(
          't1',
          const PermissionWait('perm-1', subagentId: 'task-1'),
          at: 5,
          between: true,
        ),
      ),
      5,
      front: false,
    ).wait;
    expect(permission.asking?.on.subagentId, 'task-1');
    final form = heardWait(
      up,
      const Transcribed(
        ElicitationRequestedAction(
          't1',
          FormWait('form-1', 'Name it', subagentId: 'task-1', between: true),
        ),
      ),
      5,
      front: false,
    ).wait;
    expect(form.asking?.on.subagentId, 'task-1');
  });
}
