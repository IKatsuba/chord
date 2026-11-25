// The host opening long-lived children on the original's fake agent, through
// the test runtime catalog: admission per launch, the messages sent while a
// child starts going in order once it is up, chord's note to main of a child
// that did not start, and the refusals before anything starts.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart' hide Cleared;
import 'package:chord/server/tools.dart' as tools show Cleared;
import 'package:chord/session/tasks.dart' show wrapMessage;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/agents_host.dart';
import 'package:chord/session/conversation.dart' show Conversation, Starting;
import 'package:chord/session/session.dart' show Session;
import 'package:chord/session/window_agents.dart' show ChildInfo;
import 'package:chord/session/place.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/starting.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import '../fixtures/runtimes.dart';
import 'conversation_fake.dart' show ScriptedSession;
import 'settings_test.dart' show select, value;

/// chord's server as the host uses it, keeping who was let in and let go.
final class FakeServer implements ChordServer {
  final admitted = <String, Caller>{};
  final revoked = <String>[];
  var _tokens = 0;

  @override
  String get url => 'http://127.0.0.1:9/mcp';

  @override
  Admitted admit(Caller caller) {
    final token = 'token-${++_tokens}';
    admitted[token] = caller;
    return (
      token: token,
      server: {
        'type': 'http',
        'name': 'chord',
        'url': url,
        'headers': [
          {'name': 'Authorization', 'value': 'Bearer $token'},
        ],
      },
    );
  }

  @override
  void revoke(String token) => revoked.add(token);

  @override
  Future<void> close() async {}
}

/// Main on the fake, with the host over it.
final class Rig {
  Rig() {
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    host = AgentsHost(
      runtimeNames: const ['fake', 'codex'],
      startupOf: (runtime) => switch (runtime) {
        'fake' => SessionStart(command: runtimes.commandOf('fake')),
        // A real runtime's own command, which the catalog never starts.
        'codex' => const SessionStart(command: ['npx', 'codex-acp']),
        _ => null,
      },
      openChildSession: connection.openChild,
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

  final runtimes = TestRuntimes();
  final server = FakeServer();
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  AppState? stateOf(int key) => connection.fold.stateOf(key);

  List<UserEntry> prompts(int key) => [
    ...?stateOf(key)?.transcript.entries.whereType<UserEntry>(),
  ];

  Future<void> close() async {
    await connection.close();
    runtimes.dispose();
  }
}

/// Waits, up to 20 s, for [done].
Future<void> until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('until');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<Rig> started() async {
  final rig = Rig();
  addTearDown(rig.close);
  await until(() => rig.stateOf(mainKey)?.start.phase == StartPhase.connected);
  return rig;
}

void main() {
  wireTests();
  testerHostStartupTests();
  clearTests();
  closeNoteModelTests();
  closeTests();
  testerHostCloseTests();
  requiredModelTests();
  effortTests();
  endedTests();
  final skip = fakeAgentSkip;

  test('a child opens on the fake, admitted for its launch, its first turn '
      "main's message", () async {
    final rig = await started();
    final answer =
        await rig.host.open(
              mainKey,
              const SpawnArgs(
                agent: 'fake',
                prompt: 'Read the parser.',
                name: 'parser',
              ),
              rig.person,
            )
            as Started;
    expect(answer.id, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect((answer.name, answer.agent), ('parser', 'fake'));
    final child = rig.connection.agents.agents.children.single;
    expect(child.id, answer.id);
    await until(() => rig.prompts(child.key).isNotEmpty);
    final first = rig.prompts(child.key).single;
    expect(first.text, 'Read the parser.');
    expect(first.from, fromMain);
    final caller = rig.server.admitted.values.firstWhere(
      (each) => each.role == Role.child,
    );
    expect((caller.key, caller.agent), (mainKey, answer.id));
    expect(caller.launch?.call(), isTrue);
    // Its launch let go, its token is revoked and its calls are stale.
    await rig.connection.agents.closeChild(child.key);
    final token = rig.server.admitted.entries
        .firstWhere((e) => e.value.role == Role.child)
        .key;
    await until(() => rig.server.revoked.contains(token));
    expect(caller.launch?.call(), isFalse);
  }, skip: skip);

  test(
    'messages sent while a child starts go once it is up, in order',
    () async {
      final rig = await started();
      await rig.host.open(
        mainKey,
        const SpawnArgs(agent: 'fake', prompt: 'first', name: 'parser'),
        rig.person,
      );
      final told = rig.host.tell(rig.person, 'parser', 'second', () {});
      expect(told.toJson(), {'delivered': 'queued', 'to': 'parser'});
      final child = rig.connection.agents.agents.children.single;
      await until(() => rig.prompts(child.key).length == 2);
      expect(
        [for (final p in rig.prompts(child.key)) p.text],
        ['first', 'second'],
      );
    },
    skip: skip,
  );

  test("a child that does not start is said to main, from chord, as a turn "
      'of its own', () async {
    final rig = await started();
    await rig.host.open(
      mainKey,
      const SpawnArgs(agent: 'codex', prompt: 'hello'),
      rig.person,
    );
    await until(() => rig.prompts(mainKey).any((p) => p.from?.name == 'chord'));
    final note = rig
        .prompts(mainKey)
        .firstWhere((p) => p.from?.name == 'chord');
    expect(note.text, startsWith('codex (codex) did not start: '));
    expect(
      note.text,
      endsWith(' It takes no messages; open_agent starts another.'),
    );
    // Its launch never opened: its token went with it.
    final token = rig.server.admitted.entries
        .firstWhere((e) => e.value.role == Role.child)
        .key;
    expect(rig.server.revoked, contains(token));
  }, skip: skip);

  test('refusals before anything starts', () async {
    final rig = await started();
    Future<String> refusal(SpawnArgs args) async =>
        (await rig.host.open(mainKey, args, rig.person) as Refused).error;
    expect(
      await refusal(const SpawnArgs(agent: 'gemini', prompt: 'x')),
      'No agent named gemini; chord knows fake, codex',
    );
    expect(
      await refusal(const SpawnArgs(agent: 'fake', prompt: 'x', name: 'a"b')),
      'An agent name must not contain the character "',
    );
    expect(rig.connection.agents.agents.children, isEmpty);
    final stale = Caller(
      role: Role.person,
      key: mainKey,
      window: rig.host,
      launch: () => false,
    );
    expect(
      (await rig.host.open(
                mainKey,
                const SpawnArgs(agent: 'fake', prompt: 'x'),
                stale,
              )
              as Refused)
          .error,
      'Your session was cleared or closed; nothing more goes from it',
    );
  }, skip: skip);

  test("main is admitted to chord's server for its launch", () async {
    final rig = await started();
    final main = rig.server.admitted.values.firstWhere(
      (each) => each.role == Role.person,
    );
    expect(main.key, mainKey);
    expect(main.launch?.call(), isTrue);
  }, skip: skip);
}

void wireTests() {
  test("the fake's agentsquiet opens parser and docs through chord's own "
      'server over HTTP', () async {
    final server = await serveChord();
    final runtimes = TestRuntimes();
    final connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    final host = AgentsHost(
      runtimeNames: const ['fake'],
      startupOf: (runtime) => runtime == 'fake'
          ? SessionStart(command: runtimes.commandOf('fake'))
          : null,
      openChildSession: connection.openChild,
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
    addTearDown(() async {
      await connection.close();
      await server.close();
      runtimes.dispose();
    });
    await until(
      () =>
          connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
    );
    expect(connection.conversation.send('agentsquiet'), isTrue);
    await until(
      () =>
          connection.agents.agents.children.length == 2 &&
          connection.agents.agents.children.every(
            (child) =>
                (connection.fold
                            .stateOf(child.key)
                            ?.transcript
                            .entries
                            .whereType<UserEntry>() ??
                        const <UserEntry>[])
                    .isNotEmpty,
          ),
    );
    expect(
      [for (final child in connection.agents.agents.children) child.name],
      ['parser', 'docs'],
    );
  }, skip: fakeAgentSkip);
}

/// Main on the fake with the host over it and chord's own server, as the
/// window has them.
Future<StartConnection> served() async {
  final server = await serveChord();
  final runtimes = TestRuntimes();
  final connection = StartConnection(
    command: runtimes.commandOf('fake'),
    env: runtimes.env,
    cwd: runtimes.home.path,
    agent: 'fake',
    open: runtimes.opener,
  );
  final host = AgentsHost(
    runtimeNames: const ['fake'],
    startupOf: (runtime) => runtime == 'fake'
        ? SessionStart(command: runtimes.commandOf('fake'))
        : null,
    openChildSession: connection.openChild,
    agents: connection.agents,
    opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    closed: (key, front) => connection.fold.dispatch(SessionClosed(key, front)),
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
  await until(
    () => connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
  );
  return connection;
}

/// What chord told main, as turns of its own.
List<String> chordSaid(StartConnection connection) => [
  for (final entry
      in connection.fold
              .stateOf(mainKey)
              ?.transcript
              .entries
              .whereType<UserEntry>() ??
          const <UserEntry>[])
    if (entry.from?.name == 'chord') entry.text,
];

void endedTests() {
  test("a child whose agent exits tells main, from chord, with its last "
      'words and how to open it again', () async {
    final connection = await served();
    connection.conversation.send('agentexit');
    await until(() => chordSaid(connection).isNotEmpty);
    final said = chordSaid(connection).single;
    expect(said, startsWith("parser's agent exited"));
    expect(said, endsWith('. open_agent opens it again.'));
  }, skip: fakeAgentSkip);

  test('a child whose turn fails with its agent up tells main it is still '
      'open', () async {
    final connection = await served();
    connection.conversation.send('agentfail');
    await until(() => chordSaid(connection).isNotEmpty);
    final said = chordSaid(connection).single;
    expect(said, startsWith("parser's turn failed: "));
    expect(said, endsWith('. It is still open; send_message reaches it.'));
    // It stays open and idle.
    expect(
      [for (final child in connection.agents.agents.children) child.name],
      ['parser'],
    );
  }, skip: fakeAgentSkip);
}

void effortTests() {
  test('an open asking an effort the child refuses says the effort it is on '
      'and the refusal', () async {
    final runtimes = TestRuntimes();
    final connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
    final child = ScriptedSession()
      ..state = AgentState(
        configOptions: [
          select('effort', 'thought_level', [
            value('low'),
            value('high'),
          ], current: 'low'),
        ],
      )
      ..change = (kind, id, value) => Future.error(StateError('not today'));
    final host = AgentsHost(
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
          }) async => child,
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
    );
    connection.start();
    addTearDown(() async {
      await connection.close();
      runtimes.dispose();
    });
    await until(
      () =>
          connection.fold.stateOf(mainKey)?.start.phase == StartPhase.connected,
    );
    final answer =
        await host.open(
              mainKey,
              const SpawnArgs(agent: 'scripted', prompt: 'x', effort: 'high'),
              Caller(role: Role.person, key: mainKey, window: host),
            )
            as Started;
    expect(answer.effort, 'low');
    expect(answer.note, startsWith('Could not start on high effort'));
    expect(answer.note, contains('not today'));
  }, skip: fakeAgentSkip);
}

void requiredModelTests() {
  for (final how in ['refuses it', 'stays on another']) {
    test(
      'a child whose agent ${how == 'refuses it' ? 'refuses the model asked '
                'for' : 'stays on another model'} does not start: no job, its '
      'session closed, its token revoked, main told',
      () async {
        final runtimes = TestRuntimes();
        final server = FakeServer();
        final connection = StartConnection(
          command: runtimes.commandOf('fake'),
          env: runtimes.env,
          cwd: runtimes.home.path,
          agent: 'fake',
          open: runtimes.opener,
        );
        final child = ScriptedSession()
          ..state = AgentState(
            configOptions: [
              select('model', 'model', [
                value('small'),
                value('large'),
              ], current: 'small'),
            ],
          )
          ..change = (kind, id, value) => how == 'refuses it'
              ? Future.error(StateError('no large today'))
              : Future.value();
        final host = AgentsHost(
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
              }) async => child,
          agents: connection.agents,
          opened: (key) => connection.fold.dispatch(AgentOpened(key)),
          server: server,
        );
        connection
          ..server = server
          ..window = host
          ..start();
        addTearDown(() async {
          await connection.close();
          runtimes.dispose();
        });
        await until(
          () =>
              connection.fold.stateOf(mainKey)?.start.phase ==
              StartPhase.connected,
        );
        await host.open(
          mainKey,
          const SpawnArgs(agent: 'scripted', prompt: 'job', model: 'large'),
          Caller(role: Role.person, key: mainKey, window: host),
        );
        await until(
          () =>
              (connection.fold
                          .stateOf(mainKey)
                          ?.transcript
                          .entries
                          .whereType<UserEntry>() ??
                      const <UserEntry>[])
                  .any((entry) => entry.from?.name == 'chord'),
        );
        final note = connection.fold
            .stateOf(mainKey)!
            .transcript
            .entries
            .whereType<UserEntry>()
            .firstWhere((entry) => entry.from?.name == 'chord');
        expect(note.text, startsWith('scripted (scripted) did not start: '));
        expect(note.text, contains('large'));
        expect(child.turns, isEmpty);
        expect(child.closes, greaterThan(0));
        final token = server.admitted.entries
            .firstWhere((e) => e.value.role == Role.child)
            .key;
        expect(server.revoked, contains(token));
        final childKey = connection.agents.agents.children.single.key;
        expect(
          connection.fold.stateOf(childKey)!.start.phase,
          StartPhase.failed,
        );
      },
      skip: fakeAgentSkip,
    );
  }
}

void closeTests() {
  test("main's own close_agent closes the child, its token revoked, and "
      'tells main nothing', () async {
    final rig = await started();
    await rig.host.open(
      mainKey,
      const SpawnArgs(agent: 'fake', prompt: 'work', name: 'parser'),
      rig.person,
    );
    final child = rig.connection.agents.agents.children.single;
    await until(() => rig.prompts(child.key).isNotEmpty);
    final answer = rig.host.close(rig.person, 'parser');
    expect(answer.toJson(), {'closed': 'parser'});
    expect(rig.connection.agents.agents.children, isEmpty);
    expect(rig.stateOf(child.key), isNull);
    final token = rig.server.admitted.entries
        .firstWhere((e) => e.value.role == Role.child)
        .key;
    await until(() => rig.server.revoked.contains(token));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(rig.prompts(mainKey).where((p) => p.from?.name == 'chord'), isEmpty);
    // Closed, it is said to be closed.
    expect(
      (rig.host.close(rig.person, 'parser') as Refused).error,
      'parser is closed; open_agent starts another',
    );
    expect(
      (rig.host.tell(rig.person, 'parser', 'x', () {}) as Refused).error,
      'parser is closed; open_agent starts another',
    );
  }, skip: fakeAgentSkip);

  test(
    "the person's close tells main the child takes no more messages",
    () async {
      final rig = await started();
      final opened =
          await rig.host.open(
                mainKey,
                const SpawnArgs(agent: 'fake', prompt: 'work', name: 'parser'),
                rig.person,
              )
              as Started;
      final child = rig.connection.agents.agents.children.single;
      await until(() => rig.prompts(child.key).isNotEmpty);
      rig.host.closeByPerson(child.key);
      await until(
        () => rig.prompts(mainKey).any((p) => p.from?.name == 'chord'),
      );
      final said = rig
          .prompts(mainKey)
          .firstWhere((p) => p.from?.name == 'chord');
      expect(said.text, startsWith('The person closed parser (fake'));
      expect(
        said.text,
        endsWith(
          ', id ${opened.id}). It takes no more messages; open_agent '
          'starts another.',
        ),
      );
    },
    skip: fakeAgentSkip,
  );

  test('a ninth child is refused before anything starts', () async {
    final rig = await started();
    for (var n = 0; n < 8; n++) {
      rig.connection.agents.openChild(
        ChildInfo(id: 'c$n', name: 'c$n', runtime: 'fake', openedAt: 0),
        (emit, key) => Conversation(
          ({required onTraffic, required cancellationToken}) =>
              Completer<Session>().future,
        )..listen(emit),
      );
    }
    final admitted = rig.server.admitted.length;
    final answer = await rig.host.open(
      mainKey,
      const SpawnArgs(agent: 'fake', prompt: 'x', name: 'ninth'),
      rig.person,
    );
    expect(
      (answer as Refused).error,
      'This session has 8 agents open; close_agent one first',
    );
    expect(rig.connection.agents.agents.children, hasLength(8));
    expect(rig.server.admitted.length, admitted);
  }, skip: fakeAgentSkip);

  test("a long-lived child's close_agent stops only its own tasks", () async {
    final rig = await started();
    final child = Caller(
      role: Role.child,
      key: mainKey,
      agent: 'a1',
      window: rig.host,
    );
    expect(
      (rig.host.close(child, 'docs') as Refused).error,
      "No task docs of yours; spawn_task's answer names them",
    );
  }, skip: fakeAgentSkip);
}

AgentState offering(String current) => AgentState(
  configOptions: [
    select('model', 'model', [
      value('small'),
      value('large'),
    ], current: current),
  ],
);

void closeNoteModelTests() {
  for (final changed in [false, true]) {
    test(
      "the person's close names the model the child is on: "
      '${changed ? 'one it changed to' : 'its default, none asked'}',
      () async {
        final runtimes = TestRuntimes();
        final connection = StartConnection(
          command: runtimes.commandOf('fake'),
          env: runtimes.env,
          cwd: runtimes.home.path,
          agent: 'fake',
          open: runtimes.opener,
        );
        final child = ScriptedSession()..state = offering('small');
        final host = AgentsHost(
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
              }) async => child,
          agents: connection.agents,
          opened: (key) => connection.fold.dispatch(AgentOpened(key)),
          closed: (key, front) =>
              connection.fold.dispatch(SessionClosed(key, front)),
        );
        connection.start();
        addTearDown(() async {
          await connection.close();
          runtimes.dispose();
        });
        await until(
          () =>
              connection.fold.stateOf(mainKey)?.start.phase ==
              StartPhase.connected,
        );
        final opened =
            await host.open(
                  mainKey,
                  const SpawnArgs(
                    agent: 'scripted',
                    prompt: 'x',
                    name: 'parser',
                  ),
                  Caller(role: Role.person, key: mainKey, window: host),
                )
                as Started;
        final key = connection.agents.agents.children.single.key;
        await until(
          () => connection.agents.conversationOf(key)?.session != null,
        );
        if (changed) child.state = offering('large');
        host.closeByPerson(key);
        await until(
          () =>
              (connection.fold
                          .stateOf(mainKey)
                          ?.transcript
                          .entries
                          .whereType<UserEntry>() ??
                      const <UserEntry>[])
                  .any((entry) => entry.from?.name == 'chord'),
        );
        final note = connection.fold
            .stateOf(mainKey)!
            .transcript
            .entries
            .whereType<UserEntry>()
            .firstWhere((entry) => entry.from?.name == 'chord');
        expect(
          note.text,
          'The person closed parser (scripted · ${changed ? 'large' : 'small'}, '
          'id ${opened.id}). It takes no more messages; open_agent starts '
          'another.',
        );
      },
      skip: fakeAgentSkip,
    );
  }
}

/// Main on the fake, with children on scripted sessions handed out in turn:
/// each open, a first start's or a clear's, takes the next completer.
final class ScriptedRig {
  ScriptedRig() {
    connection = StartConnection(
      command: runtimes.commandOf('fake'),
      env: runtimes.env,
      cwd: runtimes.home.path,
      agent: 'fake',
      open: runtimes.opener,
    );
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
            final next = Completer<Session>();
            opens.add(next);
            return next.future;
          },
      agents: connection.agents,
      opened: (key) => connection.fold.dispatch(AgentOpened(key)),
      closed: (key, front) =>
          connection.fold.dispatch(SessionClosed(key, front)),
    );
    connection.start();
  }

  final runtimes = TestRuntimes();
  final opens = <Completer<Session>>[];
  late final StartConnection connection;
  late final AgentsHost host;

  Caller get person => Caller(role: Role.person, key: mainKey, window: host);

  int get child => connection.agents.agents.children.single.key;

  Future<void> close() async {
    await connection.close();
    runtimes.dispose();
  }
}

Future<ScriptedRig> scripted() async {
  final rig = ScriptedRig();
  addTearDown(rig.close);
  await until(
    () =>
        rig.connection.fold.stateOf(mainKey)?.start.phase ==
        StartPhase.connected,
  );
  return rig;
}

/// Opens `parser` on a scripted session that takes its first job.
Future<ScriptedSession> parser(ScriptedRig rig) async {
  final first = ScriptedSession();
  rig.host
      .open(
        mainKey,
        const SpawnArgs(agent: 'scripted', prompt: 'job', name: 'parser'),
        rig.person,
      )
      .ignore();
  await until(() => rig.opens.isNotEmpty);
  rig.opens.last.complete(first);
  await until(() => first.turns.isNotEmpty);
  return first;
}

void clearTests() {
  test('clear_agent answers once the fresh session is up, and what was sent '
      'meanwhile is its first turn', () async {
    final rig = await scripted();
    final old = await parser(rig);
    old.turns.single.answer();
    final clearing = rig.host.clear(rig.person, 'parser');
    await until(() => rig.opens.length == 2);
    expect(
      rig.host.tell(rig.person, 'parser', 'after the clear', () {}).toJson(),
      {'delivered': 'queued', 'to': 'parser'},
    );
    final fresh = ScriptedSession();
    rig.opens.last.complete(fresh);
    final answer = await clearing as tools.Cleared;
    expect((answer.cleared, answer.dropped), ('parser', null));
    expect(answer.id, rig.connection.agents.agents.children.single.id);
    await until(() => fresh.turns.isNotEmpty);
    expect(fresh.turns.single.text, wrapMessage(fromMain, 'after the clear'));
  }, skip: fakeAgentSkip);

  test("a clear gives the person's queued prompts back to the agent's own "
      "draft, and counts another's messages as not delivered", () async {
    final rig = await scripted();
    await parser(rig);
    final conversation = rig.connection.agents.conversationOf(rig.child)!;
    // Behind the running first job: the person's prompt and main's message.
    conversation.send('mine');
    conversation.deliver(fromMain, 'theirs');
    final clearing = rig.host.clear(rig.person, 'parser');
    await until(() => rig.opens.length == 2);
    rig.opens.last.complete(ScriptedSession());
    final answer = await clearing as tools.Cleared;
    expect(answer.dropped, '1 queued message from main was not delivered.');
    expect(rig.connection.fold.stateOf(rig.child)!.draft, contains('mine'));
    expect(
      rig.connection.fold.stateOf(rig.child)!.draft,
      isNot(contains('theirs')),
    );
  }, skip: fakeAgentSkip);

  test('a second clear while one runs is refused, and a close while '
      'clearing settles it', () async {
    final rig = await scripted();
    await parser(rig);
    final first = rig.host.clear(rig.person, 'parser');
    await until(() => rig.opens.length == 2);
    expect(
      ((await rig.host.clear(rig.person, 'parser')) as Refused).error,
      'Could not clear parser: it is being cleared already',
    );
    rig.host.tell(rig.person, 'parser', 'lost', () {});
    rig.host.close(rig.person, 'parser');
    expect(
      ((await first) as Refused).error,
      'Could not clear parser: it was closed. 1 queued message from main '
      'was not delivered.',
    );
  }, skip: fakeAgentSkip);

  test("the person's clear tells main the child is fresh; clear_agent's does "
      'not', () async {
    final rig = await scripted();
    await parser(rig);
    final clearing = rig.host.clearByPerson(rig.child);
    await until(() => rig.opens.length == 2);
    rig.opens.last.complete(ScriptedSession());
    expect(await clearing, isNull);
    await until(
      () =>
          (rig.connection.fold
                      .stateOf(mainKey)
                      ?.transcript
                      .entries
                      .whereType<UserEntry>() ??
                  const <UserEntry>[])
              .any((e) => e.from?.name == 'chord'),
    );
    final said = rig.connection.fold
        .stateOf(mainKey)!
        .transcript
        .entries
        .whereType<UserEntry>()
        .firstWhere((e) => e.from?.name == 'chord');
    expect(
      said.text,
      startsWith("The person cleared parser's context (scripted, id "),
    );
    expect(
      said.text,
      endsWith(
        'It is open with a fresh session and knows nothing of earlier '
        'turns; your next message is its first.',
      ),
    );
  }, skip: fakeAgentSkip);
}

void testerHostStartupTests() {
  group('tester: startup launch and failed-turn boundaries', () {
    for (final invalidate in ['caller', 'session']) {
      test(
        'an open invalidated at offer await by $invalidate starts no child',
        () async {
          final rig = await started();
          var live = true;
          final caller = Caller(
            role: Role.person,
            key: mainKey,
            window: rig.host,
            launch: () => live,
          );
          final pending = rig.host.open(
            mainKey,
            const SpawnArgs(agent: 'fake', prompt: 'never sent'),
            caller,
          );
          if (invalidate == 'caller') {
            live = false;
          } else {
            rig.connection.conversation.clear().ignore();
          }
          expect((await pending as Refused).error, stale.error);
          expect(rig.connection.agents.agents.children, isEmpty);
          expect(
            rig.server.admitted.values.where(
              (caller) => caller.role == Role.child,
            ),
            isEmpty,
          );
        },
        skip: fakeAgentSkip,
      );
    }

    test(
      'failed required main model revokes its launch token before closing',
      () async {
        final runtimes = TestRuntimes();
        final server = FakeServer();
        final connection = StartConnection(
          command: runtimes.commandOf('fake'),
          env: runtimes.env,
          cwd: runtimes.home.path,
          agent: 'fake',
          open: runtimes.opener,
          starting: const Starting(
            model: StartingValue('not-a-model', from: 'test', required: true),
          ),
        );
        final host = AgentsHost(
          runtimeNames: const ['fake'],
          startupOf: (_) => SessionStart(command: runtimes.commandOf('fake')),
          openChildSession: connection.openChild,
          agents: connection.agents,
          opened: (key) => connection.fold.dispatch(AgentOpened(key)),
          server: server,
        );
        connection
          ..server = server
          ..window = host
          ..start();
        addTearDown(() async {
          await connection.close();
          runtimes.dispose();
        });
        await until(
          () =>
              connection.fold.stateOf(mainKey)?.start.phase ==
              StartPhase.failed,
        );
        final main = server.admitted.entries.single;
        await until(() => server.revoked.contains(main.key));
        expect(main.value.launch?.call(), isFalse);
        expect(
          connection.fold
              .stateOf(mainKey)!
              .transcript
              .entries
              .whereType<UserEntry>(),
          isEmpty,
        );
      },
      skip: fakeAgentSkip,
    );

    test(
      'a failed child turn is reported once and accepts another message',
      () async {
        final connection = await served();
        connection.conversation.send('agentfail');
        await until(() => chordSaid(connection).isNotEmpty);
        final child = connection.agents.agents.children.single;
        final host = connection.window!;
        final answer = host.tell(
          Caller(role: Role.person, key: mainKey, window: host),
          child.id,
          'text',
          () {},
        );
        expect(answer, isA<Delivered>());
        await until(
          () =>
              (connection.fold
                          .stateOf(child.key)
                          ?.transcript
                          .entries
                          .whereType<UserEntry>() ??
                      const <UserEntry>[])
                  .any((entry) => entry.text == 'text'),
        );
        expect(chordSaid(connection), hasLength(1));
        expect(connection.agents.conversationOf(child.key)?.session, isNotNull);
      },
      skip: fakeAgentSkip,
    );
  });
}

void testerHostCloseTests() {
  group('tester: host close during active ownership', () {
    test(
      'closing a starting child revokes now and closes a late session without a job',
      () async {
        final catalog = TestRuntimes();
        final server = FakeServer();
        final gate = Completer<Session>();
        final late = ScriptedSession();
        final connection = StartConnection(
          command: catalog.commandOf('fake'),
          env: catalog.env,
          cwd: catalog.home.path,
          agent: 'fake',
          open: catalog.opener,
        );
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
              }) => gate.future,
          agents: connection.agents,
          server: server,
          opened: (key) => connection.fold.dispatch(AgentOpened(key)),
          closed: (key, front) =>
              connection.fold.dispatch(SessionClosed(key, front)),
        );
        connection
          ..server = server
          ..window = host
          ..start();
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete(late);
          await connection.close();
          catalog.dispose();
        });
        await until(
          () =>
              connection.fold.stateOf(mainKey)?.start.phase ==
              StartPhase.connected,
        );
        final caller = Caller(role: Role.person, key: mainKey, window: host);
        final opened =
            await host.open(
                  mainKey,
                  const SpawnArgs(
                    agent: 'scripted',
                    name: 'pending',
                    prompt: 'must not run',
                  ),
                  caller,
                )
                as Started;
        await until(
          () =>
              server.admitted.values.any((caller) => caller.role == Role.child),
        );
        final child = connection.agents.agents.children.single;
        final admission = server.admitted.entries.firstWhere(
          (entry) => entry.value.role == Role.child,
        );
        expect(host.close(caller, opened.id).toJson(), {'closed': 'pending'});
        expect(connection.agents.agents.children, isEmpty);
        expect(connection.fold.stateOf(child.key), isNull);
        expect(server.revoked, contains(admission.key));
        expect(admission.value.launch?.call(), isFalse);
        gate.complete(late);
        await until(() => late.closes > 0);
        expect(late.turns, isEmpty);
        expect(chordSaid(connection), isEmpty);
        expect(
          (host.tell(caller, opened.id, 'too late', () {}) as Refused).error,
          'pending is closed; open_agent starts another',
        );
      },
      skip: fakeAgentSkip,
    );

    test(
      'person close of a permission-blocked child stops it and sends one note',
      () async {
        final rig = await started();
        await rig.host.open(
          mainKey,
          const SpawnArgs(agent: 'fake', name: 'blocked', prompt: 'permission'),
          rig.person,
        );
        final child = rig.connection.agents.agents.children.single;
        await until(
          () =>
              child.conversation.session?.permissions.pending().isNotEmpty ==
              true,
        );
        rig.host.closeByPerson(child.key);
        rig.host.closeByPerson(child.key);
        await until(() => chordSaid(rig.connection).isNotEmpty);
        expect(chordSaid(rig.connection), hasLength(1));
        expect(
          chordSaid(rig.connection).single,
          startsWith('The person closed blocked'),
        );
        expect(rig.stateOf(child.key), isNull);
        expect(rig.connection.agents.agents.children, isEmpty);
        final token = rig.server.admitted.entries
            .firstWhere((entry) => entry.value.role == Role.child)
            .key;
        await until(() => rig.server.revoked.contains(token));
      },
      skip: fakeAgentSkip,
    );
  });
}
