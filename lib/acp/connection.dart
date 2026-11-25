/// A running agent and its ACP connection: started, initialised, asked, and
/// closed within the stop's bounds, as the original's `connection.ts`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cancellation_token/cancellation_token.dart';

import '../version.dart';
import 'process.dart';
import 'rpc.dart';
import 'schema.dart';
import 'traffic.dart';
import 'wire.dart';

export 'process.dart' show AgentExitError, CannotStart, Exit, StopBounds, Tail;
export 'rpc.dart' show PermissionHandler, PlanHandler, RpcException;
export 'traffic.dart';

/// An operation refused locally because the agent did not advertise it.
final class AgentCapabilityError implements Exception {
  const AgentCapabilityError(this.method);
  final String method;
  String get message => 'The agent does not offer $method.';
  @override
  String toString() => message;
}

/// How long, past the exit, the rest of stdout gets to reach the subscriber.
const drainBound = Duration(seconds: 1);

/// What chord tells an agent it can do: nothing in M0 and M1. Each
/// capability is declared by the task that draws what it changes.
ClientCapabilities clientCapabilities() => ClientCapabilities();

/// What the window declares, where someone sees it: forms and links,
/// plans by id, notices, compactions by id and commands' output as `_meta` on their tool
/// calls, which it draws, as the original's `clientCapabilities` declares
/// them for it.
/// Declared, Claude's and Codex's adapters send as a notice what they send
/// otherwise as reply text, a compaction by its id, with its summary, in
/// place of a tool call, and Claude's a command's terminal and output in
/// place of a block of text; Codex's sends its plan by id, not as reply
/// text.
ClientCapabilities windowCapabilities() => ClientCapabilities.fromJson({
  'elicitation': {'form': <String, Object?>{}, 'url': <String, Object?>{}},
  'plan': <String, Object?>{},
  'subagents': <String, Object?>{},
  'session': {
    'compaction': <String, Object?>{},
    'notices': <String, Object?>{},
  },
  '_meta': {'terminal_output_delta': true},
});

/// What `-p` declares: forms, which it declines with a line on stderr, and
/// links, which it cancels in silence; plans by id, a markdown one's text
/// the reply; notices, each a line on stderr; compactions by id and
/// commands' output as `_meta`, as the original's `clientCapabilities`
/// does, so an agent sends none of the last three as a tool call or text of
/// its own; the reply alone reaches stdout either way.
ClientCapabilities headlessCapabilities() => ClientCapabilities.fromJson({
  'elicitation': {'form': <String, Object?>{}, 'url': <String, Object?>{}},
  'plan': <String, Object?>{},
  'subagents': <String, Object?>{},
  'session': {
    'compaction': <String, Object?>{},
    'notices': <String, Object?>{},
  },
  '_meta': {'terminal_output_delta': true},
});

/// [openAgent] with `-p`'s capabilities.
Future<Agent> openHeadlessAgent({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  Relay? relay,
  CancellationToken? cancellationToken,
}) => openAgent(
  command: command,
  env: env,
  cwd: cwd,
  onTraffic: onTraffic,
  onPermission: onPermission,
  capabilities: headlessCapabilities(),
  relay: relay,
  cancellationToken: cancellationToken,
);

/// [openAgent] with the window's capabilities.
Future<Agent> openWindowAgent({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  Relay? relay,
  CancellationToken? cancellationToken,
}) => openAgent(
  command: command,
  env: env,
  cwd: cwd,
  onTraffic: onTraffic,
  onPermission: onPermission,
  capabilities: windowCapabilities(),
  relay: relay,
  cancellationToken: cancellationToken,
);

/// The agent went before it answered: how its process ended, when that was
/// seen, and the end of what it wrote to stderr.
class AgentGone implements Exception {
  /// The agent went, saying [message].
  const AgentGone(this.message, this.exit, this.stderr);

  /// `The agent exited.` or `The agent exited: <the end of its stderr>`.
  final String message;

  /// How its process ended, when that was seen in time.
  final Exit? exit;

  /// The end of its stderr, as lines.
  final Tail stderr;

  @override
  String toString() => message;
}

/// Turns each message either way into the messages the rest of chord reads:
/// the enrichers' place, beneath the tap and the routing.
abstract interface class Relay {
  /// What the rest of chord reads for [message], read from the agent.
  List<Map<String, Object?>> fromAgent(Map<String, Object?> message);

  /// What goes to the agent for [message], written by chord.
  List<Map<String, Object?>> fromChord(Map<String, Object?> message);
}

/// [message] through [relay]'s [side], or the raw message where the relay
/// throws: an enricher's fault must not lose what the agent or chord said.
List<Map<String, Object?>> relayed(
  List<Map<String, Object?>> Function(Map<String, Object?>) side,
  Map<String, Object?> message,
) {
  try {
    return side(message);
  } catch (_) {
    return [message];
  }
}

/// What each session has waiting on the person: the turn tokens of the
/// agent's requests, cancelled with the session's turn.
class Waiting {
  final _held = <String, Set<CancellationToken>>{};

  /// Holds [turn] under [sessionId]; returns what lets it go.
  void Function() hold(String sessionId, CancellationToken turn) {
    (_held[sessionId] ??= {}).add(turn);
    return () {
      final held = _held[sessionId];
      held?.remove(turn);
      if (held != null && held.isEmpty) _held.remove(sessionId);
    };
  }

  /// How many requests [sessionId] has waiting.
  int count(String sessionId) => _held[sessionId]?.length ?? 0;

  /// Cancels every request [sessionId] has waiting.
  void cancel(String sessionId) {
    for (final turn in [...?_held[sessionId]]) {
      turn.cancel();
    }
  }
}

/// The connection's one writer: [enqueue] is synchronous (encode, tap,
/// queue) and a pump adds everything queued and awaits one flush, so
/// nothing touches stdin while a flush is pending, and the tap's order is
/// the bytes' order.
class Writer {
  /// A writer onto [input], tapping onto [tap]; [onFailed] hears a pipe
  /// that failed; [relay], when given, turns each message chord writes.
  Writer(this._input, this._tap, this._onFailed, [this._relay]) {
    // Without a handler, an agent closing its stdin would end chord.
    _input.done.then((_) {}, onError: (Object _) => _fail());
  }

  final AgentInput _input;
  final TrafficTap _tap;
  final void Function() _onFailed;
  final Relay? _relay;

  final _queue = <Uint8List>[];
  var _flushing = false;
  var _sealed = false;
  var _failed = false;

  /// Whether new messages are still admitted.
  bool get open => !_sealed && !_failed;

  /// Whether the pipe failed.
  bool get failed => _failed;

  /// Queues [message] and taps it, unless it is a framing reply; false,
  /// and nothing written, once sealed or failed. The relay turns it first,
  /// a framing reply aside, which is the wire's own. Each place is taken
  /// before the tap, so a subscriber that writes or closes while it hears
  /// it comes after it, on the wire as in the tap; and admission is asked
  /// again before each of the relay's messages, so what a close heard on
  /// one of them leaves the rest out, on the wire as in the tap.
  bool enqueue(Map<String, Object?> message, {bool tapped = true}) {
    if (!open) return false;
    final relay = _relay;
    final messages = !tapped || relay == null
        ? [message]
        : relayed(relay.fromChord, message);
    for (final each in messages) {
      if (!open) break;
      _queue.add(encodeLine(each));
      if (tapped) _tap.hear(Traffic.chord(each));
      _pump();
    }
    return true;
  }

  void _pump() {
    if (_flushing || _failed || _queue.isEmpty) return;
    final Future<void> flushed;
    try {
      for (final line in _queue) {
        _input.add(line);
      }
      _queue.clear();
      flushed = _input.flush();
    } catch (_) {
      // A pipe that fails at once fails as one that fails later does.
      _fail();
      return;
    }
    _flushing = true;
    flushed.then(
      (_) {
        _flushing = false;
        _pump();
      },
      onError: (Object _) {
        _flushing = false;
        _fail();
      },
    );
  }

  /// Admits nothing more; what is queued still goes.
  void seal() => _sealed = true;

  /// Ends stdin once what is queued ahead of it is out; never awaited.
  void end() => _input.end();

  void _fail() {
    if (_failed) return;
    _failed = true;
    _queue.clear();
    _onFailed();
  }
}

/// A running agent and its ACP connection, initialised, until [close].
abstract interface class Agent {
  /// Its process id, which is also its group's.
  int get pid;

  /// The agent's whole answer to `initialize`, `_meta` included.
  InitializeResponse get init;

  /// Settles once the exit is seen and its last stderr has come, or 500 ms
  /// passed.
  Future<Exit> get exited;

  /// Null while connected; once stdout has ended, the end of its stderr,
  /// possibly empty.
  String? gone();

  /// Answers the agent's plan requests from now on; none cancels each.
  set onPlan(PlanHandler? handler);

  /// What answers the agent's forms and links; none cancels each.
  ElicitationHandler? get onElicitation;
  set onElicitation(ElicitationHandler? handler);

  /// Opens a session.
  Future<NewSessionResponse> newSession(
    NewSessionRequest request, {
    CancellationToken? cancellationToken,
  });

  /// Loads a known id; replay notifications are partitioned by the session inbox.
  Future<SessionResponse> loadSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  });

  /// Reopens a known id without requesting replay.
  Future<SessionResponse> resumeSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  });

  /// A new session that starts from the whole of [request]'s session's
  /// conversation (ACP's unstable `session/fork`); throws without asking
  /// when the agent does not offer it.
  Future<NewSessionResponse> forkSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  });

  /// Sends a prompt and settles with the agent's own answer; its updates
  /// reach the traffic, not here. Cancelling [cancellationToken] cancels
  /// the turn and ends the wait.
  Future<PromptResponse> prompt(
    PromptRequest request, {
    CancellationToken? cancellationToken,
  });

  /// Whether initialize explicitly advertised `_session/steering`.
  bool get steering;

  /// Sends only an advertised steering request, retaining unknown answer fields.
  Future<Map<String, Object?>> steer(
    SteerRequest request, {
    CancellationToken? cancellationToken,
  });

  /// Changes the session's mode through the legacy ACP method.
  Future<void> setMode(String sessionId, String modeId);

  /// Changes the session's model through the legacy ACP method.
  Future<void> setModel(String sessionId, String modelId);

  /// Renames the session by `session/set_title`; the title the agent kept.
  Future<String> setTitle(String sessionId, String title);

  /// The account the connection is signed in to, by `auth/status`.
  Future<Map<String, Object?>> authStatus();

  /// Sets a config option as a `chord acp` client sent it, [entry] whole,
  /// and keeps the full answer.
  Future<Map<String, Object?>> setConfigEntry(
    String sessionId,
    Map<String, Object?> entry,
  );

  /// Sets one select value and keeps the full answer, including metadata.
  Future<Map<String, Object?>> setConfigOption(
    String sessionId,
    String configId,
    String value,
  );

  /// Queues `session/cancel` for the session alone, which the agent passes
  /// on to its [subagents], then answers this session's waiting requests
  /// `cancelled`, and theirs, as ACP orders them; settles once queued.
  Future<void> cancel(
    String sessionId, {
    Iterable<String> subagents = const [],
  });

  /// Stops subagent [sessionId] alone by `session/cancel` with its own
  /// session id, its parent's turn going on; throws when it cannot be sent.
  Future<void> stopSubagent(String sessionId);

  /// Stops the agent within the bounds and returns once its exit is seen
  /// and what it wrote before going has reached the traffic. Idempotent;
  /// throws [AgentExitError] when even SIGKILL's exit is not seen.
  Future<void> close();
}

/// Starts the agent named by [command] (a command line or an argv), with
/// [env] laid over chord's, in [cwd]; connects to it and initialises ACP v1.
/// Rejects, with the agent stopped, when it cannot start, will not
/// initialise, or [cancellationToken] is cancelled first.
Future<Agent> openAgent({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  ClientCapabilities? capabilities,
  ElicitationHandler? onElicitation,
  Relay? relay,
  CancellationToken? cancellationToken,
  StopBounds stop = const StopBounds(),
}) async {
  cancellationToken?.throwIfCancelled();
  final tap = TrafficTap(onTraffic);
  final process = await spawnAgent(
    command: command,
    env: env,
    cwd: cwd,
    onStderr: (text) => tap.hear(Traffic.stderr(text)),
    cancellationToken: cancellationToken,
    stop: stop,
  );
  return connectAgent(
    process,
    onTraffic: onTraffic,
    onPermission: onPermission,
    capabilities: capabilities,
    onElicitation: onElicitation,
    relay: relay,
    cancellationToken: cancellationToken,
    stop: stop,
  );
}

/// [openAgent]'s connection over an agent process already started, apart
/// so a test drives the process's pipes in the order it needs. [relay],
/// when given, turns every message either way before the tap and the
/// routing see it.
Future<Agent> connectAgent(
  AgentProcess process, {
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  ClientCapabilities? capabilities,
  ElicitationHandler? onElicitation,
  Relay? relay,
  CancellationToken? cancellationToken,
  StopBounds stop = const StopBounds(),
}) async {
  final connection = _Connection(
    process,
    TrafficTap(onTraffic),
    onPermission,
    stop,
    relay,
    onElicitation,
  );
  final InitializeResponse init;
  try {
    init = InitializeResponse.fromJson(
      await connection.ask(
        'initialize',
        InitializeRequest(
          protocolVersion: protocolVersion,
          clientCapabilities: capabilities ?? clientCapabilities(),
          clientInfo: Implementation(name: 'chord', version: version),
        ).toJson(),
        cancellationToken,
      ),
    );
  } catch (_) {
    await connection.close();
    rethrow;
  }
  return connection..init = init;
}

class _Connection implements Agent {
  _Connection(
    this._process,
    this._tap,
    PermissionHandler onPermission,
    this._stop,
    this._relay, [
    ElicitationHandler? onElicitation,
  ]) {
    _writer = Writer(_process.stdin, _tap, _disconnect, _relay);
    _chord = ChordRequests(_writer.enqueue);
    _agent = AgentRequests(
      send: _writer.enqueue,
      onPermission: onPermission,
      closing: _closing,
      hold: _waiting.hold,
      onElicitation: onElicitation,
    );
    _stdout = _process.stdout.listen(
      _read,
      onError: (Object _) => _disconnect(),
      onDone: () {
        _decoder.close(_framed);
        _disconnect();
      },
      cancelOnError: true,
    );
    exited = _process.status.then((exit) async {
      _lastWords = (await _process.lastWords()).trim();
      return exit;
    })..ignore();
  }

  final AgentProcess _process;
  final TrafficTap _tap;
  final StopBounds _stop;
  final Relay? _relay;
  final _closing = CancellationToken();
  final _waiting = Waiting();
  final _decoder = LineDecoder();
  final _disconnected = Completer<void>();
  late final Writer _writer;
  late final ChordRequests _chord;
  late final AgentRequests _agent;
  late final StreamSubscription<List<int>> _stdout;
  var _routing = true;
  String? _lastWords;
  Future<void>? _closed;

  @override
  late final InitializeResponse init;

  @override
  late final Future<Exit> exited;

  @override
  int get pid => _process.pid;

  bool get _isDisconnected => _disconnected.isCompleted;

  @override
  String? gone() =>
      _isDisconnected ? (_lastWords ?? _process.stderrTail().trim()) : null;

  @override
  set onPlan(PlanHandler? handler) => _agent.onPlan = handler;

  @override
  ElicitationHandler? get onElicitation => _agent.onElicitation;

  @override
  set onElicitation(ElicitationHandler? handler) =>
      _agent.onElicitation = handler;

  void _read(List<int> chunk) {
    try {
      _decoder.add(chunk, _framed);
    } on MessageTooLargeError {
      // As the SDK, the line fails the connection.
      _stdout.cancel();
      _disconnect();
    }
  }

  // Wire order: the relay, then for each message it makes the tap, then
  // the routing, as it is read.
  void _framed(Framed framed) {
    switch (framed) {
      case FramedMessage(:final message):
        final relay = _relay;
        final messages = relay == null
            ? [message]
            : relayed(relay.fromAgent, message);
        for (final each in messages) {
          _tap.hear(Traffic.agent(each));
          if (_routing) route(each, chord: _chord, agent: _agent);
        }
      case FramingReply(:final reply):
        _writer.enqueue(reply, tapped: false);
    }
  }

  /// stdout ended, failed or was cut, or stdin's pipe failed: the
  /// connection is gone, and every waiting request fails with the agent's
  /// last words.
  ///
  /// As the SDK's close: nothing more is admitted or routed, the agent's
  /// waiting requests are withdrawn (their fallbacks go nowhere, since
  /// nothing is admitted), and chord's waiting requests fail. What was read
  /// before is routed already.
  void _disconnect() {
    if (_disconnected.isCompleted) return;
    _disconnected.complete();
    _routing = false;
    _writer.seal();
    _closing.cancel();
    unawaited(_chord.close());
  }

  /// The agent's going as an error: [AgentGone] once its last words have
  /// come, with its exit if seen within [stderrSettle] more, or the
  /// launcher's [CannotStart] when its program could not be executed.
  Future<Exception> _goneError() async {
    final tail = (await _process.lastWords()).trim();
    final exit = await settledWithin(_process.status, stderrSettle);
    if (exit case Rejected(error: final CannotStart cannotStart)) {
      return cannotStart;
    }
    return AgentGone(
      tail.isEmpty ? 'The agent exited.' : 'The agent exited: $tail',
      exit is Fulfilled<Exit> ? exit.value : null,
      _process.stderrEnd(),
    );
  }

  /// [_goneError], unless [token] is cancelled while the last words are
  /// awaited, which ends the wait at once with the token's exception.
  Future<Exception> _exitError(CancellationToken? token) {
    if (token == null) return _goneError();
    final error = Completer<Exception>();
    final listener = OnCancel((exception) {
      if (!error.isCompleted) error.complete(exception);
    })..listen(token);
    _goneError().then((gone) {
      if (!error.isCompleted) error.complete(gone);
    });
    return error.future.whenComplete(listener.forget);
  }

  /// Asks [method] and waits for the answer, giving up on [token] or on the
  /// connection's end, whichever comes first.
  Future<Map<String, Object?>> ask(
    String method,
    Map<String, Object?> params,
    CancellationToken? token,
  ) async {
    token?.throwIfCancelled();
    // Withdrawn work must not reach the agent.
    if (_isDisconnected || !_writer.open) throw await _exitError(token);
    // The connection's end fails the request in the client, so nothing
    // here waits on the end itself.
    final Object? result;
    try {
      result = await _chord.request(method, params, token: token);
    } catch (_) {
      // A request the ended connection fails is the agent's exit.
      if (token?.isCancelled != true && _isDisconnected) {
        throw await _exitError(token);
      }
      rethrow;
    }
    if (result is! Map<String, Object?>) {
      throw FormatException('The agent answered $method with $result.');
    }
    return result;
  }

  @override
  Future<NewSessionResponse> newSession(
    NewSessionRequest request, {
    CancellationToken? cancellationToken,
  }) async => NewSessionResponse.fromJson(
    await ask('session/new', request.toJson(), cancellationToken),
  );

  @override
  Future<SessionResponse> loadSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    if (init.agentCapabilities?.loadSession != true) {
      throw const AgentCapabilityError('session/load');
    }
    return SessionResponse.fromJson(
      await ask('session/load', request.toJson(), cancellationToken),
    );
  }

  @override
  Future<SessionResponse> resumeSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final offered = init.agentCapabilities?.sessionCapabilities?['resume'];
    if (offered == null || offered == false || offered == 0 || offered == '') {
      throw const AgentCapabilityError('session/resume');
    }
    return SessionResponse.fromJson(
      await ask('session/resume', request.toJson(), cancellationToken),
    );
  }

  @override
  Future<NewSessionResponse> forkSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final offered = init.agentCapabilities?.sessionCapabilities?['fork'];
    if (offered == null || offered == false || offered == 0 || offered == '') {
      throw const AgentCapabilityError('session/fork');
    }
    return NewSessionResponse.fromJson(
      await ask('session/fork', request.toJson(), cancellationToken),
    );
  }

  @override
  bool get steering {
    final meta = init.toJson()['_meta'];
    final offered = meta is Map ? meta['steering'] : null;
    return offered is Map && offered['supported'] == true;
  }

  @override
  Future<Map<String, Object?>> steer(
    SteerRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    if (!steering) throw const AgentCapabilityError('_session/steering');
    return ask('_session/steering', request.toJson(), cancellationToken);
  }

  @override
  Future<void> setMode(String sessionId, String modeId) async {
    await ask('session/set_mode', {
      'sessionId': sessionId,
      'modeId': modeId,
    }, null);
  }

  @override
  Future<Map<String, Object?>> setConfigEntry(
    String sessionId,
    Map<String, Object?> entry,
  ) => ask('session/set_config_option', {
    ...entry,
    'sessionId': sessionId,
  }, null);

  @override
  Future<Map<String, Object?>> authStatus() => ask('auth/status', {}, null);

  @override
  Future<String> setTitle(String sessionId, String title) async {
    final answer = await ask('session/set_title', {
      'sessionId': sessionId,
      'title': title,
    }, null);
    final kept = answer['title'];
    if (kept is! String) {
      throw FormatException(
        'The agent answered session/set_title with $answer.',
      );
    }
    return kept;
  }

  @override
  Future<void> setModel(String sessionId, String modelId) async {
    await ask('session/set_model', {
      'sessionId': sessionId,
      'modelId': modelId,
    }, null);
  }

  @override
  Future<Map<String, Object?>> setConfigOption(
    String sessionId,
    String configId,
    String value,
  ) => ask('session/set_config_option', {
    'sessionId': sessionId,
    'configId': configId,
    'value': value,
  }, null);

  @override
  Future<PromptResponse> prompt(
    PromptRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final listener = OnCancel((_) {
      cancel(request.sessionId).catchError((_) {});
    });
    if (cancellationToken != null && !cancellationToken.isCancelled) {
      listener.listen(cancellationToken);
    }
    try {
      return PromptResponse.fromJson(
        await ask('session/prompt', request.toJson(), cancellationToken),
      );
    } finally {
      listener.forget();
    }
  }

  @override
  Future<void> cancel(
    String sessionId, {
    Iterable<String> subagents = const [],
  }) async {
    if (!_writer.open) throw await _goneError();
    // The cancel goes ahead of the answers to what the session asked, as
    // ACP orders them: an agent that heard a cancelled answer first could
    // end its turn as though nothing were interrupted.
    _chord.notify(
      'session/cancel',
      CancelNotification(sessionId: sessionId).toJson(),
    );
    for (final each in [sessionId, ...subagents]) {
      _waiting.cancel(each);
    }
  }

  @override
  Future<void> stopSubagent(String sessionId) async {
    if (!_writer.open) throw await _goneError();
    _chord.notify(
      'session/cancel',
      CancelNotification(sessionId: sessionId).toJson(),
    );
  }

  @override
  Future<void> close() => _closed ??= _close();

  Future<void> _close() async {
    // One synchronous turn: every waiting request's fallback is enqueued by
    // its token's onCancel, then nothing new is admitted, then stdin ends
    // once the queue ahead of it is out.
    _closing.cancel();
    _writer.seal();
    _writer.end();
    try {
      await _process.stop(_stop);
    } finally {
      // stdout ends once the group is gone; what it held still counts.
      await settledWithin(_disconnected.future, drainBound);
      _routing = false;
      _disconnect();
      // Not awaited: what it would wait for is already over.
      unawaited(_stdout.cancel());
      await _chord.close();
    }
    // The agent is gone all the same; only its close says otherwise.
    if (agentCloseFailsFlag) throw AgentExitError([_process.pid]);
  }
}

/// A private test flag, defined only at compile time by the compile-tag
/// tests (CTUI-114) and never read from the environment: every agent's
/// close, once its agent has stopped, fails as one whose exit was not seen
/// does, so a compiled chord's way out can be proven not to wait for ever
/// on a close another error zone began. Off, it is compiled out.
const agentCloseFailsFlag = bool.fromEnvironment('CHORD_AGENT_CLOSE_FAILS');
