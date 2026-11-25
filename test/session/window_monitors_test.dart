import 'dart:async';

import 'package:chord/server/tools.dart';
import 'package:chord/session/monitors.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/session/window_monitors.dart';
import 'package:test/test.dart';

import '../server/fake_window.dart';

/// A conversation's monitors as the test keeps them: started, and stopped.
final class _Keeper implements MonitorsKeeper {
  _Keeper(this.name);

  final String name;
  final cwds = <String>[];

  /// While set, a start waits on it, counted as starting.
  Completer<void>? gate;
  var _starting = 0;

  @override
  var monitors = <RunningMonitor>[];

  @override
  int get monitorsHeld => monitors.length + _starting;

  @override
  Future<MonitorAnswer> startMonitor(MonitorArgs args, String cwd) async {
    if (gate case final gate?) {
      _starting += 1;
      await gate.future;
      _starting -= 1;
    }
    final id = 'm${monitors.length + 1}';
    cwds.add(cwd);
    monitors = [
      ...monitors,
      RunningMonitor(
        MonitorInfo(
          id: id,
          description: args.description,
          command: args.command,
          startedAt: 0,
          timeoutMs: 600000,
        ),
      ),
    ];
    return StartedMonitor(id, args.description, 600000);
  }

  @override
  StopMonitorAnswer stopMonitor(String id) {
    final at = monitors.indexWhere((each) => each.info.id == id);
    if (at < 0) return Refused('No running monitor $id of yours');
    final monitor = monitors[at];
    monitors = [...monitors]..removeAt(at);
    return StoppedMonitor(id, monitor.info.description, 0, 0);
  }
}

const MonitorArgs _args = (
  command: 'tail -f log',
  description: 'log',
  timeoutMs: null,
);

final _window = FakeWindow();

Caller _caller(int key, {String? agent, String? task}) => Caller(
  role: agent == null && task == null ? Role.person : Role.child,
  key: key,
  window: _window,
  agent: agent,
  task: task,
);

/// Main with children a1 and a2.
({
  WindowAgents<_Keeper> agents,
  int first,
  _Keeper parent,
  _Keeper one,
  _Keeper two,
})
_opened() {
  final parent = _Keeper('parent'), one = _Keeper('one'), two = _Keeper('two');
  var agents = openMain(noAgents<_Keeper>(), 'fake', parent);
  final first = agents.main!.key;
  for (final (id, keeper) in [('a1', one), ('a2', two)]) {
    agents = openChild(
      agents,
      ChildInfo(id: id, name: keeper.name, runtime: 'fake', openedAt: 0),
      keeper,
    )!.agents;
  }
  return (agents: agents, first: first, parent: parent, one: one, two: two);
}

Map<String, Object?> _json(Answer answer) => answer.toJson();

void main() {
  test('main and its children share the eight', () async {
    final (:agents, :first, :parent, :one, :two) = _opened();
    Future<MonitorAnswer> start(Caller caller) =>
        startMonitorIn(agents, caller, _args, '/work');
    for (var i = 0; i < 3; i++) {
      await start(_caller(first));
      await start(_caller(first, agent: 'a1'));
    }
    await start(_caller(first, agent: 'a2'));
    await start(_caller(first, agent: 'a2'));
    expect(
      [
        for (final keeper in [parent, one, two]) keeper.monitors.length,
      ],
      [3, 3, 2],
    );

    const refused = {
      'error': 'This session has 8 monitors running; stop_monitor one first',
    };
    expect(_json(await start(_caller(first))), refused);
    expect(_json(await start(_caller(first, agent: 'a1'))), refused);
    expect(_json(await start(_caller(first, agent: 'a2'))), refused);
    expect(two.monitors.length, 2);

    // One stopped makes room again, for any of the window's agents.
    stopMonitorIn(agents, _caller(first, agent: 'a1'), 'm1');
    expect(await start(_caller(first, agent: 'a2')), isA<StartedMonitor>());
    expect(parent.cwds, ['/work', '/work', '/work']);
  });

  test('a caller lists and stops only its own monitors; a task has '
      'none', () async {
    final (:agents, :first, :parent, :one, two: _) = _opened();
    await startMonitorIn(agents, _caller(first), (
      command: 'tail -f log',
      description: 'mine',
      timeoutMs: null,
    ), '/w');
    await startMonitorIn(agents, _caller(first, agent: 'a1'), (
      command: 'tail -f log',
      description: 'theirs',
      timeoutMs: null,
    ), '/w');
    List<String> listed(Caller caller) => [
      for (final monitor in monitorsIn(agents, caller))
        monitor.info.description,
    ];
    expect(listed(_caller(first)), ['mine']);
    expect(listed(_caller(first, agent: 'a1')), ['theirs']);
    expect(listed(_caller(first, agent: 'a2')), isEmpty);
    expect(listed(_caller(first, task: 't1')), isEmpty);

    // Both are m1, each in its own conversation: a2 reaches neither.
    expect(_json(stopMonitorIn(agents, _caller(first, agent: 'a2'), 'm1')), {
      'error': 'No running monitor m1 of yours',
    });
    expect(_json(stopMonitorIn(agents, _caller(first, agent: 'a1'), 'm1')), {
      'id': 'm1',
      'description': 'theirs',
      'events': 0,
      'ran_ms': 0,
    });
    expect(listed(_caller(first)), ['mine']);
    expect(parent.monitors.length, 1);
    expect(one.monitors.length, 0);

    const closed = {'error': 'This session has closed'};
    expect(
      _json(
        await startMonitorIn(agents, _caller(first, task: 't1'), _args, '/w'),
      ),
      closed,
    );
    expect(
      _json(stopMonitorIn(agents, _caller(first, task: 't1'), 'm1')),
      closed,
    );
    expect(
      _json(
        await startMonitorIn(agents, _caller(first, agent: 'a9'), _args, '/w'),
      ),
      closed,
    );
    expect(
      _json(await startMonitorIn(agents, _caller(99), _args, '/w')),
      closed,
    );
  });

  test('monitors still starting count against the eight, across the '
      "window's agents", () async {
    final (:agents, :first, :parent, :one, :two) = _opened();
    final gate = Completer<void>();
    for (final keeper in [parent, one, two]) {
      keeper.gate = gate;
    }
    final callers = [
      for (var i = 0; i < 3; i++) ...[
        _caller(first),
        _caller(first, agent: 'a1'),
        _caller(first, agent: 'a2'),
      ],
    ];
    final answers = [
      for (final caller in callers) startMonitorIn(agents, caller, _args, '/w'),
    ];
    gate.complete();
    final settled = await Future.wait(answers);
    expect(settled.whereType<StartedMonitor>(), hasLength(8));
    expect(_json(settled.last), {
      'error': 'This session has 8 monitors running; stop_monitor one first',
    });
  });

  group('CTUI-74 tester: fork monitor ownership', () {
    test(
      'fork key owns its m1; tasks have none and the window cap includes forks',
      () async {
        final opened = _opened();
        final keeper = _Keeper('fork');
        final fork = openChild(
          opened.agents,
          const ChildInfo(
            id: 'f1',
            name: 'fork',
            runtime: 'fake',
            openedAt: 0,
            forkedFrom: 'main',
          ),
          keeper,
        )!;
        final agents = fork.agents;
        final forkKey = agents.children.last.key;
        final caller = Caller(
          role: Role.person,
          key: forkKey,
          window: _window,
          fork: true,
        );
        await startMonitorIn(agents, _caller(opened.first), _args, '/w');
        await startMonitorIn(agents, caller, _args, '/fork');
        expect(monitorsIn(agents, caller).single.info.id, 'm1');
        stopMonitorIn(agents, caller, 'm1');
        expect(keeper.monitors, isEmpty);
        expect(opened.parent.monitors, hasLength(1));
        final task = Caller(
          role: Role.child,
          key: forkKey,
          window: _window,
          fork: true,
          task: 'task',
        );
        expect(monitorsIn(agents, task), isEmpty);
        expect((await startMonitorIn(agents, task, _args, '/fork')).toJson(), {
          'error': 'This session has closed',
        });
        for (var i = 0; i < 7; i++) {
          await startMonitorIn(agents, caller, _args, '/fork');
        }
        expect(
          (await startMonitorIn(
            agents,
            _caller(opened.first),
            _args,
            '/w',
          )).toJson(),
          {
            'error':
                'This session has 8 monitors running; stop_monitor one first',
          },
        );
      },
    );
  });
}
