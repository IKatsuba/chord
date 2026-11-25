// A session whose task agents still run is busy with them, as the
// original's session/busy.ts and ui/app/closing.ts say: after a prompt of
// the person's waiting, before the turn itself.
import 'package:chord/session/busy.dart';
import 'package:chord/session/conversation.dart' show QueuedPrompt;
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/closing.dart';
import 'package:test/test.dart';

import 'transcript/fold.dart';

UpdateAction _task(String id, SubagentState state) => UpdateAction(
  't1',
  taskUpdate(
    id,
    state,
    task: state == SubagentState.running
        ? TaskStart(id: id, name: id, runtime: 'fake', prompt: 'go')
        : null,
  ),
);

void main() {
  test('running tasks make a session busy, counted; ended ones and '
      "adapters' subagents do not", () {
    final working = fold([
      PromptAction('t1', 'go', 1),
      _task('a', SubagentState.running),
      _task('b', SubagentState.running),
      _task('c', SubagentState.running),
      _task('c', SubagentState.completed),
      update('t1', {
        'sessionUpdate': 'subagent_update',
        'sessionId': 'sub',
        'state': {'state': 'running'},
      }),
    ]);
    expect(runningTasks(working), 2);
    expect(busyOf(working, const []), isA<BusyTasks>());
    expect((busyOf(working, const []) as BusyTasks).count, 2);
    // The person's own prompt waiting says more.
    expect(
      busyOf(working, const [QueuedPrompt('q', 'next')]),
      isA<BusyQueued>(),
    );
    // After the turn, the tasks still keep it busy.
    final after = fold([
      const ResultAction('t1', TurnAnswered('end_turn')),
    ], working);
    expect(busyOf(after, const []), isA<BusyTasks>());
  });

  test("a busy child's close line counts its task agents", () {
    expect(
      agentCloseArmedLine('parser', const BusyTasks(2), 'x'),
      'parser has 2 task agents running · x again to stop it and close',
    );
    expect(
      agentCloseArmedLine('parser', const BusyTasks(1), 'x'),
      'parser has 1 task agent running · x again to stop it and close',
    );
  });
}
