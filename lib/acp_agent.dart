/// `chord acp`: chord as an ACP agent on its own stdin and stdout, each
/// session one process of the startup agent, from the original's
/// `acp_agent.ts`. [AcpHost] holds the sessions and touches IO only
/// through the ports it is given; [runAcp] wires it to a byte stream in and
/// a sink out.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, ProcessSignal;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:collection/collection.dart';

import 'acp/agent_app.dart';
import 'acp/connection.dart';
import 'acp/host_fold.dart';
import 'acp/rpc.dart';
import 'acp/schema.dart' show ClientCapabilities, jsTruthy;
import 'acp/stdio.dart';
import 'acp/upstream_turns.dart';
import 'acp/wire.dart';
import 'platform/process.dart';
import 'platform/resources.dart' show Resources;
import 'platform/signals.dart' show leaveSignals;
import 'server/runtimes.dart' show Runtimes, sessionProbe;
import 'server/server.dart' show ChordServer;
import 'server/tools.dart'
    show Caller, Refused, Role, Started, settingsBoxClaim;
import 'session/agent_state.dart';
import 'session/agents_host.dart';
import 'session/auth_status.dart';
import 'session/conversation.dart';
import 'session/config.dart' show optionsFromConfigOptions;
import 'notices.dart' show dimcodeAtRisk, dimcodeWords;
import 'session/efforts.dart';
import 'session/elicitations.dart'
    show AcceptReply, CancelReply, DeclineReply, ElicitationReply;
import 'session/initial_options.dart' show InitialValues;
import 'kept.dart';
import 'session/leaving.dart';
import 'mcp.dart' show loadMcpServers;
import 'session/models.dart';
import 'session/modes.dart';
import 'session/open_agents.dart';
import 'session/place.dart';
import 'session/record.dart';
import 'session/window_agents.dart' show Child, agentOf;
import 'session/replay.dart'
    show PastEvent, PastLeftOpen, PastPrompt, PastRenamed, PastUpdate;
import 'session/session.dart';
import 'session/sessions.dart';
import 'session/sign_in.dart';
import 'session/start_failure.dart';
import 'session/starting.dart' show agentMessageOf;
import 'session/transcript/types.dart';
import 'session/upstream.dart';
import 'session/upstream_commands.dart';
import 'session/state_dir.dart';
import 'session/team_command.dart';
import 'session/team_selection.dart' show recordedSelection;
import 'settings.dart';
import 'version.dart' as chord show version;

/// The `_meta` key chord says its own of ACP under.
const acpMeta = 'chord/acp';

/// The extensions this chord has, each at its version, as `initialize`
/// says.
const acpExtensions = {
  'session/state': 1,
  'session/steer': 1,
  'agents': 1,
  'monitors': 1,
};

/// What a person who ran it by hand reads on stderr; only a stdin that is
/// a terminal is a person's. A client's stdin is a pipe, and sees no note.
/// On [linux] (by default, the host's) it names Ctrl-C alone: dart:io never
/// ends a Linux terminal's stdin at Ctrl-D (docs/decisions.md, CTUI-192).
List<String> byHandNote({required bool stdinIsTerminal, bool? linux}) =>
    stdinIsTerminal
    ? [
        'chord: acp serves ACP on stdin and stdout, for a client that starts '
            'it.',
        (linux ?? Platform.isLinux)
            ? 'chord: nothing to press here. Ctrl-C leaves; `chord` opens a '
                  'window.'
            : 'chord: nothing to press here. Ctrl-D or Ctrl-C leaves; `chord` '
                  'opens a window.',
      ]
    : const [];

/// Starts an agent as [openAgent] does, declaring [capabilities] toward it
/// and answering its forms and links with [onElicitation].
typedef AgentLauncher =
    Future<Agent> Function({
      required Object command,
      Map<String, String>? env,
      required String cwd,
      required void Function(Traffic traffic) onTraffic,
      required PermissionHandler onPermission,
      ClientCapabilities? capabilities,
      ElicitationHandler? onElicitation,
      Relay? relay,
      CancellationToken? cancellationToken,
    });

/// [openAgent] as an [AgentLauncher].
Future<Agent> launchAgent({
  required Object command,
  Map<String, String>? env,
  required String cwd,
  required void Function(Traffic traffic) onTraffic,
  required PermissionHandler onPermission,
  ClientCapabilities? capabilities,
  ElicitationHandler? onElicitation,
  Relay? relay,
  CancellationToken? cancellationToken,
}) => openAgent(
  command: command,
  env: env,
  cwd: cwd,
  onTraffic: onTraffic,
  onPermission: onPermission,
  capabilities: capabilities,
  onElicitation: onElicitation,
  relay: relay,
  cancellationToken: cancellationToken,
);

/// The error every request gets once the way out has started.
RpcException closingError() => RpcException(-32603, 'chord is closing');

/// -32002 for a session the client named that chord does not hold.
RpcException sessionNotFound(String sessionId) =>
    RpcException(-32002, 'Resource not found', data: {'sessionId': sessionId});

/// What `_chord/session/state` says before anything runs.
final _idle = sessionStateParamsOf((
  state: SessionStateKind.idle,
  origin: null,
));

/// [state] as it is compared, so only a change goes.
String sessionStateParamsOf(SessionState state) =>
    '${state.state.wire}/${state.origin?.name}';

/// A session this process holds, from its start until its agent is gone.
final class AcpEntry {
  AcpEntry._(this.name);

  /// Its name on stderr, for a way out it holds up.
  final String name;

  /// Main's, kept: the host lets go of it as soon as it closes.
  late final Conversation conversation;

  /// Main and its long-lived children, each with its conversation.
  late final OpenAgents<Conversation> agents;

  /// What chord's tools read and ask of this session's agents.
  late final AgentsHost host;

  /// Main's key in [agents].
  int? key;

  /// What the host reads back of each of its sessions, by key.
  final folds = <int, FoldedSession>{};

  /// Its long-lived children as the client knows them, by their keys.
  final routes = <int, ChildRoute>{};

  /// The children's asks out with the client, apart from main's own, so
  /// main's state says only what main waits on.
  final childAsks = <String, CancellationToken>{};

  /// Main's admission to chord's server for its launch, let go of.
  void Function() releaseMain = () {};

  /// None until it is up.
  UpstreamSession? upstream;

  /// What the agent last said of the session's configuration.
  AgentState state = AgentState.empty;

  /// Whether the client has its id: what comes before waits for that.
  var live = false;

  /// What goes up once the client has its id.
  final held = <void Function()>[];

  /// Set on a `session/load`: its past, which goes up ahead of the answer.
  List<PastEvent>? past;

  /// The id a load or a resume claimed for it.
  String? reopens;

  /// Whether it still holds [reopens] in the host's claims.
  var claimed = false;

  /// The children its record says were left open, as a reopen answers.
  List<Object?>? leftOpen;

  /// The request still waiting for it to be up, and its withdrawal.
  ({Object? requestId, OnCancel withdrawn})? opening;

  /// Closed by the client, or by the way out: no state goes after.
  var closed = false;

  /// Whether dimcode's notice went for it, main's or a child's.
  var noticed = false;

  /// Its agent went: it takes no more prompts, and closes when it can.
  var gone = false;

  // Kept: an event heard in chord's zone may begin it and the way out
  // await it from this server's (CTUI-114).
  /// Its close, once begun.
  Kept<void>? closing;

  /// Which `session/prompt` each turn answers.
  Turns turns = noTurns;

  /// What `_chord/session/state` last said of it, so only a change goes.
  String stateSent = _idle;

  /// Its asks out with the client, by this session's own id for each; each
  /// token withdraws its ask.
  final asks = <String, CancellationToken>{};

  /// What a `$/cancel_request` does for each prompt not yet answered.
  final cancels = <Object?, OnCancel>{};
}

/// A long-lived child of a session, as the client knows it.
final class ChildRoute {
  /// The route of a child under [parent], known to the client as
  /// [upstreamId].
  ChildRoute(this.parent, this.upstreamId);

  /// Its immediate parent's id: main's.
  final String parent;

  /// `<parent>/<child id>`.
  final String upstreamId;

  /// None until it is up.
  UpstreamSession? upstream;

  /// What it said or asked before that, which goes up in order then.
  final held = <void Function()>[];

  /// How its last turn ended, for its `idle` state.
  String? stopReason;

  /// Its process went on its own.
  String? gone;

  /// Why it did not start.
  String? failed;

  /// What was last said of it, and how, so only a change goes up.
  AgentReport? told;
  String? sent;
}

/// Whoever an ask comes from, main or a long-lived child, and where its
/// asks out with the client are kept.
typedef _Asker = ({
  Conversation conversation,
  UpstreamSession? upstream,
  Map<String, CancellationToken> asks,
});

/// What `chord acp` holds: every session the client can name, until the
/// way out.
final class AcpHost {
  /// A host serving [agent] at [version] to a client through [output]:
  /// [launch] starts each agent, [place] reads a session's directory,
  /// [records] the records in [stateDir]. [stderr] tells the person and
  /// [exit] ends the process. [server] is chord's own MCP server, which
  /// every session's main and children are admitted to; [children] says
  /// what a session's children start on, its startup agent alone without
  /// it; [childRecording] keeps each child's record. [configHome] and
  /// [home] say where chord's `settings` tool reads and writes.
  AcpHost({
    required this.agent,
    required this.version,
    required this._output,
    required this._place,
    required this.stateDir,
    required this._stderr,
    required void Function(LeaveExit how) exit,
    this._launch = launchAgent,
    Future<List<SessionRecord>> Function()? records,
    // By-id loads read only the records with the id; when only [records]
    // is given, they are taken from what it reads.
    Future<List<SessionRecord>> Function(String id)? recordsWithId,
    Recording Function(void Function(String message) failed)? recording,
    ProcessGroups? groups,
    Duration leaveTime = leaveTime,
    Duration drainTime = drainTime,
    this._server,
    this._children,
    Recording Function(RecordChild child)? childRecording,
    this.configHome,
    this.home,
    this._resources,
  }) : _records = records ?? (() => readRecords(stateDir)),
       _recordsWithId =
           recordsWithId ??
           (records == null
               ? ((id) => readRecordsWithId(stateDir, id))
               : ((id) async => recordsWithIdOf(await records(), id))),
       _recording =
           recording ?? ((failed) => FileRecording(stateDir, failed: failed)),
       // A failure to keep a child's record is said nowhere, as the
       // original says nothing of it.
       _childRecording =
           childRecording ??
           ((child) => FileRecording(stateDir, failed: (_) {}, child: child)) {
    _chord = ChordRequests(_send, withdraws: true);
    _client = ClientRequests(
      send: _send,
      closing: _closing,
      onNotificationFailed: (method, error) =>
          _say('chord: the client sent $method: ${error.message}'),
    );
    _leaving = Leaving(
      answer: _answerAll,
      drained: _output.drained,
      closeConnection: _closeConnection,
      steps: () => [
        for (final entry in [..._entries])
          LeaveStep(
            entry.upstream?.upstreamId ?? entry.name,
            () => _closeEntry(entry),
          ),
        if (_server case final server?)
          LeaveStep("chord's server", server.close),
        if (_resources case final resources?)
          // Fails with the readers' cleanup warnings, which the way out
          // names on stderr.
          LeaveStep('resource readers', () async {
            final warnings = await resources.close();
            if (warnings.isNotEmpty) throw StateError(warnings.join('; '));
          }),
      ],
      stderr: _say,
      exit: exit,
      groups: groups,
      leaveTime: leaveTime,
      drainTime: drainTime,
    );
    _serve();
  }

  /// The one agent this process runs, by the name chord knows it.
  final String agent;

  /// chord's version, as `initialize` says it.
  final String version;

  /// Where records are kept, as the window's are.
  final String stateDir;

  /// Where the user's settings are; none without a home.
  final String? configHome;

  /// The person's home, which the settings tool shows paths from.
  final String? home;

  // One client asks for every session, so one `settings` box among them.
  final _settingsBox = settingsBoxClaim();

  final Output _output;
  final PlaceReader _place;
  final AgentLauncher _launch;
  final void Function(String line) _stderr;
  final Future<List<SessionRecord>> Function() _records;
  final Future<List<SessionRecord>> Function(String id) _recordsWithId;
  final Recording Function(void Function(String message) failed) _recording;
  final ChordServer? _server;

  // The providers' limits, which get_budgets reads; none reads none.
  /// The providers' limits readers; their close is a leave step.
  final Resources? _resources;
  final ChildrenReader? _children;
  final Recording Function(RecordChild child) _childRecording;
  final _closing = CancellationToken();
  late final ChordRequests _chord;
  late final ClientRequests _client;
  late final Leaving _leaving;
  void Function()? _onClosed;

  /// Each session the client can name, by the name it has for it.
  final sessions = <String, AcpEntry>{};

  /// The ids a load or a resume is opening again.
  final reopening = <String>{};

  /// Every session not closed yet, those still starting and those gone too,
  /// in start order.
  final _entries = <AcpEntry>{};

  /// The openings still reading their place, which have no entry yet.
  final _placing = <Object?>{};

  /// What the client declared in its first `initialize`.
  Map<String, Object?>? capabilities;
  var _starts = 0;

  /// Whether anything still waits on the connection's end: a prompt or an
  /// opening not yet answered.
  bool get watchingClose => _closing.hasCancellables;

  /// Whether the way out has begun.
  bool get leaving => _leaving.started;

  /// Starts the way out, once, for [reason].
  Future<void> leave(LeaveReason reason) => _leaving.leave(reason);

  /// One message the client sent, handled in the order it came.
  void hear(Map<String, Object?> message) =>
      serve(message, chord: _chord, client: _client, send: _send);

  /// What reading stops on, once the way out closes the connection.
  set onClosed(void Function() stop) => _onClosed = stop;

  void _send(Map<String, Object?> message) => _output.send(message);

  void _say(String line) {
    try {
      _stderr(line);
    } catch (_) {
      // A stderr gone is no reason to stop serving.
    }
  }

  void _notify(String method, Map<String, Object?> params) {
    if (!_closing.isCancelled) _chord.notify(method, params);
  }

  void _serve() {
    _client
      ..immediate('initialize', checkOf('initialize'), _initialize)
      ..deferred('session/new', checkOf('session/new'), _newSession)
      ..immediate('session/list', checkOf('session/list'), _listSessions)
      ..deferred(
        'session/load',
        checkOf('session/load'),
        (request) => _reopened(request, replays: true),
      )
      ..deferred(
        'session/resume',
        checkOf('session/resume'),
        (request) => _reopened(request, replays: false),
      )
      ..immediate('session/close', checkOf('session/close'), _closeSession)
      ..deferred('session/prompt', checkOf('session/prompt'), _prompt)
      ..notification('session/cancel', checkOf('session/cancel'), _cancel)
      ..immediate(
        '_chord/session/steer',
        checkOf('_chord/session/steer'),
        _steer,
      )
      ..immediate(
        '_chord/agents/send',
        checkOf('_chord/agents/send'),
        _sendAgent,
      )
      ..immediate(
        '_chord/agents/close',
        checkOf('_chord/agents/close'),
        _closeAgent,
      )
      ..immediate(
        '_chord/monitors/stop',
        checkOf('_chord/monitors/stop'),
        _stopMonitor,
      )
      ..immediate(
        'session/set_config_option',
        checkOf('session/set_config_option'),
        _setConfigOption,
      )
      ..immediate('session/set_mode', checkOf('session/set_mode'), _setMode)
      ..immediate('session/set_title', checkOf('session/set_title'), _setTitle)
      ..immediate(
        'auth/status',
        checkOf('auth/status'),
        (_) => _sourceStatus(),
      );
  }

  void _refuseIfClosing() {
    if (_leaving.started) throw closingError();
  }

  AcpEntry _named(String sessionId) =>
      sessions[sessionId] ?? (throw sessionNotFound(sessionId));

  Map<String, Object?> _initialize(Served<Map<String, Object?>> request) {
    capabilities ??=
        request.params['clientCapabilities'] as Map<String, Object?>?;
    return {
      'protocolVersion': 1,
      'agentInfo': {'name': 'chord', 'version': version},
      'authMethods': <Object?>[],
      'agentCapabilities': {
        // Served from one session's agent, whichever runs.
        'auth': {'status': <String, Object?>{}},
        'loadSession': true,
        'promptCapabilities': {
          'image': true,
          'audio': false,
          'embeddedContext': true,
        },
        'mcpCapabilities': {'http': true, 'sse': true},
        // chord's record takes any rename, whatever the agent takes.
        'sessionCapabilities': {
          'list': <String, Object?>{},
          'resume': <String, Object?>{},
          'close': <String, Object?>{},
          'title': <String, Object?>{},
        },
      },
      '_meta': {
        acpMeta: {
          'version': 1,
          'extensions': acpExtensions,
          'agent': {'name': agent},
        },
      },
    };
  }

  Future<Map<String, Object?>> _listSessions(
    Served<Map<String, Object?>> request,
  ) async {
    final cwd = request.params['cwd'];
    return {
      'sessions': [
        for (final earlier in earlierSessions(
          await _records(),
          agent: agent,
          cwd: cwd is String ? cwd : null,
        ))
          {
            'sessionId': earlier.resume.sessionId,
            'cwd': earlier.resume.cwd,
            'title': earlier.prompt,
            'updatedAt': earlier.lastUsedAt,
          },
      ],
    };
  }

  Future<Map<String, Object?>> _closeSession(
    Served<Map<String, Object?>> request,
  ) async {
    _refuseIfClosing();
    final sessionId = request.params['sessionId'] as String;
    final entry = _named(sessionId);
    sessions.remove(sessionId);
    _step(entry, const TurnsClosing());
    _withdrawAll(entry);
    await _closeEntry(entry);
    return const {};
  }

  void _newSession(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final params = request.params;
    _placing.add(request.id);
    _placed(params, request)
        .then((placed) {
          // Checked again where the agent would start: the way out may have
          // begun, or the client withdrawn it, since the place was read.
          _refuseIfClosing();
          if (_withdrawn(request)) throw requestCancelled(request.id);
          final (:place, :servers, :children) = placed;
          _up(
            _openEntry(
              place,
              params['cwd'] as String,
              servers,
              children,
              entries: [
                for (final entry
                    in params['configOptions'] as List? ?? const [])
                  entry as Map<String, Object?>,
              ],
            ),
            request,
          );
        })
        // A failure of the start itself, before or here, is the request's.
        .catchError((Object error) => _client.fail(request.id, error))
        .whenComplete(() => _placing.remove(request.id));
  }

  /// A session opened again under the id the client asked for: with its
  /// past relayed ahead of the answer when it [replays], with nothing of it
  /// otherwise.
  void _reopened(
    Served<Map<String, Object?>> request, {
    required bool replays,
  }) {
    _refuseIfClosing();
    final params = request.params;
    final sessionId = params['sessionId'] as String;
    final cwd = params['cwd'] as String;
    if (sessions.containsKey(sessionId) || reopening.contains(sessionId)) {
      throw RpcException(
        -32602,
        'Invalid params: Session $sessionId is already open here.',
      );
    }
    // Claimed before any await, so a second load of it is refused.
    reopening.add(sessionId);
    _placing.add(request.id);
    AcpEntry? opened;
    () async {
          final Resume from;
          try {
            from = sessionById(
              await _recordsWithId(sessionId),
              sessionId,
              agent: agent,
              cwd: cwd,
            );
          } on ResumeError catch (error) {
            throw RpcException(-32602, 'Invalid params: ${error.message}');
          }
          if (from.cwd != cwd) {
            throw RpcException(
              -32602,
              'Invalid params: Session $sessionId is in ${from.cwd}.',
            );
          }
          _refuseIfClosing();
          final (:place, :servers, :children) = await _placed(params, request);
          _refuseIfClosing();
          if (_withdrawn(request)) throw requestCancelled(request.id);
          final entry = opened = _openEntry(
            place,
            cwd,
            servers,
            children,
            resume: from,
            replays: replays,
          );
          _up(entry, request);
        }()
        .catchError((Object error) {
          if (opened == null) reopening.remove(sessionId);
          _client.fail(request.id, error);
        })
        .whenComplete(() => _placing.remove(request.id));
  }

  /// Lets go of the id [entry] claimed, once its opening is answered.
  void _unclaim(AcpEntry entry) {
    if (!entry.claimed) return;
    entry.claimed = false;
    reopening.remove(entry.reopens);
  }

  /// What a client's servers and the session's directory start a session
  /// on; refused before anything starts.
  Future<
    ({AcpPlace place, List<Map<String, Object?>> servers, AcpChildren children})
  >
  _placed(Map<String, Object?> params, Served<Object?> request) async {
    final servers = [
      for (final server in params['mcpServers'] as List? ?? const [])
        server as Map<String, Object?>,
    ];
    for (final server in servers) {
      if (server['type'] == 'acp') {
        throw RpcException(
          -32602,
          'Invalid params: MCP server ${server['name']} has an acp transport, '
          'which chord does not take from a client.',
        );
      }
    }
    final place = await _place(params['cwd'] as String);
    _refuseIfClosing();
    final start = place.start;
    if (start == null) {
      throw RpcException(-32603, 'Unknown agent "$agent".');
    }
    if (start.refused case final refused?) throw RpcException(-32603, refused);
    // Without a reader, children start only on the startup agent, as it
    // starts in this place.
    final children =
        await _children?.call(params['cwd'] as String) ??
        (
          runtimes: [agent],
          startOf: (String runtime) => runtime == agent ? start : null,
        );
    _refuseIfClosing();
    // A cancel while the place was read: no agent is started for it.
    if (_withdrawn(request)) throw requestCancelled(request.id);
    // A client's server is the nearest layer, by name, over the files':
    // a later one of the same name takes the earlier's place.
    final byName = <String, Map<String, Object?>>{
      for (final defined in start.mcpServers)
        '${defined.server['name']}': defined.server,
      for (final server in servers) '${server['name']}': server,
    };
    return (place: place, servers: [...byName.values], children: children);
  }

  /// Whether the client withdrew [request], as opposed to the connection
  /// closing under it.
  bool _withdrawn(Served<Object?> request) =>
      request.token.isCancelled && !_closing.isCancelled;

  AcpEntry _openEntry(
    AcpPlace place,
    String cwd,
    List<Map<String, Object?>> servers,
    AcpChildren children, {
    List<Map<String, Object?>> entries = const [],
    Resume? resume,
    bool replays = false,
  }) {
    final start = place.start!;
    final entry = AcpEntry._('session ${++_starts}')
      ..reopens = resume?.sessionId
      ..claimed = resume != null
      ..past = replays ? [] : null;
    final notices = jsTruthy(
      (capabilities?['session'] as Map<String, Object?>?)?['notices'],
    );
    // Main's forms go to the client as they come; a child's, and a task's,
    // wait in its own conversation, which says who asks.
    SessionOpener opener(ElicitationHandler? onElicitation) =>
        ({
          required Object command,
          Map<String, String>? env,
          required String cwd,
          required void Function(Traffic traffic) onTraffic,
          required PermissionHandler onPermission,
          Relay? relay,
          CancellationToken? cancellationToken,
        }) => _launch(
          command: command,
          env: env,
          cwd: cwd,
          onTraffic: onTraffic,
          onPermission: onPermission,
          capabilities: ClientCapabilities.fromJson(
            acpCapabilities(notices: notices),
          ),
          onElicitation: onElicitation,
          relay: relay,
          cancellationToken: cancellationToken,
        );

    late final Conversation conversation;
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async {
        final chordServer = _admitMain(entry);
        final release = entry.releaseMain;
        try {
          final session = await openSession(
            agent: agent,
            command: start.command!,
            env: start.env,
            cwd: cwd,
            open: opener((params, token) => _askForm(entry, params, token)),
            mcpServers: servers,
            chordServer: chordServer,
            noMcpServers: start.noMcpServers,
            noMcpServersFrom: start.noMcpServersFrom,
            entries: entries,
            resume: resume,
            // Read for a resume too, for what it left open.
            past: resume != null,
            initial: start.starting.initial,
            pinned: start.pinned,
            onTraffic: onTraffic,
            // The agent says a link it asked for has been followed.
            onElicitationComplete: (params) =>
                _notify('elicitation/complete', params),
            cancellationToken: cancellationToken,
          );
          // Its process gone, its calls go nowhere.
          session.exited.whenComplete(release).ignore();
          return session;
        } catch (_) {
          release();
          rethrow;
        }
      },
      recording: _recording((message) => conversation.recordingFailed(message)),
      starting: Starting(
        model: start.starting.model,
        effort: start.starting.effort,
        mode: start.starting.mode,
        entries: entries,
      ),
    );
    entry.conversation = conversation;

    // A child's session of [runtime], where main works, on the settings'
    // servers only and chord's for its launch.
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
        open: opener(null),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
        pinned: start.pinned,
        mcpServers: [for (final defined in start.mcpServers) defined.server],
        chordServer: chordServer,
        fork: fork,
        noMcpServers: start.noMcpServers,
        noMcpServersFrom: start.noMcpServersFrom,
        onElicitationComplete: (params) =>
            _notify('elicitation/complete', params),
      );
    }

    entry.agents = OpenAgents<Conversation>(
      conversation: (_, emit, key) {
        entry.key = key;
        conversation.listen(emit);
        return conversation;
      },
      heard: (key, event, _) => _hostHeard(entry, key, event),
      // A close takes main out first: what it still says, a cancelled
      // turn's end and its asks withdrawn, is told as ever. A child told
      // closed has nothing more to say; what it asked is still out with
      // the client until it is withdrawn.
      closingHeard: (key, event) {
        if (key == entry.key) return _heard(entry, event);
        if (_settledKey(event) case final settled?) {
          _withdrawChild(entry, settled);
        }
      },
    );
    entry.host = AgentsHost(
      cwd: cwd,
      configHome: configHome,
      home: home,
      settingsBox: _settingsBox,
      runtimeNames: children.runtimes,
      startupOf: children.startOf,
      openChildSession: openChild,
      openForkSession: openChild,
      agents: entry.agents,
      // Placed in the roster only once the call that told this returns.
      opened: (key) => scheduleMicrotask(() => _report(entry, key)),
      closed: (key, _) {
        _tellClosed(entry, key);
        entry.folds.remove(key);
      },
      server: _server,
      resources: _resources?.read,
      // Main's goes by _heard, which has its options as they stand.
      watched: (_, runtime, event) {
        // Up already at risk, or moved there since.
        if (event
            case Connected(:final state) || AgentStateChanged(:final state)) {
          _tellDimcode(entry, runtime, state);
        }
      },
      recordingOf: _childRecording,
      transcriptOf: (key) => entry.folds[key]?.transcript,
      runtimes: Runtimes(
        probe: sessionProbe(
          refusedOf: (runtime) => children.startOf(runtime)?.refused,
          // Read with no MCP servers, and closed at once.
          open: (runtime, token) {
            final start = children.startOf(runtime) ?? const SessionStart();
            return openChild(
              runtime,
              SessionStart(
                command: start.command,
                env: start.env,
                noMcpServers: true,
              ),
              initial: (model: null, effort: null, mode: null),
              onTraffic: (_) {},
              cancellationToken: token,
            );
          },
        ),
      ),
    );
    _entries.add(entry);
    entry.agents.start(agent);
    return entry;
  }

  /// Main admitted to chord's server for one launch, until that launch is
  /// let go; none without a server.
  Map<String, Object?>? _admitMain(AcpEntry entry) {
    final server = _server;
    final key = entry.key;
    if (server == null || key == null) return null;
    var live = true;
    final admitted = server.admit(
      Caller(
        role: Role.person,
        key: key,
        window: entry.host,
        launch: () => live,
      ),
    );
    entry.releaseMain();
    entry.releaseMain = () {
      live = false;
      server.revoke(admitted.token);
    };
    return admitted.server;
  }

  /// Session [key] of [entry]'s host heard [event]: folded first, as the
  /// host and the server read it back, then told as main's or a child's.
  void _hostHeard(AcpEntry entry, int key, ConversationEvent event) {
    entry.folds[key] = foldEvent(entry.folds[key], event);
    if (key == entry.key) {
      _heard(entry, event);
    } else {
      _childHeard(entry, key, event);
    }
  }

  /// The key an ask of [event]'s settling was kept under, if it settles
  /// one.
  static String? _settledKey(ConversationEvent event) => switch (event) {
    Transcribed(action: PermissionSettledAction(:final id)) => 'permission:$id',
    Transcribed(action: ElicitationSettledAction(:final id)) => 'form:$id',
    Transcribed(action: PlanSettledAction(:final id)) => 'plan:$id',
    _ => null,
  };

  /// A long-lived child's route, made on first need once main is up.
  ChildRoute? _routeOf(AcpEntry entry, int key) {
    final had = entry.routes[key];
    if (had != null) return had;
    final child = agentOf(entry.agents.agents, key)?.child;
    final main = entry.upstream?.upstreamId;
    if (child == null || main == null) return null;
    return entry.routes[key] = ChildRoute(main, '$main/${child.id}');
  }

  /// What chord says of child [key], if it has changed.
  void _report(AcpEntry entry, int key) {
    final route = _routeOf(entry, key);
    final child = agentOf(entry.agents.agents, key)?.child;
    if (route == null || child == null) return;
    final state = child.conversation.session?.state;
    final report = route.told = AgentReport(
      parent: route.parent,
      upstreamId: route.upstreamId,
      title: child.name,
      state: route.gone == null
          ? agentStateOf(
              entry.folds[key] ?? noFold,
              stopReason: route.stopReason,
            )
          : const {'state': 'unknown'},
      runtime: child.runtime,
      model:
          (state == null
              ? null
              : modelsFrom(state.configOptions, state.models)?.current) ??
          child.info.model,
      effort: state == null ? null : effortsFrom(state.configOptions)?.current,
      mode:
          (state == null
              ? null
              : modesFrom(state.configOptions, state.modes)?.current) ??
          child.info.mode,
      team: child.info.team,
      gone: route.gone,
      failed: route.failed,
    );
    final notification = agentUpdate(capabilities ?? const {}, report);
    if (notification == null) return;
    final said = jsonEncode(notification);
    if (said == route.sent) return;
    route.sent = said;
    _notify('session/update', notification);
  }

  /// A child gone: said once, under what was last said of it.
  void _tellClosed(AcpEntry entry, int key) {
    final told = entry.routes.remove(key)?.told;
    if (told == null) return;
    final notification = agentUpdate(capabilities ?? const {}, told.asClosed);
    if (notification != null) _notify('session/update', notification);
  }

  /// A long-lived child's event, as the client hears of it.
  void _childHeard(AcpEntry entry, int key, ConversationEvent event) {
    final route = _routeOf(entry, key);
    final child = entry.agents.conversationOf(key);
    if (route == null || child == null) return;
    _Asker asker() =>
        (conversation: child, upstream: route.upstream, asks: entry.childAsks);
    // A session's subscribers hear what it buffered ahead of `connected`.
    void whenUp(void Function() go) {
      if (route.upstream == null) {
        route.held.add(go);
      } else {
        go();
      }
    }

    void up(Map<String, Object?> update, {String? subagentId}) {
      final upstream = route.upstream;
      if (upstream == null) return;
      final mapped = mapUpdate(
        upstream,
        capabilities ?? const {},
        update,
        subagentId: subagentId,
      );
      route.upstream = mapped.session;
      if (mapped.notification case final notification?) {
        _notify('session/update', notification);
      }
    }

    switch (event) {
      case Connected(:final sessionId):
        route.upstream = childSession(sessionId, route.upstreamId);
        final held = [...route.held];
        route.held.clear();
        for (final go in held) {
          go();
        }
      // A fresh session under the same identity: nothing of the last holds.
      case Cleared():
        route
          ..upstream = null
          ..stopReason = null
          ..gone = null
          ..failed = null
          ..held.clear();
      case ConnectFailed(:final message):
        route.failed = message;
      case Gone():
        route.gone = 'exited';
      case Transcribed(action: UpdateAction(:final update, :final subagentId)):
        whenUp(() => up(update.toJson(), subagentId: subagentId));
      case Transcribed(action: PromptAction(:final text, :final from)):
        route.stopReason = null;
        whenUp(
          () => up(
            messageChunk(route.upstreamId, text, from: from?.toJson())['update']
                as Map<String, Object?>,
          ),
        );
      case Transcribed(action: ResultAction(:final result)):
        if (result case TurnAnswered(:final stopReason)) {
          route.stopReason = stopReason;
        }
      case Transcribed(action: PermissionRequestedAction(:final wait)):
        whenUp(
          () => _once(
            entry,
            () => _askPermission(entry, asker(), wait.id, wait.subagentId),
          ),
        );
      case Transcribed(action: ElicitationRequestedAction(:final elicitation)):
        whenUp(
          () => _once(
            entry,
            () => _askElicitation(
              entry,
              asker(),
              elicitation.id,
              elicitation.subagentId,
            ),
          ),
        );
      case Transcribed(action: PlanRequestedAction(:final plan)):
        whenUp(() => _once(entry, () => _askPlan(entry, asker(), plan)));
      case MonitorsChanged():
        whenUp(() => _tellMonitors(route.upstreamId, event));
      default:
        if (_settledKey(event) case final settled?) {
          _withdrawChild(entry, settled);
        }
    }
    _report(entry, key);
  }

  /// Answers [request] once [entry] is up, or with its failure; a
  /// withdrawal while it starts closes it and answers -32800.
  void _up(AcpEntry entry, Served<Object?> request) {
    final withdrawn = OnCancel((_) {
      if (_closing.isCancelled || entry.opening == null) return;
      entry.opening = null;
      void cancelled([Object? _]) {
        _client.fail(request.id, requestCancelled(request.id));
        _unclaim(entry);
      }

      _closeEntry(entry).then(cancelled, onError: cancelled);
    });
    entry.opening = (requestId: request.id, withdrawn: withdrawn);
    withdrawn.listen(request.token);
  }

  _Asker _mainAsker(AcpEntry entry) => (
    conversation: entry.conversation,
    upstream: entry.upstream,
    asks: entry.asks,
  );

  void _heard(AcpEntry entry, ConversationEvent event) {
    // A launch let go: its calls to chord's server stop now.
    if (event is Cleared || event is Closing) entry.releaseMain();
    if (turnInputOf(event) case final input? when input is! TurnsDisconnected) {
      _step(entry, input);
      if (input is TurnEnded && entry.gone && entry.turns.lost == null) {
        _closeEntry(entry).ignore();
      }
    }
    switch (event) {
      case Transcribed(action: PermissionRequestedAction(:final wait)):
        _once(
          entry,
          () => _askPermission(
            entry,
            _mainAsker(entry),
            wait.id,
            wait.subagentId,
          ),
        );
      case Transcribed(action: PermissionSettledAction(:final id)):
        // The client's own answer has left the table already.
        _withdraw(entry, 'permission:$id');
      // Main's own forms go to the client raw; one that comes as an event
      // is a task's.
      case Transcribed(action: ElicitationRequestedAction(:final elicitation)):
        _once(
          entry,
          () => _askElicitation(
            entry,
            _mainAsker(entry),
            elicitation.id,
            elicitation.subagentId,
          ),
        );
      case Transcribed(action: ElicitationSettledAction(:final id)):
        _withdraw(entry, 'form:$id');
      case Transcribed(action: PlanRequestedAction(:final plan)):
        _once(entry, () => _askPlan(entry, _mainAsker(entry), plan));
      case Transcribed(action: PlanSettledAction(:final id)):
        _withdraw(entry, 'plan:$id');
      case HistoryReplayed(:final past?):
        // Its past is no news: kept for a load to relay ahead of its answer.
        entry.leftOpen = past.whereType<PastLeftOpen>().lastOrNull?.agents;
        entry.past?.addAll(past);
      case Connected(:final sessionId, :final state):
        entry.state = state;
        _connected(entry, sessionId);
      case ConnectFailed(:final message, :final signIn, :final failure):
        final opening = entry.opening;
        entry.opening = null;
        opening?.withdrawn.forget();
        final error = RpcException(
          signIn == null ? -32603 : -32000,
          message,
          data: {
            'lines': [
              ...failureLines(agent, failure),
              if (signIn != null) ...signInLines(agent, signIn),
            ],
          },
        );
        void failed([Object? _]) {
          if (opening != null) _client.fail(opening.requestId, error);
          _unclaim(entry);
        }

        _closeEntry(entry).then(failed, onError: failed);
      case AgentStateChanged(:final state):
        entry.state = state;
        _tellConfig(entry);
        _tellDimcode(entry, agent, state);
      case Transcribed(action: UpdateAction(:final update, :final subagentId)):
        _relay(entry, update.toJson(), subagentId: subagentId);
        if (subagentId == null) _tellConfig(entry);
      case Transcribed(action: FailedAction(:final turnId, :final message)):
        // A set the client asked for is that request's error instead.
        if (!RegExp(r'^(mode|model)-').hasMatch(turnId)) _warn(entry, message);
      case Transcribed(action: WarnedAction(:final message)):
        _warn(entry, message);
      case MonitorsChanged():
        // Its close stops them: no news to a client that closed it.
        _once(entry, () {
          if (entry.upstream case final upstream? when !entry.closed) {
            _tellMonitors(upstream.upstreamId, event);
          }
        });
      case Gone():
        entry.gone = true;
        _tellAccount();
        if (entry.upstream case final upstream?) {
          sessions.remove(upstream.upstreamId);
        }
        _step(entry, const TurnsDisconnected());
        // A turn lost with its agent still answers when its result comes.
        if (entry.turns.lost == null) _closeEntry(entry).ignore();
      default:
        break;
    }
    _tellState(entry);
  }

  /// [result] as a `session/prompt` answers it.
  static Object _answerOf(TurnResult result) => switch (result) {
    TurnFailed(:final message) => RpcException(-32603, message),
    TurnAnswered(:final stopReason, :final usage) => {
      'stopReason': stopReason,
      'usage': ?usage,
    },
  };

  void _step(AcpEntry entry, TurnInput input) {
    final (:turns, :sends) = reduceTurns(entry.turns, input);
    entry.turns = turns;
    if (input is TurnsClosing) entry.closed = true;
    for (final send in sends) {
      if (send
          case TurnAnswer(:final requestId) ||
              TurnCancelled(:final requestId) ||
              TurnSessionGone(:final requestId)) {
        entry.cancels.remove(requestId)?.forget();
      }
      switch (send) {
        case TurnAnswer(:final requestId, :final result):
          switch (_answerOf(result)) {
            case final RpcException error:
              _client.fail(requestId, error);
            case final answer:
              _client.respond(requestId, answer);
          }
        case TurnCancelled(:final requestId):
          _client.respond(requestId, const {'stopReason': 'cancelled'});
        case TurnSessionGone(:final requestId, :final turnId):
          _client.fail(
            requestId,
            sessionNotFound(entry.upstream?.upstreamId ?? ''),
          );
          // Not left for a dead session to play.
          entry.conversation.cancelPrompt(turnId);
        case TurnMessage(:final text, :final from):
          _relay(
            entry,
            messageChunk(
                  entry.upstream?.upstreamId ?? '',
                  text,
                  from: from,
                )['update']
                as Map<String, Object?>,
          );
      }
    }
  }

  /// Main's state, if it changed: its turn by who began it, and whether an
  /// ask of its own is open.
  void _tellState(AcpEntry entry) {
    final upstream = entry.upstream;
    if (upstream == null || !entry.live || entry.closed) return;
    final state = sessionStateOf(entry.turns, asking: entry.asks.isNotEmpty);
    final said = sessionStateParamsOf(state);
    if (said == entry.stateSent) return;
    entry.stateSent = said;
    _notify(
      '_chord/session/state',
      sessionStateParams(upstream.upstreamId, state),
    );
  }

  /// Runs [go] once the client has [entry]'s id; at once when it has.
  void _once(AcpEntry entry, void Function() go) {
    if (entry.live) {
      go();
    } else {
      entry.held.add(go);
    }
  }

  void _withdraw(AcpEntry entry, String key) {
    entry.asks.remove(key)?.cancel();
    _tellState(entry);
  }

  void _withdrawChild(AcpEntry entry, String key) =>
      entry.childAsks.remove(key)?.cancel();

  void _withdrawAll(AcpEntry entry) {
    for (final asks in [entry.asks, entry.childAsks]) {
      for (final key in [...asks.keys]) {
        asks.remove(key)?.cancel();
      }
    }
  }

  /// One request to the client under [key] in [asks], main's or the
  /// children's, settled once: a late answer, after its ask was withdrawn,
  /// finds nothing; an error is no answer, said on stderr. Nothing is
  /// settled once the connection went.
  void _ask(
    AcpEntry entry,
    Map<String, CancellationToken> asks,
    String key,
    String method,
    Map<String, Object?> params,
    void Function(Map<String, Object?>? answer) settle, {
    CancellationToken? token,
  }) {
    final withdrawn = CancellationToken();
    asks[key] = withdrawn;
    final asked = _chord.request(
      method,
      params,
      token: token == null
          ? withdrawn
          : MergedCancellationToken([withdrawn, token]),
    );
    // After the ask it describes is on its way.
    _tellState(entry);
    asked.then(
      (answer) {
        if (!identical(asks[key], withdrawn)) return;
        asks.remove(key);
        settle(answer is Map<String, Object?> ? answer : null);
        _tellState(entry);
      },
      onError: (Object error) {
        if (_closing.isCancelled || !identical(asks[key], withdrawn)) {
          return;
        }
        asks.remove(key);
        if (error is! CancelledException) {
          _say(
            'chord: the client answered $method with an error: '
            '${error is RpcException ? error.message : error}',
          );
        }
        settle(null);
        _tellState(entry);
      },
    );
  }

  bool get _takesSubagents => jsTruthy(capabilities?['subagents']);

  void _askPermission(
    AcpEntry entry,
    _Asker asker,
    String id,
    String? subagentId,
  ) {
    final conversation = asker.conversation;
    final request = conversation.permissionRequest(id);
    final upstream = asker.upstream;
    if (request == null || upstream == null) return;
    // A task's own agent asks under its own session, which the client
    // knows by the task's id.
    final named = subagentId ?? request.sessionId;
    // A session's own ask names no subagent, so one that names the session
    // is a task's agent passing itself off as it.
    if (!asksIn(upstream, named) || subagentId == upstream.agentId) {
      _say('chord: refused a permission for a session it does not know');
      conversation.reject(id);
      return;
    }
    // It can name no session that client knows, and must not wait unseen.
    if ((upstream.nested || named != upstream.agentId) && !_takesSubagents) {
      _say(
        "chord: refused a subagent's permission: the client takes no "
        'subagents',
      );
      conversation.reject(id);
      return;
    }
    final options = [
      for (final option in request.raw.toJson()['options'] as List)
        option as Map<String, Object?>,
    ];
    _ask(
      entry,
      asker.asks,
      'permission:$id',
      'session/request_permission',
      {...request.raw.toJson(), 'sessionId': upstreamIdOf(upstream, named)},
      (answer) {
        if (permissionAnswerOf(options, answer) case final chosen?) {
          conversation.choose(id, chosen);
        } else {
          conversation.reject(id);
        }
      },
    );
  }

  /// A form or link waiting in a conversation, a child's or a task's, put
  /// to the client under the id it knows its asker by.
  void _askElicitation(
    AcpEntry entry,
    _Asker asker,
    String id,
    String? subagentId,
  ) {
    final conversation = asker.conversation;
    final request = conversation.elicitationRequest(id);
    final upstream = asker.upstream;
    if (request == null || upstream == null) return;
    final asked = request.sessionId;
    final sessionId = asked == null ? null : subagentId ?? asked;
    // One scoped to a request names none of the client's.
    if (sessionId == null || !asksIn(upstream, sessionId)) {
      conversation.answer(id, const CancelReply());
      return;
    }
    // A subagent's names none that client knows, and must not wait unseen.
    if ((upstream.nested || sessionId != upstream.agentId) &&
        !_takesSubagents) {
      _say("chord: refused a subagent's form: the client takes no subagents");
      conversation.answer(id, const CancelReply());
      return;
    }
    _ask(
      entry,
      asker.asks,
      'form:$id',
      'elicitation/create',
      {...request.raw, 'sessionId': upstreamIdOf(upstream, sessionId)},
      (answer) => conversation.answer(id, _replyOf(elicitationReplyOf(answer))),
    );
  }

  /// [reply] as the client sent it, as the conversation answers it.
  static ElicitationReply _replyOf(Map<String, Object?> reply) =>
      switch (reply['action']) {
        'accept' => AcceptReply(switch (reply['content']) {
          final Map<String, Object?> content => content,
          _ => null,
        }),
        'decline' => const DeclineReply(),
        _ => const CancelReply(),
      };

  /// A plan put to the client as an ordinary permission, its answer the
  /// agent's in its own words, never a yes but the client's.
  void _askPlan(AcpEntry entry, _Asker asker, PlanWait plan) {
    final conversation = asker.conversation;
    final upstream = asker.upstream;
    // It can name no session that client knows, and is never a yes.
    if (upstream != null && upstream.nested && !_takesSubagents) {
      _say("chord: refused a subagent's plan: the client takes no subagents");
      conversation.answerPlan(plan.id, const PlanCancelled());
      return;
    }
    _ask(
      entry,
      asker.asks,
      'plan:${plan.id}',
      'session/request_permission',
      planPermission(upstream?.upstreamId ?? '', plan),
      (answer) => conversation.answerPlan(plan.id, planAnswerOf(plan, answer)),
    );
  }

  var _forms = 0;

  /// A form or a link the agent asks for, relayed raw once the client has
  /// the session's id: a request-scoped one, or one naming a session not
  /// announced, is cancelled; [token] withdraws it.
  Future<Map<String, Object?>> _askForm(
    AcpEntry entry,
    Map<String, Object?> params,
    CancellationToken token,
  ) {
    final answered = Completer<Map<String, Object?>>();
    void cancelled() {
      if (!answered.isCompleted) answered.complete(const {'action': 'cancel'});
    }

    _once(entry, () {
      // Withdrawn while it was held, by a turn's cancel or the close: as
      // the original finds no request left, nothing is forwarded.
      if (token.isCancelled) return cancelled();
      final upstream = entry.upstream;
      final sessionId = params['sessionId'];
      if (upstream == null ||
          sessionId is! String ||
          !asksIn(upstream, sessionId)) {
        return cancelled();
      }
      if (sessionId != upstream.agentId && !_takesSubagents) {
        _say("chord: refused a subagent's form: the client takes no subagents");
        return cancelled();
      }
      _ask(
        entry,
        entry.asks,
        // Never a conversation's own id, which a task's form goes under.
        'form:${++_forms}',
        'elicitation/create',
        {...params, 'sessionId': upstreamIdOf(upstream, sessionId)},
        (answer) {
          if (!answered.isCompleted) {
            answered.complete(elicitationReplyOf(answer));
          }
        },
        token: token,
      );
    });
    return answered.future;
  }

  void _prompt(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final params = request.params;
    final entry = _named(params['sessionId'] as String);
    final command = commandOf([
      for (final block in params['prompt'] as List)
        block as Map<String, Object?>,
    ]);
    if (command != null && !command.alone) {
      return _commandAnswered(entry, request.id, command.name, (
        text: notAloneRefusal(command.name),
        failed: true,
      ));
    }
    final asked = command?.name == 'team'
        ? teamCommand(command!.args, acpTeamWords)
        : null;
    if (asked != null && asked is! TeamNew) {
      return _commanding(entry, request.id, 'team', _teamSaid(entry, asked));
    }
    if (command?.name == 'new') {
      return _commanding(
        entry,
        request.id,
        'new',
        entry.host
            .newTyped(command!.args, show: (_) {})
            .then(
              (answer) => switch (answer) {
                Started(:final name, :final agent, :final note) => (
                  text: openedText(name, agent, note),
                  failed: false,
                ),
                Refused(:final error) => (text: error, failed: true),
              },
            ),
      );
    }
    final (:prompt, :refused) = _promptOf(entry, params['prompt']);
    if (refused != null) throw RpcException(-32602, 'Invalid params: $refused');
    final turnId = 'acp-${++_turnIds}';
    // Before the send, which emits before it returns, and with no await
    // since the request came, or a cancel could pass it.
    _step(entry, TurnBind(request.id, turnId));
    // Forgotten once the prompt is answered, however that comes.
    entry.cancels[request.id] = OnCancel((_) {
      // The connection's end cancels this too, and is no client's cancel.
      if (_closing.isCancelled) return;
      if (turnOf(entry.turns, request.id) case final running?) {
        entry.conversation.cancelPrompt(running);
      }
    })..listen(request.token);
    if (!entry.conversation.sendTurn(
      turnId,
      // `/team new` is a turn of the agent's, its words after the line
      // that names propose_team.
      asked is TeamNew ? newTeamPrompt(asked.words) : prompt!.text,
      parts: prompt!.parts,
    )) {
      entry.cancels.remove(request.id)?.forget();
      _step(entry, TurnUnbind(turnId));
      throw sessionNotFound(params['sessionId'] as String);
    }
  }

  static const CommandSaid _closedSaid = (
    text: 'This session has closed',
    failed: true,
  );

  /// `/team`'s forms but `new`, which is a turn of the agent's, in the
  /// words a client's own interface shows.
  Future<CommandSaid> _teamSaid(AcpEntry entry, TeamCommand asked) async {
    final host = entry.host;
    switch (asked) {
      case TeamRefused(:final problem):
        return (text: problem, failed: true);
      case TeamList():
        final listing = await host.listTeams();
        return listing == null
            ? _closedSaid
            : (
                text: teamsText(listing, DateTime.now().millisecondsSinceEpoch),
                failed: false,
              );
      case TeamShow(:final name):
        // An open selected run: only a window draws its receipt.
        if (host.selectedRunId(name) case final runId?) {
          return (text: selectedRunRefusal(name, runId), failed: true);
        }
        String? running;
        final answer = await host.showTyped(name, (
          file,
          lead,
          team,
          job,
          members,
        ) {
          running = runText(
            name: lead.name,
            file: file,
            team: team,
            job: job,
            since: lead.info.openedAt,
            open: [for (final member in members) member.name],
            now: DateTime.now().millisecondsSinceEpoch,
          );
          return ShownTeam(name: name, file: file, team: team);
        });
        final shown = answer.shown;
        return switch (shown) {
          TeamReceiptShown(:final call) => (
            text: selectedRunRefusal(
              name,
              recordedSelection(call)?['runId'] as String? ?? name,
            ),
            failed: true,
          ),
          ShownTeam(:final name, :final file, :final team) => (
            text: running ?? teamText(name, file, team),
            failed: false,
          ),
          _ => (text: answer.refused ?? _closedSaid.text, failed: true),
        };
      case TeamRunJob(:final name, :final job):
        final answer = await host.runTyped(name, job);
        final ran = answer.ran?.answer;
        return ran is Map
            ? (
                text: startedText(
                  name,
                  ran['name'] as String,
                  ran['note'] as String?,
                ),
                failed: false,
              )
            : (text: answer.refused ?? _closedSaid.text, failed: true);
      case TeamStop(:final name):
        var said = _closedSaid;
        host.stopTyped(name, acpTeamWords, (text, {required failed}) {
          said = (text: text, failed: failed);
        });
        return said;
      case TeamNew():
        return _closedSaid;
    }
  }

  var _turnIds = 0;

  ({UpstreamPrompt? prompt, String? refused}) _promptOf(
    AcpEntry entry,
    Object? blocks,
  ) {
    final session = entry.conversation.session;
    return promptOf(
      [for (final block in blocks as List) block as Map<String, Object?>],
      agent,
      takesImages: session?.takesImages() ?? false,
      takesEmbeddedContext: session?.takesEmbeddedContext() ?? false,
    );
  }

  void _cancel(Map<String, Object?> params) {
    final sessionId = params['sessionId'] as String;
    // As the original, the interrupt alone: an ask goes with the cancel of
    // the turn or cycle it came in, and one asked between turns stays open.
    if (sessions[sessionId] case final entry?) {
      return entry.conversation.interrupt();
    }
    for (final entry in [..._entries]) {
      if (_cancelledIn(entry, sessionId)) return;
    }
  }

  /// A cancel of a child of [entry], if [sessionId] names one: a
  /// long-lived one's turn stops and it stays open, a task of chord's
  /// ends as the person's `x` ends it, and an agent's own subagent is
  /// stopped by its agent.
  bool _cancelledIn(AcpEntry entry, String sessionId) {
    final askers = <(Conversation?, UpstreamSession?)>[
      (entry.conversation, entry.upstream),
    ];
    for (final MapEntry(:key, value: route) in entry.routes.entries) {
      final child = entry.agents.conversationOf(key);
      if (route.upstreamId == sessionId) {
        child?.interrupt();
        return true;
      }
      if (child != null) askers.add((child, route.upstream));
    }
    for (final (conversation, upstream) in askers) {
      final id = upstream == null ? null : childOf(upstream, sessionId);
      if (id == null) continue;
      if (conversation?.task(id) case final task?) {
        task.cancel(TaskStop.x);
      } else {
        // The subagent may have ended before the stop landed.
        conversation?.stopSubagent(id).catchError((Object _) {});
      }
      return true;
    }
    return false;
  }

  /// The long-lived child the client names [sessionId], open and not gone;
  /// a task, an adapter's subagent or a closed child is no such child.
  ({AcpEntry entry, int key, Child<Conversation> child, ChildRoute route})
  _childNamed(String sessionId) {
    for (final entry in _entries) {
      for (final MapEntry(:key, value: route) in entry.routes.entries) {
        final child = agentOf(entry.agents.agents, key)?.child;
        if (route.upstreamId == sessionId &&
            route.gone == null &&
            child != null) {
          return (entry: entry, key: key, child: child, route: route);
        }
      }
    }
    throw sessionNotFound(sessionId);
  }

  /// `_chord/agents/close` on a task of chord's the client names
  /// [sessionId]: a running one stopped as a cancel with no key stops it,
  /// and one ended said to be. None when it names no task.
  Map<String, Object?>? _taskClosed(String sessionId) {
    for (final entry in _entries) {
      final owners = [
        (entry.key, entry.upstream),
        for (final MapEntry(:key, value: route) in entry.routes.entries)
          (key, route.upstream),
      ];
      for (final (key, upstream) in owners) {
        final id = key == null || upstream == null
            ? null
            : childOf(upstream, sessionId);
        if (key == null || id == null) continue;
        final (:running, :ended) = entry.host.tasksNamed(key, id);
        if (running.firstWhereOrNull((each) => each.id == id)
            case final task?) {
          task.cancel();
          return {
            'closed': [task.start.name],
          };
        }
        if (ended.firstWhereOrNull((each) => each.id == id) case final done?) {
          return {
            'closed': <String>[],
            'ended': [done.name],
          };
        }
      }
    }
    return null;
  }

  Map<String, Object?> _sendAgent(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final params = request.params;
    final sessionId = params['sessionId'] as String;
    final (:entry, :key, :child, :route) = _childNamed(sessionId);
    final conversation = child.conversation;
    // Its start failed: nothing takes the words until it is cleared.
    if (route.failed != null) throw sessionNotFound(sessionId);
    // As in the window, nothing is held for a child not up: the person
    // sends again once it is.
    if (entry.host.isClearing(key)) {
      throw RpcException(
        -32603,
        '${child.name} is being cleared; send once its subagent_update says '
        'idle',
      );
    }
    final session = conversation.session;
    if (session == null) {
      throw RpcException(
        -32603,
        '${child.name} is starting; send once its subagent_update says idle',
      );
    }
    final (:prompt, :refused) = promptOf(
      [
        for (final block in params['prompt'] as List)
          block as Map<String, Object?>,
      ],
      child.runtime,
      takesImages: session.takesImages(),
      takesEmbeddedContext: session.takesEmbeddedContext(),
    );
    if (refused != null) throw RpcException(-32602, 'Invalid params: $refused');
    final busy = agentStateOf(entry.folds[key] ?? noFold)['state'] != 'idle';
    if (!conversation.send(prompt!.text, prompt.text, const [], prompt.parts)) {
      throw sessionNotFound(sessionId);
    }
    return {'delivery': busy ? 'queued' : 'sent'};
  }

  /// A session's monitors, as its [MonitorsChanged] has them, whole.
  void _tellMonitors(String sessionId, MonitorsChanged event) =>
      _notify('_chord/monitors/changed', {
        'sessionId': sessionId,
        'running': [for (final monitor in event.running) monitor.toJson()],
        'ended': [for (final monitor in event.ended) monitor.toJson()],
      });

  /// `_chord/monitors/stop`: a session's own monitor stopped, as its
  /// agent's `stop_monitor` stops it; a refusal is -32002 with its words.
  Map<String, Object?> _stopMonitor(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final params = request.params;
    final sessionId = params['sessionId'] as String;
    final main = sessions[sessionId];
    final (entry, agent) = switch (main) {
      final main? => (main, null),
      null => switch (_childNamed(sessionId)) {
        (:final entry, :final child, key: _, route: _) => (entry, child.id),
      },
    };
    final key = entry.key;
    if (key == null) throw sessionNotFound(sessionId);
    return switch (entry.host.stopMonitorOf(
      key,
      agent,
      params['id'] as String,
    )) {
      Refused(:final error) => throw RpcException(-32002, error),
      final stopped => stopped.toJson(),
    };
  }

  Map<String, Object?> _closeAgent(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final sessionId = request.params['sessionId'] as String;
    if (_taskClosed(sessionId) case final task?) return task;
    final (:entry, :key, :child, route: _) = _childNamed(sessionId);
    final name = child.name;
    entry.host.closeByPerson(key);
    // A lead's members join its names with CTUI-37.
    return {
      'closed': [name],
    };
  }

  /// The `session/prompt` requests a command of chord's answers, by id.
  final _commands = <Object?>{};

  /// What [name] came to, as one chunk ahead of its answer: not an error,
  /// as nothing failed at the protocol's level, and no turn of the agent's.
  void _commandAnswered(
    AcpEntry entry,
    Object? requestId,
    String name,
    CommandSaid said,
  ) {
    _notify(
      'session/update',
      commandChunk(
        entry.upstream?.upstreamId ?? '',
        name,
        said.text,
        said.failed,
      ),
    );
    _client.respond(requestId, {'stopReason': 'end_turn'});
  }

  /// Answered by [work], or once by the way out, whichever comes first.
  void _commanding(
    AcpEntry entry,
    Object? requestId,
    String name,
    Future<CommandSaid> work,
  ) {
    _commands.add(requestId);
    work.then(
      (said) {
        if (_commands.remove(requestId)) {
          _commandAnswered(entry, requestId, name, said);
        }
      },
      onError: (Object error) {
        if (_commands.remove(requestId)) _client.fail(requestId, error);
      },
    );
  }

  Map<String, Object?> _steer(Served<Map<String, Object?>> request) {
    _refuseIfClosing();
    final params = request.params;
    final sessionId = params['sessionId'] as String;
    final entry = _named(sessionId);
    final (:prompt, :refused) = _promptOf(entry, params['prompt']);
    if (refused != null) throw RpcException(-32602, 'Invalid params: $refused');
    final turnId = 'acp-${++_turnIds}';
    // Before the send: a turn of its own is then the client's, and its
    // words are not told back.
    _step(entry, TurnSteered(turnId));
    if (!entry.conversation.sendTurn(
      turnId,
      prompt!.text,
      parts: prompt.parts,
    )) {
      _step(entry, TurnUnbind(turnId));
      throw sessionNotFound(sessionId);
    }
    // Its own entry, not the oldest: another may be queued ahead.
    return {
      'delivery': entry.conversation.steerQueued(turnId) == 'sent'
          ? 'sent'
          : 'queued',
    };
  }

  void _connected(AcpEntry entry, String agentId) {
    final opening = entry.opening;
    if (opening == null) return;
    opening.withdrawn.forget();
    // A reopened session is under the id the client asked for, claimed for
    // it; anything else keeps clear of what is claimed and what is live.
    final upstreamId = entry.reopens == agentId
        ? agentId
        : aliasFor({...sessions.keys, ...reopening}, agentId);
    final (session: upstream, :configOptions) = answeredConfig(
      UpstreamSession(agentId, upstreamId),
      entry.state,
    );
    entry.upstream = upstream;
    entry.opening = null;
    sessions[upstreamId] = entry;
    final session = entry.conversation.session;
    session?.subscribeAccount((_) => _tellAccount());
    _tellAccount();
    // The client asked for this id: a load's past goes ahead of the answer.
    // A new id goes first, as nothing of the session is placed without it.
    final past = entry.past;
    if (past != null) {
      entry.live = true;
      for (final event in past) {
        switch (event) {
          case PastPrompt(:final text, :final from):
            _relay(
              entry,
              messageChunk(upstreamId, text, from: from)['update']
                  as Map<String, Object?>,
            );
          case PastUpdate(:final update, :final subagentId):
            _relay(entry, update, subagentId: subagentId);
          case PastRenamed(:final title):
            // chord's own line, said as the agent here, chord, says a title.
            _relay(entry, {
              'sessionUpdate': 'session_info_update',
              'title': title,
            });
          case PastLeftOpen():
            break;
        }
      }
      past.clear();
    }
    _client.respond(opening.requestId, {
      if (entry.reopens == null) 'sessionId': upstreamId,
      'configOptions': configOptions,
      '_meta': {
        acpMeta: {
          'image': session?.takesImages() ?? false,
          'embeddedContext': session?.takesEmbeddedContext() ?? false,
        },
        if (session != null && session.heldBack.isNotEmpty)
          'chord/held_back': [
            for (final held in session.heldBack) held.toJson(),
          ],
        'chord/left_open': ?entry.leftOpen,
      },
    });
    _unclaim(entry);
    _tellDimcode(entry, agent, entry.state);
    // An agent that sends no list still shows chord's, once its session is
    // answered and what it held has gone, whichever way it opened.
    if (past != null) {
      _release(entry);
      _output.expect(opening.requestId).then((_) => _tellCommands(entry));
    } else {
      // Nothing of the session goes before the client has its id.
      _output.expect(opening.requestId).then((_) {
        _release(entry);
        _tellCommands(entry);
      });
    }
  }

  void _tellCommands(AcpEntry entry) {
    final upstream = entry.upstream;
    if (upstream == null) return;
    final (:session, :notification) = commandsIfNone(upstream);
    entry.upstream = session;
    if (notification != null) _notify('session/update', notification);
  }

  void _release(AcpEntry entry) {
    entry.live = true;
    for (final go in [...entry.held]) {
      go();
    }
    entry.held.clear();
    _tellConfig(entry);
    _tellState(entry);
  }

  void _relay(
    AcpEntry entry,
    Map<String, Object?> update, {
    String? subagentId,
  }) {
    final upstream = entry.upstream;
    if (upstream == null || !entry.live) {
      entry.held.add(() => _relay(entry, update, subagentId: subagentId));
      return;
    }
    final mapped = mapUpdate(
      upstream,
      capabilities ?? const {},
      update,
      subagentId: subagentId,
    );
    entry.upstream = mapped.session;
    if (mapped.notification case final notification?) {
      _notify('session/update', notification);
    }
  }

  void _tellConfig(AcpEntry entry) {
    final upstream = entry.upstream;
    if (upstream == null || !entry.live) return;
    final changed = configChange(upstream, entry.state);
    entry.upstream = changed.session;
    if (changed.notification case final notification?) {
      _notify('session/update', notification);
    }
  }

  /// What chord carries on past: stderr always, and `notice` for who takes
  /// it.
  void _warn(AcpEntry entry, String message) {
    _say('chord: $message');
    _relay(entry, {
      'sessionUpdate': 'notice',
      'severity': 'warning',
      'title': message,
    });
  }

  /// dimcode's notice, once a session's, if [runtime] has it at risk.
  void _tellDimcode(AcpEntry entry, String runtime, AgentState state) {
    if (entry.noticed ||
        !dimcodeAtRisk(
          runtime,
          optionsFromConfigOptions(state.configOptions),
        )) {
      return;
    }
    entry.noticed = true;
    for (final paragraph in dimcodeWords.paragraphs) {
      _say('chord: $paragraph');
    }
    _relay(entry, {
      'sessionUpdate': 'notice',
      'severity': 'warning',
      'title': dimcodeWords.title,
      'description': dimcodeWords.paragraphs.join('\n\n'),
    });
  }

  Future<void> _closeEntry(AcpEntry entry) {
    if (entry.closing case final closing?) return closing.future;
    entry.host.shutDown();
    for (final key in [...entry.routes.keys]) {
      _tellClosed(entry, key);
    }
    final closing = entry.agents
        .closeAll()
        .catchError(
          (Object error) => throw switch (error) {
            // Each agent's own words, for stderr to say what did not close.
            CloseFailures(errors: [final only]) => only,
            CloseFailures(:final errors) => StateError(
              errors.map(_closeWords).join('; '),
            ),
            _ => error,
          },
        )
        .whenComplete(() {
          _entries.remove(entry);
          _tellAccount();
        });
    entry.closing = Kept(closing);
    return closing;
  }

  static String _closeWords(Object error) => switch (error) {
    StateError(:final message) => message,
    _ => '$error',
  };

  /// Where `auth/status` is read: the oldest session still live, as the
  /// method names none, so no other's account is mixed in.
  AcpEntry? get _accountSource {
    for (final entry in _entries) {
      if (!entry.gone &&
          entry.closing == null &&
          entry.conversation.session != null) {
        return entry;
      }
    }
    return null;
  }

  /// The source's account, `unknown` while it has said none or there is
  /// none.
  Map<String, Object?> _sourceStatus() =>
      switch (_accountSource?.conversation.session?.account) {
        AccountHeard(:final status) => status,
        _ => const {'state': 'unknown'},
      };

  /// What the client was last told of the account, its keys in order, so
  /// only a change of value goes.
  String _toldAccount = _canonical(const {'state': 'unknown'});

  void _tellAccount() {
    final status = _sourceStatus();
    final said = _canonical(status);
    if (said == _toldAccount) return;
    _toldAccount = said;
    _notify('auth/status_update', status);
  }

  /// [value] as JSON with every object's keys sorted.
  static String _canonical(Object? value) {
    Object? sorted(Object? value) => switch (value) {
      final Map map => {
        for (final key in (map.keys.map((key) => '$key').toList()..sort()))
          key: sorted(map[key]),
      },
      final List list => [for (final each in list) sorted(each)],
      _ => value,
    };
    return jsonEncode(sorted(value));
  }

  /// An agent's refusal as it gave it; anything else -32603 in its words.
  static RpcException _refusal(Object error) => switch (error) {
    RpcException() => error,
    _ => RpcException(-32603, agentMessageOf(error)),
  };

  Future<Map<String, Object?>> _setConfigOption(
    Served<Map<String, Object?>> request,
  ) async {
    _refuseIfClosing();
    final params = request.params;
    final sessionId = params['sessionId'] as String;
    final configId = params['configId'] as String;
    final entry = _named(sessionId);
    final setter = configSetter(entry.state, configId);
    final value = params['value'];
    if (setter == null || value is! String || params['type'] == 'boolean') {
      throw RpcException(
        -32602,
        'Invalid params: No option $configId takes that value.',
      );
    }
    final conversation = entry.conversation;
    try {
      await switch (setter) {
        ConfigSetter.mode => conversation.setMode(value),
        ConfigSetter.model => conversation.setModel(value),
        ConfigSetter.option => conversation.setOption(configId, value),
      };
    } catch (error) {
      throw _refusal(error);
    }
    final upstream = entry.upstream;
    if (upstream == null) throw sessionNotFound(sessionId);
    final (session: told, :configOptions) = answeredConfig(
      upstream,
      entry.state,
    );
    entry.upstream = told;
    return {'configOptions': configOptions};
  }

  Future<Map<String, Object?>> _setMode(
    Served<Map<String, Object?>> request,
  ) async {
    _refuseIfClosing();
    final entry = _named(request.params['sessionId'] as String);
    try {
      await entry.conversation.setMode(request.params['modeId'] as String);
    } catch (error) {
      throw _refusal(error);
    }
    return const {};
  }

  /// A live session is renamed as the window renames it; one listed and not
  /// loaded is recorded, for its agent to be told at the next load.
  Future<Map<String, Object?>> _setTitle(
    Served<Map<String, Object?>> request,
  ) async {
    _refuseIfClosing();
    final sessionId = request.params['sessionId'] as String;
    final title = (request.params['title'] as String)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) {
      throw RpcException(-32602, 'Invalid params: The title is empty.');
    }
    if (sessions[sessionId] case final entry?) {
      final RenameTaken? renamed;
      try {
        renamed = await entry.conversation.rename(title);
      } catch (error) {
        throw _refusal(error);
      }
      if (renamed == null) throw sessionNotFound(sessionId);
      return {'title': renamed.title};
    }
    // Only the records naming the id: the listing's newest of them is the
    // same as on the full scan.
    final listed = earlierSessions(
      await _recordsWithId(sessionId),
      agent: agent,
    ).where((earlier) => earlier.resume.sessionId == sessionId).firstOrNull;
    final record = listed?.resume.record;
    if (record == null) throw sessionNotFound(sessionId);
    await recordPendingRename(
      record,
      title,
      DateTime.now().millisecondsSinceEpoch,
    );
    return {'title': title};
  }

  /// The way out's answers, on a signal or a crash only: every session
  /// still opening refused, each answer expected.
  void _answerAll() {
    // Refused now, before the connection closes; what they read finds them
    // answered.
    for (final requestId in [..._placing]) {
      _output.expect(requestId);
      _client.fail(requestId, closingError());
    }
    for (final requestId in [..._commands]) {
      _output.expect(requestId);
      _client.respond(requestId, {'stopReason': 'cancelled'});
    }
    _commands.clear();
    for (final entry in [..._entries]) {
      for (final requestId in entry.turns.bound.values) {
        _output.expect(requestId);
      }
      _step(entry, const TurnsClosing());
      _withdrawAll(entry);
      if (entry.opening case final opening?) {
        entry.opening = null;
        opening.withdrawn.forget();
        _output.expect(opening.requestId);
        _client.fail(opening.requestId, closingError());
        _unclaim(entry);
      }
    }
  }

  void _closeConnection() {
    _closing.cancel();
    _onClosed?.call();
    // Releases every ask still waiting on the client, withdrawn ones too.
    _chord.close().ignore();
    _output.close();
  }

  /// How many of chord's requests to the client wait for an answer.
  int get asking => _chord.waiting;
}

/// Serves ACP on [input] to [sink] until the way out, which [exit] ends:
/// each line decoded and handled in order, a framing error answered,
/// [input]'s end the way out as `eof`, an oversized line or a failed write
/// as `broken`.
AcpHost runAcp({
  required Stream<List<int>> input,
  required OutputSink sink,
  required String agent,
  required String version,
  required PlaceReader place,
  required String stateDir,
  required void Function(String line) stderr,
  required void Function(LeaveExit how) exit,
  AgentLauncher launch = launchAgent,
  Future<List<SessionRecord>> Function()? records,
  Future<List<SessionRecord>> Function(String id)? recordsWithId,
  Recording Function(void Function(String message) failed)? recording,
  ProcessGroups? groups,
  Duration leaveTime = leaveTime,
  Duration drainTime = drainTime,
  ChordServer? server,
  Resources? resources,
  ChildrenReader? children,
  Recording Function(RecordChild child)? childRecording,
  String? configHome,
  String? home,
}) {
  late final AcpHost host;
  void say(String line) {
    try {
      stderr(line);
    } catch (_) {}
  }

  final output = Output(
    sink,
    onFailed: (error) {
      if (host.leaving) return;
      say('chord: the connection closed: $error');
      host.leave(const LeaveBroken());
    },
  );
  host = AcpHost(
    agent: agent,
    version: version,
    output: output,
    place: place,
    stateDir: stateDir,
    stderr: stderr,
    exit: exit,
    launch: launch,
    records: records,
    recordsWithId: recordsWithId,
    recording: recording,
    groups: groups,
    leaveTime: leaveTime,
    drainTime: drainTime,
    server: server,
    resources: resources,
    children: children,
    childRecording: childRecording,
    configHome: configHome,
    home: home,
  );
  final decoder = LineDecoder();
  void framed(Framed framed) => switch (framed) {
    FramedMessage(:final message) => host.hear(message),
    FramingReply(:final reply) => output.send(reply),
  };
  late final StreamSubscription<List<int>> reading;
  reading = input.listen(
    (chunk) {
      try {
        decoder.add(chunk, framed);
      } on MessageTooLargeError catch (error) {
        if (host.leaving) return;
        say('chord: the connection closed: $error');
        host.leave(const LeaveBroken());
      }
    },
    onDone: () {
      if (host.leaving) return;
      decoder.close(framed);
      host.leave(const LeaveEof());
    },
    onError: (Object error) {
      if (host.leaving) return;
      say('chord: the connection closed: $error');
      host.leave(const LeaveBroken());
    },
  );
  host.onClosed = () => reading.cancel();
  return host;
}

/// The signal [reason] dies by, for a caller that watches signals.
ProcessSignal? signalOf(LeaveReason reason) =>
    reason is LeaveSignal ? reason.signal : null;

/// What `chord acp` serves once its call is accepted: [agent] as [flags]
/// name it, the launch directory [cwd]'s settings [launched] read once.
final class AcpStart {
  /// A start of [agent] from [cwd].
  const AcpStart({
    required this.agent,
    required this.flags,
    required this.launched,
    required this.noMcpServers,
    required this.cwd,
    required this.configHome,
    required this.home,
  });

  /// The agent every session starts, by the name chord knows it.
  final String agent;

  /// The command line's own values.
  final Flags flags;

  /// The launch directory's settings, read once.
  final LoadedSettings launched;

  /// `--no-mcp-servers`.
  final bool noMcpServers;

  /// The launch directory.
  final String cwd;

  /// Where the user's settings are.
  final String? configHome;

  /// The person's home, for the paths stderr shows.
  final String? home;
}

/// `chord acp` on a process's streams: [start] served on [input] and
/// [sink] until the way out, which ends in [exit]. The by-hand note goes
/// first when [stdinIsTerminal]; each of [signals] starts the way out, and
/// an error nothing caught is a crash, its stack said on [stderr]. [server]
/// is chord's own MCP server, which every session's agents are admitted to.
AcpHost serveAcp(
  AcpStart start, {
  required Stream<List<int>> input,
  required OutputSink sink,
  required void Function(String line) stderr,
  required void Function(LeaveExit how) exit,
  required bool stdinIsTerminal,
  List<ProcessSignal> signals = leaveSignals,
  Stream<ProcessSignal> Function(ProcessSignal signal)? watch,
  AgentLauncher launch = launchAgent,
  String? stateDir,
  McpReader readMcp = loadMcpServers,
  ChordServer? server,
  Resources? resources,
}) {
  void say(String line) {
    try {
      stderr(line);
    } catch (_) {
      // A stderr gone is no reason to stop serving.
    }
  }

  AcpHost? host;
  final watching = <StreamSubscription<ProcessSignal>>[];
  runZonedGuarded(
    () {
      for (final line in byHandNote(stdinIsTerminal: stdinIsTerminal)) {
        say(line);
      }
      final served = host = runAcp(
        input: input,
        sink: sink,
        agent: start.agent,
        version: chord.version,
        place: placeReader(
          agent: start.agent,
          launchDir: start.cwd,
          launched: start.launched,
          flags: start.flags,
          noMcpServers: start.noMcpServers,
          configHome: start.configHome,
          home: start.home,
          readMcp: readMcp,
          report: (found) {
            for (final problem in found) {
              say(problemLine(problem));
            }
          },
        ),
        children: childrenReader(
          agent: start.agent,
          launchDir: start.cwd,
          launched: start.launched,
          flags: start.flags,
          noMcpServers: start.noMcpServers,
          configHome: start.configHome,
          home: start.home,
          readMcp: readMcp,
        ),
        server: server,
        resources: resources,
        configHome: start.configHome,
        home: start.home,
        stateDir: stateDir ?? chordStateDir(),
        stderr: say,
        exit: (how) {
          // Off first, so a signal raised again is not heard again.
          for (final subscription in watching) {
            subscription.cancel();
          }
          exit(how);
        },
        launch: launch,
      );
      for (final signal in signals) {
        watching.add(
          (watch ?? (signal) => signal.watch())(
            signal,
          ).listen((_) => served.leave(LeaveSignal(signal)).ignore()),
        );
      }
    },
    (error, stack) {
      say('$error');
      say('$stack');
      host?.leave(const LeaveCrash()).ignore();
    },
  );
  return host!;
}

/// How `chord acp` ends the process once its way out is done: by [how]'s
/// signal at once, through [raise]; else with its code through [exit], once
/// [flush] has written stderr's last lines or [bound] has passed. Node
/// writes stderr to a pipe at once; Dart queues it, and a stderr nobody
/// reads holds chord no longer than the bound.
Future<void> exitAcp(
  LeaveExit how, {
  required Future<void> Function() flush,
  required void Function(int code) exit,
  required void Function(ProcessSignal signal) raise,
  Duration bound = drainTime,
}) async {
  if (how.signal case final signal?) return raise(signal);
  try {
    await flush().timeout(bound);
  } catch (_) {
    // A stderr gone or held is no reason to stay.
  }
  exit(how.code!);
}
