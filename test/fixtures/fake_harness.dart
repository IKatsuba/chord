// Opens the fake agent, the Dart port of the original's, for a test:
// skipped only where its snapshot cannot be built, its traffic recorded
// from before the start, and always closed in tearDown, however the test
// ends.
import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/acp/process.dart' show AgentProcess, spawnAgent;
import 'package:chord/acp/rpc.dart' show ElicitationHandler;
import 'package:chord/acp/schema.dart' show ClientCapabilities;
import 'package:chord/session/session.dart' show SessionOpener;
import 'package:test/test.dart';

import 'fake.dart';

export 'fake.dart';

/// Why the fake agent's tests are skipped here, or null when they run:
/// only where the Dart fake cannot be built.
String? get fakeAgentSkip => fakeAgent.reason;

/// The original's test bounds: an agent that ignores stdin closing and
/// SIGTERM, as the fake does, is gone within half a second.
const fakeStopBounds = StopBounds(
  exit: Duration(milliseconds: 100),
  term: Duration(milliseconds: 300),
  kill: Duration(milliseconds: 2000),
);

/// The original's bounds for a close that must end the agent with code 0
/// (STOP in its tests/acp/connection_test.ts): the agent goes by itself at
/// stdin's end, and a loaded machine may take longer than
/// [fakeStopBounds]' 100 ms to let it (CTUI-61).
const fakeCloseBounds = StopBounds(
  exit: Duration(milliseconds: 300),
  term: Duration(milliseconds: 300),
  kill: Duration(milliseconds: 2000),
);

/// Every crossing heard from an agent, kept in order, with a way to wait
/// for one.
final class TrafficRecorder {
  final List<Traffic> heard = [];
  final _waiters = <(bool Function(Traffic), Completer<Traffic>)>[];

  /// Keeps [traffic] and wakes the waiters it matches.
  void add(Traffic traffic) {
    heard.add(traffic);
    _waiters.removeWhere((waiter) {
      final (matches, done) = waiter;
      if (!matches(traffic)) return false;
      done.complete(traffic);
      return true;
    });
  }

  /// The first crossing, heard already or to come, that [matches].
  Future<Traffic> next(bool Function(Traffic traffic) matches) {
    for (final traffic in heard) {
      if (matches(traffic)) return Future.value(traffic);
    }
    final done = Completer<Traffic>();
    _waiters.add((matches, done));
    return done.future;
  }

  /// The `update` of every `session/update` the agent sent, in order.
  List<Map<String, Object?>> get updates => [
    for (final traffic in heard)
      if (traffic case AgentTraffic(
        message: {
          'method': 'session/update',
          'params': {'update': final Map<String, Object?> update},
        },
      ))
        update,
  ];

  /// The text of every `agent_message_chunk`, joined.
  String get said => [
    for (final update in updates)
      if (update case {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': final String text},
      })
        text,
  ].join();

  /// Everything the agent wrote to stderr, joined.
  String get stderr => [
    for (final traffic in heard)
      if (traffic case StderrTraffic(:final text)) text,
  ].join();
}

/// The pid of every fake this test process started, for a check that
/// none is left.
final Set<int> fakeAgentPids = {};

/// One start of the fake agent: its traffic, its process and its open.
final class FakeAgentRun {
  FakeAgentRun._(this.traffic, this.opening, this.cwd);

  /// What crossed, from before the start.
  final TrafficRecorder traffic;

  /// Cancelled in tearDown to give up a start still pending.
  final CancellationToken opening;

  /// The agent's own working directory, a fresh one removed in tearDown.
  final String cwd;

  /// Settles with the agent's process once its group exists, before
  /// `initialize` is answered, so a test knows its pid even when it hangs.
  late final Future<AgentProcess> process;

  /// Settles with the agent once it has initialised.
  late final Future<Agent> agent;
}

/// Starts the fake agent playing [scenario] with [flags] and [env], in a
/// fresh directory, closes it in tearDown with [fakeStopBounds], and answers
/// its permission requests with [onPermission] (by default, a failure,
/// which the connection answers `cancelled`). It is [openAgent] in its two
/// steps, so the process is known before the open settles.
FakeAgentRun startFake({
  String? scenario,
  List<String> flags = const [],
  Map<String, String>? env,
  PermissionHandler? onPermission,
  StopBounds stop = fakeStopBounds,
  ClientCapabilities? capabilities,
}) {
  final cwd = Directory.systemTemp.createTempSync('chord-fake-').path;
  final run = FakeAgentRun._(TrafficRecorder(), CancellationToken(), cwd);
  final tap = TrafficTap(run.traffic.add);
  run.process = spawnAgent(
    command: fakeAgentCommand(scenario, flags),
    env: env,
    cwd: cwd,
    onStderr: (text) => tap.hear(Traffic.stderr(text)),
    cancellationToken: run.opening,
    stop: stop,
  );
  run.process.then(
    (process) => fakeAgentPids.add(process.pid),
    onError: (_) {},
  );
  run.agent = run.process.then(
    (process) => connectAgent(
      process,
      onTraffic: run.traffic.add,
      onPermission:
          onPermission ??
          (request, token) => Future.error(StateError('unexpected permission')),
      cancellationToken: run.opening,
      stop: stop,
      capabilities: capabilities,
    ),
  );
  // A start the test expects to fail is still awaited here, never left
  // unhandled.
  run.agent.ignore();
  addTearDown(() async {
    run.opening.cancel();
    try {
      final Agent agent;
      try {
        agent = await run.agent;
      } on AgentExitError {
        rethrow;
      } on Object {
        // A start that failed or was given up: the open stopped what it
        // started, and only an exit never seen would be a failure here.
        return;
      }
      await agent.close();
    } finally {
      Directory(cwd).deleteSync(recursive: true);
    }
  });
  return run;
}

/// [openAgent] as a [SessionOpener] for the fake, with [fakeStopBounds];
/// [onPid] hears each agent's pid once it has initialised, and every pid
/// goes into [fakeAgentPids].
SessionOpener fakeSessionOpener([void Function(int pid)? onPid]) =>
    fakeOpenerWith(onPid: onPid);

/// [fakeSessionOpener] declaring [capabilities] toward the agent and
/// answering its forms and links with [onElicitation], as `chord acp` opens.
SessionOpener fakeOpenerWith({
  void Function(int pid)? onPid,
  ClientCapabilities? capabilities,
  ElicitationHandler? onElicitation,
}) =>
    ({
      required command,
      env,
      required cwd,
      required onTraffic,
      required onPermission,
      relay,
      cancellationToken,
    }) async {
      final agent = await openAgent(
        command: command,
        env: env,
        cwd: cwd,
        onTraffic: onTraffic,
        onPermission: onPermission,
        capabilities: capabilities,
        onElicitation: onElicitation,
        relay: relay,
        cancellationToken: cancellationToken,
        stop: fakeStopBounds,
      );
      fakeAgentPids.add(agent.pid);
      onPid?.call(agent.pid);
      return agent;
    };
