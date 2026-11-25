// A clear during a child's first start settles both the clear and an
// open_agent still waiting on that start for its effort.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/server/tools.dart' as tools show Cleared;
import 'package:chord/ui/app/window_fold.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'agents_host_test.dart' show Rig, started, scripted, until, chordSaid;
import 'conversation_fake.dart' show ScriptedSession;

void main() {
  testerClearOwnershipTests();
  test('a clear while a child first starts settles the clear and the open '
      'waiting on its effort', () async {
    final rig = await scripted();
    final opening = rig.host.open(
      mainKey,
      const SpawnArgs(
        agent: 'scripted',
        prompt: 'job',
        name: 'parser',
        effort: 'high',
      ),
      rig.person,
    );
    await until(() => rig.opens.isNotEmpty);
    // Before the first start answers, the child is cleared.
    final clearing = rig.host.clear(rig.person, 'parser');
    await until(() => rig.opens.length == 2);
    rig.opens.first.complete(ScriptedSession());
    rig.opens.last.complete(ScriptedSession());
    final cleared = await clearing.timeout(const Duration(seconds: 5));
    expect(cleared, isA<tools.Cleared>());
    final opened = await opening.timeout(const Duration(seconds: 5));
    expect(opened, isA<Started>());
  }, skip: fakeAgentSkip);
}

Future<({Rig rig, AgentsHost host, List<Completer<Session>> opens})>
_testerClearHost() async {
  final rig = await started();
  final opens = <Completer<Session>>[];
  addTearDown(() {
    for (final gate in opens) {
      if (!gate.isCompleted) gate.complete(ScriptedSession());
    }
  });
  final host = AgentsHost(
    runtimeNames: const ['scripted'],
    startupOf: (_) => const SessionStart(command: 'scripted'),
    openChildSession:
        (
          runtime,
          start, {
          required initial,
          chordServer,
          required onTraffic,
          required cancellationToken,
        }) {
          final gate = Completer<Session>();
          opens.add(gate);
          return gate.future;
        },
    agents: rig.connection.agents,
    server: rig.server,
    opened: (key) => rig.connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) =>
        rig.connection.fold.dispatch(SessionClosed(key, front)),
  );
  rig.connection.window = host;
  return (rig: rig, host: host, opens: opens);
}

void testerClearOwnershipTests() {
  group('tester: clear identity, admission and personal restoration', () {
    test(
      'restart keeps roster identity and renews admission before held messages run',
      () async {
        final h = await _testerClearHost();
        final caller = Caller(role: Role.person, key: mainKey, window: h.host);
        final old = ScriptedSession(), docs = ScriptedSession();
        for (final (name, session) in [('parser', old), ('docs', docs)]) {
          await h.host.open(
            mainKey,
            SpawnArgs(agent: 'scripted', name: name, prompt: 'job'),
            caller,
          );
          await until(() => h.opens.length > (name == 'parser' ? 0 : 1));
          h.opens.last.complete(session);
          await until(() => session.turns.isNotEmpty);
        }
        final before = [
          for (final child in h.rig.connection.agents.agents.children)
            (child.key, child.id, child.name, child.colour),
        ];
        final parser = h.rig.connection.agents.agents.children.first;
        final oldToken = h.rig.server.admitted.entries.firstWhere(
          (entry) => entry.value.agent == parser.id,
        );
        old.turns.single.answer();
        final clearing = h.host.clear(caller, parser.id);
        await until(() => h.opens.length == 3);
        expect(h.rig.server.revoked, contains(oldToken.key));
        expect(oldToken.value.launch?.call(), isFalse);
        final freshToken = h.rig.server.admitted.entries.lastWhere(
          (entry) => entry.value.agent == parser.id,
        );
        expect(freshToken.key, isNot(oldToken.key));
        expect(freshToken.value.launch?.call(), isTrue);
        h.host.tell(caller, parser.id, 'first fresh', () {});
        h.host.tell(caller, parser.id, 'second fresh', () {});
        final fresh = ScriptedSession();
        h.opens.last.complete(fresh);
        expect(await clearing, isA<tools.Cleared>());
        await until(() => fresh.turns.isNotEmpty);
        expect(fresh.turns.single.text, wrapMessage(fromMain, 'first fresh'));
        fresh.turns.single.answer();
        await until(() => fresh.turns.length == 2);
        expect(fresh.turns.last.text, wrapMessage(fromMain, 'second fresh'));
        expect([
          for (final child in h.rig.connection.agents.agents.children)
            (child.key, child.id, child.name, child.colour),
        ], before);
        expect(old.turns, hasLength(1));
        expect(chordSaid(h.rig.connection), isEmpty);
      },
      skip: fakeAgentSkip,
    );

    test(
      'clear counts distinct senders and restores personal held prompts with images in order',
      () async {
        final h = await _testerClearHost();
        final caller = Caller(role: Role.person, key: mainKey, window: h.host);
        await h.host.open(
          mainKey,
          const SpawnArgs(agent: 'scripted', name: 'parser', prompt: 'job'),
          caller,
        );
        await until(() => h.opens.isNotEmpty);
        final old = ScriptedSession()
          ..steering = true
          ..cutsSteeringCalls = true;
        h.opens.last.complete(old);
        await until(() => old.turns.isNotEmpty);
        final child = h.rig.connection.agents.agents.children.single;
        final conversation = child.conversation;
        old.say({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'held',
          'title': 'held',
          'status': 'in_progress',
        });
        const image = (id: 1, mediaType: 'image/png', data: 'eA==', bytes: 1);
        h.rig.connection.fold.dispatch(
          SessionActed(child.key, ImagesAddedAction([image])),
        );
        conversation.send('first [Image #1]');
        conversation.send('second');
        conversation.steerQueued();
        await until(
          () => h.rig.connection.fold.stateOf(child.key)!.queue.length == 2,
        );
        h.rig.connection.fold.dispatch(
          SessionActed(child.key, const ImagesSentAction('')),
        );
        expect(h.rig.connection.fold.stateOf(child.key)!.images, isEmpty);
        conversation.deliver(fromMain, 'message one');
        conversation.deliver(
          const MessageFrom('docs', reachable: true),
          'message two',
        );
        conversation.deliver(
          const MessageFrom('docs', reachable: true),
          'message three',
        );
        final clearing = h.host.clear(caller, child.id);
        await until(() => h.opens.length == 2);
        final fresh = ScriptedSession();
        h.opens.last.complete(fresh);
        final answer = await clearing as tools.Cleared;
        expect(
          answer.dropped,
          '3 queued messages from main and docs were not delivered.',
        );
        final state = h.rig.connection.fold.stateOf(child.key)!;
        expect(
          state.draft.indexOf('first [Image #1]'),
          greaterThanOrEqualTo(0),
        );
        expect(
          state.draft.indexOf('second'),
          greaterThan(state.draft.indexOf('first [Image #1]')),
        );
        expect(state.draft, isNot(contains('message')));
        expect(state.images, [image]);
        expect(fresh.turns, isEmpty);
        expect(old.steered, isEmpty);
      },
      skip: fakeAgentSkip,
    );
  });
}
