// Task agents through the original's fake and chord's own server over
// HTTP, as the original's scenarios in tests/fixtures/fake_agent/
// scenarios/tasks.ts and efforts.ts and agents.ts' `agenttask` play them:
// the task's work and asks in its parent's view, its message and report,
// Esc and close_agent stopping it, efforts, and a task whose agent exits
// with its ask open.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart' show Transcribed;
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';

/// The original's TASK_REPORT and TASK_MESSAGE.
const _report =
    'The tokenizer dropped a closing quote when a string ended the line. '
    'Fixed in src/parse/tokenize.ts, with two cases added to '
    'tests/parse/tokenize_test.ts. bun dev test passes.';
const _message =
    'Found it: a string at the end of a line lost its closing quote. '
    'Fixing src/parse/tokenize.ts now.';

/// Main on the fake with the host over it and chord's own server, each
/// agent process it starts kept by its pid.
final class _Rig {
  final pids = <int>[];
  late final TestRuntimes runtimes = TestRuntimes(onPid: pids.add);
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  AppState state([int key = mainKey]) => connection.fold.stateOf(key)!;

  Transcript transcript([int key = mainKey]) => state(key).transcript;

  /// The task blocks of [key]'s transcript.
  List<Subagent> tasks([int key = mainKey]) => [
    for (final entry in transcript(key).entries)
      if (entry is SubagentEntry && entry.subagent.task != null) entry.subagent,
  ];

  /// The permissions [key]'s session waits on.
  List<PermissionWait> asks([int key = mainKey]) =>
      switch (transcript(key).turn) {
        AwaitingPermission(:final permissions) => permissions,
        _ => const [],
      };

  /// The turns of [key]'s that messages started, or went into.
  List<UserEntry> messages([int key = mainKey]) => [
    for (final entry in transcript(key).entries)
      if (entry is UserEntry && entry.from != null) entry,
  ];

  String said([int key = mainKey]) => [
    for (final entry in transcript(key).entries)
      if (entry is AssistantEntry) entry.text.text,
  ].join('\n');
}

Future<_Rig> _served() async {
  final server = await serveChord();
  final rig = _Rig();
  final runtimes = rig.runtimes;
  rig.connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  rig.host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: rig.connection.openChild,
    agents: rig.connection.agents,
    opened: (key) => rig.connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) =>
        rig.connection.fold.dispatch(SessionClosed(key, front)),
    server: server,
  );
  rig.connection
    ..server = server
    ..window = rig.host
    ..start();
  addTearDown(() async {
    await rig.connection.close();
    await server.close();
    runtimes.dispose();
  });
  await _until(
    () =>
        rig.connection.fold.stateOf(mainKey)?.start.phase ==
        StartPhase.connected,
  );
  return rig;
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  _testerTaskExitOrder();
  final skip = fakeAgentSkip;

  test("task: the task's write is asked in main's view and answered there; "
      'its message and its report reach main, its spend on its end', () async {
    final rig = await _served();
    rig.connection.conversation.send('task');
    await _until(() => rig.asks().isNotEmpty);
    final block = rig.tasks().single;
    final info = block.task!;
    expect(
      (info.name, info.runtime, info.model),
      ('Fix the tokenizer', 'fake', 'fake-small'),
    );
    final ask = rig.asks().single;
    expect(ask.subagentId, block.id);
    expect(ask.title, 'Edit src/parse/tokenize.ts');
    rig.connection.conversation.choose(ask.id, 'allow');
    await _until(
      () => rig.messages().any((m) => m.from?.note == MessageNote.report),
    );
    expect(rig.asks(), isEmpty);
    final [told, report] = rig.messages();
    expect(told.from, const MessageFrom('Fix the tokenizer', runtime: 'fake'));
    expect(told.text, _message);
    expect(
      report.from,
      const MessageFrom(
        'Fix the tokenizer',
        runtime: 'fake',
        note: MessageNote.report,
      ),
    );
    expect(report.text, _report);
    final ended = rig.tasks().single;
    expect(ended.state, SubagentState.completed);
    expect(ended.task!.spent?.tokens?['totalTokens'], isNotNull);
    // Its work is drawn in its block, not in main's own entries.
    expect(
      ended.entries.whereType<ToolEntry>().map((e) => e.call.title),
      contains('Edit src/parse/tokenize.ts'),
    );
  }, skip: skip);

  test("agenttask: parser's task asks in parser's view, and reports to "
      'parser', () async {
    final rig = await _served();
    rig.connection.conversation.send('agenttask');
    await _until(() => rig.connection.agents.agents.children.isNotEmpty);
    final parser = rig.connection.agents.agents.children.single.key;
    await _until(() => rig.asks(parser).isNotEmpty);
    expect(rig.asks(), isEmpty);
    final ask = rig.asks(parser).single;
    expect(ask.subagentId, rig.tasks(parser).single.id);
    rig.connection.agents.conversationOf(parser)!.choose(ask.id, 'allow');
    await _until(
      () => rig.messages(parser).any((m) => m.from?.note == MessageNote.report),
    );
    expect(rig.messages(parser).last.text, _report);
    expect(rig.tasks(), isEmpty);
  }, skip: skip);

  test('taskeffort: the answer says the effort the task started on, and its '
      'block too', () async {
    final rig = await _served();
    rig.connection.conversation.send('taskeffort');
    await _until(() => rig.said().contains('Started on'));
    expect(rig.said(), contains('Started on high.'));
    expect(rig.said(), isNot(contains('Could not')));
    expect(rig.tasks().single.task!.effort, 'high');
  }, skip: skip);

  test("taskmaxeffort: an effort the runtime refuses leaves the task on the "
      "runtime's own, said in the answer and in main's turn", () async {
    const refusal =
        'Could not start on max effort, asked by spawn_task: the agent '
        'offers low, medium, high';
    final rig = await _served();
    rig.connection.conversation.send('taskmaxeffort');
    await _until(() => rig.said().contains('Started on'));
    expect(rig.said(), contains('Started on medium. $refusal.'));
    expect(
      rig.transcript().entries.whereType<ErrorEntry>().map((e) => e.message),
      contains('Tune the parser: $refusal'),
    );
    expect(rig.tasks().single.task!.effort, 'medium');
  }, skip: skip);

  test('tasklong then taskclose: close_agent by name stops the task, its end '
      'naming main, with no report and no line held; once ended, said '
      'so', () async {
    final rig = await _served();
    rig.connection.conversation.send('tasklong');
    await _until(() => rig.said().contains('The build is being watched.'));
    expect(rig.tasks().single.state, SubagentState.running);
    await _until(() => rig.transcript().turn is Idle);
    rig.connection.conversation.send('taskclose');
    await _until(() => rig.said().contains('The build is no longer watched.'));
    await _until(() => rig.tasks().single.state != SubagentState.running);
    final ended = rig.tasks().single;
    expect(ended.state, SubagentState.cancelled);
    expect(ended.task!.stoppedWith, const TaskStop.agent('main'));
    expect(rig.messages(), isEmpty);
    expect(rig.host.close(rig.person, 'Watch the build').toJson(), {
      'ended': 'Watch the build',
    });
  }, skip: skip);

  test('Esc on a turn with its task asking stops the task with no report; '
      'its ask goes with it', () async {
    final rig = await _served();
    rig.connection.conversation.send('taskstays');
    await _until(() => rig.asks().isNotEmpty);
    rig.connection.conversation.interrupt();
    await _until(
      () =>
          rig.tasks().single.state != SubagentState.running &&
          rig.transcript().turn is Idle,
    );
    final ended = rig.tasks().single;
    expect(ended.state, SubagentState.cancelled);
    expect(ended.task!.stoppedWith, TaskStop.esc);
    expect(rig.asks(), isEmpty);
    // No report, and no turn of main's from the task.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(rig.messages(), isEmpty);
  }, skip: skip);

  test("tasktitled: a task's agent naming its own session leaves main's "
      'title alone', () async {
    final rig = await _served();
    rig.connection.conversation.send('tasktitled');
    await _until(
      () =>
          rig.tasks().isNotEmpty &&
          rig.tasks().single.state != SubagentState.running,
    );
    expect(rig.connection.conversation.title, isNull);
  }, skip: skip);

  test("a task's agent exiting with its ask open: the ask is withdrawn "
      'before its end, as the original does, so no box is left; main gets '
      'its failure, the queue its ask held let go', () async {
    final rig = await _served();
    rig.connection.conversation.send('taskbetween');
    await _until(() => rig.asks().isNotEmpty);
    // Main's agent first, then the task's.
    expect(rig.pids, hasLength(2));
    Process.killPid(rig.pids.last, ProcessSignal.sigkill);
    await _until(
      () => rig.messages().any((m) => m.from?.note == MessageNote.failed),
    );
    expect(rig.asks(), isEmpty);
    expect(rig.tasks().single.state, SubagentState.disconnected);
    expect(rig.messages().single.text, 'fake exited');
  }, skip: skip);

  test('spawn_task and close_agent on tasks: refusals, two of one name, one '
      'closed by its id, and a message from a task that has ended', () async {
    final rig = await _served();
    expect(
      (await rig.host.spawn(
        rig.person,
        const SpawnArgs(agent: 'fakx', prompt: 'go'),
      )).toJson(),
      {'error': 'No agent named fakx; chord knows fake'},
    );
    const args = SpawnArgs(agent: 'fake', prompt: 'taskwait', name: 'Watch');
    final first = await rig.host.spawn(rig.person, args) as Started;
    final second = await rig.host.spawn(rig.person, args) as Started;
    expect(first.toJson(), {'id': first.id, 'name': 'Watch', 'agent': 'fake'});
    expect(rig.host.close(rig.person, 'Watch').toJson(), {
      'error':
          '2 of your tasks are named Watch; close_agent one by its id: '
          '${first.id} and ${second.id}',
    });
    expect(rig.host.close(rig.person, first.id).toJson(), {'closed': 'Watch'});
    await _until(
      () => rig.tasks().any((t) => t.state == SubagentState.cancelled),
    );
    final task = Caller(
      role: Role.child,
      key: mainKey,
      task: first.id,
      window: rig.host,
    );
    expect(rig.host.message(task, 'late', () {}).toJson(), {
      'error': 'Your task has ended; nothing more reaches its parent',
    });
    final running = Caller(
      role: Role.child,
      key: mainKey,
      task: second.id,
      window: rig.host,
    );
    expect(rig.host.message(running, 'Still watching.', () {}).toJson(), {
      'delivered': 'sent',
    });
    await _until(() => rig.messages().isNotEmpty);
    expect(
      rig.messages().single.from,
      const MessageFrom('Watch', runtime: 'fake'),
    );
  }, skip: skip);
}

void _testerTaskExitOrder() {
  group('CTUI-35 tester: task process exit', () {
    test(
      'withdraws before disconnected, releases the held queue, and closes every owned process',
      () async {
        final rig = await _served();
        final actions = <TranscriptAction>[];
        final stop = rig.connection.listen((event) {
          if (event is Transcribed) actions.add(event.action);
        });
        addTearDown(stop);
        rig.connection.conversation.send('taskbetween');
        await _until(() => rig.asks().isNotEmpty);
        final id = rig.tasks().single.id;
        final ask = rig.asks().single.id;
        rig.connection.conversation.send('queued after the task ask');
        await _until(
          () => rig.state().queue.any(
            (q) => q.text == 'queued after the task ask',
          ),
        );
        expect(rig.pids, hasLength(2));
        expect(Process.killPid(rig.pids.last, ProcessSignal.sigkill), isTrue);
        await _until(
          () => rig.messages().any((m) => m.from?.note == MessageNote.failed),
        );
        await _until(
          () => rig.transcript().entries.whereType<UserEntry>().any(
            (e) => e.text == 'queued after the task ask',
          ),
        );
        final withdrawn = actions.indexWhere(
          (a) => a is PermissionSettledAction && a.id == ask,
        );
        final ended = actions.indexWhere(
          (a) =>
              a is UpdateAction &&
              a.update.kind == 'subagent_update' &&
              a.update.toJson()['sessionId'] == id &&
              (a.update.toJson()['state'] as Map?)?['state'] == 'disconnected',
        );
        expect(withdrawn, isNonNegative);
        expect(ended, greaterThan(withdrawn));
        expect(rig.asks(), isEmpty);
        expect(rig.messages().single.text, 'fake exited');
        await rig.connection.close();
        for (final pid in rig.pids) {
          final result = await Process.run('kill', ['-0', '$pid']);
          expect(
            result.exitCode,
            isNot(0),
            reason: 'owned fake process $pid is still alive',
          );
        }
      },
      skip: fakeAgentSkip,
    );
  });
}
