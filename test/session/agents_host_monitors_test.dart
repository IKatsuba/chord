// The window's monitors through the host, on the fake: started in the
// caller's own conversation, their lines a message to it, refused to a
// task and to a launch let go, and gone with a child that closes.
@TestOn('posix')
library;

import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'agents_host_test.dart' show started, until;

void main() {
  final skip = fakeAgentSkip;

  test("a monitor's lines reach the caller's own conversation as a message "
      'from it', () async {
    final rig = await started();
    final answer = await rig.host.monitor(rig.person, (
      command: "printf 'ready\\n'; sleep 30",
      description: 'server',
      timeoutMs: null,
    ));
    expect(answer.toJson(), {
      'id': 'm1',
      'description': 'server',
      'timeout_ms': 600000,
    });
    expect([for (final m in rig.host.monitors(rig.person)) m.info.id], ['m1']);
    await until(() => rig.prompts(mainKey).any((p) => p.from != null));
    final message = rig.prompts(mainKey).firstWhere((p) => p.from != null);
    expect(message.text, 'ready');
    expect(message.from?.monitor?.id, 'm1');

    final task = Caller(
      role: Role.child,
      key: mainKey,
      window: rig.host,
      task: 't1',
    );
    expect(rig.host.monitors(task), isEmpty);
    expect((await rig.host.monitor(task, _args)).toJson(), {
      'error': 'This session has closed',
    });
    expect(rig.host.stopMonitor(rig.person, 'm1').toJson(), {
      'id': 'm1',
      'description': 'server',
      'events': 1,
      'ran_ms': isA<int>(),
    });
    expect(rig.host.monitors(rig.person), isEmpty);
  }, skip: skip);

  test('a launch let go is refused, and a closing child takes its monitors '
      'with it', () async {
    final rig = await started();
    final opened =
        await rig.host.open(
              mainKey,
              const SpawnArgs(agent: 'fake', prompt: 'Watch.', name: 'watcher'),
              rig.person,
            )
            as Started;
    final child = rig.connection.agents.agents.children.single;
    final caller = rig.server.admitted.values.firstWhere(
      (each) => each.agent == opened.id,
    );
    await until(() => rig.prompts(child.key).isNotEmpty);
    expect(
      await rig.host.monitor(caller, _args),
      isA<StartedMonitor>().having((s) => s.id, 'id', 'm1'),
    );
    expect(rig.host.monitors(caller), hasLength(1));
    expect(rig.host.monitors(rig.person), isEmpty);

    await rig.connection.agents.closeChild(child.key);
    expect(rig.host.monitors(caller), isEmpty);
    expect((await rig.host.monitor(caller, _args)).toJson(), stale.toJson());
    expect(rig.host.stopMonitor(caller, 'm1').toJson(), stale.toJson());
  }, skip: skip);
}

const _args = (command: 'sleep 30', description: 'waits', timeoutMs: null);
