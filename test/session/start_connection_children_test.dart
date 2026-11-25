// StartConnection as the opener of main and of its children: main's facts
// stay its own, and a runtime read under way is given up as it closes.
import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';
import 'package:chord/acp/rpc.dart' show OnCancel;
import 'package:chord/server/runtimes.dart';
import 'package:chord/session/place.dart' show SessionStart;

/// An agent whose answers and exit the test gives.
class Scripted implements Agent {
  Scripted({this.info, this.closeAnswer});

  final Completer<void>? closeAnswer;

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
  }
}

/// One opener for main and its children: each open gets the next agent,
/// or, for [hanging] commands, waits until its token is cancelled.
final class Openers {
  Openers(this.agents, {this.hanging = const {}});
  final List<Scripted> agents;
  final Set<Object> hanging;
  final tokens = <CancellationToken?>[];
  var _next = 0;

  Future<Agent> call({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) {
    tokens.add(cancellationToken);
    if (hanging.contains(command)) {
      final given = Completer<Agent>();
      OnCancel(given.completeError).listen(cancellationToken!);
      return given.future;
    }
    return Future.value(agents[_next++]);
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  retirementTests();
  test("main's facts are its own agent's, whatever a child opened meanwhile "
      'says of itself', () async {
    final mainAgent = Scripted(info: {'name': 'main-agent', 'version': '1.0'});
    final childAgent = Scripted(
      info: {'name': 'child-agent', 'version': '9.9'},
    );
    final open = Openers([mainAgent, childAgent]);
    final connection = StartConnection(
      command: 'main',
      cwd: '/work',
      open: open.call,
      owner: Owned(),
    )..start();
    addTearDown(connection.close);
    await settle();
    final child = connection.openChild(
      'fake',
      const SessionStart(command: 'child'),
      initial: (model: null, effort: null, mode: null),
      onTraffic: (_) {},
      cancellationToken: CancellationToken(),
    );
    await settle();
    childAgent.session.complete(
      NewSessionResponse.fromJson({'sessionId': 'c'}),
    );
    await child;
    mainAgent.session.complete(NewSessionResponse.fromJson({'sessionId': 'm'}));
    await settle();
    await settle();
    final state = connection.state.value;
    expect(state.phase, StartPhase.connected);
    expect((state.agentName, state.agentVersion), ('main-agent', '1.0'));
  });

  test("a runtime read under way is given up as the window closes, not "
      'waited out', () async {
    final mainAgent = Scripted();
    final open = Openers([mainAgent], hanging: {'probe'});
    final connection = StartConnection(
      command: 'main',
      cwd: '/work',
      open: open.call,
      owner: Owned(),
    );
    final runtimes = Runtimes(
      probe: sessionProbe(
        refusedOf: (_) => null,
        open: (runtime, token) => connection.openChild(
          runtime,
          const SessionStart(command: 'probe', noMcpServers: true),
          initial: (model: null, effort: null, mode: null),
          onTraffic: (_) {},
          cancellationToken: token,
        ),
      ),
    );
    connection
      ..closeWith(runtimes.close)
      ..start();
    await settle();
    final read = runtimes.read('codex', probe: true);
    await settle();
    final probeToken = open.tokens.last;
    expect(probeToken?.isCancelled, isFalse);
    await connection.close().timeout(const Duration(seconds: 2));
    expect(probeToken?.isCancelled, isTrue);
    expect(await read, isA<OfferError>());
  });
}

void retirementTests() {
  test("main's /clear keeps its old session's spend even when that session's "
      'close fails, and the fresh one carries on', () async {
    final failingClose = Completer<void>();
    // Its close is awaited later; the failure is the agent's, not unhandled.
    failingClose.future.ignore();
    final first = Scripted(closeAnswer: failingClose);
    final second = Scripted();
    final open = Openers([first, second]);
    final connection = StartConnection(
      command: 'main',
      cwd: '/work',
      open: open.call,
      owner: Owned(),
    )..start();
    // Closing the window says the old agent did not close: not this test's.
    addTearDown(() => connection.close().catchError((Object _) {}));
    await settle();
    first.session.complete(NewSessionResponse.fromJson({'sessionId': 'one'}));
    await settle();
    await settle();
    connection.conversation.clear().ignore();
    await settle();
    second.session.complete(NewSessionResponse.fromJson({'sessionId': 'two'}));
    failingClose.completeError(StateError('the old agent would not close'));
    for (var i = 0; i < 20; i++) {
      await settle();
    }
    expect(connection.fold.windowed.value.kept.single.main, isTrue);
    expect(connection.fold.windowed.value.kept.single.sessionId, 'one');
    expect(connection.state.value.sessionId, 'two');
  });
}
