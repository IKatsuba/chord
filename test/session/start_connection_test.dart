import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler, OnCancel;
import 'package:chord/acp/schema.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord_tui/chord_tui.dart' show ScrollState;
import 'package:test/test.dart';

/// An agent whose answers and exit the test gives.
class _Agent implements Agent {
  _Agent({this.info, this.closeAnswer, this.closeFails = false});

  final Completer<void>? closeAnswer;

  /// Whether its close fails, in the zone that called it.
  final bool closeFails;

  final Map<String, Object?>? info;
  final session = Completer<NewSessionResponse>();
  final exit = Completer<Exit>();
  var closes = 0;
  NewSessionRequest? asked;

  @override
  int get pid => 0;

  @override
  InitializeResponse get init =>
      InitializeResponse.fromJson({'protocolVersion': 1, 'agentInfo': ?info});

  @override
  Future<Exit> get exited => exit.future;

  @override
  String? gone() => null;

  @override
  set onPlan(PlanHandler? handler) {}

  @override
  ElicitationHandler? onElicitation;

  @override
  Future<NewSessionResponse> newSession(
    NewSessionRequest request, {
    CancellationToken? cancellationToken,
  }) {
    asked = request;
    return session.future;
  }

  @override
  Future<SessionResponse> loadSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();
  @override
  Future<SessionResponse> resumeSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();
  @override
  Future<NewSessionResponse> forkSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();
  @override
  bool get steering => false;
  @override
  Future<Map<String, Object?>> steer(
    SteerRequest request, {
    CancellationToken? cancellationToken,
  }) async => throw const AgentCapabilityError('_session/steering');
  @override
  Future<PromptResponse> prompt(
    PromptRequest request, {
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<void> setMode(String sessionId, String modeId) async {}
  @override
  Future<void> setModel(String sessionId, String modelId) async {}
  @override
  Future<String> setTitle(String sessionId, String title) async => title;
  @override
  Future<Map<String, Object?>> authStatus() async => {};
  @override
  Future<Map<String, Object?>> setConfigEntry(
    String sessionId,
    Map<String, Object?> entry,
  ) async => {};
  @override
  Future<Map<String, Object?>> setConfigOption(
    String sessionId,
    String configId,
    String value,
  ) async => {};

  @override
  Future<void> cancel(
    String sessionId, {
    Iterable<String> subagents = const [],
  }) async {}

  @override
  Future<void> stopSubagent(String sessionId) async {}

  @override
  Future<void> close() async {
    closes++;
    await closeAnswer?.future;
    if (closeFails) throw StateError('close failed');
  }
}

/// An opener that hands the test what it was given, and settles as told.
class _Opener {
  final opened = Completer<Agent>();
  Object? command;
  Map<String, String>? env;
  String? cwd;
  CancellationToken? token;
  late void Function(Traffic traffic) onTraffic;
  late PermissionHandler onPermission;

  Future<Agent> call({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) {
    this.command = command;
    this.env = env;
    this.cwd = cwd;
    this.onTraffic = onTraffic;
    this.onPermission = onPermission;
    token = cancellationToken;
    return opened.future;
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  for (final lateStep in ['initialize', 'session/new']) {
    test(
      'late old $lateStep refusal cannot replace current opening facts',
      () async {
        final first = _Opener(), second = _Opener();
        var opens = 0;
        final local = StartConnection(
          command: 'fixture',
          cwd: '/work',
          owner: Owned(),
          open:
              ({
                required command,
                env,
                required cwd,
                required onTraffic,
                required onPermission,
                relay,
                cancellationToken,
              }) => (opens++ == 0 ? first : second).call(
                command: command,
                env: env,
                cwd: cwd,
                onTraffic: onTraffic,
                onPermission: onPermission,
                relay: relay,
                cancellationToken: cancellationToken,
              ),
        )..start();
        final old = _Agent();
        if (lateStep == 'session/new') {
          first.opened.complete(old);
          await settle();
          expect(old.asked, isNotNull);
        }
        final changed = local.conversation.clear();
        expect(opens, 2);
        final current = _Agent();
        second.opened.complete(current);
        await settle();
        current.session.complete(
          NewSessionResponse.fromJson({'sessionId': 'current'}),
        );
        for (var i = 0; i < 3; i++) {
          await settle();
        }
        expect(local.app.value.start.sessionId, 'current');
        final error = RpcException(-32602, 'old refusal');
        if (lateStep == 'initialize') {
          first.opened.completeError(error);
        } else {
          old.session.completeError(error);
        }
        await changed;
        for (var i = 0; i < 3; i++) {
          await settle();
        }
        expect(local.state.value.phase, StartPhase.connected);
        expect(local.app.value.start.phase, StartPhase.connected);
        expect(local.app.value.start.sessionId, 'current');
        expect(local.app.value.start.reason, isNull);
        await local.close();
        expect(current.closes, 1);
        if (lateStep == 'session/new') expect(old.closes, 1);
      },
    );
  }

  test(
    'owner closes each late overlapping acquisition exactly once after clear',
    () async {
      final first = _Opener(), second = _Opener();
      var opens = 0;
      final local = StartConnection(
        command: 'fixture',
        cwd: '/work',
        owner: Owned(),
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => (opens++ == 0 ? first : second).call(
              command: command,
              env: env,
              cwd: cwd,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            ),
      )..start();
      local.conversation.clear();
      expect(opens, 2);
      var closed = false;
      final closing = local.close().then((_) => closed = true);
      final a = _Agent(), b = _Agent();
      first.opened.complete(a);
      await settle();
      expect(a.closes, 1);
      expect(closed, isFalse);
      second.opened.complete(b);
      await closing;
      expect(a.closes, 1);
      expect(b.closes, 1);
      expect(a.asked, isNull);
      expect(b.asked, isNull);
      await local.close();
      expect(a.closes, 1);
      expect(b.closes, 1);
    },
  );

  test(
    'owner close awaits a known retired agent during replacement startup',
    () async {
      final first = _Opener(), second = _Opener();
      var opens = 0;
      final local = StartConnection(
        command: 'fixture',
        cwd: '/work',
        owner: Owned(),
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) => (opens++ == 0 ? first : second).call(
              command: command,
              env: env,
              cwd: cwd,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            ),
      )..start();
      final release = Completer<void>();
      final old = _Agent(closeAnswer: release);
      first.opened.complete(old);
      old.session.complete(NewSessionResponse.fromJson({'sessionId': 'old'}));
      await settle();
      final retired = local.conversation.clear();
      await settle();
      expect(old.closes, 1);
      var closed = false;
      final closing = local.close().then((_) => closed = true);
      final fresh = _Agent();
      second.opened.complete(fresh);
      await settle();
      expect(fresh.closes, 1);
      expect(closed, isFalse);
      release.complete();
      await closing;
      await retired;
      expect(closed, isTrue);
      expect(old.closes, 1);
      expect(fresh.closes, 1);
    },
  );

  late _Opener opener;
  late Owned owner;
  late StartConnection connection;
  late List<StartPhase> phases;

  setUp(() {
    opener = _Opener();
    owner = Owned();
    connection = StartConnection(
      command: 'fake --acp',
      cwd: '/work',
      open: opener.call,
      owner: owner,
    );
    phases = [];
    connection.state.addListener(
      () => phases.add(connection.state.value.phase),
    );
  });

  for (final directly in [false, true]) {
    test(
      'Closing is folded before external wheel dispatch, direct=$directly',
      () async {
        connection.start();
        final agent = _Agent();
        opener.opened.complete(agent);
        await settle();
        var transitions = 0;
        connection.app.addListener(() {
          if (connection.app.value.closing) transitions++;
        });
        connection.listen((event) {
          if (event is Closing) {
            final state = connection.app.value;
            expect(state.closing, isTrue);
            expect(reduceWindow(state, const WheeledAction.up()), same(state));
          }
        });
        connection.app.value = const AppState(
          scroll: ScrollState(content: 100, view: 20, following: true),
        );
        final closing = directly
            ? connection.conversation.close()
            : connection.close();
        expect(connection.app.value.closing, isTrue);
        final closedState = connection.app.value;
        agent.session.complete(
          NewSessionResponse.fromJson({'sessionId': 'late'}),
        );
        agent.exit.complete(const Exit(1));
        opener.onTraffic(const Traffic.stderr('late output'));
        await settle();
        await closing;
        await connection.close();
        expect(connection.app.value, same(closedState));
        expect(transitions, 1);
      },
    );
  }

  test('catalog argv and environment reach the opener', () async {
    const command = ['fixture', 'two words', '--acp'];
    connection = StartConnection(
      command: command,
      env: const {'AUGMENT_DISABLE_AUTO_UPDATE': '1'},
      cwd: '/work',
      open: opener.call,
      owner: owner,
    );
    connection.start();
    await settle();
    expect(opener.command, same(command));
    expect(opener.env, containsPair('AUGMENT_DISABLE_AUTO_UPDATE', '1'));
    opener.opened.completeError(StateError('test finished'));
    await connection.close();
  });

  test('starts the command in the directory, then opens a session there '
      'with no MCP servers', () async {
    connection.start();
    expect(connection.state.value.phase, StartPhase.starting);
    expect(opener.command, 'fake --acp');
    expect(opener.cwd, '/work');
    final agent = _Agent(info: {'name': 'fake-agent', 'version': '2.0'});
    opener.opened.complete(agent);
    await settle();
    expect(agent.asked?.cwd, '/work');
    expect(agent.asked?.mcpServers, isEmpty);
    agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
    await settle();
    final state = connection.state.value;
    expect(state.phase, StartPhase.connected);
    expect(state.sessionId, 's1');
    expect(state.agentName, 'fake-agent');
    expect(state.agentVersion, '2.0');
  });

  test('the servers it is given go with session/new, unless its agent '
      'takes none', () async {
    const files = {
      'name': 'files',
      'command': 'files-mcp',
      'args': <Object?>[],
      'env': <Object?>[],
    };
    for (final none in [false, true]) {
      connection = StartConnection(
        command: 'fake --acp',
        cwd: '/work',
        open: opener.call,
        owner: owner,
        mcpServers: const [files],
        noMcpServers: none,
        noMcpServersFrom: none ? '--no-mcp-servers' : null,
      );
      connection.start();
      final agent = _Agent();
      opener.opened.complete(agent);
      await settle();
      expect(agent.asked?.mcpServers, none ? isEmpty : [files]);
      agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
      await settle();
      await connection.close();
      opener = _Opener();
    }
  });

  test('app state is folded before a listener attached before start', () async {
    final seen = <StartPhase>[];
    connection.listen((event) {
      if (event is Connected) seen.add(connection.app.value.start.phase);
    });
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
    await settle();
    expect(seen, [StartPhase.connected]);
    await connection.close();
    expect(agent.closes, 1);
  });

  test('closing from the connected app notification closes once', () async {
    Future<void>? closing;
    connection.app.addListener(() {
      if (connection.app.value.start.phase == StartPhase.connected) {
        closing = connection.close();
      }
    });
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
    await settle();
    await closing;
    await connection.close();
    expect(agent.closes, 1);
    expect(owner.closeOwned(), isEmpty);
  });

  test('close before start leaves no owned opener or app event', () async {
    await connection.close();
    connection.start();
    expect(opener.command, isNull);
    expect(connection.app.value.start.phase, StartPhase.idle);
    expect(owner.closeOwned(), isEmpty);
  });

  test('a second start does nothing', () {
    connection
      ..start()
      ..start();
    expect(phases, [StartPhase.starting]);
  });

  test('opening bridge releases a transport request when cancelled', () async {
    connection.start();
    final token = CancellationToken();
    final waiting = opener.onPermission(
      RequestPermissionRequest.fromJson({}),
      token,
    );
    token.cancel();
    final answer = await waiting;
    expect(answer.toJson(), {
      'outcome': {'outcome': 'cancelled'},
    });
  });

  test(
    'an agent gone at start fails with the end of its stderr below',
    () async {
      connection.start();
      opener.opened.completeError(
        AgentGone('The agent exited: boom', null, const Tail(['boom'], 2)),
      );
      await settle();
      final state = connection.state.value;
      expect(state.phase, StartPhase.failed);
      expect(
        state.reason,
        'it closed its connection before answering initialize.',
      );
      expect(state.stderrLines, ['boom']);
      expect(state.stderrCut, 2);
    },
  );

  test('a program that cannot start fails with its words', () async {
    connection.start();
    opener.opened.completeError(const CannotStart('fake', 'not found'));
    await settle();
    expect(connection.state.value.reason, 'cannot start fake: not found');
    expect(connection.state.value.stderrLines, isEmpty);
  });

  test('a refused session fails with its message and closes the agent', () async {
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    await settle();
    agent.session.completeError(
      RpcException(-32601, 'Method not found: session/new'),
    );
    await settle();
    expect(connection.state.value.phase, StartPhase.failed);
    expect(
      connection.state.value.reason,
      'it does not serve ACP sessions: not an ACP agent, or not at this version.',
    );
    expect(agent.closes, 1);
  });

  test('an exit after connecting is gone, with the stderr heard', () async {
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    await settle();
    opener.onTraffic(const Traffic.stderr('first\nlast words\n'));
    agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
    await settle();
    agent.exit.complete(const Exit(1));
    await settle();
    final state = connection.state.value;
    expect(state.phase, StartPhase.gone);
    expect(state.reason, 'The agent exited.');
    expect(state.stderrLines, ['first', 'last words']);
    expect(state.sessionId, 's1');
  });

  test('close gives up an opening, and an agent that comes late is closed, '
      'not drawn', () async {
    connection.start();
    final closing = connection.close();
    expect(opener.token!.isCancelled, isTrue);
    final agent = _Agent();
    opener.opened.complete(agent);
    await closing;
    expect(agent.closes, 1);
    expect(phases, [StartPhase.starting]);
  });

  test('close after connecting closes the agent and draws no gone', () async {
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    agent.session.complete(NewSessionResponse.fromJson({'sessionId': 's1'}));
    await settle();
    await connection.close();
    agent.exit.complete(const Exit(0));
    await settle();
    expect(agent.closes, 1);
    expect(connection.state.value.phase, StartPhase.connected);
  });

  test('a cancelled opening after close draws no failure', () async {
    connection.start();
    final closing = connection.close();
    opener.opened.completeError(CancelledException());
    await closing;
    expect(phases, [StartPhase.starting]);
  });

  test('is owned once started, so a forced way out closes it', () async {
    expect(owner.closeOwned(), isEmpty);
    connection.start();
    final agent = _Agent();
    opener.opened.complete(agent);
    await settle();
    await Future.wait(owner.closeOwned());
    expect(agent.closes, 1);
    expect(opener.token!.isCancelled, isTrue);
  });

  test('closing it itself leaves nothing owned', () async {
    connection.start();
    opener.opened.complete(_Agent());
    await connection.close();
    expect(owner.closeOwned(), isEmpty);
  });

  group('a command chord refuses to split', () {
    for (final (command, reason) in [
      (
        'bun agent.ts && echo marker',
        'The agent command "bun agent.ts && echo marker" holds shell '
            'syntax; give a plain command line.',
      ),
      ('', 'The agent command is empty.'),
    ]) {
      test('fails with the original'
          's words: "$command"', () async {
        final refused = StartConnection(
          command: command,
          cwd: '/',
          owner: Owned(),
        )..start();
        await settle();
        expect(refused.state.value.phase, StartPhase.failed);
        expect(refused.state.value.reason, reason);
        expect(
          statusLine(refused.state.value, 'fake'),
          'fake did not start: $reason',
        );
        await refused.close();
      });
    }
  });

  group('tester CTUI-45: command and environment lifecycle', () {
    test(
      'argv tokens stay literal across simultaneous catalog starts',
      () async {
        final firstOpener = _Opener();
        final secondOpener = _Opener();
        final firstEnv = {
          'FIXTURE_AGENT': 'first',
          'FIXTURE_ONLY_FIRST': 'yes',
        };
        final secondEnv = {'FIXTURE_AGENT': 'second'};
        final firstCommand = [
          'fixture',
          '',
          'two words',
          r'$LITERAL',
          'é界😀',
          r'x\y',
          ';',
          '\x1b[31m',
        ];
        final secondCommand = ['other-fixture', '--acp'];
        final first = StartConnection(
          command: firstCommand,
          env: firstEnv,
          cwd: '/work/first',
          open: firstOpener.call,
          owner: Owned(),
        );
        final second = StartConnection(
          command: secondCommand,
          env: secondEnv,
          cwd: '/work/second',
          open: secondOpener.call,
          owner: Owned(),
        );
        first.start();
        second.start();
        expect(firstOpener.command, same(firstCommand));
        expect(secondOpener.command, same(secondCommand));
        expect(firstOpener.env, containsPair('FIXTURE_AGENT', 'first'));
        expect(secondOpener.env, containsPair('FIXTURE_AGENT', 'second'));
        expect(secondOpener.env, isNot(contains('FIXTURE_ONLY_FIRST')));
        expect(firstEnv, {
          'FIXTURE_AGENT': 'first',
          'FIXTURE_ONLY_FIRST': 'yes',
        });
        expect(secondEnv, {'FIXTURE_AGENT': 'second'});
        expect(firstOpener.cwd, '/work/first');
        expect(secondOpener.cwd, '/work/second');
        final firstAgent = _Agent();
        final secondAgent = _Agent();
        firstOpener.opened.complete(firstAgent);
        secondOpener.opened.complete(secondAgent);
        firstAgent.session.complete(
          NewSessionResponse.fromJson({'sessionId': 'first'}),
        );
        secondAgent.session.complete(
          NewSessionResponse.fromJson({'sessionId': 'second'}),
        );
        await settle();
        expect(first.state.value.sessionId, 'first');
        expect(second.state.value.sessionId, 'second');
        await first.close();
        expect(firstAgent.closes, 1);
        expect(secondAgent.closes, 0);
        expect(second.state.value.phase, StartPhase.connected);
        await second.close();
        expect(secondAgent.closes, 1);
      },
    );

    test('argv opening cancelled before a late agent closes it once', () async {
      const command = ['fixture', 'two words', '--acp'];
      final local = StartConnection(
        command: command,
        env: const {'FIXTURE_AGENT': 'late'},
        cwd: '/work',
        open: opener.call,
        owner: owner,
      )..start();
      final closing = local.close();
      expect(opener.command, same(command));
      expect(opener.env, containsPair('FIXTURE_AGENT', 'late'));
      expect(opener.token!.isCancelled, isTrue);
      final agent = _Agent();
      opener.opened.complete(agent);
      await closing;
      await local.close();
      expect(agent.closes, 1);
      expect(agent.asked, isNull);
      expect(local.state.value.phase, StartPhase.starting);
      expect(owner.closeOwned(), isEmpty);
    });
  });

  group('tester opening lifecycle', () {
    test(
      'close while session/new waits ignores its late refusal and exit',
      () async {
        connection.start();
        final agent = _Agent();
        opener.opened.complete(agent);
        await settle();
        expect(agent.asked, isNotNull);
        await connection.close();
        agent.session.completeError(RpcException(-32603, 'late refusal'));
        agent.exit.complete(const Exit(1));
        await settle();
        expect(phases, [StartPhase.starting]);
        expect(owner.closeOwned(), isEmpty);
      },
    );
  });

  // CTUI-76: a clear the window makes while its agent starts runs in the
  // app's guarded zone; a signal's leave closes from another. An error does
  // not cross error zones, so the close must not wait on that start's
  // failure, or chord outlives its terminal.
  test('a close from another zone is not held by a start a clear began '
      'in the app\'s zone', () async {
    var opens = 0;
    final c = StartConnection(
      command: 'agent',
      cwd: '.',
      owner: Owned(),
      open:
          ({
            required command,
            env,
            required cwd,
            required onTraffic,
            required onPermission,
            relay,
            cancellationToken,
          }) {
            opens++;
            // An agent that never initialises, given up once cancelled.
            final started = Completer<Agent>();
            OnCancel((error) {
              if (!started.isCompleted) started.completeError(error);
            }).listen(cancellationToken!);
            return started.future;
          },
    )..start();
    await pumpEventQueue();
    final cleared = Completer<void>();
    runZonedGuarded(() {
      c.conversation.clear().whenComplete(cleared.complete).ignore();
    }, (_, _) {});
    await cleared.future;
    expect(opens, 2);
    await c.close().timeout(const Duration(seconds: 5));
  });

  // CTUI-114: the clear retires a session whose agent's close fails, in the
  // app's guarded zone; the leave's close of that acquisition, from another
  // zone, must hear the failure rather than wait for ever on it.
  test('a close from another zone is not held by an agent close a clear '
      'began and that failed in the app\'s zone', () async {
    final first = _Agent(closeFails: true);
    var opens = 0;
    final c = StartConnection(
      command: 'agent',
      cwd: '.',
      owner: Owned(),
      open:
          ({
            required command,
            env,
            required cwd,
            required onTraffic,
            required onPermission,
            relay,
            cancellationToken,
          }) async => opens++ == 0 ? first : _Agent(),
    )..start();
    await pumpEventQueue();
    first.session.complete(NewSessionResponse.fromJson({'sessionId': 'old'}));
    await pumpEventQueue();
    runZonedGuarded(() {
      c.conversation.clear().ignore();
    }, (_, _) {});
    while (first.closes == 0) {
      await pumpEventQueue();
    }
    expect(opens, 2);
    // Heard as it failed, in this zone.
    await expectLater(
      c.close().timeout(const Duration(seconds: 5)),
      throwsA(isA<StateError>()),
    );
    expect(first.closes, 1);
  });

  // CTUI-114: each close kept for a later wait (a session's, a
  // conversation's, a clear's retirement) is heard as it failed by a waiter
  // in another error zone than the one that began it.
  group('closes begun in the app zone and failed', () {
    Future<StartConnection> connected(_Agent first, [_Agent? next]) async {
      var opens = 0;
      final c = StartConnection(
        command: 'agent',
        cwd: '.',
        owner: Owned(),
        open:
            ({
              required command,
              env,
              required cwd,
              required onTraffic,
              required onPermission,
              relay,
              cancellationToken,
            }) async => opens++ == 0 ? first : next ?? _Agent(),
      )..start();
      await pumpEventQueue();
      first.session.complete(NewSessionResponse.fromJson({'sessionId': 'old'}));
      await pumpEventQueue();
      return c;
    }

    Future<void> inAppZone(void Function() body) async {
      runZonedGuarded(body, (_, _) {});
      await pumpEventQueue();
    }

    final failed = throwsA(isA<StateError>());
    // Awaited, as the way out awaits it: a timeout on the future itself
    // hears an error another zone's await would not.
    Future<void> awaited(Future<void> closing) async => await closing;
    const bound = Duration(seconds: 5);

    test("a session's close", () async {
      final c = await connected(_Agent(closeFails: true));
      final session = c.conversation.session!;
      await inAppZone(() => session.close().ignore());
      await expectLater(awaited(session.close()).timeout(bound), failed);
    });

    test("a conversation's close", () async {
      final c = await connected(_Agent(closeFails: true));
      await inAppZone(() => c.conversation.close().ignore());
      await expectLater(awaited(c.conversation.close()).timeout(bound), failed);
    });

    test("a clear's retirement", () async {
      final first = _Agent(closeFails: true), next = _Agent();
      final c = await connected(first, next);
      await inAppZone(() => c.conversation.clear().ignore());
      while (first.closes == 0) {
        await pumpEventQueue();
      }
      next.session.complete(NewSessionResponse.fromJson({'sessionId': 'new'}));
      await expectLater(awaited(c.conversation.close()).timeout(bound), failed);
    });
  });
}
