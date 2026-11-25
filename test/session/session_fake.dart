// The session on the original's fake agent, and the steps its tests share:
// the original's tests/session/session_fake.ts.
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';

export '../fixtures/fake_harness.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// Opens a session on the fake agent playing [scenario] with [flags],
/// declaring [capabilities] toward it, hands it and its traffic to [body],
/// then closes it and proves the agent is gone, whatever [body] did.
Future<void> withSession(
  Future<void> Function(Session session, TrafficRecorder traffic) body, {
  String? scenario,
  List<String> flags = const [],
  acp.ClientCapabilities? capabilities,
}) async {
  final dir = Directory.systemTemp.createTempSync('chord-session-');
  final traffic = TrafficRecorder();
  final pids = <int>[];
  final session = await openSession(
    agent: 'fake',
    command: fakeAgentCommand(scenario, flags),
    cwd: dir.path,
    open: fakeOpenerWith(onPid: pids.add, capabilities: capabilities),
    onTraffic: traffic.add,
  );

  try {
    expect(pids, hasLength(1));
    await body(session, traffic);
  } finally {
    await session.close();
    expect(pids.where(_alive), isEmpty, reason: 'the agent is still running');
    dir.deleteSync(recursive: true);
  }
}

/// What a prompt brought until the agent answered it.
typedef Ran = ({Turn turn, List<acp.SessionUpdate> updates, TurnResult result});

/// Sends [text] and collects the updates it brought until its answer;
/// [onUpdate] hears the updates so far after each.
Future<Ran> run(
  Session session,
  String text, {
  void Function(List<acp.SessionUpdate> updates, Turn turn)? onUpdate,
}) async {
  final updates = <acp.SessionUpdate>[];
  Turn? turn;
  final unsubscribe = session.subscribe((update) {
    updates.add(update);
    if (turn case final turn?) onUpdate?.call(updates, turn);
  });

  try {
    turn = session.prompt(text);
    return (turn: turn, updates: updates, result: await turn.result);
  } finally {
    unsubscribe();
  }
}

/// The updates a prompt brought until the agent answered it.
Future<List<acp.SessionUpdate>> collect(Session session, String text) async =>
    (await run(session, text)).updates;

/// The text of the agent's message chunks, or of [kind]'s.
List<String> said(
  List<acp.SessionUpdate> updates, [
  String kind = 'agent_message_chunk',
]) => [
  for (final update in updates)
    if (update.kind == kind)
      ((update.toJson()['content'] as Map)['text'] as String),
];

/// The tool calls and updates to them among [updates], as their JSON.
List<Map<String, Object?>> calls(List<acp.SessionUpdate> updates) => [
  for (final update in updates)
    if (update.kind == 'tool_call' || update.kind == 'tool_call_update')
      update.toJson(),
];
