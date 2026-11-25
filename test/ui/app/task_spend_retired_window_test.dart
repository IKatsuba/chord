// A task's ending, with what it spent, after the session that started it
// was let go: by main's /clear, or by the person closing the agent it ran
// in. As the original's tests/ui/app/sessions_test.tsx `taskcost` case, it
// goes to that session's kept part, once, and never to the fresh one.
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
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake_harness.dart';
import '../../fixtures/runtimes.dart';
import 'editor_window_test.dart' show plainLaunch, settle;

/// The fake's `taskcost` task, which says it cost $0.01 and works on.
const _task = 'Count the cost';

/// Main on the fake in the window, with chord's own server and the host
/// that keeps what a closing agent spent, as the launch wires them.
Future<StartConnection> _window(WidgetTester t, Size size) async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final fold = connection.fold;
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => fold.dispatch(AgentOpened(key)),
    closed: (key, front) => fold.dispatch(SessionClosed(key, front)),
    keepClosing: (key, {from, required name, runtime}) => fold.dispatch(
      SpendClosing(key, from: from, name: name, runtime: runtime),
    ),
    keptClosed: (key) => fold.dispatch(SpendClosed(key)),
    server: server,
  );
  connection
    ..server = server
    ..window = host
    ..start();
  addTearDown(() async {
    await connection.close();
    await server.close();
    runtimes.dispose();
  });
  await t.pumpWidget(
    TranscriptWindow(launch: plainLaunch, connection: connection),
    size: size,
  );
  await _until(
    t,
    () => fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return connection;
}

Future<void> _until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 1500 && !done(); i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// The task blocks [key]'s transcript holds.
List<Subagent> _tasks(StartConnection connection, int key) => [
  for (final entry
      in connection.fold.stateOf(key)?.transcript.entries ?? const <Entry>[])
    if (entry is SubagentEntry && entry.subagent.task != null) entry.subagent,
];

/// [key]'s task has said its cost and works on, its parent's turn over.
Future<void> _working(WidgetTester t, StartConnection connection, int key) =>
    _until(t, () {
      final tasks = _tasks(connection, key);
      return connection.fold.stateOf(key)?.transcript.turn is Idle &&
          tasks.length == 1 &&
          tasks.single.state == SubagentState.running &&
          tasks.single.entries.any(
            (entry) =>
                entry is AssistantEntry &&
                entry.text.text.contains('Working until stopped.'),
          );
    });

/// `/cost`'s table, from its heading to its total, without the report's
/// margin.
Future<List<String>> _cost(WidgetTester t) async {
  await t.type('/cost');
  await t.press('enter');
  await settle(t);
  final lines = t.screen.lines;
  final head = lines.lastIndexWhere((row) => row.contains('This session'));
  expect(head, isNot(-1), reason: t.screen.text);
  final total = lines.indexWhere((row) => row.contains('Total'), head);
  expect(total, isNot(-1), reason: t.screen.text);
  final margin = lines[head].indexOf('This session');
  return [
    for (final row in lines.sublist(head, total + 1))
      row.substring(margin).trimRight(),
  ];
}

void main() {
  _testerTaskWindowFeeds();
  final skip = fakeAgentSkip;
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets("a task running as main clears ends into main's part "
          'before /clear, once, and the fresh session never hears of '
          'it', (t) async {
        final connection = await _window(t, size);
        await t.type('taskcost');
        await t.press('enter');
        await _working(t, connection, mainKey);
        await t.type('/clear');
        await t.press('enter');
        final fold = connection.fold;
        await _until(
          t,
          () =>
              fold.windowed.value.kept.isNotEmpty &&
              fold.windowed.value.closing.isEmpty &&
              fold.stateOf(mainKey)!.start.phase == StartPhase.connected,
        );
        // The fresh session: no task, no spend of the old one.
        expect(_tasks(connection, mainKey), isEmpty);
        expect(fold.stateOf(mainKey)!.spent, isNull);
        final kept = fold.windowed.value.kept.single;
        expect(kept.main, isTrue);
        expect(kept.tasks.single.task!.name, _task);
        expect(kept.tasks.single.state, SubagentState.cancelled);
        expect(kept.tasks.single.task!.spent!.cost, (
          amount: 0.01,
          currency: 'USD',
        ));
        // The task once, under main's earlier session, its $0.01 in the
        // total as the original's 0.0225.
        expect(await _cost(t), [
          'This session              Cost  Tokens',
          'main              not reported       —',
          r'before /clear          $0.0125   2,000',
          r'  Count the cost       $0.0100       —  task agent, ended',
          r'Total                  $0.0225   2,000  fake not reported',
        ]);
      }, skip: skip);

      testWidgets('a task running in an agent the person closes ends into '
          "that agent's kept part, once", (t) async {
        final connection = await _window(t, size);
        final host = connection.window! as AgentsHost;
        final person = Caller(role: Role.person, key: mainKey, window: host);
        await host.open(
          mainKey,
          const SpawnArgs(agent: 'fake', prompt: 'taskcost', name: 'parser'),
          person,
        );
        final key = connection.agents.agents.children.single.key;
        await _working(t, connection, key);
        host.close(person, 'parser');
        final fold = connection.fold;
        await _until(
          t,
          () =>
              fold.windowed.value.kept.isNotEmpty &&
              fold.windowed.value.closing.isEmpty,
        );
        final kept = fold.windowed.value.kept.single;
        expect(kept.name, 'parser');
        expect(kept.tasks.single.task!.name, _task);
        expect(kept.tasks.single.state, SubagentState.cancelled);
        expect(kept.tasks.single.task!.spent!.cost, (
          amount: 0.01,
          currency: 'USD',
        ));
        expect(await _cost(t), [
          'This session              Cost  Tokens',
          'main              not reported       —',
          r'parser                 $0.0125   2,000  agent, closed',
          r'  Count the cost       $0.0100       —  task agent, ended',
          r'Total                  $0.0225   2,000  fake not reported',
        ]);
      }, skip: skip);
    });
  }
}

void _testerTaskWindowFeeds() {
  group('CTUI-35 tester: actual task window feeds', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'two main clears keep both task bills exactly once at $size',
        (t) async {
          final connection = await _window(t, size);
          for (var round = 1; round <= 2; round++) {
            await t.type('taskcost');
            await t.press('enter');
            await _working(t, connection, mainKey);
            await t.type('/clear');
            await t.press('enter');
            await _until(
              t,
              () =>
                  connection.fold.windowed.value.kept.length == round &&
                  connection.fold.windowed.value.closing.isEmpty &&
                  connection.fold.stateOf(mainKey)!.start.phase ==
                      StartPhase.connected,
            );
          }
          final kept = connection.fold.windowed.value.kept;
          expect(kept.expand((part) => part.tasks), hasLength(2));
          expect(
            kept.expand((part) => part.tasks).map((task) => task.id).toSet(),
            hasLength(2),
          );
          expect(_tasks(connection, mainKey), isEmpty);
          final table = await _cost(t);
          expect(table.where((line) => line.contains(_task)), hasLength(2));
          expect(table.last, contains(r'$0.0450'));
          expect(table.last, contains('4,000'));
        },
        skip: fakeAgentSkip,
      );

      testWidgets(
        'a real child clear immediately followed by close keeps its old task bill once at $size',
        (t) async {
          final connection = await _window(t, size);
          final host = connection.window! as AgentsHost;
          final person = Caller(role: Role.person, key: mainKey, window: host);
          final opened =
              await host.open(
                    mainKey,
                    const SpawnArgs(
                      agent: 'fake',
                      prompt: 'taskcost',
                      name: 'parser',
                    ),
                    person,
                  )
                  as Started;
          final key = connection.agents.agents.children.single.key;
          await _working(t, connection, key);
          final clearing = host.clear(person, opened.id);
          host.close(person, opened.id);
          await clearing;
          await _until(
            t,
            () =>
                connection.agents.agents.children.isEmpty &&
                connection.fold.windowed.value.closing.isEmpty,
          );
          final table = await _cost(t);
          expect(table.where((line) => line.contains(_task)), hasLength(1));
          expect(table.last, contains(r'$0.0225'));
          expect(_tasks(connection, mainKey), isEmpty);
        },
        skip: fakeAgentSkip,
      );

      testWidgets(
        'a hidden child task supplies the real status notice and attention target at $size',
        (t) async {
          final connection = await _window(t, size);
          final host = connection.window! as AgentsHost;
          final person = Caller(role: Role.person, key: mainKey, window: host);
          await host.open(
            mainKey,
            const SpawnArgs(
              agent: 'fake',
              prompt: 'taskbetween',
              name: 'parser',
            ),
            person,
          );
          final key = connection.agents.agents.children.single.key;
          await _until(
            t,
            () =>
                connection.fold.stateOf(key)?.transcript.turn
                    is AwaitingPermission,
          );
          final notice = t.screen.lines
              .where((line) => line.contains('needs your permission'))
              .join();
          expect(
            notice,
            anyOf(
              contains('Agent(Fix the tokenizer)'),
              contains("parser's task"),
            ),
            reason: t.screen.text,
          );
          expect(connection.fold.front, mainKey);
          await t.press('ctrl+x a');
          await settle(t);
          expect(connection.fold.front, key);
          expect(t.screen, shows('Agent(Fix the tokenizer) · fake asks'));
          // The first attention key goes to parser; its between-turn box
          // then waits for parser's own attention key before taking Enter.
          if (heldBack(connection.app.value)) {
            await t.press('ctrl+x a');
            await settle(t);
          }
          await t.press('enter');
          await _until(
            t,
            () => _tasks(connection, key).single.state != SubagentState.running,
          );
          final turn = connection.fold.stateOf(key)!.transcript.turn;
          expect(
            turn is AwaitingPermission && turn.permissions.isNotEmpty,
            isFalse,
          );
        },
        skip: fakeAgentSkip,
      );
    }
  });
}
