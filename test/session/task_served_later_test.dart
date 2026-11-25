// A receipt chord serves a task after the task has ended, through the
// original's fake and chord's own server over HTTP. The task's launch is
// revoked as it ends, yet ../chord's servedLater
// (src/session/agents_host.ts) checks no launch: the receipt still reaches
// the task's block in its parent, until the parent's session is cleared.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';

/// The original's TASK_MESSAGE, which the `task` scenario's task sends
/// through chord's send_message.
const _message =
    'Found it: a string at the end of a line lost its closing quote. '
    'Fixing src/parse/tokenize.ts now.';

/// Main on the fake with the host over it and chord's own server.
final class _Rig {
  final TestRuntimes runtimes = TestRuntimes();
  late final StartConnection connection;
  late final AgentsHost host;

  Transcript get transcript => connection.fold.stateOf(mainKey)!.transcript;

  List<Subagent> get tasks => [
    for (final entry in transcript.entries)
      if (entry is SubagentEntry && entry.subagent.task != null) entry.subagent,
  ];

  List<PermissionWait> get asks => switch (transcript.turn) {
    AwaitingPermission(:final permissions) => permissions,
    _ => const [],
  };
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

/// The task's send_message call in its block, if the block is there.
ToolCall? _sent(_Rig rig) {
  for (final task in rig.tasks) {
    for (final entry in task.entries) {
      if (entry is ToolEntry &&
          (entry.call.title ?? '').contains('send_message')) {
        return entry.call;
      }
    }
  }
  return null;
}

void main() {
  test("a receipt served after the task ended, its launch revoked, reaches "
      "the task's block; once the parent is cleared, nothing", () async {
    final rig = await _served();
    rig.connection.conversation.send('task');
    await _until(() => rig.asks.isNotEmpty);
    final id = rig.tasks.single.id;
    // The launch the task was admitted for, revoked as the task ends, the
    // way its conversation's release revokes it.
    var live = true;
    final caller = Caller(
      role: Role.child,
      key: mainKey,
      task: id,
      window: rig.host,
      launch: () => live,
    );
    final later = rig.host.servedLater(caller);
    rig.connection.conversation.choose(rig.asks.single.id, 'allow');
    await _until(
      () =>
          rig.tasks.single.state != SubagentState.running &&
          rig.transcript.turn is Idle,
    );
    live = false;

    // The task's message, served while it ran, already tied to its call in
    // the block; served again now, as a queued message going in later is,
    // it takes the place of what was tied there.
    final before = _sent(rig)!;
    final input = {'text': _message};
    expect(before.rawInput, input);
    final asked = before.chord?.asked;
    expect(asked, isNotNull);
    final receipt = ChordCall(
      tool: ChordTool.sendMessage,
      input: input,
      answer: const {'delivered': 'queued'},
      queued: true,
      asked: asked,
    );
    expect(before.chord, isNot(same(receipt)));
    later(receipt);
    expect(_sent(rig)!.chord, same(receipt));

    await rig.connection.conversation.clear();
    final fresh = rig.transcript;
    later(
      ChordCall(
        tool: ChordTool.sendMessage,
        input: input,
        queued: true,
        asked: asked,
      ),
    );
    expect(rig.transcript, same(fresh));
    expect(rig.tasks, isEmpty);
  }, skip: fakeAgentSkip);
}
