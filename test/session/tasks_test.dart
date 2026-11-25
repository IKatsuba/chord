// The original's tests/session/tasks_test.ts: messages' wrappers and
// senders, task names, and a task agent from its start to its report, its
// stops and its spend, against a stand-in parent and session.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/permissions.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  test("a monitor's wrapper names it, its end and its id, and a record "
      'keeps it', () {
    const event = MessageFrom('dev "server"', monitor: (id: 'm1', end: null));
    expect(
      wrapMessage(event, 'ERROR'),
      '<message from="dev &quot;server&quot; · monitor" monitor="m1">\n'
      'ERROR\n</message>',
    );
    const ended = MessageFrom(
      'build',
      monitor: (id: 'm2', end: MonitorTimedOut(1000)),
    );
    expect(fromLine(ended), 'build · monitor · timed out');
    for (final from in [
      event,
      ended,
      const MessageFrom('b', monitor: (id: 'm3', end: MonitorExited(1))),
      const MessageFrom(
        'b',
        monitor: (id: 'm3', end: MonitorKilled('SIGKILL')),
      ),
      const MessageFrom('b', monitor: (id: 'm3', end: MonitorStopped())),
      const MessageFrom(
        'b',
        monitor: (id: 'm3', end: MonitorFlooded(FloodBy.bytes)),
      ),
    ]) {
      expect(MessageFrom.fromJson(from.toJson()), from);
    }
    expect(ended.toJson(), {
      'name': 'build',
      'monitor': {
        'id': 'm2',
        'end': {'kind': 'timed_out', 'timeoutMs': 1000},
      },
    });
    // An end this version does not know is no sender it can draw.
    expect(
      MessageFrom.fromJson({
        'name': 'b',
        'monitor': {
          'id': 'm1',
          'end': {'kind': 'melted'},
        },
      }),
      isNull,
    );
  });
  test("a message's wrapper names its sender as its row does", () {
    const from = MessageFrom(
      'Fix "the" tokenizer',
      runtime: 'codex',
      note: MessageNote.report,
    );
    expect(
      wrapMessage(from, 'Fixed.\nTwo tests added.'),
      '<message from="Fix &quot;the&quot; tokenizer · codex · report">\n'
      'Fixed.\nTwo tests added.\n</message>',
    );
    expect(fromLine(const MessageFrom('chord')), 'chord');
    expect(
      fromLine(
        const MessageFrom('scan', runtime: 'fake', note: MessageNote.failed),
      ),
      'scan · fake · failed',
    );
  });

  test('a sender send_message reaches is drawn with @, a task and chord '
      'bare', () {
    expect(senderName(const MessageFrom('main', reachable: true)), '@main');
    expect(
      senderName(
        const MessageFrom('parser', runtime: 'codex', reachable: true),
      ),
      '@parser',
    );
    expect(
      senderName(const MessageFrom('Fix the tokenizer', runtime: 'codex')),
      'Fix the tokenizer',
    );
    expect(senderName(const MessageFrom('chord')), 'chord');
  });
  taskAgentTests();
}

/// A parent that keeps what a task did to it, and a session that does
/// nothing but say what it was asked.
final class _Harness implements TaskParent, TaskSession {
  _Harness() {
    task = TaskAgent(
      const TaskStart(
        id: 'task-1',
        name: 'Fix it',
        runtime: 'fake',
        model: 'fake-small',
        prompt: 'taskchild',
      ),
      this,
      () => 42,
    )..begin(this);
  }

  late final TaskAgent task;
  final relayed = <ConversationEvent>[];
  final delivered = <(MessageFrom, String)>[];
  final aheads = <(MessageFrom, String)>[];
  final ends = <String>[];
  final sent = <String>[];
  final asked = <String>[];

  @override
  void relay(ConversationEvent event) => relayed.add(event);
  @override
  void deliver(MessageFrom from, String text) => delivered.add((from, text));
  @override
  void ahead(MessageFrom from, String text) => aheads.add((from, text));
  @override
  void ended() => ends.add('task-1');

  @override
  void start() {}
  @override
  bool send(String text) {
    sent.add(text);
    return true;
  }

  @override
  void interrupt() => asked.add('interrupt');
  @override
  void choose(String id, String optionId) => asked.add('choose $id $optionId');
  @override
  void reject(String id) => asked.add('reject $id');
  @override
  void answer(String id, ElicitationReply reply) => asked.add('answer $id');
  @override
  Future<void> close() async {}
  @override
  PendingPermission? permissionRequest(String id) => null;
  @override
  PendingElicitation? elicitationRequest(String id) => null;

  void hear(TranscriptAction action) => task.heard(Transcribed(action));

  void connect() => task.heard(const Connected('s1', AgentState.empty));

  void prompt([String text = 'x']) => hear(PromptAction('r1', text, 1));

  void result(TurnResult result) => hear(ResultAction('r1', result));

  /// The last update relayed, as JSON.
  Map<String, Object?> get last =>
      ((relayed.last as Transcribed).action as UpdateAction).update.toJson();
}

UpdateAction _chunk(String text) => UpdateAction(
  'r1',
  acp.SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
);

void taskAgentTests() {
  test("a task is named as asked, or by its prompt's first line", () {
    expect(taskName(' Fix it ', 'anything'), 'Fix it');
    expect(taskName(null, '\n  Run the tests\nand say'), 'Run the tests');
    expect(taskName('', ''), 'task');
  });

  test("a task's first turn is its job: its work relayed under its id, its "
      'last message the report', () {
    final h = _Harness();
    expect(h.relayed, hasLength(1));
    expect(h.last['_meta'], {
      'chord/task': {
        'name': 'Fix it',
        'runtime': 'fake',
        'model': 'fake-small',
      },
    });
    h.connect();
    expect(h.sent, ['taskchild']);
    h.prompt('taskchild');
    h.hear(_chunk('Looking.'));
    h.hear(
      UpdateAction(
        'r1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'title': 'Read a',
        }),
      ),
    );
    h.hear(_chunk('Fixed it.'));
    h.result(const TurnAnswered('end_turn'));
    expect(
      [
        for (final event in h.relayed.sublist(1, 4))
          ((event as Transcribed).action as UpdateAction).subagentId,
      ],
      ['task-1', 'task-1', 'task-1'],
    );
    expect(h.last, {
      'sessionUpdate': 'subagent_update',
      'sessionId': 'task-1',
      'state': {'state': 'completed'},
    });
    expect(h.delivered, [
      (
        const MessageFrom('Fix it', runtime: 'fake', note: MessageNote.report),
        'Fixed it.',
      ),
    ]);
    expect(h.ends, ['task-1']);
    expect(h.task.running, isFalse);
  });

  test("a task's permission is asked in the parent's name for it, and "
      'answered through it', () {
    final h = _Harness();
    h.hear(const PermissionRequestedAction('r1', PermissionWait('p1')));
    h.task.choose('p1', 'allow');
    final relayed =
        (h.relayed.last as Transcribed).action as PermissionRequestedAction;
    expect(
      (relayed.wait.id, relayed.wait.subagentId, relayed.at),
      ('p1', 'task-1', 42),
    );
    expect(h.asked, ['choose p1 allow']);
  });

  test("a task's form is asked in the parent's name for it", () {
    final h = _Harness();
    h.hear(const ElicitationRequestedAction('r1', FormWait('e1', 'Name?')));
    final relayed =
        (h.relayed.last as Transcribed).action as ElicitationRequestedAction;
    expect(relayed.elicitation.subagentId, 'task-1');
  });

  test('a failed turn ends the task failed with the error as its report; a '
      'refused start fails it before', () {
    final failed = _Harness()..prompt();
    failed.result(const TurnFailed('rate limited'));
    expect(failed.delivered, [
      (
        const MessageFrom('Fix it', runtime: 'fake', note: MessageNote.failed),
        'rate limited',
      ),
    ]);

    final lacking = _Harness();
    lacking.task.heard(
      const ConnectFailed(
        'Could not start on fake-small, asked by spawn_task: no',
      ),
    );
    lacking.connect();
    expect(lacking.delivered, [
      (
        const MessageFrom('Fix it', runtime: 'fake', note: MessageNote.failed),
        'Could not start on fake-small, asked by spawn_task: no',
      ),
    ]);
    expect(lacking.sent, isEmpty);
    expect(lacking.ends, ['task-1']);
  });

  test("the servers a task's agent was not given are said in its parent's "
      'turn, named as the task', () {
    final h = _Harness();
    const message =
        '1 MCP server was not passed to fake, which takes them over stdio '
        'and HTTP only: tracker (sse). /mcp lists it.';
    h.hear(const WarnedAction('w1', message));
    final relayed = (h.relayed.last as Transcribed).action as WarnedAction;
    expect((relayed.turnId, relayed.message), ('w1', 'Fix it: $message'));
  });

  test("an agent's exit ends the task disconnected, its runtime named", () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.hear(const DisconnectedAction('r1', at: 2));
    expect(h.last['state'], {'state': 'disconnected'});
    expect(h.delivered.single.$2, 'fake exited');
  });

  test('a task the parent stopped ends cancelled with no report, a line '
      'held for the next prompt instead', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel();
    h.result(const TurnAnswered('cancelled'));
    expect(h.asked, ['interrupt']);
    expect(h.delivered, isEmpty);
    expect(h.aheads, [
      (
        const MessageFrom('Fix it', runtime: 'fake'),
        'The person stopped this task before it reported.',
      ),
    ]);
    expect(h.last['state'], {'state': 'cancelled'});
  });

  test('a task its agent stopped says so on its end, and its parent is held '
      'no line', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel(const TaskStop.agent('main'));
    // The first stop's words stay.
    h.task.cancel(TaskStop.x);
    h.result(const TurnAnswered('cancelled'));
    expect(h.asked, ['interrupt', 'interrupt']);
    expect(h.delivered, isEmpty);
    expect(h.aheads, isEmpty);
    expect(h.last['_meta'], {
      'chord/stopped': {'agent': 'main'},
    });
  });

  test('a stop with no key first stays bare when its agent closes it after, '
      'and its line is held', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel();
    h.task.cancel(const TaskStop.agent('main'));
    h.result(const TurnAnswered('cancelled'));
    expect(h.aheads, hasLength(1));
    expect(h.last.containsKey('_meta'), isFalse);
  });

  test("a turn that completes after its agent's close still ends stopped by "
      'it, with no report', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel(const TaskStop.agent('main'));
    h.result(const TurnAnswered('end_turn'));
    expect(h.delivered, isEmpty);
    expect(h.aheads, isEmpty);
    expect(h.last['state'], {'state': 'cancelled'});
    expect(h.last['_meta'], {
      'chord/stopped': {'agent': 'main'},
    });
  });

  test("an agent's exit after its close still ends the task stopped by it, "
      'not disconnected', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel(const TaskStop.agent('main'));
    h.hear(const DisconnectedAction('r1', at: 2));
    expect(h.delivered, isEmpty);
    expect(h.aheads, isEmpty);
    expect(h.last['state'], {'state': 'cancelled'});
  });

  test('an agent close first keeps its name when a stop with no key '
      'follows', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel(const TaskStop.agent('main'));
    h.task.cancel();
    h.result(const TurnAnswered('cancelled'));
    expect(h.aheads, isEmpty);
    expect(h.last['_meta'], {
      'chord/stopped': {'agent': 'main'},
    });
  });

  test('a task the person stopped first keeps its x when its agent closes '
      'it after', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.task.cancel(TaskStop.x);
    h.task.cancel(const TaskStop.agent('main'));
    h.result(const TurnAnswered('cancelled'));
    expect(h.aheads, hasLength(1));
    expect(h.last['_meta'], {'chord/stopped': 'x'});
  });

  test('a task its agent closes while it starts ends there, its job never '
      'sent and no line held', () {
    final h = _Harness();
    h.task.cancel(const TaskStop.agent('main'));
    h.connect();
    expect(h.sent, isEmpty);
    expect(h.delivered, isEmpty);
    expect(h.aheads, isEmpty);
    expect(h.ends, ['task-1']);
    expect(h.last['_meta'], {
      'chord/stopped': {'agent': 'main'},
    });
  });

  test('a task stopped while it starts ends cancelled there, and its job is '
      'never sent', () {
    final h = _Harness();
    h.task.cancel();
    h.connect();
    expect(h.sent, isEmpty);
    expect(h.asked, isEmpty);
    expect(h.delivered, isEmpty);
    expect(h.aheads, hasLength(1));
    expect(h.ends, ['task-1']);
    expect(h.task.running, isFalse);
  });

  Map<String, Object?> ending(bool estimated, [Map<String, num>? tokens]) {
    final h = _Harness()
      ..connect()
      ..prompt('taskchild');
    h.hear(
      UpdateAction(
        'r1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'usage_update',
          'used': 2000,
          'size': 200000,
          'cost': {'amount': 0.0125, 'currency': 'USD'},
          if (estimated)
            '_meta': {
              'chord/filled': ['cost'],
            },
        }),
      ),
    );
    h.result(
      TurnAnswered(
        'end_turn',
        usage:
            tokens ??
            {'inputTokens': 1000, 'outputTokens': 200, 'totalTokens': 2000},
      ),
    );
    return h.last;
  }

  test("a task's ending update carries what it spent: its turn's tokens and "
      'its last cost, marked when chord estimated it', () {
    expect(ending(false)['_meta'], {
      'chord/spent': {
        'tokens': {
          'inputTokens': 1000,
          'outputTokens': 200,
          'totalTokens': 2000,
        },
        'cost': {'amount': 0.0125, 'currency': 'USD'},
      },
    });
    expect(
      (ending(true)['_meta']! as Map)['chord/spent'],
      containsPair('estimated', true),
    );
    // Zero is said, not left out.
    expect(
      ((ending(false, {'totalTokens': 0})['_meta']! as Map)['chord/spent']
          as Map)['tokens'],
      {'totalTokens': 0},
    );
  });

  test('a task whose agent reported nothing ends with nothing said of its '
      'spend', () {
    final h = _Harness()
      ..connect()
      ..prompt();
    h.result(const TurnAnswered('end_turn'));
    expect(h.last, {
      'sessionUpdate': 'subagent_update',
      'sessionId': 'task-1',
      'state': {'state': 'completed'},
    });
  });

  test('a late successful reply cannot report after an agent close; a '
      'completed report is not changed by a late close', () {
    for (final closeFirst in [true, false]) {
      final h = _Harness()
        ..connect()
        ..prompt();
      h.hear(_chunk('Finished before the wire drained.'));
      if (closeFirst) h.task.cancel(const TaskStop.agent('main'));
      h.result(const TurnAnswered('end_turn'));
      h.task.cancel(const TaskStop.agent('main'));
      expect(h.task.running, isFalse);
      expect(h.ends, ['task-1']);
      expect(h.aheads, isEmpty);
      expect(h.delivered, [
        if (!closeFirst)
          (
            const MessageFrom(
              'Fix it',
              runtime: 'fake',
              note: MessageNote.report,
            ),
            'Finished before the wire drained.',
          ),
      ]);
      expect(h.last['state'], {
        'state': closeFirst ? 'cancelled' : 'completed',
      });
    }
  });
}
