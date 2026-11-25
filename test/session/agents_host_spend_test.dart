// What a child spent counts for the window after it goes: kept under its
// key as it closes, its last events too, and a cleared child's old launch
// kept under a key of its own.
@Tags(['fake_agent'])
library;

import 'package:chord/server/tools.dart';
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
import 'agents_host_test.dart' show until;
import 'conversation_fake.dart' show ScriptedSession;

final class Rig {
  Rig() {
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    final fold = connection.fold;
    host = AgentsHost(
      runtimeNames: const ['scripted'],
      startupOf: (runtime) => const SessionStart(command: 'scripted'),
      openChildSession:
          (
            runtime,
            start, {
            required initial,
            chordServer,
            required onTraffic,
            required cancellationToken,
          }) {
            final next = ScriptedSession();
            sessions.add(next);
            return Future.value(next);
          },
      agents: connection.agents,
      opened: (key) => fold.dispatch(AgentOpened(key)),
      closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
      keepClosing: (key, {from, required name, runtime}) => fold.dispatch(
        SpendClosing(key, from: from, name: name, runtime: runtime),
      ),
      keptClosed: (key) => fold.dispatch(SpendClosed(key)),
    );
    connection.start();
  }

  final runtimes = TestRuntimes();
  final sessions = <ScriptedSession>[];
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);
  WindowedState get windowed => connection.fold.windowed.value;

  Future<int> parser() async {
    await host.open(
      mainKey,
      const SpawnArgs(agent: 'scripted', prompt: 'job', name: 'parser'),
      person,
    );
    await until(() => sessions.isNotEmpty && sessions.last.turns.isNotEmpty);
    return connection.agents.agents.children.single.key;
  }
}

Future<Rig> started() async {
  final rig = Rig();
  addTearDown(() async {
    await rig.connection.close();
    rig.runtimes.dispose();
  });
  await until(
    () =>
        rig.connection.fold.stateOf(mainKey)?.start.phase ==
        StartPhase.connected,
  );
  return rig;
}

void main() {
  overlapTests();
  lateTests();
  test("a closed child's spend is kept under its key until its close "
      'settles, then counted for the window', () async {
    final rig = await started();
    final key = await rig.parser();
    rig.sessions.single.turns.single.answer(
      const TurnAnswered('end_turn', usage: {'inputTokens': 100}),
    );
    await until(() => rig.connection.fold.stateOf(key)!.spent != null);
    rig.host.close(rig.person, 'parser');
    // Held while it closes, gone from the window's sessions.
    expect(rig.windowed.sessions.containsKey(key), isFalse);
    expect(rig.windowed.closing.containsKey(key), isTrue);
    await until(() => rig.windowed.kept.isNotEmpty);
    expect(rig.windowed.closing, isEmpty);
    expect(rig.windowed.kept.single.spent!.turns.values, [
      {'inputTokens': 100},
    ]);
  }, skip: fakeAgentSkip);

  test("a cleared child's old launch is kept under a key of its own", () async {
    final rig = await started();
    final key = await rig.parser();
    rig.sessions.first.turns.single.answer(
      const TurnAnswered('end_turn', usage: {'inputTokens': 100}),
    );
    await until(() => rig.connection.fold.stateOf(key)!.spent != null);
    await rig.host.clear(rig.person, 'parser');
    await until(() => rig.windowed.kept.isNotEmpty);
    expect(rig.windowed.kept.single.spent!.turns.values, [
      {'inputTokens': 100},
    ]);
    expect(rig.connection.fold.stateOf(key)!.spent, isNull);
    expect(rig.windowed.sessions.containsKey(key), isTrue);
  }, skip: fakeAgentSkip);
}

void lateTests() {
  test("a busy child's turn ending as it closes counts once its close "
      'settles', () async {
    final rig = await started();
    final key = await rig.parser();
    final session = rig.sessions.single;
    session.onClose = () => session.turns.single.answer(
      const TurnAnswered('cancelled', usage: {'inputTokens': 42}),
    );
    rig.host.close(rig.person, 'parser');
    expect(rig.windowed.sessions.containsKey(key), isFalse);
    await until(() => rig.windowed.kept.isNotEmpty);
    expect(rig.windowed.kept.single.spent!.turns.values, [
      {'inputTokens': 42},
    ]);
    expect(rig.windowed.closing, isEmpty);
  }, skip: fakeAgentSkip);

  test("a cleared child's old turn ending after the clear counts as the old "
      'launch, never the fresh one, each retirement its own', () async {
    final rig = await started();
    final key = await rig.parser();
    for (final (index, tokens) in [(0, 5), (1, 9)]) {
      final old = rig.sessions[index];
      if (index > 0) {
        // The fresh session's own turn, running as it is cleared again.
        rig.connection.agents.conversationOf(key)!.send('again');
        await until(() => old.turns.isNotEmpty);
      }
      old.onClose = () => old.turns.last.answer(
        TurnAnswered('cancelled', usage: {'inputTokens': tokens}),
      );
      await rig.host.clear(rig.person, 'parser');
      await until(() => rig.windowed.kept.length == index + 1);
    }
    expect(
      [for (final kept in rig.windowed.kept) kept.spent!.turns.values.single],
      [
        {'inputTokens': 5},
        {'inputTokens': 9},
      ],
    );
    expect(rig.connection.fold.stateOf(key)!.spent, isNull);
  }, skip: fakeAgentSkip);
}

void overlapTests() {
  test("a cleared child's old turn ending after the child closed too still "
      'counts as the old launch, not the closed one', () async {
    final rig = await started();
    await rig.parser();
    final old = rig.sessions.first;
    // Cleared with its first turn still running, then closed.
    final clearing = rig.host.clear(rig.person, 'parser');
    await until(() => rig.sessions.length == 2);
    await clearing;
    // The fresh launch spends on its own before it closes.
    final key = rig.connection.agents.agents.children.single.key;
    final fresh = rig.sessions.last;
    rig.connection.agents.conversationOf(key)!.send('again');
    await until(() => fresh.turns.isNotEmpty);
    fresh.turns.single.answer(
      const TurnAnswered('end_turn', usage: {'inputTokens': 3}),
    );
    await until(() => rig.connection.fold.stateOf(key)!.spent != null);
    rig.host.close(rig.person, 'parser');
    old.turns.single.answer(
      const TurnAnswered('cancelled', usage: {'inputTokens': 11}),
    );
    await until(
      () => rig.windowed.closing.isEmpty && rig.windowed.kept.length == 2,
    );
    // Each launch is kept with its own turn alone.
    expect(
      [for (final kept in rig.windowed.kept) kept.spent!.turns.values.toList()],
      unorderedEquals([
        [
          {'inputTokens': 11},
        ],
        [
          {'inputTokens': 3},
        ],
      ]),
    );
    expect(rig.windowed.closing, isEmpty);
  }, skip: fakeAgentSkip);
}
