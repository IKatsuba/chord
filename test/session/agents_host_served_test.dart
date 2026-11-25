// What chord's server served goes to the caller's own session, main's or
// the child's, so the call that asked for it is drawn by it.
@Tags(['fake_agent'])
library;

import 'package:chord/server/tools.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'agents_host_test.dart' show started, until;

const _list = ChordCall(tool: ChordTool.listSessions, input: {'n': 1});

void main() {
  _testerClosedReceipts();
  test("a call served to main, or to a child, reaches that session's "
      'transcript alone', () async {
    final rig = await started();
    final answer =
        await rig.host.open(
              mainKey,
              const SpawnArgs(agent: 'fake', prompt: 'Read.', name: 'parser'),
              rig.person,
            )
            as Started;
    final child = rig.connection.agents.agents.children.single;
    await until(() => rig.prompts(child.key).isNotEmpty);
    // No call of these arguments is in either transcript, so each waits for
    // its call in the session it was served to.
    rig.host.served(rig.person, _list);
    await until(() => rig.stateOf(mainKey)!.transcript.served.isNotEmpty);
    expect(rig.stateOf(child.key)!.transcript.served, isEmpty);
    final caller = Caller(
      role: Role.child,
      key: mainKey,
      window: rig.host,
      agent: answer.id,
    );
    rig.host.servedLater(caller)(
      const ChordCall(tool: ChordTool.sendMessage, input: {'text': 'x'}),
    );
    await until(() => rig.stateOf(child.key)!.transcript.served.isNotEmpty);
    expect(
      rig.stateOf(child.key)!.transcript.served.single.tool,
      ChordTool.sendMessage,
    );
    expect(rig.stateOf(mainKey)!.transcript.served.single, _list);
  }, skip: fakeAgentSkip);

  test("a child's calls served through the caller chord admitted reach it; "
      "after a clear the old launch's, now or later, are dropped and the "
      "fresh launch's land", () async {
    final rig = await started();
    final answer =
        await rig.host.open(
              mainKey,
              const SpawnArgs(agent: 'fake', prompt: 'Read.', name: 'parser'),
              rig.person,
            )
            as Started;
    final child = rig.connection.agents.agents.children.single;
    await until(() => rig.prompts(child.key).isNotEmpty);
    final old = rig.server.admitted.values.firstWhere(
      (each) => each.agent == answer.id,
    );
    const before = ChordCall(tool: ChordTool.listSessions, input: {'n': 1});
    rig.host.served(old, before);
    await until(() => rig.stateOf(child.key)!.transcript.served.isNotEmpty);
    expect(rig.stateOf(child.key)!.transcript.served.single, before);
    expect(rig.stateOf(mainKey)!.transcript.served, isEmpty);
    final later = rig.host.servedLater(old);

    await rig.host.clear(rig.person, answer.id);
    await until(
      () => rig.server.admitted.values.any(
        (each) => each.agent == answer.id && !identical(each, old),
      ),
    );
    expect(old.launch?.call(), isFalse);
    rig.host.served(
      old,
      const ChordCall(tool: ChordTool.listSessions, input: {'n': 2}),
    );
    later(const ChordCall(tool: ChordTool.sendMessage, input: {'text': 'x'}));
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(rig.stateOf(child.key)!.transcript.served, isEmpty);

    final fresh = rig.server.admitted.values.lastWhere(
      (each) => each.agent == answer.id,
    );
    const now = ChordCall(tool: ChordTool.listSessions, input: {'n': 3});
    rig.host.servedLater(fresh)(now);
    await until(() => rig.stateOf(child.key)!.transcript.served.isNotEmpty);
    expect(rig.stateOf(child.key)!.transcript.served.single, now);
    expect(rig.stateOf(mainKey)!.transcript.served, isEmpty);
  }, skip: fakeAgentSkip);
}

void _testerClosedReceipts() {
  group('CTUI-35 tester: receipt owner after close', () {
    test(
      'old callbacks cannot reach a reopened child with the same name',
      () async {
        final rig = await started();
        final first =
            await rig.host.open(
                  mainKey,
                  const SpawnArgs(
                    agent: 'fake',
                    prompt: 'Read.',
                    name: 'parser',
                  ),
                  rig.person,
                )
                as Started;
        final oldChild = rig.connection.agents.agents.children.single;
        await until(() => rig.prompts(oldChild.key).isNotEmpty);
        final old = rig.server.admitted.values.firstWhere(
          (c) => c.agent == first.id,
        );
        final late = rig.host.servedLater(old);
        rig.host.close(rig.person, first.id);
        await until(() => rig.stateOf(oldChild.key) == null);
        final second =
            await rig.host.open(
                  mainKey,
                  const SpawnArgs(
                    agent: 'fake',
                    prompt: 'Again.',
                    name: 'parser',
                  ),
                  rig.person,
                )
                as Started;
        final freshChild = rig.connection.agents.agents.children.single;
        await until(() => rig.prompts(freshChild.key).isNotEmpty);
        expect(freshChild.key, isNot(oldChild.key));
        expect(second.id, isNot(first.id));
        rig.host.served(old, _list);
        late(_list);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(rig.stateOf(freshChild.key)!.transcript.served, isEmpty);
        expect(rig.stateOf(mainKey)!.transcript.served, isEmpty);
        final fresh = rig.server.admitted.values.lastWhere(
          (c) => c.agent == second.id,
        );
        rig.host.servedLater(fresh)(_list);
        expect(rig.stateOf(freshChild.key)!.transcript.served, [_list]);
      },
      skip: fakeAgentSkip,
    );
  });
}
