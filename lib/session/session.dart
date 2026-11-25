/// One agent process and one ACP session in it, until `close()`: its
/// updates through the one ingress, its permission requests parked for the
/// person, and its prompts sent one turn at a time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';

import '../acp/connection.dart';
import '../kept.dart';
import '../cost_counts.dart';
import '../files.dart' as files;
import '../acp/schema.dart' as acp;
import 'agent_state.dart';
import 'auth_status.dart';
import 'models.dart';
import 'modes.dart';
import 'enrich.dart';
import 'enrichers.dart';
import 'inbox.dart';
import 'initial_options.dart';
import 'plan_asks.dart';
import 'elicitations.dart';
import 'permissions.dart';
import 'replay.dart';
import 'servers.dart';
import 'sessions.dart';
import 'sign_in.dart';
import 'start_failure.dart' as failure;
import 'transcript/types.dart';
import 'usage.dart' show tokensOf;

/// Starts an agent as [openAgent] does, for a test to put another in its
/// place.
typedef SessionOpener =
    Future<Agent> Function({
      required Object command,
      Map<String, String>? env,
      required String cwd,
      required void Function(Traffic traffic) onTraffic,
      required PermissionHandler onPermission,
      Relay? relay,
      CancellationToken? cancellationToken,
    });

/// What chord lays over an agent's environment from the person's [parent]
/// one: Claude's task list tools turned on, which it needs to send a plan,
/// unless the person set them either way.
Map<String, String> agentEnv(Map<String, String> parent) =>
    parent.containsKey('CLAUDE_CODE_ENABLE_TODO_TOOLS')
    ? const {}
    : const {'CLAUDE_CODE_ENABLE_TODO_TOOLS': '1'};

/// A prompt sent: its id, how it ended, and the way to stop it.
final class Turn {
  const Turn(this.id, this.result, this.cancel);

  /// The turn's own id.
  final String id;

  /// How the turn ended; never throws.
  final Future<TurnResult> result;

  /// Asks the agent to stop the turn, by `session/cancel`.
  final Future<void> Function() cancel;
}

/// A session-owned resolver; cancellation retires its pending attachment walk.
typedef ResolveMentionLinks =
    Future<List<acp.ContentBlock>> Function(
      List<String> paths,
      String cwd, {
      CancellationToken? cancellationToken,
    });

/// An image in a prompt.
typedef PromptImage = ({String mimeType, String data});

/// What a prompt carries beside its text and mentions: images, embedded
/// resources and resource links, each block as the client sent it; sent
/// after the text in that order, the mentions' links between the
/// resources and these links, as the original sends them.
final class PromptParts {
  /// The [images], [resources] and [links] of a prompt.
  const PromptParts({
    this.images = const [],
    this.resources = const [],
    this.links = const [],
  });

  /// Nothing beside the text, as every prompt of the window.
  static const none = PromptParts();

  /// Its images.
  final List<PromptImage> images;

  /// Its embedded resources, whole `resource` blocks.
  final List<Map<String, Object?>> resources;

  /// Its resource links, whole `resource_link` blocks.
  final List<Map<String, Object?>> links;
}

/// A session's account as its agent says it: the `auth/status` answer,
/// and the pushes after, a push heard since the ask winning over a later
/// answer, as the SDK may hand over the answer after it.
final class _Account {
  AccountState state = noAccount;
  var _pushedSinceAsked = false;
  final _listeners = <void Function(AccountState)>{};

  void _fold(AccountEvent event) {
    final next = foldAccount(state, event);
    if (identical(next, state)) return;
    state = next;
    for (final listener in [..._listeners]) {
      listener(next);
    }
  }

  /// A push of the connection's, heard from before `initialize` on.
  void hear(Traffic traffic) {
    if (traffic case AgentTraffic(
      message: {
        'method': 'auth/status_update',
        'params': final Map<String, Object?> status,
      },
    )) {
      _pushedSinceAsked = true;
      _fold(AccountStatus(status));
    }
  }

  /// Asks [connection], when it advertises `auth.status`; never awaited.
  void ask(Agent connection) {
    // As the original reads the raw answer: a truthy marker.
    if (connection.init.toJson() case {
      'agentCapabilities': {'auth': {'status': final status}},
    } when acp.jsTruthy(status)) {
      _fold(const AccountAsked());
      _pushedSinceAsked = false;
      connection.authStatus().then((status) {
        if (!_pushedSinceAsked) _fold(AccountStatus(status));
      }, onError: (Object _) => _fold(const AccountAskFailed()));
    }
  }

  void Function() subscribe(void Function(AccountState) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// The account once a pending ask is heard, given up after [authWait] or
  /// once [token] is cancelled, so a sign-in's first line says what is
  /// known.
  Future<AccountState> settled([CancellationToken? token]) async {
    if (state is! AccountPending) return state;
    final done = Completer<void>();
    void settle() {
      if (!done.isCompleted) done.complete();
    }

    final timer = Timer(authWait, settle);
    final stop = subscribe((_) => settle());
    final cancelled = token == null
        ? null
        : (CancellableCompleter<void>(token, onCancel: settle)
            ..future.ignore());
    try {
      await done.future;
    } finally {
      timer.cancel();
      stop();
      if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
    }
    return state;
  }
}

/// How long a sign-in waits for an account still being asked for.
const authWait = Duration(milliseconds: 1000);

/// How an advertised adapter handled a personal steering request.
enum SteerOutcome { injected, startedNewTurn, refused }

/// Finalized content captured at the transport's actual outbound admission.
final class SubmittedContent {
  const SubmittedContent._(
    this.turnId,
    this.prompt,
    this.images,
    this.links,
    this.resources,
  );
  final String turnId, prompt;
  final num images;
  final List<Map<String, Object?>> links, resources;

  factory SubmittedContent.fromWire(String turnId, List<Object?> blocks) {
    final detached = jsonDecode(jsonEncode(blocks)) as List;
    final text = StringBuffer();
    var images = 0;
    final links = <Map<String, Object?>>[],
        resources = <Map<String, Object?>>[];
    for (final block in detached.whereType<Map<String, Object?>>()) {
      switch (block['type']) {
        case 'text':
          if (block['text'] is String) text.write(block['text']);
        case 'image':
          images++;
        case 'resource_link':
          links.add(Map.unmodifiable(block));
        case 'resource':
          final resource = block['resource'];
          if (resource is Map && resource['uri'] is String) {
            resources.add(
              Map.unmodifiable({
                'uri': resource['uri'],
                'mimeType': ?resource['mimeType'],
              }),
            );
          }
      }
    }
    return SubmittedContent._(
      turnId,
      text.toString(),
      images,
      List.unmodifiable(links),
      List.unmodifiable(resources),
    );
  }
}

final class _PromptContent {
  _PromptContent(
    this.turnId,
    this.onSubmitted, {
    this.method = 'session/prompt',
  });
  final String method;
  final String turnId;
  final void Function(SubmittedContent)? onSubmitted;
  final token = CancellationToken();
  bool sent = false;
}

final class _PromptAdmissions {
  String? sessionId;
  _PromptContent? _active;
  var _closed = false;

  Future<T> asking<T>(_PromptContent content, Future<T> Function() send) {
    if (_closed) throw StateError('The session is closed.');
    final previous = _active;
    _active = content;
    try {
      return send();
    } finally {
      _active = _closed ? null : previous;
    }
  }

  void hear(Traffic traffic) {
    final content = _active;
    if (_closed ||
        content == null ||
        content.sent ||
        traffic is! ChordTraffic) {
      return;
    }
    final message = traffic.message, params = traffic.message['params'];
    if (message['method'] != content.method ||
        params is! Map ||
        params['sessionId'] != sessionId ||
        params['prompt'] is! List) {
      return;
    }
    content.sent = true;
    try {
      content.onSubmitted?.call(
        SubmittedContent.fromWire(
          content.turnId,
          params['prompt'] as List<Object?>,
        ),
      );
    } catch (_) {
      // Recording failures cannot break an admitted ACP request.
    }
  }

  void close() {
    _closed = true;
    _active = null;
  }
}

/// The name Claude's ACP adapter gives itself in `initialize`.
const _claudeAdapter = '@agentclientprotocol/claude-agent-acp';

/// What chord adds to the request that opens a session, new, forked or
/// again: for Claude's adapter, its prompt suggestions off, which it would
/// otherwise make and chord never shows; nothing for any other agent. The
/// same value each time lets the adapter reuse a session it still has live.
Map<String, Object?>? _openingMeta(Agent connection) =>
    connection.init.agentInfo?.name == _claudeAdapter
    ? const {
        'claudeCode': {
          'options': {'promptSuggestions': false},
        },
      }
    : null;

/// One agent process and one ACP session in it, until [close].
abstract interface class Session {
  /// The agent's name, as chord knows it.
  String get agent;

  /// Where the session works.
  String get cwd;

  /// The agent's id for the session.
  String get id;

  /// The original record path remains the append destination, even if missing.
  String? get record;

  /// Frozen facts of a successfully reopened session; absent for a new one.
  Resume? get resumed;

  /// Consumes detached prepared actions once, releasing setup copies afterward.
  PreparedHistory takeHistory();

  /// What the agent has said of the session, seeded from its answer.
  AgentState get state;

  /// The agent's permission requests, waiting on the person.
  PermissionBridge get permissions;

  /// The agent's plans put to the person, waiting on an answer.
  PlanBridge get plans;

  /// The agent's forms and links, waiting on the person.
  ElicitationBridge get elicitations;

  /// Settles once the agent's exit is seen.
  Future<void> get exited;

  /// Null while connected; once the agent is gone, the end of its stderr.
  String? gone();

  /// Calls [listener] with each of the session's updates; the first
  /// listener hears what came before it first. Returns the unsubscribe.
  void Function() subscribe(void Function(acp.SessionUpdate update) listener);

  /// As [subscribe], with the updates the agent sends for the session's
  /// subagents, at any depth, each with its subagent's id: they are the
  /// session's work too, but not what the session's own agent said.
  void Function() subscribeAll(
    void Function(acp.SessionUpdate update, String? subagentId) listener,
  );

  /// Sends [text] as a prompt, with [parts] after it.
  Turn prompt(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  });

  /// Whether the agent takes images in a prompt, as the
  /// `promptCapabilities` it gave in `initialize` say.
  bool takesImages();

  /// Whether the agent takes embedded resources in a prompt, as its
  /// `initialize` advertises `embeddedContext`.
  bool takesEmbeddedContext();

  /// The servers its agent was not given, and why.
  List<HeldBack> get heldBack;

  /// The name chord's own server went by for its agent, `chord` or the
  /// first free `chord-2`, …; null when its agent was not given it.
  String? get chordServer;

  /// chord's own server as its agent was passed it, its URL and the name
  /// it went by; null when its agent was not given it.
  Map<String, Object?>? get chordServerPassed;

  /// Sets a client's config option [entry] as it sent it, by
  /// `session/set_config_option`; the session's options from the answer.
  Future<void> setConfigEntry(Map<String, Object?> entry);

  /// What the agent says of the account its connection is signed in to,
  /// as its `auth/status` answer and pushes leave it.
  AccountState get account;

  /// Hears each change of [account]; returns what stops it.
  void Function() subscribeAccount(
    void Function(AccountState account) listener,
  );

  /// Whether the agent takes a title, as its `initialize` advertises
  /// `sessionCapabilities.title`.
  bool takesTitles();

  /// Whether the agent forks a session, as its `initialize` advertises
  /// `sessionCapabilities.fork`.
  bool forks();

  /// Renames the session by `session/set_title`: the title the agent kept.
  Future<String> setTitle(String title);

  /// Whether the adapter advertises the running-turn steering extension.
  bool steers();

  /// Whether steering cuts calls already open, as the original Claude adapter.
  bool cutsCallsOnSteer();

  /// Whether the agent runs cycles of its own once a turn has ended, which
  /// start unmarked and end on a usage update of an autonomous origin:
  /// Claude's adapter, by the name it gives in `initialize`.
  bool startsOwnCycles();

  /// Sends the same personal payload without starting a client-owned turn.
  Future<SteerOutcome> steer(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  });

  /// Asks the agent to stop the running turn, by `session/cancel`.
  Future<void> cancel();

  /// Stops subagent [id]'s work alone, its parent's turn going on; throws
  /// when the stop cannot be sent.
  Future<void> stopSubagent(String id);

  /// Changes the mode using its config option, or the legacy ACP call.
  Future<void> setMode(String id);

  /// Changes the model using its config option, or the legacy ACP call.
  Future<void> setModel(String id);

  /// Sets one config option to the agent's value id.
  Future<void> setOption(String id, String value);

  /// Withdraws what waits on the person and stops the agent within the
  /// connection's bounds. Idempotent.
  Future<void> close();
}

/// Starts the agent [command] names, as [agent], with [env] and chord's own
/// laid over chord's environment, in [cwd], and opens a session in it.
/// [onTraffic] hears every crossing after the session's own ingress.
/// [mcpServers] go to the agent by the transports it advertises, the rest
/// held back, and all with [noMcpServers]; a new session asks for
/// [entries], a client's initial config options, where the agent takes
/// them. With [past], a reopened session keeps its raw ACP past for
/// `chord acp` to relay.
/// Rejects, with the agent stopped, when it cannot start or open a session,
/// or [cancellationToken] is cancelled first.
Future<Session> openSession({
  required String agent,
  required Object command,
  Map<String, String>? env,
  required String cwd,
  SessionOpener open = openAgent,
  ResolveMentionLinks resolveMentions = files.mentionLinks,
  Resume? resume,
  String? fork,
  InitialValues initial = (model: null, effort: null, mode: null),
  List<Map<String, Object?>> entries = const [],
  List<Map<String, Object?>> mcpServers = const [],
  Map<String, Object?>? chordServer,
  bool noMcpServers = false,
  String? noMcpServersFrom = noMcpServersFlag,
  bool past = false,
  String? pinned,
  num Function()? now,
  void Function(Traffic traffic)? onTraffic,
  void Function(Map<String, Object?> params)? onElicitationComplete,
  CancellationToken? cancellationToken,
}) async {
  cancellationToken?.throwIfCancelled();
  final recorded = resume?.record == null
      ? PreparedHistory.empty
      : await readRecordedHistory(
          resume!.record,
          cancellationToken: cancellationToken,
          past: past,
        );
  cancellationToken?.throwIfCancelled();
  final directory = resume?.cwd ?? cwd;
  final relay = enricherRelay(
    m1Enrichers,
    totals: usageCountOf(agent) == UsageCount.session,
  );
  if (resume != null) {
    // The running total its agent last gave, for an agent that gives one.
    final total = usageCountOf(agent) == UsageCount.session
        ? recorded.actions
              .whereType<UsageAction>()
              .map((action) => action.figures.usage)
              .where((usage) => usage.isNotEmpty)
              .lastOrNull
        : null;
    relay.recall(resume.sessionId, recorded.recalled, total: total);
  }
  final inbox = SessionInbox();
  final admissions = _PromptAdmissions();
  final bridge = PermissionBridge();
  final account = _Account();
  final Agent connection;
  try {
    connection = await open(
      command: command,
      env: {...?env, ...agentEnv(Platform.environment)},
      cwd: directory,
      onTraffic: (traffic) {
        account.hear(traffic);
        inbox.hear(traffic);
        admissions.hear(traffic);
        // The agent says a link it asked for has been followed.
        if (traffic case AgentTraffic(
          message: {
            'method': 'elicitation/complete',
            'params': final Map<String, Object?> params,
          },
        )) {
          onElicitationComplete?.call(params);
        }
        onTraffic?.call(traffic);
      },
      onPermission: bridge.handler,
      relay: relay,
      cancellationToken: cancellationToken,
    );
  } catch (error) {
    if (cancellationToken?.isCancelled == true) rethrow;
    throw failure.startFailed(
      error,
      failure.StartStep.initialize,
      pinned: pinned,
    );
  }
  // Beside session/new, never awaited.
  account.ask(connection);
  final (:servers, :heldBack, :chord) = serversFor(
    agent,
    connection.init.agentCapabilities?.mcpCapabilities,
    mcpServers,
    chord: chordServer,
    none: noMcpServers,
    from: noMcpServers ? noMcpServersFrom : null,
  );
  final String id;
  var history = PreparedHistory.empty;
  var step = failure.StartStep.newSession;

  // What the answer must hold is read inside, so a malformed one stops the
  // agent as a refused one does.
  try {
    cancellationToken?.throwIfCancelled();
    if (fork != null) {
      // From the whole of [fork]'s conversation, which the agent copies and
      // replays nothing of; what was on screen is chord's to copy.
      step = failure.StartStep.forkSession;
      final answer = await connection.forkSession(
        acp.ReopenSessionRequest(
          sessionId: fork,
          cwd: directory,
          mcpServers: servers,
          meta: _openingMeta(connection),
        ),
        cancellationToken: cancellationToken,
      );
      id = answer.sessionId;
      inbox.open(id, answer);
    } else if (resume == null) {
      final answer = await connection.newSession(
        acp.NewSessionRequest(
          cwd: directory,
          mcpServers: servers,
          configOptions: initialEntries(
            connection.init,
            initial,
            entries: entries,
          ),
          meta: _openingMeta(connection),
        ),
        cancellationToken: cancellationToken,
      );
      id = answer.sessionId;
      inbox.open(id, answer);
    } else {
      id = resume.sessionId;
      final offers = connection.init.agentCapabilities;
      final advertised = offers?.sessionCapabilities?['resume'];
      final canResume = acp.jsTruthy(advertised);
      final method =
          canResume && (recorded.rawHasPast || offers?.loadSession != true)
          ? 'session/resume'
          : 'session/load';
      step = method == 'session/resume'
          ? failure.StartStep.resumeSession
          : failure.StartStep.loadSession;
      inbox.beginReopen(method, id);
      final request = acp.ReopenSessionRequest(
        sessionId: id,
        cwd: directory,
        mcpServers: servers,
        meta: _openingMeta(connection),
      );
      final answer = method == 'session/resume'
          ? await connection.resumeSession(
              request,
              cancellationToken: cancellationToken,
            )
          : await connection.loadSession(
              request,
              cancellationToken: cancellationToken,
            );
      cancellationToken?.throwIfCancelled();
      final replay = inbox.completeReopen(
        answer,
        rawHasPast: recorded.rawHasPast,
      );
      final projected = recorded.rawHasPast
          ? recorded
          : pastActions(
              replay,
              (now ?? () => DateTime.now().millisecondsSinceEpoch)(),
            );
      history = PreparedHistory(
        rawHasPast: recorded.rawHasPast,
        omitted: recorded.omitted || projected.omitted,
        actions: projected.actions,
        pendingRename: recorded.pendingRename,
        title: recorded.rawHasPast ? recorded.title : projected.title,
        // One source per open: the record's past, or what the agent
        // replayed of a session chord never recorded.
        past: !past
            ? null
            : recorded.rawHasPast
            ? recorded.past
            : [
                for (final (:update, :subagentId) in replay)
                  PastUpdate(update.toJson(), subagentId: subagentId),
              ],
      );
    }
    cancellationToken?.throwIfCancelled();
    admissions.sessionId = id;
  } catch (error) {
    // A start the agent refused for want of a login says so, with the
    // ways in it offered.
    final asked = cancellationToken?.isCancelled == true
        ? error
        : asSignIn(
            failure.startFailed(error, step, pinned: pinned),
            connection.init.authMethods,
          );
    final refused = asked is SignInNeeded
        ? withAccount(asked, await account.settled(cancellationToken))
        : asked;
    admissions.close();
    bridge.close();
    inbox.close();
    await connection.close();
    if (resume != null && cancellationToken?.isCancelled != true) {
      throw ResumeError(
        'it cannot resume session ${resume.sessionId}: ${failure.startMessage(refused)}',
        cause: refused,
      );
    }
    if (cancellationToken?.isCancelled == true) rethrow;
    throw refused;
  }

  return _Session(
    agent,
    directory,
    id,
    connection,
    inbox,
    bridge,
    resolveMentions,
    admissions,
    history,
    resume,
    account,
    heldBack,
    chord?['name'] as String?,
    chord,
  );
}

final class _Session implements Session {
  _Session(
    this.agent,
    this.cwd,
    this.id,
    this._connection,
    this._inbox,
    this.permissions,
    this._resolveMentions,
    this._admissions,
    this._history,
    this.resumed,
    this._account,
    this.heldBack,
    this.chordServer,
    this.chordServerPassed,
  ) : exited = _connection.exited.then((_) {}, onError: (Object _) {}) {
    // Its plans are put to the person from now on, as the session is there
    // to show them.
    _connection.onPlan = plans.handler;
    // So are its forms and links, unless whoever opened the agent answers
    // them itself, as `chord acp` passes them on to its client.
    _connection.onElicitation ??= elicitations.handler;
  }

  @override
  final plans = PlanBridge();

  @override
  final elicitations = ElicitationBridge();

  @override
  final String agent;

  @override
  final String cwd;

  @override
  final String id;

  @override
  final PermissionBridge permissions;

  @override
  final Future<void> exited;

  final Agent _connection;
  final SessionInbox _inbox;
  final ResolveMentionLinks _resolveMentions;
  final _PromptAdmissions _admissions;
  PreparedHistory _history;
  @override
  final Resume? resumed;
  @override
  String? get record => resumed?.record;
  @override
  PreparedHistory takeHistory() {
    final history = _history;
    _history = PreparedHistory.empty;
    return history;
  }

  final _prompts = <_PromptContent>{};
  final _steers = <_PromptContent>{};
  var _turns = 0, _steerIds = 0;
  // Kept: its close may be begun in one error zone and awaited in another
  // (CTUI-114).
  Kept<void>? _closing;

  @override
  AgentState get state => _inbox.state;

  @override
  String? gone() => _connection.gone();

  @override
  void Function() subscribe(void Function(acp.SessionUpdate update) listener) =>
      _inbox.subscribe(listener);

  @override
  void Function() subscribeAll(
    void Function(acp.SessionUpdate update, String? subagentId) listener,
  ) => _inbox.subscribeAll(listener);

  @override
  Turn prompt(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  }) {
    final id = '${this.id}-turn-${++_turns}';
    final content = _PromptContent(turnId ?? id, onSubmitted);
    _prompts.add(content);
    final result = _result(
      text,
      List<String>.unmodifiable(mentions),
      parts,
      content,
    );
    return Turn(id, result, () => _cancelPrompt(content));
  }

  @override
  bool takesImages() => _promptCapability('image');

  @override
  bool takesEmbeddedContext() => _promptCapability('embeddedContext');

  final _Account _account;

  @override
  final List<HeldBack> heldBack;

  @override
  final String? chordServer;

  @override
  final Map<String, Object?>? chordServerPassed;

  @override
  AccountState get account => _account.state;

  @override
  void Function() subscribeAccount(
    void Function(AccountState account) listener,
  ) => _account.subscribe(listener);

  @override
  bool takesTitles() => switch (_connection.init.toJson()) {
    // As the original reads the raw answer: a truthy marker.
    {'agentCapabilities': {'sessionCapabilities': {'title': final title}}} =>
      acp.jsTruthy(title),
    _ => false,
  };

  @override
  bool forks() => acp.jsTruthy(
    _connection.init.agentCapabilities?.sessionCapabilities?['fork'],
  );

  @override
  Future<String> setTitle(String title) => _connection.setTitle(id, title);

  bool _promptCapability(String name) => switch (_connection.init.toJson()) {
    {
      'agentCapabilities': {
        'promptCapabilities': final Map<String, Object?> taken,
      },
    } =>
      taken[name] == true,
    _ => false,
  };

  @override
  bool steers() => _connection.steering;

  @override
  bool cutsCallsOnSteer() => _connection.init.agentInfo?.name == _claudeAdapter;

  @override
  bool startsOwnCycles() => _connection.init.agentInfo?.name == _claudeAdapter;

  @override
  Future<SteerOutcome> steer(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  }) async {
    if (!steers()) throw const AgentCapabilityError('_session/steering');
    final content = _PromptContent(
      turnId ?? '$id-steer-${++_steerIds}',
      onSubmitted,
      method: '_session/steering',
    );
    _steers.add(content);
    try {
      final links = mentions.isEmpty
          ? const <acp.ContentBlock>[]
          : await _links(List.unmodifiable(mentions), content);
      content.token.throwIfCancelled();
      if (_closing != null) throw StateError('The session is closed.');
      final answer = await _admissions.asking(
        content,
        () => _connection.steer(
          acp.SteerRequest(
            sessionId: id,
            prompt: _blocks(text, parts, links),
            meta: const {
              'steering': {'idleBehavior': 'promptRequired'},
            },
          ),
          cancellationToken: content.token,
        ),
      );
      return switch (answer['outcome']) {
        'injected' => SteerOutcome.injected,
        'startedNewTurn' => SteerOutcome.startedNewTurn,
        _ => SteerOutcome.refused,
      };
    } finally {
      _steers.remove(content);
    }
  }

  Future<List<acp.ContentBlock>> _links(
    List<String> mentions,
    _PromptContent content,
  ) async {
    if (mentions.isEmpty || _closing != null) return const [];
    try {
      return await _resolveMentions(
        mentions,
        cwd,
        cancellationToken: content.token,
      ).asCancellable(content.token);
    } catch (_) {
      // Mention links supplement literal text; a failed walk costs none.
      return const [];
    }
  }

  Future<void> _cancelPrompt(_PromptContent content) async {
    if (!_prompts.contains(content)) return;
    content.token.cancel();
    if (content.sent) {
      await _connection.cancel(id, subagents: _inbox.subagents);
    }
  }

  /// A prompt's blocks: its [text], then [parts]' images and resources,
  /// then its mentions' [links], then [parts]' links, as the original
  /// orders them for a turn and a steer alike.
  static List<acp.ContentBlock> _blocks(
    String text,
    PromptParts parts,
    List<acp.ContentBlock> links,
  ) => [
    acp.ContentBlock.text(text),
    for (final image in parts.images)
      acp.ContentBlock.fromJson({
        'type': 'image',
        'mimeType': image.mimeType,
        'data': image.data,
      }),
    for (final resource in parts.resources)
      acp.ContentBlock.fromJson(Map.unmodifiable(resource)),
    for (final link in links)
      acp.ContentBlock.fromJson(Map.unmodifiable(link.toJson())),
    for (final link in parts.links)
      acp.ContentBlock.fromJson(Map.unmodifiable(link)),
  ];

  Future<TurnResult> _result(
    String text,
    List<String> mentions,
    PromptParts parts,
    _PromptContent content,
  ) async {
    try {
      final links = mentions.isEmpty
          ? const <acp.ContentBlock>[]
          : await _links(mentions, content);
      if (content.token.isCancelled) {
        return const TurnAnswered(acp.StopReason.cancelled);
      }
      if (_closing != null) {
        await _closing!.future;
        final words = _connection.gone();
        return TurnFailed(
          words == null || words.isEmpty
              ? 'The agent exited.'
              : 'The agent exited: $words',
        );
      }
      final response = await _admissions.asking(
        content,
        () => _connection.prompt(
          acp.PromptRequest(sessionId: id, prompt: _blocks(text, parts, links)),
        ),
      );
      final stopReason = response.toJson()['stopReason'];

      // Nothing invents a stop reason the agent did not give.
      if (stopReason is! String) {
        throw FormatException(
          'The agent answered session/prompt with ${response.toJson()}.',
        );
      }

      final usage = response.toJson()['usage'];
      return TurnAnswered(
        stopReason,
        usage: usage is Map<String, Object?> ? tokensOf(usage) : null,
      );
    } catch (error) {
      // The agent gone, its going is told before the turn it took with it,
      // as the original's: a task's parent hears that its agent exited.
      if (error is AgentGone) await exited;
      return switch (error) {
        // A prompt refused for want of a login is its sign-in block, worded
        // from the account.
        RpcException(:final message, code: authRequired) => TurnFailed(
          message,
          code: authRequired,
          signIn: SignIn(
            message,
            waysOf(_connection.init.authMethods),
            account: await _account.settled(content.token),
          ),
        ),
        RpcException(:final message, :final code) => TurnFailed(
          message,
          code: code,
        ),
        AgentGone(:final message) => TurnFailed(message),
        FormatException(:final message) => TurnFailed(message),
        _ => TurnFailed('$error'),
      };
    } finally {
      _prompts.remove(content);
    }
  }

  @override
  Future<void> setMode(String mode) async {
    final key = modeConfigId(state.configOptions);
    if (key == null) {
      await _connection.setMode(id, mode);
    } else {
      await setOption(key, mode);
    }
  }

  @override
  Future<void> setModel(String model) async {
    final key = modelConfigId(state.configOptions);
    if (key != null) {
      await setOption(key, model);
      return;
    }
    await _connection.setModel(id, model);
    // The legacy method acknowledges the model without a later update.
    if (isModelState(state.models)) {
      _inbox.replaceState(
        AgentState(
          configOptions: state.configOptions,
          modes: state.modes,
          commands: state.commands,
          models: {
            ...state.models as Map<String, Object?>,
            'currentModelId': model,
          },
        ),
      );
    }
  }

  @override
  Future<void> setConfigEntry(Map<String, Object?> entry) async {
    final answered = await _connection.setConfigEntry(id, entry);
    _inbox.replaceState(withOptions(state, answered['configOptions']));
  }

  @override
  Future<void> setOption(String key, String value) async {
    final answered = await _connection.setConfigOption(id, key, value);
    _inbox.replaceState(withOptions(state, answered['configOptions']));
  }

  @override
  Future<void> stopSubagent(String id) => _connection.stopSubagent(id);

  // The content token stops only link resolution. Sent turns still use
  // session/cancel so the agent's own ending response is retained.
  @override
  Future<void> cancel() async {
    final prompts = _prompts.toList();
    for (final content in prompts) {
      content.token.cancel();
    }
    if (prompts.isEmpty || prompts.any((content) => content.sent)) {
      await _connection.cancel(id, subagents: _inbox.subagents);
    }
  }

  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing.future;
    final done = Completer<void>();
    _closing = Kept(done.future);
    _admissions.close();
    _inbox.closing();
    _history = PreparedHistory.empty;
    for (final content in [..._prompts, ..._steers]) {
      content.token.cancel();
    }
    permissions.close();
    plans.close();
    elicitations.close();
    // What the agent sends as its transport drains still reaches the
    // session's listeners, as the original keeps them through its close.
    Future<void>.sync(_connection.close)
        .whenComplete(_inbox.close)
        .then(done.complete, onError: done.completeError);
    return done.future;
  }
}
