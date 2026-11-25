// A fork in the window, as the original's sessions.ts forkTyped and
// agents_host.ts keep one (CHD-101, guide 'Forking a conversation'): a
// top-level agent beside main, of no one, from the source's conversation
// through session/fork, named as open_agent names, refused as the original
// words it; main's /clear leaves it, and its close and clear tell no one.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/server/tools.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'agents_host_test.dart' show FakeServer, until;

/// Main on the fake, which forks when [forks], with the host over it.
final class _Rig {
  _Rig({bool forks = true})
    : runtimes = TestRuntimes(
        fakes: {
          'fake': (scenario: null, flags: forks ? ['--fork'] : <String>[]),
        },
      ) {
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    host = AgentsHost(
      runtimeNames: const ['fake'],
      startupOf: (runtime) => runtime == 'fake'
          ? SessionStart(command: runtimes.commandOf('fake'))
          : null,
      openChildSession: connection.openChild,
      openForkSession: connection.openChild,
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
      server: server,
    );
    connection
      ..server = server
      ..window = host
      ..start();
  }

  final TestRuntimes runtimes;
  final server = FakeServer();
  late final StartConnection connection;
  late final AgentsHost host;

  WindowAgents get agents => connection.agents.agents;

  Future<ForkAnswer?> fork([String named = '', bool busy = false]) =>
      host.forkTyped(named, busy: (_) => busy, show: connection.agents.pick);

  /// What main was told by chord, in order.
  List<String> toldMain() => [
    for (final entry
        in connection.fold.stateOf(mainKey)?.transcript.entries ??
            const <Entry>[])
      if (entry case UserEntry(:final text, from: MessageFrom(name: 'chord')))
        text,
  ];

  Future<void> close() async {
    await connection.close();
    runtimes.dispose();
  }
}

Future<_Rig> _started({bool forks = true}) async {
  final rig = _Rig(forks: forks);
  addTearDown(rig.close);
  await until(
    () =>
        rig.connection.fold.stateOf(mainKey)?.start.phase ==
        StartPhase.connected,
  );
  return rig;
}

void main() {
  final skip = fakeAgentSkip;

  test(
    'a fork of main opens beside it, of no one, named fork then fork 2, '
    'from main\'s session, picked once up, its calls the person\'s own',
    () async {
      final rig = await _started();
      final main = rig.agents.main!;
      final first = await rig.fork() as Forked;
      expect((first.name, first.from), ('fork', main.key));
      final fork = rig.agents.children.single;
      expect(
        (fork.name, fork.forkedFrom, fork.runtime),
        ('fork', 'main', 'fake'),
      );
      expect(rig.agents.picked, fork.key);
      expect(
        fork.conversation.session?.id,
        isNot(main.conversation.session?.id),
      );
      final caller = rig.server.admitted.values.last;
      expect(
        (caller.role, caller.key, caller.fork, caller.agent),
        (Role.person, fork.key, true, null),
      );
      // Asked from main again, the next is numbered; a name of its own is
      // kept, a bad one refused in open_agent's words.
      rig.connection.agents.pick(main.key);
      expect((await rig.fork() as Forked).name, 'fork 2');
      rig.connection.agents.pick(main.key);
      expect((await rig.fork('tests') as Forked).name, 'tests');
      rig.connection.agents.pick(main.key);
      expect(
        (await rig.fork('a"b') as ForkRefused).refused,
        'An agent name must not contain the character "',
      );
      // A fork of a fork says where it parted.
      rig.connection.agents.pick(fork.key);
      final again = await rig.fork() as Forked;
      expect(again.from, fork.key);
      expect(rig.agents.children.last.forkedFrom, 'fork');
      expect(rig.toldMain(), isEmpty);
    },
    skip: skip,
  );

  test('it is refused while its source works, and by an agent that does not '
      'fork', () async {
    final rig = await _started();
    expect(
      (await rig.fork('', true) as ForkRefused).refused,
      'main is working · /fork once its turn ends',
    );
    final plain = await _started(forks: false);
    expect(
      (await plain.fork() as ForkRefused).refused,
      'This agent does not fork sessions',
    );
    expect(rig.agents.children, isEmpty);
    expect(plain.agents.children, isEmpty);
  }, skip: skip);

  test("an ordinary child picked is refused; main's /clear leaves forks, and "
      "a fork's clear and close tell no one", () async {
    final rig = await _started();
    final main = rig.agents.main!;
    final person = Caller(role: Role.person, key: main.key, window: rig.host);
    final opened =
        await rig.host.open(
              main.key,
              const SpawnArgs(agent: 'fake', prompt: 'go', name: 'parser'),
              person,
            )
            as Started;
    final child = rig.agents.children.singleWhere((c) => c.id == opened.id);
    rig.connection.agents.pick(child.key);
    expect(
      (await rig.fork() as ForkRefused).refused,
      '/fork forks main or a fork',
    );
    rig.connection.agents.pick(main.key);
    await rig.fork();
    final fork = rig.agents.children.singleWhere((c) => c.forkedFrom != null);
    // Forks come after main's own children in the list.
    expect([for (final c in rig.agents.children) c.name], ['parser', 'fork']);
    final told = rig.toldMain().length;

    final before = fork.conversation.session?.id;
    expect(await rig.host.clearByPerson(fork.key), isNull);
    await until(() => fork.conversation.session?.id != before);
    rig.host.closeMainChildren();
    expect([for (final c in rig.agents.children) c.name], ['fork']);
    rig.host.closeByPerson(fork.key);
    expect(rig.agents.children, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Only parser's close by /clear was main's to hear of, if anything.
    expect(
      rig.toldMain().skip(told).where((text) => text.contains('fork')),
      isEmpty,
    );
  }, skip: skip);

  test("from a fork: list_sessions names it a session of its own, its "
      "monitors and tasks are its own, and main and it cannot message one "
      'another', () async {
    final rig = await _started();
    final main = rig.agents.main!;
    await rig.fork();
    final fork = rig.agents.children.single;
    final caller = rig.server.admitted.values.last;
    expect(caller.fork, isTrue);

    final sessions = rig.host.sessions();
    expect(
      [for (final s in sessions) (s.key, s.children.length)],
      [(main.key, 0), (fork.key, 0)],
    );
    expect(sessions.last.id, fork.conversation.session?.id);

    // Its monitor is its own, not main's.
    final started = await rig.host.monitor(caller, (
      command: 'sleep 30',
      description: 'waits',
      timeoutMs: null,
    ));
    expect(started, isA<StartedMonitor>());
    expect(fork.conversation.monitors, hasLength(1));
    expect(main.conversation.monitors, isEmpty);

    // A task of its own starts under it.
    final task = await rig.host.spawn(
      caller,
      const SpawnArgs(agent: 'fake', prompt: 'look', name: 'look'),
    );
    expect(task, isA<Started>());
    expect(fork.conversation.task((task as Started).id), isNotNull);

    // Neither reaches the other by name.
    final toMain = rig.host.tell(caller, 'main', 'hi', () {});
    expect(toMain, isA<Refused>());
    final person = Caller(role: Role.person, key: main.key, window: rig.host);
    expect(rig.host.tell(person, fork.name, 'hi', () {}), isA<Refused>());
  }, skip: skip);
  group('CTUI-74 tester: fork startup races', () {
    test(
      'a source cleared while fork starts gets no stale pick or answer',
      () async {
        final gate = Completer<void>();
        final rig = await _testerGatedFork(gate);
        final old = rig.connection.conversation.session!.id;
        final shown = <int>[];
        final pending = rig.host.forkTyped(
          '',
          busy: (_) => false,
          show: shown.add,
        );
        await until(() => rig.connection.agents.agents.children.isNotEmpty);
        await rig.connection.conversation.clear();
        await until(
          () =>
              rig.connection.conversation.session?.id != old &&
              rig.connection.conversation.session != null,
        );
        gate.complete();
        expect(await pending, isNull);
        expect(shown, isEmpty);
        final fork = rig.connection.agents.agents.children.single;
        expect(fork.forkedFrom, 'main');
        expect(fork.conversation.session, isNotNull);
      },
      skip: skip,
    );

    test(
      'a fork closed while starting never picks a late replacement',
      () async {
        final gate = Completer<void>();
        final rig = await _testerGatedFork(gate);
        final shown = <int>[];
        final pending = rig.host.forkTyped(
          '',
          busy: (_) => false,
          show: shown.add,
        );
        await until(() => rig.connection.agents.agents.children.isNotEmpty);
        final key = rig.connection.agents.agents.children.single.key;
        rig.host.closeByPerson(key);
        gate.complete();
        final result = await pending;
        expect(result, isA<ForkRefused>());
        expect(shown, isEmpty);
        expect(rig.connection.agents.agents.children, isEmpty);
        expect(rig.connection.conversation.session, isNotNull);
      },
      skip: skip,
    );
  });
}

/// Main on the fake with only fork startup held at the test's gate.
Future<({StartConnection connection, AgentsHost host})> _testerGatedFork(
  Completer<void> gate,
) async {
  final runtimes = TestRuntimes(
    fakes: {
      'fake': (scenario: null, flags: ['--fork']),
    },
  );
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (_) => SessionStart(command: runtimes.commandOf('fake')),
    openChildSession: connection.openChild,
    openForkSession:
        (
          runtime,
          start, {
          required initial,
          chordServer,
          required onTraffic,
          required cancellationToken,
          required fork,
        }) async {
          await gate.future;
          return connection.openChild(
            runtime,
            start,
            initial: initial,
            chordServer: chordServer,
            onTraffic: onTraffic,
            cancellationToken: cancellationToken,
            fork: fork,
          );
        },
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
    server: FakeServer(),
  );
  connection.window = host;
  addTearDown(() async {
    if (!gate.isCompleted) gate.complete();
    await connection.close();
    runtimes.dispose();
  });
  connection.start();
  await until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return (connection: connection, host: host);
}
