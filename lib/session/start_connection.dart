/// The window's owned agent and conversation, folded into app state.
library;

import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord_tui/chord_tui.dart';

import '../acp/connection.dart';
import '../acp/rpc.dart' show ElicitationHandler;
import '../acp/schema.dart';
import '../agents.dart' show ListedAgent;
import '../notify.dart' show Wait;
import '../ui/app/sessions.dart' show WindowNotices;
import '../ui/app/state.dart';
import '../ui/app/window_fold.dart';
import '../ui/prompt/queue.dart' show restoredDraft;
import '../server/server.dart';
import '../server/tools.dart' show Caller, Role, WindowView;
import '../ui/start_state.dart';
import 'initial_options.dart' show InitialValues;
import 'place.dart' show SessionStart;

import '../kept.dart';
import 'conversation.dart';
import 'leaving.dart';
import 'open_agents.dart';
import 'session.dart';
import 'setting_picked_up.dart';
import 'sessions.dart';
import 'start_failure.dart' as failure;
import 'record.dart';

/// Starts one session through Conversation and owns its shutdown.
class StartConnection {
  /// A connection started once by [start], closed by the window or owner.
  StartConnection({
    required this.command,
    required String cwd,
    this.agent = 'agent',
    this.env = const {},
    this.open = openAgent,
    this.owner,
    this.resume,
    this.recording,
    this.starting = const Starting(),
    this.warnings = const [],
    this.keysFailed,
    this.vim = false,
    this.theme,
    this.pinned,
    this.mcpServers = const [],
    this.noMcpServers = false,
    this.noMcpServersFrom,
    this.configHome,
  }) : cwd = resume?.cwd ?? cwd;

  /// Where the user's settings are, beside which dismissed notices are
  /// recorded; none records none.
  final String? configHome;

  /// dimcode's one-time notice, watched over every session of the window,
  /// opened in front when it comes due.
  late final WindowNotices notices = WindowNotices(
    configHome: configHome,
    opened: (id) => fold.dispatch(FrontActed(NoticeOpenedAction(id))),
  );

  /// The MCP servers each session is offered, as ACP sends them; those its
  /// agent does not take are held back and said.
  final List<Map<String, Object?>> mcpServers;

  /// The agent takes none of [mcpServers], as [noMcpServersFrom] set it.
  final bool noMcpServers;
  final String? noMcpServersFrom;

  /// The registry's `package@version` npx or uvx runs, for an agent
  /// chord starts from its catalog.
  final String? pinned;

  /// The command selected by the CLI.
  final Object command;

  /// Catalog environment laid over the process environment for this agent.
  final Map<String, String> env;

  /// The session's working directory.
  final String cwd;

  /// The agent's CLI name, used by the session.
  final String agent;

  /// The injectable transport opener.
  final SessionOpener open;

  /// Who closes this connection on a forced way out.
  final Owned? owner;

  /// Optional selected opening and process-owned record drain.
  final Resume? resume;
  final Recording? recording;

  /// The model, effort and mode the session is put on before it is shown.
  final Starting starting;

  /// The settings problems the transcript says first.
  final List<String> warnings;

  /// What the status line says of the keybindings file's problems.
  final String? keysFailed;

  /// Whether the prompt starts in vim mode, as the user's file keeps it.
  final bool vim;

  /// The `theme` setting the window starts in; `auto` without one.
  final String? theme;

  /// Every session's state, folded in the order its events come.
  final fold = WindowFold();

  /// The front session's reducer state, read by the transcript window.
  ValueNotifier<AppState> get app => fold.app;

  /// The window's agents: main's conversation, and each child's.
  late final OpenAgents<Conversation> agents = OpenAgents(
    conversation: (agent, emit, key) {
      _emit = emit;
      return conversation;
    },
    heard: (key, event, wait) {
      _heard(key, event);
      if (wait == null || _closing) return;
      for (final listener in List.of(_waited)) {
        listener(key, wait);
      }
    },
    // Main's last events, as the window closes, are still the window's
    // own; a child's count only for what it spent.
    closingHeard: (key, event) => key == mainKey
        ? _heard(key, event)
        : fold.dispatch(ClosingHeard(key, event)),
  );
  void Function(ConversationEvent event)? _emit;

  // The keys main's let-go sessions are kept under: none a session has.
  var _retiredKeys = -1000000;

  final _closers = <void Function()>[];

  /// Calls [closer] as the connection closes, before it waits on what it
  /// opened: a read under way is given up at once, not waited out.
  void closeWith(void Function() closer) => _closers.add(closer);

  /// Connection facts retained for start-page consumers; no live receipt UI.
  final ValueNotifier<StartState> state = ValueNotifier(StartState.idle);

  /// Main's conversation: the session and turn intents the input
  /// dispatches, made once and started with main.
  late final Conversation conversation = _makeConversation();

  Conversation _makeConversation() {
    final conversation = Conversation(
      _openConversation,
      recording: recording,
      resume: resume,
      starting: starting,
      warnings: warnings,
      reopen: (selected, {required onTraffic, required cancellationToken}) =>
          _openConversation(
            resume: selected,
            onTraffic: onTraffic,
            cancellationToken: cancellationToken,
          ),
    );
    // Through the agents, which fold each event into its agent's wait
    // before the window hears it.
    // A conversation closed before it started is heard as main's.
    conversation.listen(
      (event) => _emit != null ? _emit!(event) : _heard(mainKey, event),
    );
    return conversation;
  }

  final _openings = <Future<Agent?>>[];
  Future<void>? _closed;
  var _started = false;
  var _closing = false;
  var _publicationGeneration = 0;
  Implementation? _info;
  void Function()? _forget;

  final _keyed = <void Function(int key, ConversationEvent event)>[];
  final _waited = <void Function(int key, Wait wait)>[];

  /// Subscribes to every wait on the person an agent's event starts, by the
  /// agent's key, after the agents' roster has taken the event in.
  void Function() listenWaits(void Function(int key, Wait wait) listener) {
    _waited.add(listener);
    return () => _waited.remove(listener);
  }

  /// Subscribes to every agent's events, by its key, after the fold has
  /// taken each in.
  void Function() listenKeyed(
    void Function(int key, ConversationEvent event) listener,
  ) {
    _keyed.add(listener);
    return () => _keyed.remove(listener);
  }

  /// Subscribes after the internal reducer, so app state already reflects events.
  void Function() listen(void Function(ConversationEvent event) listener) =>
      conversation.listen(listener);

  /// Starts the conversation once; a close before start prevents it.
  void start() {
    if (_started || _closing) return;
    _started = true;
    _forget = (owner ?? owned).closeOnForcedExit(close);
    final generation = _publicationGeneration;
    state.value = reduceStart(state.value, const StartRequested());
    if (_closing || generation != _publicationGeneration) return;
    app.value = AppState.starting
        .withKeysFailed(keysFailed)
        .withVim(vim)
        .withTheme(theme);
    if (!_closing && generation == _publicationGeneration) {
      agents.start(agent);
    }
  }

  /// chord's own MCP server, which each launch of every session is admitted
  /// to; none leaves chord's tools out.
  ChordServer? server;

  /// What chord's tools read of the window and ask of it, the host; main is
  /// admitted to [server] once it is set.
  WindowView? window;

  /// Told a saved setting the window takes up at once; the window sets it
  /// while it shows this connection.
  void Function(SettingPickedUp picked)? settingPickedUp;

  /// The agents as `chord agents` lists them, PATH looked at, for `/new` to
  /// describe and order the host's runtimes by; none describes nothing.
  List<ListedAgent> listedAgents = const [];

  void Function() _releaseMain = () {};

  /// Main admitted to [server] for one launch, until that launch is let go.
  Map<String, Object?>? _admitMain() {
    final server = this.server, window = this.window;
    if (server == null || window == null) return null;
    var live = true;
    final admitted = server.admit(
      Caller(
        role: Role.person,
        key: mainKey,
        window: window,
        launch: () => live,
      ),
    );
    _releaseMain();
    _releaseMain = () {
      live = false;
      server.revoke(admitted.token);
    };
    return admitted.server;
  }

  /// A child's session, of [runtime], started as [start] says where main
  /// works, given chord's server as [chordServer]: through the same owned
  /// opener as main's, so the window's close stops it.
  Future<Session> openChild(
    String runtime,
    SessionStart start, {
    required InitialValues initial,
    Map<String, Object?>? chordServer,
    required void Function(Traffic traffic) onTraffic,
    required CancellationToken cancellationToken,
    String? fork,
  }) {
    final command = start.command;
    if (start.refused != null || command == null) {
      return Future.error(
        StateError(start.refused ?? '$runtime has no command'),
      );
    }
    return openSession(
      agent: runtime,
      command: command,
      env: start.env,
      cwd: cwd,
      initial: initial,
      open: _openManaged,
      onTraffic: onTraffic,
      cancellationToken: cancellationToken,
      pinned: start.pinned,
      mcpServers: mcpServers,
      chordServer: chordServer,
      fork: fork,
      noMcpServers: start.noMcpServers,
      noMcpServersFrom: start.noMcpServersFrom,
    );
  }

  Future<Session> _openConversation({
    required void Function(Traffic traffic) onTraffic,
    required CancellationToken cancellationToken,
    Resume? resume,
  }) async {
    final chordServer = _admitMain();
    final release = _releaseMain;
    try {
      final session = await openSession(
        agent: agent,
        command: command,
        env: env,
        cwd: cwd,
        resume: resume,
        initial: starting.initial,
        open: _openMain,
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
        pinned: pinned,
        mcpServers: mcpServers,
        chordServer: chordServer,
        noMcpServers: noMcpServers,
        noMcpServersFrom: noMcpServersFrom,
      );
      // Its process gone, its calls go nowhere.
      session.exited.whenComplete(release).ignore();
      return session;
    } catch (error) {
      release();
      if (!_closing && !cancellationToken.isCancelled) {
        state.value = reduceStart(state.value, _failed(error));
      }
      rethrow;
    }
  }

  /// Main's opener: the agent it opened names the start page's facts, as
  /// no child's or probe's may.
  Future<Agent> _openMain({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) async {
    final opened = await _openManaged(
      command: command,
      env: env,
      cwd: cwd,
      onTraffic: onTraffic,
      onPermission: onPermission,
      relay: relay,
      cancellationToken: cancellationToken,
    );
    _info = opened.init.agentInfo;
    return opened;
  }

  Future<Agent> _openManaged({
    required Object command,
    Map<String, String>? env,
    required String cwd,
    required void Function(Traffic traffic) onTraffic,
    required PermissionHandler onPermission,
    Relay? relay,
    CancellationToken? cancellationToken,
  }) async {
    final opening = open(
      command: command,
      env: env,
      cwd: cwd,
      onTraffic: onTraffic,
      onPermission: onPermission,
      relay: relay,
      cancellationToken: cancellationToken,
    ).then<Agent>(_OwnedAgent.new);
    // Kept as a future that never fails, settled in the zone that made it:
    // an error does not cross error zones, so a close from another zone (a
    // signal's) awaiting an acquisition a key press began would wait for
    // ever on its failure.
    _openings.add(opening.then<Agent?>((agent) => agent, onError: (_) => null));
    final opened = await opening;
    if (_closing) {
      await opened.close();
      throw CancelledException();
    }
    if (cancellationToken?.isCancelled == true) {
      await opened.close();
      cancellationToken!.throwIfCancelled();
    }
    return opened;
  }

  void _heard(int key, ConversationEvent event) {
    // Main's here; every other session's through the host's watch.
    if (key == mainKey) notices.watched('main:$key', agent, event);
    // A child's events are its own; the start page and the forced exit
    // are main's.
    if (key != mainKey) {
      if (_closing) return;
      fold.heard(key, event);
      // The person's prompts a clear took back from an agent go back to
      // its own draft, shown or not; main's, the window puts back itself.
      if (event case QueueWithdrawn(:final prompts) when key != fold.front) {
        final draft = restoredDraft(prompts, fold.stateOf(key)?.draft ?? '');
        fold.dispatch(
          SessionActed(key, DraftEditedAction(draft, draft.length)),
        );
      }
      for (final listener in List.of(_keyed)) {
        listener(key, event);
      }
      return;
    }
    // Only ownership transitions invalidate an outer publication. Ordinary
    // nested same-opening events must still allow its valid connection facts.
    if (event is Cleared || event is Closing) _publicationGeneration++;
    final generation = _publicationGeneration;
    // A launch let go: its calls to chord's server stop now.
    if (event is Cleared || event is Closing) _releaseMain();
    // What main's session spent before a clear or a resume counts as main's,
    // its late figures too, until it settles.
    if (event is Cleared) {
      final retired = --_retiredKeys;
      fold.dispatch(
        SpendClosing(
          retired,
          from: key,
          name: 'main',
          runtime: agent,
          main: true,
        ),
      );
      // Kept on either outcome: a close that failed is the retirement's
      // to report, not this bookkeeping's.
      conversation.retired
          .whenComplete(() => fold.dispatch(SpendClosed(retired)))
          .ignore();
    }
    if (event is Closing) {
      fold.heard(key, event);
      return;
    }
    if (_closing) return;
    switch (event) {
      case Cleared():
        _info = null;
        state.value = reduceStart(StartState.idle, const StartRequested());
      case Connected(:final sessionId):
        state.value = reduceStart(
          state.value,
          SessionOpened(
            sessionId,
            agentName: _info?.name,
            agentVersion: _info?.version,
          ),
        );
      case Gone(:final reason, :final stderrLines, :final stderrCut):
        state.value = reduceStart(
          state.value,
          AgentExited(reason, lines: stderrLines, cut: stderrCut),
        );
      default:
        break;
    }
    if (!_closing && generation == _publicationGeneration) {
      fold.heard(key, event);
    }
  }

  /// Cancels an opening and closes its agent, or closes the live conversation.
  Future<void> close() {
    final known = _closed;
    if (known != null) return known;
    final done = Completer<void>();
    _closed = done.future;
    _close().then(done.complete, onError: done.completeError);
    return done.future;
  }

  Future<void> _close() async {
    _closing = true;
    _forget?.call();
    for (final closer in _closers) {
      closer();
    }
    // Before main started, its conversation is not the agents' yet.
    final closing = agents.agents.main == null
        ? conversation.close()
        : agents.closeAll();
    closing.ignore();
    // Every acquisition is owned even if clear retired it before session/new
    // answered. Closing its transport releases normal requests; an injected
    // non-cooperating session answer may remain pending after its agent died.
    Future<void> closeOpening(Future<Agent?> opening) async {
      await (await opening)?.close();
    }

    try {
      await Future.wait(_openings.map(closeOpening));
    } finally {
      await recording?.flushed();
    }
    unawaited(closing.catchError((Object _) {}));
  }
}

// Session retirement and owner shutdown may both close one acquisition.
// Memoize per agent, so a late acquisition never borrows another's lifetime.
final class _OwnedAgent implements Agent {
  _OwnedAgent(this._agent);
  final Agent _agent;
  // Kept: a clear in the window's zone may begin it, a signal's leave in
  // chord's await it (CTUI-114).
  Kept<void>? _closed;
  @override
  int get pid => _agent.pid;
  @override
  InitializeResponse get init => _agent.init;
  @override
  Future<Exit> get exited => _agent.exited;
  @override
  String? gone() => _agent.gone();
  @override
  set onPlan(PlanHandler? handler) => _agent.onPlan = handler;

  @override
  ElicitationHandler? get onElicitation => _agent.onElicitation;

  @override
  set onElicitation(ElicitationHandler? handler) =>
      _agent.onElicitation = handler;
  @override
  Future<NewSessionResponse> newSession(
    NewSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.newSession(request, cancellationToken: cancellationToken);
  @override
  Future<SessionResponse> loadSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.loadSession(request, cancellationToken: cancellationToken);
  @override
  Future<SessionResponse> resumeSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.resumeSession(request, cancellationToken: cancellationToken);
  @override
  Future<NewSessionResponse> forkSession(
    ReopenSessionRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.forkSession(request, cancellationToken: cancellationToken);
  @override
  bool get steering => _agent.steering;
  @override
  Future<Map<String, Object?>> steer(
    SteerRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.steer(request, cancellationToken: cancellationToken);
  @override
  Future<PromptResponse> prompt(
    PromptRequest request, {
    CancellationToken? cancellationToken,
  }) => _agent.prompt(request, cancellationToken: cancellationToken);
  @override
  Future<void> cancel(
    String sessionId, {
    Iterable<String> subagents = const [],
  }) => _agent.cancel(sessionId, subagents: subagents);
  @override
  Future<void> stopSubagent(String sessionId) => _agent.stopSubagent(sessionId);
  @override
  Future<void> setMode(String sessionId, String modeId) =>
      _agent.setMode(sessionId, modeId);
  @override
  Future<void> setModel(String sessionId, String modelId) =>
      _agent.setModel(sessionId, modelId);
  @override
  Future<String> setTitle(String sessionId, String title) =>
      _agent.setTitle(sessionId, title);
  @override
  Future<Map<String, Object?>> authStatus() => _agent.authStatus();
  @override
  Future<Map<String, Object?>> setConfigEntry(
    String sessionId,
    Map<String, Object?> entry,
  ) => _agent.setConfigEntry(sessionId, entry);
  @override
  Future<Map<String, Object?>> setConfigOption(
    String sessionId,
    String configId,
    String value,
  ) => _agent.setConfigOption(sessionId, configId, value);
  @override
  Future<void> close() =>
      (_closed ??= Kept(Future<void>.sync(_agent.close))).future;
}

StartFailed _failed(Object error) {
  final facts = failure.startFailureOf(error);
  if (facts != null) {
    return StartFailed(
      failure.startupWords(error),
      lines: facts.stderr?.lines ?? const [],
      cut: facts.stderr?.cut ?? 0,
    );
  }
  return switch (error) {
    AgentGone(:final stderr) => StartFailed(
      'The agent exited.',
      lines: stderr.lines,
      cut: stderr.cut,
    ),
    RpcException(:final message) => StartFailed(message),
    FormatException(:final message) => StartFailed(message),
    _ => StartFailed('$error'),
  };
}
