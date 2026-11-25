/// The window's agents as chord's tools see them: long-lived children
/// opened where main works, each admitted to chord's server for each of its
/// launches, the messages sent to one still starting held until it is up,
/// main told of a child that did not start, closes and clears, and the
/// task agents main or a child starts with spawn_task. From the original's
/// `session/agents_host.ts`.
library;

import 'dart:async';
import 'dart:io' show Directory;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../acp/schema.dart' as acp show PermissionOption;
import '../agent_name.dart';
import '../settings.dart' show SettingChange, homePath, readTeamSelection;
import '../teams.dart';
import 'team_command.dart'
    show
        ListedTeam,
        TeamListing,
        TeamRun,
        TeamWords,
        ranNote,
        stoppedLine,
        teamRefusal;
import '../settings_tool.dart' show SettingsWhere;
import '../server/runtimes.dart';
import '../server/server.dart';
import '../acp/connection.dart' show Traffic;
import '../server/tools.dart' hide Cleared, Delivery;
import '../server/tools.dart' as tools show Cleared, Delivery;
import 'conversation.dart';
import 'efforts.dart';
import 'initial_options.dart' show InitialValues;
import 'models.dart';
import 'modes.dart' show modesFrom;
import 'new_args.dart';
import 'open_agents.dart';
import 'place.dart' show SessionStart;
import 'budgets.dart';
import 'record.dart' show RecordChild, Recording;
import 'resource_access.dart';
import 'session.dart';
import 'sign_in.dart' show signInNote;
import 'start_failure.dart' show failureNote, sentence, stepWords;
import 'starting.dart';
import 'tasks.dart';
import 'team_selection.dart';
import 'transcript/subagents.dart' show isRunning, subagentsIn;
import 'transcript/types.dart';
import 'window_agents.dart';
import 'monitors.dart' show MonitorArgs, RunningMonitor;
import 'window_monitors.dart';

/// Opens a child's session of a runtime, started as its start says, given
/// chord's server entry for its launch.
typedef OpenChildSession =
    Future<Session> Function(
      String runtime,
      SessionStart start, {
      required InitialValues initial,
      Map<String, Object?>? chordServer,
      required void Function(Traffic traffic) onTraffic,
      required CancellationToken cancellationToken,
    });

/// Opens a session of a runtime as [OpenChildSession] does, that starts
/// from the whole of session [fork]'s conversation, ACP's `session/fork`.
typedef OpenForkSession =
    Future<Session> Function(
      String runtime,
      SessionStart start, {
      required InitialValues initial,
      Map<String, Object?>? chordServer,
      required void Function(Traffic traffic) onTraffic,
      required CancellationToken cancellationToken,
      required String fork,
    });

/// What the host reads of the window's own: the main session's key, once
/// main is open.
const _mainName = 'main';

/// How the parent's messages read to a child: from `main`.
const fromMain = MessageFrom(_mainName, reachable: true);

/// The call `/new` made, as its command's row draws it and main's record
/// keeps it: `open_agent` of [agent], typed, with what it [answer]ed.
ChordCall newCall(String agent, Started answer) => ChordCall(
  tool: ChordTool.openAgent,
  input: {'agent': agent, 'typed': '/new'},
  answer: answer.toJson(),
);

/// Said to a caller whose session was let go meanwhile.
const stale = Refused(
  'Your session was cleared or closed; nothing more goes from it',
);

/// Whether a launch asked for by a caller, or by the person in main
/// [key]'s session, still stands: the session it was asked in is the one up,
/// and the caller's own launch is. Committed once its agent's first job went.
final class LaunchGuard {
  /// The launch asked for now in main [_key]'s session, by [_caller] if
  /// an agent asked.
  LaunchGuard(this._host, this._key, [this._caller])
    : _parent = _host._conversationAt(_key),
      _session = _host._conversationAt(_key)?.session;

  final AgentsHost _host;
  final int _key;
  final Caller? _caller;
  final Conversation? _parent;
  final Session? _session;

  /// Whether its agent's first job has gone to it.
  var committed = false;

  /// Whether it still stands.
  bool valid() =>
      _session != null &&
      identical(_host._conversationAt(_key), _parent) &&
      identical(_parent?.session, _session) &&
      _parent?.closing != true &&
      _caller?.launch?.call() != false;
}

/// A team's open run: the file as it was read when the run started, so a
/// file changed since does not change a running team, and the job it was
/// handed.
typedef _Run = ({
  FoundTeam found,
  Team team,
  String job,
  SelectedRun? selected,
});

/// What a selected run knows of its team, with its receipt so far, and how
/// the receipt is published again once it changes.
final class SelectedRun {
  /// A run of [frozen], its receipt [receipt] so far.
  SelectedRun(this.frozen, this.receipt, this.publish);

  final FrozenSelection frozen;
  SelectionReceipt receipt;

  /// Serves the receipt as it stands to main's record and the lead's.
  void Function() publish;
}

/// A selected start's own checks, held per child until its first job goes.
typedef _Validation = ({
  Completer<String?> done,
  String? Function(Conversation conversation)? checkStarted,
  void Function(String reason)? refused,
});

/// [team] as a run holds it: its lists unmodifiable, so nothing changes the
/// team a run started with.
Team _frozen(Team team) => Team(
  description: team.description,
  lead: team.lead,
  members: List.unmodifiable(team.members),
  body: team.body,
);

/// What `/fork` came to: the fork, or why not.
sealed class ForkAnswer {
  const ForkAnswer();
}

/// Forked into [name], from the agent with key [from].
final class Forked extends ForkAnswer {
  const Forked(this.name, this.from);
  final String name;
  final int from;
}

/// Not forked, as [refused] says; [from] is the source's key once the fork
/// was asked of its agent.
final class ForkRefused extends ForkAnswer {
  const ForkRefused(this.refused, [this.from]);
  final String refused;
  final int? from;
}

/// The window's agents and chord's tools over them.
final class AgentsHost implements WindowView {
  /// A host over [agents], opening children of [runtimeNames] as
  /// [startupOf] says through [openChildSession], each admitted to
  /// [server]; [opened] is told of each child ahead of its first event.
  /// `recordingOf` makes each child its own record; `transcriptOf` gives
  /// the transcript the window drew for a key, a resumed past among it.
  AgentsHost({
    required List<String> runtimeNames,
    required SessionStart? Function(String runtime) startupOf,
    required OpenChildSession openChildSession,
    required OpenAgents<Conversation> agents,
    required void Function(int key) opened,
    void Function(int key, int front)? closed,
    void Function(int key, {int? from, required String name, String? runtime})?
    keepClosing,
    void Function(int key)? keptClosed,
    ChordServer? server,
    Runtimes? runtimes,
    this._recordingOf,
    this._transcriptOf,
    String? cwd,
    OpenForkSession? openForkSession,
    this._configHome,
    this._home,
    void Function()? Function()? settingsBox,
    this._settingSaved,
    this._resources,
    this._selectionPolicy,
    this._watched,
  }) : _cwd = cwd ?? Directory.current.path,
       _settingsBox = settingsBox ?? settingsBoxClaim(),
       _names = runtimeNames,
       _startOf = startupOf,
       _openSession = openChildSession,
       _openFork = openForkSession,
       _roster0 = agents,
       _told = opened,
       _toldClosed = closed,
       _holdSpend = keepClosing,
       _settleSpend = keptClosed,
       _chord = server,
       _offers =
           runtimes ??
           Runtimes(probe: (runtime, token) => Future.error(StateError('')));

  final List<String> _names;

  // Each event of a child, task or fork session, by an id naming it apart
  // from main's key and its runtime, ahead of its being told.
  final void Function(String id, String agent, ConversationEvent event)?
  _watched;

  // The merged teamSelection policy as a selected run reads it now; the
  // settings files' by default.
  final Future<({Map<String, Object?>? policy, String? error})> Function()?
  _selectionPolicy;

  // The providers' limits, which get_budgets reads; none reads none.
  final ReadLimits? _resources;

  // Where the window's agents work, which a monitor's command runs in.
  final String _cwd;

  // Where the user's settings are, and the home paths are shown from.
  final String? _configHome, _home;

  // The window's one place for a settings change waiting on the person.
  final void Function()? Function() _settingsBox;
  final void Function(List<String> path, SettingChange change)? _settingSaved;

  // Each child's own record, which names it and its parent; none keeps no
  // record.
  final Recording Function(RecordChild child)? _recordingOf;

  // The transcript the window drew for a session, by its key: a resumed
  // past's task blocks and the agents it left open are read there.
  final Transcript? Function(int key)? _transcriptOf;
  final SessionStart? Function(String) _startOf;
  final OpenChildSession _openSession;
  final OpenForkSession? _openFork;
  final OpenAgents<Conversation> _roster0;
  final void Function(int) _told;
  final void Function(int key, int front)? _toldClosed;
  final void Function(
    int key, {
    int? from,
    required String name,
    String? runtime,
  })?
  _holdSpend;
  final void Function(int key)? _settleSpend;

  // The keys a cleared child's old launch is kept under: none a session
  // ever has.
  var _retiredKeys = 0;
  final ChordServer? _chord;
  final Runtimes _offers;

  // The messages sent to a child still starting, by its key: the first is
  // its first turn once it is up, the rest go into that turn.
  final _early = <int, List<(MessageFrom, String)>>{};

  // The children being cleared, by key: settled once the fresh session is
  // up, failed or closing, with why not and the senders of what waited.
  final _clearing =
      <int, void Function(String? failed, List<MessageFrom> later)>{};

  // Each task agent's own conversation, by its id, while it runs.
  final _taskSessions = <String, Conversation>{};

  // What an open waits on when it asked for an effort: its start.
  final _starts = <int, Completer<void>>{};

  // Each open run, by its lead's id.
  final _runs = <String, _Run>{};

  // The team part each team agent's first message, and a clear's next one,
  // goes with, by its key.
  final _parts = <int, TeamPart>{};

  // The launch each child opened for a run waits on, by its key, until its
  // first job goes.
  final _launches = <int, LaunchGuard>{};

  // Each start's validation, by its key, until its first job went or it
  // was refused.
  final _validations = <int, _Validation>{};

  WindowAgents<Conversation> get _roster => _roster0.agents;

  Conversation? _conversationAt(int key) => _roster0.conversationOf(key);

  bool _stale(Caller caller) => caller.launch?.call() == false;

  /// Whether child [key] is being cleared, its fresh session not up yet.
  bool isClearing(int key) => _clearing.containsKey(key);

  /// The tasks the session at [key], main or a long-lived child, started
  /// that [to] names, by id or name: those running, and those ended.
  ({List<TaskAgent> running, List<({String id, String name})> ended})
  tasksNamed(int key, String to) => _tasksNamed(key, _conversationAt(key), to);

  @override
  List<OpenSessionView> sessions() {
    final roster = _roster;
    final main = roster.main;
    if (main == null) return const [];
    String? modelOf(Conversation? conversation) {
      final session = conversation?.session;
      return session == null
          ? null
          : modelsFrom(
              session.state.configOptions,
              session.state.models,
            )?.current;
    }

    return [
      (
        key: main.key,
        runtime: main.agent,
        id: main.conversation.session?.id,
        model: modelOf(main.conversation),
        children: [
          for (final child in roster.children)
            if (child.forkedFrom == null)
              (
                id: child.id,
                name: child.name,
                runtime: child.runtime,
                model: modelOf(child.conversation) ?? child.info.model,
              ),
        ],
      ),
      // A fork is a session of its own, beside main's.
      for (final fork in roster.children)
        if (fork.forkedFrom != null)
          (
            key: fork.key,
            runtime: fork.runtime,
            id: fork.conversation.session?.id,
            model: modelOf(fork.conversation) ?? fork.info.model,
            children: const <ChildView>[],
          ),
    ];
  }

  @override
  List<String> runtimes() => _names;

  @override
  Future<RuntimeOffer?> offer(String runtime, {required bool probe, int? key}) {
    // A runtime with a session open says what it offers there.
    for (final child in _roster.children) {
      final session = child.conversation.session;
      if (child.runtime == runtime && session != null) {
        _offers.heard(runtime, offeredOf(session.state));
      }
    }
    final main = _roster.main;
    final session = main?.conversation.session;
    if (main?.agent == runtime && session != null) {
      _offers.heard(runtime, offeredOf(session.state));
    }
    return _offers.read(runtime, probe: probe);
  }

  /// Why a child of [args]'s runtime cannot start from [parent], main
  /// [key]'s or a child of it: a bad name, a parent closing, a runtime chord
  /// cannot start there, or a model it is known to lack; null when it may.
  Future<String?> _startRefusal(
    int key,
    Conversation? parent,
    SpawnArgs args,
    String kind, [
    String? named0,
  ]) async {
    final name = named0 ?? args.name?.trim();
    final named = kind == 'agent'
        ? agentNameProblem(name == null || name.isEmpty ? args.agent : name)
        : null;
    if (named != null) return 'An agent name $named';
    final startup = _names.contains(args.agent) ? _startOf(args.agent) : null;
    if (parent?.session == null) {
      return 'This session is closing; no $kind can start from it';
    }
    if (startup == null) {
      return 'No agent named ${args.agent}; chord knows ${_names.join(', ')}';
    }
    if (startup.refused case final refused?) return refused;
    final known = await offer(args.agent, probe: false, key: key);
    final model = args.model;
    if (model != null &&
        known is Offer &&
        known.models.isNotEmpty &&
        !known.models.any((each) => each.id == model)) {
      return '${args.agent} offers no model $model; it offers '
          '${[for (final each in known.models) each.id].join(', ')}';
    }
    final mode = args.mode;
    final modes = known is Offer ? known.modes : null;
    if (mode != null &&
        modes != null &&
        modes.isNotEmpty &&
        !modes.any((each) => each.id == mode)) {
      return '${args.agent} has no mode $mode · '
          '${[for (final each in modes) each.id].join(', ')}';
    }
    return null;
  }

  /// Why main [key] cannot open another child of its own, if it cannot.
  String? _fullRefusal(int key) {
    final roster = ownedBy(_roster, key);
    if (roster == null) return 'This session has closed';
    return ownChildren(roster).length >= maxChildren
        ? 'This session has $maxChildren agents open; close_agent one first'
        : null;
  }

  @override
  Future<OpenAnswer> open(int key, SpawnArgs args, Caller caller) async {
    if (_stale(caller)) return stale;
    final session = _conversationAt(key)?.session;
    final refused =
        await _startRefusal(key, _conversationAt(key), args, 'agent') ??
        _fullRefusal(key);
    // Its session let go while it waited: what it asked goes nowhere.
    if (_stale(caller) || _conversationAt(key)?.session != session) {
      return stale;
    }
    final roster = ownedBy(_roster, key);
    if (roster == null || refused != null) {
      return Refused(refused ?? 'This session has closed');
    }
    final opened = _openChild(key, roster, args, 'asked by open_agent');
    if (opened == null) {
      return Refused(_fullRefusal(key) ?? 'This session has closed');
    }
    final (:placed, :id, :name, :started, validated: _) = opened;
    String? effort, note;
    if (args.effort != null) {
      await started;
      final conversation = _conversationAt(placed);
      final session = conversation?.session;
      effort = session == null
          ? null
          : effortsFrom(session.state.configOptions)?.current;
      note = conversation?.effortRefused;
    }
    return Started(
      id: id,
      name: name,
      agent: args.agent,
      model: args.model,
      effort: effort,
      note: note,
    );
  }

  /// `/new [agent] --name <name>` as the person typed it: a child of main
  /// on the agent named or main's runtime, by the name given or the one
  /// `open_agent` gives with none, idle until the person's first prompt in
  /// its view. [show] goes to it at once; main hears of it ahead of its
  /// next prompt. Refused as `open_agent` is, or for a name taken as it
  /// is, never numbered as chord's own are.
  Future<OpenAnswer> newTyped(
    String typed, {
    required void Function(int key) show,
  }) async {
    final main = _roster.main;
    if (main == null) return const Refused('This session has closed');
    final asked = newArgs(typed);
    if (asked case NewProblem(:final problem)) return Refused(problem);
    final NewAsked(:agent, :name) = asked as NewAsked;
    final args = SpawnArgs(agent: agent ?? main.agent, prompt: '', name: name);
    // Asked for by name, a taken one is refused, not numbered; the name is
    // read before the agent, as the original orders the refusals.
    String? nameRefusal() {
      if (name == null) return null;
      final problem = agentNameProblem(name);
      if (problem != null) return 'An agent name $problem';
      final roster = ownedBy(_roster, main.key);
      return roster != null && takenNames(roster).contains(name)
          ? 'The name $name is taken in this window'
          : null;
    }

    final early = nameRefusal();
    if (early != null) return Refused(early);
    final refused =
        await _startRefusal(
          main.key,
          _conversationAt(main.key),
          args,
          'agent',
        ) ??
        _fullRefusal(main.key) ??
        // Another child may have taken it while the agent was looked up.
        nameRefusal();
    final roster = ownedBy(_roster, main.key);
    if (roster == null || refused != null) {
      return Refused(refused ?? 'This session has closed');
    }
    final opened = _openChild(
      main.key,
      roster,
      args,
      'asked by /new',
      idle: true,
    );
    if (opened == null) {
      return Refused(_fullRefusal(main.key) ?? 'This session has closed');
    }
    show(opened.placed);
    _conversationAt(main.key)?.aside(
      const MessageFrom('chord'),
      'The person opened @${opened.name} (${args.agent}) with /new; it has '
      'no prompt yet. It reports to you, and send_message reaches it.',
    );
    final started = Started(
      id: opened.id,
      name: opened.name,
      agent: args.agent,
    );
    // Main's record keeps it, so a resume names it among those left open.
    _conversationAt(main.key)?.ranTyped(newCall(args.agent, started));
    return started;
  }

  /// `/fork [name]`: the agent on screen, main or a fork, forked into a
  /// new agent of its runtime beside main, of no one, in a process of its
  /// own, shown by [show] once it is up. Its name and the key of the agent
  /// it was forked from, or why it was not forked, with that key once it
  /// was asked of the agent; null once the source's session has gone
  /// meanwhile, as a line in its next session would be about another
  /// conversation. [busy] says whether an agent works, asks or has prompts
  /// queued, which it is not forked while.
  Future<ForkAnswer?> forkTyped(
    String named, {
    required bool Function(int key) busy,
    required void Function(int key) show,
    void Function(int key, int source)? opened,
  }) async {
    final roster = _roster;
    final main = roster.main;
    if (main == null) return const ForkRefused('This session has closed');
    final picked = pickedChild(roster);
    if (picked != null && picked.forkedFrom == null) {
      return const ForkRefused('/fork forks main or a fork');
    }
    final sourceKey = picked?.key ?? main.key;
    final sourceName = picked?.name ?? _mainName;
    final runtime = picked?.runtime ?? main.agent;
    final session = _conversationAt(sourceKey)?.session;
    const closing = 'This session is closing; nothing can fork from it';
    if (session == null) return const ForkRefused(closing);
    if (!session.forks()) {
      return const ForkRefused('This agent does not fork sessions');
    }
    if (busy(sourceKey)) {
      return ForkRefused('$sourceName is working · /fork once its turn ends');
    }
    final problem = agentNameProblem(named);
    if (problem != null) return ForkRefused('An agent name $problem');
    final id = const Uuid().v4().substring(0, 8);
    final name = childName(roster, named.isEmpty ? 'fork' : named, 'fork');
    final forkKey = roster.nextKey;
    final up = Completer<String?>();
    // Its state is there before its first event, which may come at once;
    // the window's, its view the source's conversation as it stood.
    if (opened != null) {
      opened(forkKey, sourceKey);
    } else {
      _told(forkKey);
    }
    final key = _roster0.openChild(
      ChildInfo(
        id: id,
        name: name,
        runtime: runtime,
        forkedFrom: sourceName,
        openedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      (emit, own) =>
          _childConversation(
            SpawnArgs(agent: runtime, prompt: ''),
            // The person's, in the fork's own session, under its own key.
            (launch) => Caller(
              role: Role.person,
              key: forkKey,
              fork: true,
              window: this,
              launch: launch,
            ),
            'asked by /fork',
            emit,
            // Its own record, of no parent: `/resume` opens it as a session
            // of its own.
            record: RecordChild(parent: () => null, name: name),
            fork: session.id,
          )..listen((event) {
            // Its clears settle as a child's do; no parent hears of it.
            if (_clearedHeard(own, event)) return;
            _forkHeard(own, event, up, sourceName);
          }),
    );
    if (key == null) return const ForkRefused(closing);
    final failed = await up.future;
    if (!identical(_conversationAt(sourceKey)?.session, session)) return null;
    if (failed != null) {
      return ForkRefused('Could not fork: $failed', sourceKey);
    }
    // Closed as it came up: nothing to pick or announce.
    if (agentOf(_roster, key) == null) {
      return ForkRefused(
        'Could not fork: it was closed before it started',
        sourceKey,
      );
    }
    show(key);
    return Forked(name, sourceKey);
  }

  /// A fork's first start as its `/fork` waits on it: up, failed or gone.
  void _forkHeard(
    int own,
    ConversationEvent event,
    Completer<String?> up,
    String from,
  ) {
    if (up.isCompleted) return;
    switch (event) {
      case Connected():
        up.complete(null);
        // Where it parted, under what it was copied from.
        scheduleMicrotask(() => _conversationAt(own)?.forked(from));
      case ConnectFailed(:final message, :final error):
        // The agent's own words, as the original says a fork's failure.
        up.complete(error ?? message);
        scheduleMicrotask(() => _dropChild(own));
      case Closing() || Transcribed(action: DisconnectedAction()):
        up.complete('it was closed before it started');
      default:
    }
  }

  /// Places a child of main [key] of [args]'s runtime in [roster]: its
  /// first turn main's prompt, or none when [idle]; [asked] names who asked
  /// for its model and effort. Its key, chord's id and name for it, and
  /// its start; null when the roster had no room.
  ({
    int placed,
    String id,
    String name,
    Future<void> started,
    Future<String?> validated,
  })?
  _openChild(
    int key,
    WindowAgents<Conversation> roster,
    SpawnArgs args,
    String asked, {
    bool idle = false,
    String? named,
    ({String name, String? lead})? team,
    TeamPart? part,
    MessageFrom from = fromMain,
    Conversation? Function()? parent,
    LaunchGuard? launch,
    String? id,
    String? Function(Conversation conversation)? checkStarted,
    void Function(String reason)? refused,
  }) {
    final name = named ?? childName(roster, args.name, args.agent);
    final parentOf = parent ?? () => _conversationAt(key);
    // Eight hex digits: the parent quotes it, and so does the person's
    // close.
    id ??= const Uuid().v4().substring(0, 8);
    final childKey = _roster.nextKey;
    _early[childKey] = idle ? [] : [(from, args.prompt)];
    if (part != null) _parts[childKey] = part;
    if (launch != null) _launches[childKey] = launch;
    final validation = Completer<String?>();
    _validations[childKey] = (
      done: validation,
      checkStarted: checkStarted,
      refused: refused,
    );
    final started = _starts[childKey] = Completer<void>();
    // Its state is there before its first event, which may come at once.
    _told(childKey);
    final placed = _roster0.openChild(
      ChildInfo(
        id: id,
        name: name,
        runtime: args.agent,
        openedAt: DateTime.now().millisecondsSinceEpoch,
        model: args.model,
        mode: args.mode,
        team: team?.name,
        lead: team?.lead,
      ),
      (emit, own) => _childConversation(
        args,
        (launch) => Caller(
          role: Role.child,
          key: key,
          agent: id,
          window: this,
          launch: launch,
          team: team == null
              ? null
              : team.lead == null
              ? TeamSide.lead
              : TeamSide.member,
        ),
        asked,
        emit,
        record: RecordChild(
          parent: () => parentOf()?.session?.id,
          name: name,
          id: id,
          team: team?.lead == null ? team?.name : null,
        ),
      )..listen((event) => _heard(key, own, event)),
    );
    if (placed == null) {
      _early.remove(childKey);
      _starts.remove(childKey);
      _parts.remove(childKey);
      _launches.remove(childKey);
      _refuse(
        childKey,
        'The attempted agent could not be opened; no first job was '
        'delivered.',
      );
      return null;
    }
    return (
      placed: placed,
      id: id,
      name: name,
      started: started.future,
      validated: validation.future,
    );
  }

  /// Settles child [key]'s start as refused for [reason], its first reason
  /// kept: closing is a consequence, not a cause.
  void _refuse(int key, String reason) {
    final validation = _validations.remove(key);
    if (validation == null || validation.done.isCompleted) return;
    validation.refused?.call(reason);
    validation.done.complete(reason);
  }

  /// Settles child [key]'s start as validated: its first job went.
  void _validated(int key) {
    final validation = _validations.remove(key);
    if (validation != null && !validation.done.isCompleted) {
      validation.done.complete(null);
    }
  }

  /// A child's own conversation: a session of [args]'s runtime where main
  /// works, on the model asked for or not at all, each launch admitted to
  /// chord's server as [callerOf] that launch says; [asked] names who asked
  /// for its model and effort.
  Conversation _childConversation(
    SpawnArgs args,
    Caller Function(bool Function() launch) callerOf,
    String asked,
    void Function(ConversationEvent event) emit, {
    RecordChild? record,
    String? fork,
  }) {
    final start = _startOf(args.agent) ?? const SessionStart();
    void Function() release = () {};
    // A fork forks once; a clear opens it afresh, from nothing.
    var forking = fork;
    final conversation = Conversation(
      ({required onTraffic, required cancellationToken}) async {
        if (start.refused case final refused?) throw StateError(refused);
        var live = true;
        final admitted = _chord?.admit(callerOf(() => live));
        release();
        void revoke() {
          live = false;
          if (admitted != null) _chord?.revoke(admitted.token);
        }

        release = revoke;
        try {
          final initial = (
            model: args.model ?? start.starting.model?.id,
            effort: args.effort ?? start.starting.effort?.id,
            mode: args.mode ?? start.starting.mode?.id,
          );
          final from = forking;
          forking = null;
          final session = from != null && _openFork != null
              ? await _openFork(
                  args.agent,
                  start,
                  initial: initial,
                  chordServer: admitted?.server,
                  onTraffic: onTraffic,
                  cancellationToken: cancellationToken,
                  fork: from,
                )
              : await _openSession(
                  args.agent,
                  start,
                  initial: initial,
                  chordServer: admitted?.server,
                  onTraffic: onTraffic,
                  cancellationToken: cancellationToken,
                );
          // Its process gone, its calls go nowhere.
          session.exited.whenComplete(revoke).ignore();
          return session;
        } catch (_) {
          revoke();
          rethrow;
        }
      },
      starting: Starting(
        // The model asked for, which the child runs on or not at all.
        model: args.model == null
            ? start.starting.model
            : StartingValue(args.model!, from: asked, required: true),
        // Never required: a refusal leaves it on the runtime's own.
        effort: args.effort == null
            ? start.starting.effort
            : StartingValue(args.effort!, from: asked),
        // The mode a team file set, likewise, or else the settings' one.
        mode: args.mode == null
            ? start.starting.mode
            : StartingValue(args.mode!, from: asked, required: true),
      ),
      recording: record == null ? null : _recordingOf?.call(record),
    );
    final caller = callerOf(() => false);
    final watchedAs = caller.task ?? caller.agent ?? 'child:${caller.key}';
    conversation.listen((event) {
      _watched?.call(watchedAs, args.agent, event);
      // A launch let go, or one that failed its start: its calls stop now,
      // not once its process has gone.
      if (event is Cleared || event is Closing || event is ConnectFailed) {
        release();
      }
      emit(event);
    });
    return conversation;
  }

  /// One of child [own]'s events, as main [key]'s host hears it.
  void _heard(int key, int own, ConversationEvent event) {
    _tellEnded(key, own, event);
    // Gone before its first job: the start is refused, as cancelled when
    // its launch was let go.
    if (event is Closing ||
        (event is Transcribed && event.action is DisconnectedAction)) {
      final launch = _launches[own];
      _refuse(
        own,
        event is Closing || launch?.valid() == false
            ? 'Cancelled before its first job; the attempted agent is closing.'
            : 'Startup ended before the first job; the attempted agent is '
                  'closing.',
      );
    }
    // An open waiting on the start settles whichever start it was, a
    // clear's included.
    if (event is Connected || event is ConnectFailed || event is Closing) {
      final started = _starts.remove(own);
      if (started != null && !started.isCompleted) started.complete();
    }
    if (_clearedHeard(own, event)) return;
    if (event is! Connected && event is! ConnectFailed) return;
    final held = _early.remove(own) ?? const [];
    final launch = _launches.remove(own);
    // After the event is drawn, so the first turn comes after it.
    scheduleMicrotask(() {
      final child = agentOf(_roster, own)?.child;
      final check = _validations[own]?.checkStarted;
      if (child == null) {
        _refuse(own, 'The attempted agent closed before its first job.');
        return;
      }
      // Its launch let go while it started: it runs nothing.
      if (launch != null && !launch.valid()) {
        _refuse(
          own,
          'Cancelled before its first job; the attempted agent is closing.',
        );
        _dropChild(own);
        return;
      }
      if (event is Connected) {
        final invalid = check?.call(child.conversation);
        if (invalid != null) {
          _refuse(own, invalid);
          _dropChild(own);
          return;
        }
        for (final (index, (from, text)) in held.indexed) {
          if (index == 0) {
            launch?.committed = true;
            child.conversation.deliver(from, text, _parts[own]);
          } else {
            child.conversation.tell(from, text);
          }
        }
        _validated(own);
        return;
      }
      // A start refused for a value it read back keeps the receipt's own
      // words for it; one with no session left says the start failed.
      _refuse(
        own,
        (child.conversation.session == null
                ? null
                : check?.call(child.conversation)) ??
            'Initialization failed before the first job; the attempted agent '
                'is closing.',
      );
      if (check != null) {
        _dropChild(own);
        return;
      }
      final failed = event as ConnectFailed;
      final signIn = failed.signIn;
      _parentOf(child)?.deliver(
        const MessageFrom('chord'),
        '${child.name} (${child.runtime}) did not start: '
        '${sentence(stepWords(failed.message, failed.failure))}'
        '${failureNote(child.runtime, failed.failure)}'
        '${signIn == null ? '' : signInNote(child.runtime, signIn)}'
        ' It takes no messages; open_agent starts another.',
      );
    });
  }

  /// An event of child [own] while it is being cleared, which is no first
  /// start: its fresh session up, failed or closing settles the clear, and
  /// what waited for it goes then. Whether it was being cleared.
  bool _clearedHeard(int own, ConversationEvent event) {
    final settle = _clearing[own];
    if (settle == null) return false;
    if (event is! Connected && event is! ConnectFailed && event is! Closing) {
      return true;
    }
    final waited = _early.remove(own) ?? const [];
    _clearing.remove(own);
    // After the event is drawn, as a first start's messages go.
    if (event is Connected) {
      scheduleMicrotask(() {
        final child = agentOf(_roster, own)?.child;
        for (final (from, text) in waited) {
          if (child != null) _sentTo(child, from, text, () {});
        }
      });
    }
    // Up, they go; failed or closed, they are dropped, and said so.
    settle(switch (event) {
      Connected() => null,
      Closing() => 'it was closed',
      ConnectFailed(:final message) => message,
      _ => null,
    }, event is Connected ? const [] : [for (final (from, _) in waited) from]);
    return true;
  }

  /// Clears [child]'s context: its session let go as main's /clear lets
  /// main's, a fresh one in its place under the same id and name, which
  /// runs nothing until its next message. Settles once that session is up,
  /// with why not if it is not, and the messages queued to it from others
  /// that were dropped, said so.
  Future<({String? failed, String? dropped})> _clearChild(
    Child<Conversation> child,
  ) async {
    if (_clearing.containsKey(child.key)) {
      return (failed: 'it is being cleared already', dropped: null);
    }
    // Queued or held in its session, or held while it still starts.
    final before = [
      for (final (from, _)
          in _early[child.key] ?? const <(MessageFrom, String)>[])
        from,
      ...child.conversation.queuedFrom,
    ];
    final up = Completer<({String? failed, List<MessageFrom> later})>();
    _clearing[child.key] = (failed, later) =>
        up.complete((failed: failed, later: later));
    // What comes while it restarts waits for the fresh session.
    _early[child.key] = [];
    // What the old launch spent is kept under a key of its own.
    final retired = --_retiredKeys;
    _holdSpend?.call(
      retired,
      from: child.key,
      name: child.name,
      runtime: child.runtime,
    );
    child.conversation
        .clear(_parts[child.key])
        .whenComplete(() => _settleSpend?.call(retired))
        .ignore();
    final (:failed, :later) = await up.future;
    // Those sent while it restarted count too when it did not come up.
    final others = [
      for (final from in [...before, ...later]) from.name,
    ];
    final dropped = others.isEmpty
        ? null
        : '${others.length} queued message${others.length == 1 ? '' : 's'} '
              'from ${_andList({...others}.toList())} '
              '${others.length == 1 ? 'was' : 'were'} not delivered.';
    return (failed: failed, dropped: dropped);
  }

  String _notCleared(String name, String failed, String? dropped) =>
      'Could not clear $name: $failed${dropped == null ? '' : '. $dropped'}';

  @override
  Future<ClearAnswer> clear(Caller caller, String to) async {
    if (_stale(caller)) return stale;
    final lead = _leadOf(caller);
    final roster = ownedBy(_roster, caller.key);
    final child = roster == null
        ? null
        : (lead == null ? ownChildren(roster) : membersOf(roster, lead.id))
              .firstWhereOrNull((each) => each.id == to || each.name == to);
    if (child == null) {
      return Refused(
        lead == null
            ? _noChild(caller.key, to)
            : 'No member $to of yours is open',
      );
    }
    final (:failed, :dropped) = await _clearChild(child);
    return failed == null
        ? tools.Cleared(child.name, child.id, dropped: dropped)
        : Refused(_notCleared(child.name, failed, dropped));
  }

  /// The person's clear of child [key], as `/clear` on a picked child: as
  /// clear_agent, and main told once it is up, as it did not ask. Why not,
  /// if not.
  Future<String?> clearByPerson(int key) async {
    final child = agentOf(_roster, key)?.child;
    if (child == null) return null;
    final (:failed, :dropped) = await _clearChild(child);
    if (failed != null) return _notCleared(child.name, failed, dropped);
    // A fork is no one's: no one is told it was cleared.
    if (child.forkedFrom != null) return null;
    final session = _conversationAt(key)?.session;
    final model =
        (session == null
            ? null
            : modelsFrom(
                session.state.configOptions,
                session.state.models,
              )?.current) ??
        child.info.model;
    final described = [child.runtime, ?model].join(' · ');
    _parentOf(child)?.deliver(
      const MessageFrom('chord'),
      "The person cleared ${child.name}'s context ($described, id "
      '${child.id}). It is open with a fresh session and knows nothing of '
      'earlier turns; your next message is its first.'
      '${dropped == null ? '' : ' $dropped'}',
    );
    return null;
  }

  /// Tells main [key], from chord, of an [event] that ends child [own]'s
  /// work on its own, as [childEnded] words it: its agent exited, or a turn
  /// failed with it still up. A child the window has let go is no news.
  void _tellEnded(int key, int own, ConversationEvent event) {
    if (event is! Transcribed) return;
    final action = event.action;
    if (action is! DisconnectedAction && action is! ResultAction) return;
    final child = agentOf(_roster, own)?.child;
    if (child == null) return;
    final lead = isLead(child.info);
    final text = childEnded(
      child.name,
      event,
      child.conversation.session?.gone(),
      lead: lead,
    );
    if (text == null) return;
    // A lead gone leaves its members nobody to answer to.
    if (lead && action is DisconnectedAction) {
      final roster = ownedBy(_roster, key);
      for (final member
          in roster == null
              ? const <Child<Conversation>>[]
              : membersOf(roster, child.id)) {
        _dropChild(member.key);
      }
    }
    _parentOf(child)?.deliver(const MessageFrom('chord'), text);
  }

  /// The conversation a child answers to: its lead's for a member, main's
  /// for any other; none for a fork, which is no one's.
  Conversation? _parentOf(Child<Conversation> child) {
    if (child.forkedFrom != null) return null;
    final main = _roster.main;
    if (main == null) return null;
    final lead = child.lead;
    return lead == null
        ? _conversationAt(main.key)
        : _roster.children
              .firstWhereOrNull((each) => each.id == lead)
              ?.conversation;
  }

  /// The caller's own child, when it is a team's lead.
  Child<Conversation>? _leadOf(Caller caller) {
    final agent = caller.agent;
    if (caller.team != TeamSide.lead || agent == null) return null;
    return ownedBy(
      _roster,
      caller.key,
    )?.children.firstWhereOrNull((each) => each.id == agent);
  }

  /// Why main [key] has no open child [to]: closed, open when the session
  /// was left, as a resumed past's closing note names it, or never open.
  String _noChild(int key, String to) {
    final closed = ownedBy(_roster, key)?.closed.lastWhereOrNull(
      (child) => child.lead == null && (child.id == to || child.name == to),
    );
    if (closed != null) {
      return '${closed.name} is closed; open_agent starts another';
    }
    final left = [
      for (final entry in _transcriptOf?.call(key)?.entries ?? const <Entry>[])
        if (entry is LeftOpenEntry) ...entry.agents,
    ].lastWhereOrNull((agent) => agent.name == to);
    return left == null
        ? 'No agent $to is open in this session; list_sessions names them'
        : left.team == null
        ? '$to was closed when this session was left; open_agent starts '
              'another'
        : '$to was closed when this session was left; run_team starts the '
              'team again';
  }

  /// [text] to [child] from [from]: held while it starts, else told.
  MessageAnswer _sentTo(
    Child<Conversation> child,
    MessageFrom from,
    String text,
    void Function() queued,
  ) {
    final held = _early[child.key];
    if (held != null) {
      held.add((from, text));
      return Delivered(tools.Delivery.queued, to: child.name);
    }
    final delivered = child.conversation.tell(from, text, queued);
    return delivered == null
        ? Refused('${child.name} is closing; nothing reaches it')
        : Delivered(
            delivered == Delivery.sent
                ? tools.Delivery.sent
                : tools.Delivery.queued,
            to: child.name,
          );
  }

  @override
  MessageAnswer tell(
    Caller caller,
    String to,
    String text,
    void Function() queued,
  ) {
    if (_stale(caller)) return stale;
    if (caller.team != null) return _teamTell(caller, to, text, queued);
    final roster = ownedBy(_roster, caller.key);
    final target = roster == null
        ? null
        : messageRecipients(
            roster,
            caller.key,
          ).firstWhereOrNull((each) => each.id == to || each.name == to);
    final child = target == null ? null : agentOf(_roster, target.key)?.child;
    if (child == null) return Refused(_noChild(caller.key, to));
    return _sentTo(child, fromMain, text, queued);
  }

  @override
  MessageAnswer message(Caller caller, String text, void Function() queued) {
    if (_stale(caller)) return stale;
    final agent = caller.agent;
    if (agent == null) return _taskMessage(caller, text, queued);
    if (_conversationAt(caller.key) == null) {
      return const Refused('The session that opened you has closed');
    }
    final child = ownedBy(
      _roster,
      caller.key,
    )?.children.firstWhereOrNull((each) => each.id == agent);
    if (child == null) {
      return const Refused('You are closed; nothing more reaches your parent');
    }
    final delivered = _conversationAt(caller.key)?.tell(
      MessageFrom(child.name, runtime: child.runtime, reachable: true),
      text,
      queued,
    );
    return delivered == null
        ? const Refused('The session that opened you has closed')
        : Delivered(
            delivered == Delivery.sent
                ? tools.Delivery.sent
                : tools.Delivery.queued,
          );
  }

  /// Main [key]'s conversation, or its long-lived child [agent]'s.
  Conversation? _sessionOf(int key, String? agent) => agent == null
      ? _conversationAt(key)
      : ownedBy(
          _roster,
          key,
        )?.children.firstWhereOrNull((each) => each.id == agent)?.conversation;

  /// Starts a task agent for the caller, main or a long-lived child of it:
  /// a session of the runtime asked for where main works, with no row of
  /// its own, drawn in the caller's turn and closed with it.
  @override
  Future<SpawnAnswer> spawn(Caller from, SpawnArgs args) async {
    final key = from.key;
    final parent = _sessionOf(key, from.agent);
    final session = parent?.session;
    final refused = await _startRefusal(key, parent, args, 'task');
    // Its session let go while it waited: no task starts in the next one.
    if (_stale(from) || parent?.session != session) return stale;
    if (parent == null || refused != null) {
      return Refused(refused ?? 'This session has closed');
    }
    final id = const Uuid().v4();
    final name = taskName(args.name, args.prompt);
    final task = TaskAgent(
      TaskStart(
        id: id,
        name: name,
        runtime: args.agent,
        prompt: args.prompt,
        model: args.model,
      ),
      parent.taskParent(id),
      () => DateTime.now().millisecondsSinceEpoch,
    );
    // What the answer waits on when it asked for an effort: the start.
    final started = Completer<void>();
    final child = _childConversation(
      args,
      (launch) => Caller(
        role: Role.child,
        key: key,
        task: id,
        by: from.agent,
        window: this,
        launch: launch,
      ),
      'asked by spawn_task',
      (event) {
        task.heard(event);
        if ((event is Connected ||
                event is ConnectFailed ||
                event is Closing) &&
            !started.isCompleted) {
          started.complete();
        }
        if (!task.running) _taskSessions.remove(id);
      },
      record: RecordChild(
        parent: () => parent.session?.id,
        name: name,
        task: id,
      ),
    );
    _taskSessions[id] = child;
    parent.adopt(task, child);
    String? effort, note;
    if (args.effort != null) {
      await started.future;
      final up = child.session;
      effort = up == null ? null : effortsFrom(up.state.configOptions)?.current;
      note = child.effortRefused;
    }
    // Its block says the effort it started on, as it says the model.
    if (effort != null) task.startedOn(effort);
    return Started(
      id: id,
      name: name,
      agent: args.agent,
      model: args.model,
      effort: effort,
      note: note,
    );
  }

  /// The tasks [owner], main or a child of it at [key], started that [to]
  /// names, by id or name: those running, and those ended, of which only
  /// their blocks are left from before a resume.
  ({List<TaskAgent> running, List<({String id, String name})> ended})
  _tasksNamed(int key, Conversation? owner, String to) {
    final running = [
      for (final task in owner?.tasks ?? const <TaskAgent>[])
        if (task.id == to || task.start.name == to) task,
    ];
    // Those of this conversation it keeps; those before a resume, only
    // their blocks in the transcript.
    final kept = owner?.endedTasks ?? const <String, String>{};
    final drawn = [
      for (final subagent in subagentsIn(
        _transcriptOf?.call(key)?.entries ?? const [],
      ))
        if (subagent.task case final task?
            when !isRunning(subagent) && !kept.containsKey(subagent.id))
          (id: subagent.id, name: task.name),
    ];
    final ended = [
      for (final (:id, :name) in [
        for (final MapEntry(key: id, value: name) in kept.entries)
          (id: id, name: name),
        ...drawn,
      ])
        if (!running.any((each) => each.id == id) && (id == to || name == to))
          (id: id, name: name),
    ];
    return (running: running, ended: ended);
  }

  /// close_agent on a task the caller started with spawn_task, by its id or
  /// a name only one of its tasks has: a running one stopped, its end
  /// naming the caller; one ended said to have. None when [to] names no
  /// task of the caller's.
  CloseAnswer? _closeTask(Caller caller, String to) {
    final agent = caller.agent;
    final child = agent == null
        ? null
        : ownedBy(
            _roster,
            caller.key,
          )?.children.firstWhereOrNull((each) => each.id == agent);
    if (agent != null && child == null) return null;
    final (:running, :ended) = _tasksNamed(
      child?.key ?? caller.key,
      child?.conversation ?? _conversationAt(caller.key),
      to,
    );
    final found = [
      for (final task in running) task.id,
      for (final task in ended) task.id,
    ];
    if (found.length > 1) {
      return Refused(
        '${found.length} of your tasks are named $to; close_agent one by its '
        'id: ${_andList(found)}',
      );
    }
    if (running.firstOrNull case final task?) {
      task.cancel(TaskStop.agent(child?.name ?? _mainName));
      return Closed(task.start.name);
    }
    final name = ended.firstOrNull?.name;
    return name == null ? null : Ended(name);
  }

  /// Takes child [key] out of the window and closes its agent, its turn
  /// interrupted first so the agent ends it as it would any cancel.
  void _dropChild(int key) {
    final child = agentOf(_roster, key)?.child;
    if (child == null) return;
    // A lead's members go first, as a parent's children close with it;
    // each close starts at once, none waited on.
    for (final member in membersOf(_roster, child.id)) {
      _dropChild(member.key);
    }
    final selected = _runs[child.lead ?? child.id]?.selected;
    _runs.remove(child.id);
    _parts.remove(key);
    _launches.remove(key);
    // Closed while it restarts: the clear settles, what waited for the
    // fresh session counted as not delivered.
    _clearing.remove(key)?.call('it was closed', [
      for (final (from, _) in _early[key] ?? const <(MessageFrom, String)>[])
        from,
    ]);
    _early.remove(key);
    final started = _starts.remove(key);
    if (started != null && !started.isCompleted) started.complete();
    if (child.wait.working != null) child.conversation.interrupt();
    // What it spent counts for the window, its last events too, until its
    // close settles.
    _holdSpend?.call(key, name: child.name, runtime: child.runtime);
    _roster0
        .closeChild(key)
        .whenComplete(() => _settleSpend?.call(key))
        .then<void>(
          (_) {},
          onError: (Object _) {
            // A selected run's receipt says an agent may not have gone.
            if (selected == null) return;
            selected.receipt = withSelectionCleanupWarning(selected.receipt);
            selected.publish();
          },
        )
        .ignore();
    _toldClosed?.call(key, shownKey(_roster) ?? key);
  }

  @override
  CloseAnswer close(Caller caller, String to) {
    if (_stale(caller)) return stale;
    final task = _closeTask(caller, to);
    if (task != null) return task;
    // A long-lived child, or a member, stops only the tasks it started.
    if (!closesAgents(caller)) {
      return Refused("No task $to of yours; spawn_task's answer names them");
    }
    final lead = _leadOf(caller);
    final roster = ownedBy(_roster, caller.key);
    final child = roster == null
        ? null
        : (lead == null ? ownChildren(roster) : membersOf(roster, lead.id))
              .firstWhereOrNull((each) => each.id == to || each.name == to);
    if (child == null) {
      return Refused(
        lead == null
            ? _noChild(caller.key, to)
            : 'No member $to of yours is open',
      );
    }
    _dropChild(child.key);
    (lead?.conversation ?? _conversationAt(caller.key))?.agentClosed(child.id);
    return Closed(child.name);
  }

  /// Main's `/clear`, ahead of its session going: main's own children go
  /// with that session, as its task agents do, each closed as a closing
  /// child is, its spend kept as `agent, closed`. Forks stand beside main
  /// and stay. As the original's `clearFront`, no one is told and main's
  /// record notes no close: the session that opened them is let go, and
  /// the fresh one starts knowing of no children, closed ones included.
  void closeMainChildren() {
    for (final child in List.of(_roster.children)) {
      if (child.forkedFrom == null) _dropChild(child.key);
    }
    _roster0.forgetClosed();
  }

  /// `/resume` of another session, ahead of main's going: unlike `/clear`,
  /// every child goes with it, forks too, as the original's `pickSession`
  /// drops them all, each closed as a closing child is, its spend kept as
  /// `agent, closed`. No one is told, and the resumed session starts
  /// knowing of no closed children, as the original's Q184 has it.
  void closeChildrenForResume() {
    for (final child in List.of(_roster.children)) {
      _dropChild(child.key);
    }
    _roster0.forgetClosed();
  }

  /// The person closes child [key], as `x` in the list does, a lead with
  /// its members: its parent is told it takes no more messages. The
  /// members closed with it, by name.
  List<String> closeByPerson(int key) {
    final child = agentOf(_roster, key)?.child;
    if (child == null) return const [];
    final members = isLead(child.info)
        ? [for (final member in membersOf(_roster, child.id)) member.name]
        : const <String>[];
    final session = child.conversation.session;
    final model =
        (session == null
            ? null
            : modelsFrom(
                session.state.configOptions,
                session.state.models,
              )?.current) ??
        child.info.model;
    // A fork is no one's child: no one is told of it.
    final parent = _parentOf(child);
    _dropChild(key);
    if (parent == null) return members;
    parent.agentClosed(child.id);
    final described = '${[child.runtime, ?model].join(' · ')}, id ${child.id}';
    parent.deliver(
      const MessageFrom('chord'),
      isLead(child.info)
          ? 'The person closed team ${child.name}: its lead ($described)'
                '${members.isEmpty ? '' : ' and its members ${andList(members)}'}'
                '. It takes no more messages; run_team starts it again.'
          : 'The person closed ${child.name} ($described). It takes no more '
                'messages; open_agent '
                '${child.lead == null ? 'starts another' : 'opens it again'}.',
    );
    return members;
  }

  /// The caller's own session: main's, the long-lived child's, or the
  /// task's own.
  Conversation? _callerConversation(Caller caller) {
    if (caller.task case final task?) return _taskSessions[task];
    return _sessionOf(caller.key, caller.agent);
  }

  @override
  Future<MonitorAnswer> monitor(Caller caller, MonitorArgs args) async =>
      _stale(caller) ? stale : startMonitorIn(_roster, caller, args, _cwd);

  @override
  StopMonitorAnswer stopMonitor(Caller caller, String id) =>
      _stale(caller) ? stale : stopMonitorIn(_roster, caller, id);

  @override
  List<RunningMonitor> monitors(Caller caller) => monitorsIn(_roster, caller);

  @override
  Future<String?> askPerson(
    Caller caller, {
    required String title,
    required String detail,
    required List<acp.PermissionOption> options,
    required SaveBox save,
    required CancellationToken signal,
  }) =>
      _conversationAt(caller.key)?.ask(
        title: title,
        detail: detail,
        options: options,
        save: save,
        signal: signal,
      ) ??
      Future.value();

  @override
  ({SettingsWhere where, String agent}) settingsWhere(Caller caller) => (
    where: SettingsWhere(configHome: _configHome, cwd: _cwd, home: _home),
    agent: _roster.main?.agent ?? 'the agent',
  );

  @override
  void Function()? claimSettingsBox() => _settingsBox();

  @override
  void settingSaved(List<String> path, SettingChange change) =>
      _settingSaved?.call(path, change);

  /// `_chord/monitors/stop`: monitor [id] of main [key]'s session, or of
  /// its long-lived child [agent], stopped as its agent's own stop.
  StopMonitorAnswer stopMonitorOf(int key, String? agent, String id) =>
      stopMonitorIn(
        _roster,
        Caller(
          role: agent == null ? Role.person : Role.child,
          key: key,
          window: this,
          agent: agent,
        ),
        id,
      );

  /// What chord answered [caller], drawn in its session while the launch
  /// it was admitted for is still up: a session cleared since gets none of
  /// its old calls.
  @override
  void served(Caller caller, ChordCall call) {
    if (_stale(caller)) return;
    _callerConversation(caller)?.served(call);
  }

  /// A receipt that comes later, such as a queued message going in, served
  /// through [served] when it comes, so the launch is checked then. A
  /// task's that comes after it ended no longer reaches its conversation:
  /// it is kept in its record and drawn in its block in the parent.
  @override
  void Function(ChordCall call) servedLater(Caller caller) {
    final id = caller.task;
    final child = id == null ? null : _taskSessions[id];
    final parent = _sessionOf(caller.key, caller.by);
    final task = id == null ? null : parent?.task(id);
    if (id == null || child == null || task == null) {
      return (call) => served(caller, call);
    }
    final block = parent?.endedTaskServed(id);
    // No launch check here, as the original has none: the task's launch
    // is revoked as it ends, and its receipts still belong to its record
    // and its block, which the parent draws only while its session lasts.
    return (call) {
      if (task.running) return child.served(call);
      child.servedEnded(call);
      block?.call(call);
    };
  }

  /// A task's message to the session that started it, main or a child of
  /// it, while the task runs.
  MessageAnswer _taskMessage(
    Caller caller,
    String text,
    void Function() queued,
  ) {
    final owner = _sessionOf(caller.key, caller.by);
    final id = caller.task;
    final task = id == null ? null : owner?.task(id);
    if (task == null || !task.running) {
      return const Refused(
        'Your task has ended; nothing more reaches its parent',
      );
    }
    final delivered = owner?.tell(task.from, text, queued);
    return delivered == null
        ? const Refused('The session that started you has closed')
        : Delivered(
            delivered == Delivery.sent
                ? tools.Delivery.sent
                : tools.Delivery.queued,
          );
  }

  /// A team agent's message, straight to whom it names, never routed
  /// through the lead: a lead's to `main`, to one of its open members,
  /// which hear it from their parent, or to another run's lead; a member's
  /// to its lead or to another open member of its team.
  MessageAnswer _teamTell(
    Caller caller,
    String to,
    String text,
    void Function() queued,
  ) {
    final roster = ownedBy(_roster, caller.key);
    final agent = caller.agent;
    final self = agent == null
        ? null
        : roster?.children.firstWhereOrNull(
            (each) => each.id == agent || each.name == agent,
          );
    final main = roster?.main;
    if (roster == null || main == null || self == null) {
      return const Refused('You are closed; nothing more reaches anyone');
    }
    final from = MessageFrom(self.name, runtime: self.runtime, reachable: true);
    bool named(ChildInfo child) => child.id == to || child.name == to;
    final lead = isLead(self.info)
        ? self
        : roster.children.firstWhereOrNull((each) => each.id == self.lead);
    if (lead == null) {
      return const Refused('Your lead has closed; nothing more reaches it');
    }
    final targets = messageRecipients(roster, self.key);
    final target = targets.firstWhereOrNull(
      (each) => each.id == to || each.name == to,
    );
    if (target?.key == main.key) {
      final delivered = _conversationAt(main.key)?.tell(from, text, queued);
      return delivered == null
          ? const Refused('main has closed')
          : Delivered(
              delivered == Delivery.sent
                  ? tools.Delivery.sent
                  : tools.Delivery.queued,
              to: 'main',
            );
    }
    final member = target == null
        ? null
        : roster.children.firstWhereOrNull(
            (each) => each.key == target.key && each.lead == lead.id,
          );
    if (member != null) {
      return _sentTo(
        member,
        identical(self, lead) ? MessageFrom(lead.name, reachable: true) : from,
        text,
        queued,
      );
    }
    final other = target == null
        ? null
        : roster.children.firstWhereOrNull((each) => each.key == target.key);
    if (other != null) return _sentTo(other, from, text, queued);
    final closed = roster.closed.lastWhereOrNull(
      (each) =>
          named(each) &&
          (each.lead == lead.id || (identical(self, lead) && isLead(each))),
    );
    if (closed != null) {
      return Refused(
        closed.lead == null
            ? '${closed.name} is closed'
            : '${closed.name} is closed; '
                  '${identical(self, lead) ? 'open_agent opens' : '${lead.name} can open'}'
                  ' it again',
      );
    }
    return Refused(
      'No agent $to is open for you; you reach '
      '${andList([for (final each in targets) each.name])}',
    );
  }

  /// The team files where main [key] works, read now, each path as the
  /// window shows it: a project's from the directory main works in, the
  /// user's from `~`.
  Future<List<ListedTeam>> teamsAt(int key) async => [
    for (final found in await findTeams(
      configHome: _configHome,
      cwd: _cwd,
      runtimes: _names,
    ))
      (found: found, shown: _shownTeamFile(found)),
  ];

  /// The runs open in [roster], a lead each, in the order they started.
  List<TeamRun> runsIn(WindowAgents<Conversation> roster) => [
    for (final child in ownChildren(roster))
      if (isLead(child.info))
        (
          id: child.id,
          team: child.info.team!,
          name: child.name,
          since: child.info.openedAt.toInt(),
        ),
  ];

  /// `/team`'s picker and its names: the team files where the window
  /// works, read now, the runs open in it, and the two directories as the
  /// window shows them; null once main has closed.
  Future<TeamListing?> listTeams() async {
    final main = _roster.main;
    if (main == null) return null;
    final teams = await teamsAt(main.key);
    final roster = ownedBy(_roster, main.key);
    if (roster == null) return null;
    final dirs = teamDirs(configHome: _configHome, cwd: _cwd);
    return (
      teams: teams,
      runs: runsIn(roster),
      dirs: (
        project: p.relative(dirs.project, from: _cwd),
        user: dirs.user == null ? null : homePath(dirs.user!, _home),
      ),
    );
  }

  /// The team file [name] where the window works, read now.
  Future<ListedTeam?> _teamNamed(String name) async {
    final main = _roster.main;
    if (main == null) return null;
    return (await teamsAt(
      main.key,
    )).firstWhereOrNull((each) => each.found.name == name);
  }

  /// `/team run`: the run `run_team` starts, for main, with the person's
  /// words as the job; main, which took no part, hears of it ahead of its
  /// next prompt. The call to draw, or why not.
  Future<({ChordCall? ran, String? refused})> runTyped(
    String name,
    String job,
  ) async {
    final main = _roster.main;
    final launch = main == null ? null : LaunchGuard(this, main.key);
    final refused = teamRefusal(name, await _teamNamed(name));
    if (main == null || launch == null || refused != null) {
      return (ran: null, refused: refused ?? 'This session has closed');
    }
    final answer = await runTeamAt(
      main.key,
      (team: name, job: job),
      '/team lists them',
      launch: launch,
    );
    final ran = answer.ran;
    if (ran == null) return (ran: null, refused: answer.refused!.error);
    // Drawn at once, not after the lead's start: the list says the effort
    // it is on, and its transcript a refusal.
    final call = ChordCall(
      tool: ChordTool.runTeam,
      input: {'team': name, 'job': job},
      answer: ran.toJson(),
    );
    _conversationAt(main.key)
      ?..aside(const MessageFrom('chord'), ranNote(name, ran.name, job))
      ..ranTyped(call);
    return (ran: call, refused: null);
  }

  /// `/team stop`: the run [name] closed with its members, at once, as the
  /// person typed it on purpose; [said] hears what it did before main is
  /// told, as for `x`, so the command's line comes first.
  void stopTyped(
    String name,
    TeamWords words,
    void Function(String text, {required bool failed}) said,
  ) {
    final roster = ownedBy(_roster, _roster.main?.key);
    final lead = roster == null
        ? null
        : ownChildren(roster).firstWhereOrNull(
            (child) => isLead(child.info) && child.name == name,
          );
    if (roster == null || lead == null) {
      return said('No run named $name is open · ${words.noRun}', failed: true);
    }
    said(
      stoppedLine(lead.name, [
        for (final member in membersOf(roster, lead.id)) member.name,
      ], words),
      failed: false,
    );
    closeByPerson(lead.key);
  }

  /// `/team show`: team [name] as its file has it; while it runs in the
  /// host, its first run as it stands now, the file as the run read it,
  /// which [fill] turns into what is shown. Why not, if not.
  Future<({TeamShown? shown, String? refused})> showTyped(
    String name,
    ShownTeam Function(
      String file,
      Child<Conversation> lead,
      Team team,
      String job,
      List<Child<Conversation>> members,
    )
    fill,
  ) async {
    final main = _roster.main;
    final roster = main == null ? null : ownedBy(_roster, main.key);
    final running = roster == null
        ? null
        : ownChildren(roster).firstWhereOrNull(
            (child) =>
                isLead(child.info) && (child.id == name || child.name == name),
          );
    final associated = running == null ? null : _runs[running.id];
    // A run ID no open run has: the receipt main's record keeps for it.
    if (associated == null && main != null) {
      final transcript = _transcriptOf?.call(main.key);
      final calls = [
        ...?transcript?.served,
        for (final entry in transcript?.entries ?? const <Entry>[])
          if (entry case ToolEntry(:final call)) ?call.chord,
      ];
      final call = calls.lastWhereOrNull(
        (call) => recordedSelection(call)?['runId'] == name,
      );
      if (call != null) {
        return (shown: TeamReceiptShown(call), refused: null);
      }
    }
    final ListedTeam? found = associated == null
        ? await _teamNamed(name)
        : (found: associated.found, shown: _shownTeamFile(associated.found));
    final refused = teamRefusal(name, found);
    final team = found?.found.team;
    final now = main == null ? null : ownedBy(_roster, main.key);
    if (now == null || found == null || team == null) {
      return (shown: null, refused: refused ?? 'This session has closed');
    }
    final lead = ownChildren(now).firstWhereOrNull(
      (child) =>
          isLead(child.info) &&
          (child.info.team == name || child.id == name || child.name == name),
    );
    final run = lead == null ? null : _runs[lead.id];
    if (lead == null || run == null) {
      return (
        shown: ShownTeam(name: name, file: found.shown, team: team),
        refused: null,
      );
    }
    return (
      shown: fill(
        found.shown,
        lead,
        run.team,
        run.job,
        membersOf(now, lead.id),
      ),
      refused: null,
    );
  }

  /// The run ID of the open selected run whose lead is named [name]; null
  /// for a run not selected, or none open by that name.
  String? selectedRunId(String name) {
    final roster = ownedBy(_roster, _roster.main?.key);
    final lead = roster == null
        ? null
        : ownChildren(roster).firstWhereOrNull(
            (child) =>
                isLead(child.info) && (child.id == name || child.name == name),
          );
    final runId = lead == null
        ? null
        : _runs[lead.id]?.selected?.receipt['runId'];
    return runId is String ? runId : null;
  }

  /// A team file as the window shows it: a project's from the directory
  /// main works in, the user's from `~`.
  String _shownTeamFile(FoundTeam found) => found.place == TeamPlace.project
      ? p.relative(found.file, from: _cwd)
      : homePath(found.file, _home);

  @override
  Future<TeamPlaces> teamPlaces(Caller caller, String name) async {
    final dirs = teamDirs(configHome: _configHome, cwd: _cwd);
    final project = teamFile(dirs.project, name);
    final user = dirs.user == null ? null : teamFile(dirs.user!, name);
    final saved = (await teamsAt(
      caller.key,
    )).firstWhereOrNull((each) => each.found.name == name);
    // A project's file from the directory main works in, the user's from ~.
    PlacedFile shown(String file) => (
      file: file,
      shown:
          file == project ||
              (saved?.found.place == TeamPlace.project &&
                  file == saved?.found.file)
          ? p.relative(file, from: _cwd)
          : homePath(file, _home),
    );
    return (
      agent: ownedBy(_roster, caller.key)?.main?.agent ?? 'the agent',
      project: shown(project),
      user: user == null ? null : shown(user),
      saved: saved == null
          ? null
          : (
              file: saved.found.file,
              shown: shown(saved.found.file).shown,
              team: saved.found.team,
            ),
    );
  }

  @override
  Future<TeamsFound> teams(Caller caller) async {
    final roster = ownedBy(_roster, caller.key);
    return (
      found: [for (final listed in await teamsAt(caller.key)) listed.found],
      runs: [
        if (roster != null)
          for (final child in ownChildren(roster))
            if (child.team case final team?)
              (team: team, name: child.name, id: child.id),
      ],
    );
  }

  /// Where [placed]'s start left an effort asked for: the one it is on,
  /// and why it is not the one asked, if not.
  Future<({String? effort, String? note})> _effortOf(
    int placed,
    Future<void> started,
    SpawnArgs args,
  ) async {
    if (args.effort == null) return (effort: null, note: null);
    await started;
    final conversation = _conversationAt(placed);
    final session = conversation?.session;
    return (
      effort: session == null
          ? null
          : effortsFrom(session.state.configOptions)?.current,
      note: conversation?.effortRefused,
    );
  }

  /// `run_team`, and `/team run`: the team's lead opened as a child of main
  /// [key], named after the team and numbered past its first run, on the
  /// lead's runtime, model, effort and mode, with the team part and the
  /// job as main's message. Refused for a team not found, [lists] saying
  /// what lists them, a file that fails its check, and as `open_agent` is.
  /// The run, and where the file's effort left the lead once it is up.
  Future<({Refused? refused, Started? ran, Future<Started>? started})>
  runTeamAt(
    int key,
    RunTeamArgs args,
    String lists, {
    Caller? caller,
    LaunchGuard? launch,
  }) async {
    const cancelled = Refused('This launch was cancelled; no run started.');
    launch ??= LaunchGuard(this, key, caller);
    if (!launch.valid()) return (refused: cancelled, ran: null, started: null);
    final found = (await teamsAt(
      key,
    )).firstWhereOrNull((each) => each.found.name == args.team);
    if (found == null) {
      return (
        refused: Refused('No team named ${args.team} · $lists'),
        ran: null,
        started: null,
      );
    }
    final team = found.found.team;
    if (team == null) {
      return (
        refused: Refused(
          '${found.shown} is not a team chord can run: ${found.found.problem}',
        ),
        ran: null,
        started: null,
      );
    }
    final lead = team.lead;
    final spawn = SpawnArgs(
      agent: lead.agent,
      prompt: args.job,
      model: lead.model,
      effort: lead.effort,
      mode: lead.mode,
    );
    final refused =
        await _startRefusal(
          key,
          _conversationAt(key),
          spawn,
          'agent',
          args.team,
        ) ??
        _fullRefusal(key);
    final roster = ownedBy(_roster, key);
    if (!launch.valid()) return (refused: cancelled, ran: null, started: null);
    if (roster == null || refused != null) {
      return (
        refused: Refused(refused ?? 'This session has closed'),
        ran: null,
        started: null,
      );
    }
    final name = runName(roster, args.team);
    final others = [
      for (final child in ownChildren(roster))
        if (isLead(child.info)) child.name,
    ];
    final frozen = _frozen(team);
    final opened = _openChild(
      key,
      roster,
      spawn,
      'set by team ${args.team}',
      named: name,
      team: (name: args.team, lead: null),
      part: teamPart(
        args.team,
        frozen,
        LeadRole(lead: name, others: others),
        _cwd,
      ),
      launch: launch,
    );
    if (opened == null) {
      return (
        refused: Refused(_fullRefusal(key) ?? 'This session has closed'),
        ran: null,
        started: null,
      );
    }
    // Registered before its first job goes, so a lead's first open_agent
    // finds its run.
    _runs[opened.id] = (
      found: found.found,
      team: frozen,
      job: args.job,
      selected: null,
    );
    final ran = Started(
      id: opened.id,
      name: name,
      agent: spawn.agent,
      model: spawn.model,
      mode: spawn.mode,
      team: args.team,
    );
    return (
      refused: null,
      ran: ran,
      started: _effortOf(
        opened.placed,
        opened.started,
        spawn,
      ).then((started) => ran.withEffort(started.effort, started.note)),
    );
  }

  @override
  Future<RunTeamAnswer> runTeam(
    Caller caller,
    RunTeamArgs args, {
    Object? selection,
  }) async {
    if (_stale(caller)) return stale;
    final launch = LaunchGuard(this, caller.key, caller);
    if (selection != null) {
      if (!launch.valid()) {
        return const Refused('This launch was cancelled; no run started.');
      }
      return _runSelectedTeamAt(
        caller.key,
        args,
        selection,
        'list_teams lists them',
        launch,
      );
    }
    final answer = await runTeamAt(
      caller.key,
      args,
      'list_teams lists them',
      launch: launch,
    );
    final ran = answer.ran;
    if (ran == null) return answer.refused!;
    // As open_agent's, the answer waits on a lead given an effort.
    final started = await answer.started!;
    if (!launch.committed && (!launch.valid() || _keyOf(ran.id) == null)) {
      return Refused(
        'Team launch ${ran.id} was cancelled before its first job; the '
        'attempted lead is closing.',
      );
    }
    return started;
  }

  /// The merged teamSelection policy, read now; a throw says the settings
  /// could not be checked.
  Future<({Map<String, Object?>? policy, String? error})> _policyNow() async {
    try {
      return await (_selectionPolicy?.call() ??
          readTeamSelection(configHome: _configHome, cwd: _cwd, home: _home));
    } on Object {
      return (
        policy: null,
        error:
            'Team selection settings could not be validated. Correct the '
            'settings before selecting a team.',
      );
    }
  }

  /// What [agent] is known to offer where main [key] works, without
  /// starting it: null when nothing is known; an error for a runtime its
  /// settings refuse.
  Future<({SelectionCapabilities? known, String? error})> _capabilities(
    String agent,
    int key,
  ) async {
    // A configured refusal is known before probing; missing evidence is
    // different.
    if (_startOf(agent)?.refused != null) {
      return (
        known: null,
        error: 'The selected runtime configuration is unavailable.',
      );
    }
    final offer = await this.offer(agent, probe: false, key: key);
    if (offer is! Offer) return (known: null, error: null);
    return (
      known: (
        models: offer.models.isEmpty
            ? null
            : [
                for (final model in offer.models)
                  (
                    id: model.id,
                    efforts: model.efforts == null
                        ? null
                        : [for (final effort in model.efforts!) effort.id],
                  ),
              ],
        modes: offer.modes == null
            ? null
            : [for (final mode in offer.modes!) mode.id],
        efforts: offer.efforts == null
            ? null
            : [for (final effort in offer.efforts!) effort.id],
      ),
      error: null,
    );
  }

  /// [run]'s receipt with role [name] of [kind] refused for [reason],
  /// published again.
  void _refuseSelected(
    SelectedRun run,
    String kind,
    String name,
    String reason,
  ) {
    run.receipt = {
      ...run.receipt,
      'roles': [
        for (final role in (run.receipt['roles'] as List).cast<Map>())
          role['role'] == kind && role['name'] == name
              ? {...role, 'state': 'refused', 'note': reason}
              : role,
      ],
    };
    run.publish();
  }

  /// [run]'s role [name] of [kind] confirmed or refused by what
  /// [conversation]'s session came up on, published again; why it was
  /// refused, if it was.
  String? _confirmSelected(
    SelectedRun run,
    String kind,
    String name,
    Conversation conversation,
  ) {
    final roles = (run.receipt['roles'] as List).cast<Map>();
    final role = roles.firstWhere(
      (role) => role['role'] == kind && role['name'] == name,
    );
    String? bounded(String? value) =>
        value != null && value.isNotEmpty && value.length <= 128 ? value : null;
    final session = conversation.session;
    final state = session?.state;
    final actual = <String, Object?>{
      'agent': bounded(session?.agent),
      'model': bounded(
        state == null
            ? null
            : modelsFrom(state.configOptions, state.models)?.current,
      ),
      'mode': bounded(
        state == null
            ? null
            : modesFrom(state.configOptions, state.modes)?.current,
      ),
      'effort': bounded(
        state == null ? null : effortsFrom(state.configOptions)?.current,
      ),
    };
    final planned = role['planned'] as Map;
    final soft =
        planned['effort'] != null &&
        (conversation.effortRefused != null ||
            planned['effort'] != actual['effort']);
    final confirmed = confirmSelectionRole(
      role.cast<String, Object?>(),
      actual,
      soft
          ? 'The requested effort was not confirmed; the runtime effort '
                'remains advisory.'
          : null,
    );
    run.receipt = {
      ...run.receipt,
      'roles': [
        for (final each in roles) identical(each, role) ? confirmed : each,
      ],
    };
    run.publish();
    return confirmed['state'] == 'refused'
        ? (confirmed['note'] as String? ??
              'The selected configuration was not confirmed.')
        : null;
  }

  /// `run_team` with a selection: the saved team re-checked against the
  /// person's policy now and what each runtime is known to offer, frozen,
  /// its lead admitted and opened on the frozen choice, and the run's
  /// receipt served as each role is confirmed or refused, appended to the
  /// records captured when the launch was admitted.
  Future<RunTeamAnswer> _runSelectedTeamAt(
    int key,
    RunTeamArgs args,
    Object selection,
    String lists,
    LaunchGuard launch,
  ) async {
    const cancelled = Refused('This launch was cancelled; no run started.');
    final found = (await teamsAt(
      key,
    )).firstWhereOrNull((each) => each.found.name == args.team);
    if (!launch.valid()) return cancelled;
    if (found == null) return Refused('No team named ${args.team} · $lists');
    final saved = found.found.team;
    if (saved == null) {
      return const Refused('The saved team is invalid. No run started.');
    }
    final policy = await _policyNow();
    if (policy.error case final error?) return Refused(error);
    final preliminary = freezeSelection(
      saved,
      selection,
      policy.policy!,
      _names,
    );
    if (preliminary.error case final error?) return Refused(error);
    final first = preliminary.frozen!.team;
    final capabilities = <String, SelectionCapabilities>{};
    for (final agent in {
      first.lead.agent,
      for (final member in first.members) member.agent,
    }) {
      final (:known, :error) = await _capabilities(agent, key);
      if (error != null) {
        final roles = [
          if (first.lead.agent == agent) 'lead',
          for (final member in first.members)
            if (member.agent == agent) member.name,
        ];
        return Refused('${roles.join(', ')}.agent: $error No run started.');
      }
      if (known != null) capabilities[agent] = known;
      if (!launch.valid()) return cancelled;
    }
    final chosen = freezeSelection(
      saved,
      selection,
      policy.policy!,
      _names,
      capabilities: capabilities,
    );
    if (chosen.error case final error?) return Refused(error);
    final frozen = chosen.frozen!;
    final lead = frozen.team.lead;
    final opening = SpawnArgs(
      agent: lead.agent,
      prompt: args.job,
      model: lead.model,
      effort: lead.effort,
      mode: lead.mode,
    );
    final refused =
        await _startRefusal(
          key,
          _conversationAt(key),
          opening,
          'agent',
          args.team,
        ) ??
        _fullRefusal(key);
    final roster = ownedBy(_roster, key);
    if (!launch.valid()) return cancelled;
    if (refused != null || roster == null) {
      return const Refused(
        'The selected lead cannot be admitted. No run started.',
      );
    }
    final id = const Uuid().v4().substring(0, 8);
    final name = runName(roster, args.team);
    // The records the launch was admitted to: a late receipt lands there,
    // whatever main or the lead has become.
    final write = _conversationAt(key)?.captureServed();
    void Function(ChordCall call)? leadWrite;
    late final SelectedRun selected;
    selected = SelectedRun(
      frozen,
      selectionReceipt(id, (
        name: found.found.name,
        place: found.found.place.name,
      ), frozen),
      () {
        final failed = (selected.receipt['roles'] as List)
            .cast<Map>()
            .firstWhereOrNull(
              (role) => role['role'] == 'lead' && role['state'] == 'refused',
            );
        final call = ChordCall(
          tool: ChordTool.runTeam,
          input: {'team': args.team, 'job': args.job, 'selection': selection},
          asked: id,
          answer: {
            'id': id,
            'name': name,
            'team': args.team,
            'agent': lead.agent,
            'receipt': selected.receipt,
          },
          error: failed == null
              ? null
              : 'Team launch $id: ${failed['note'] ?? 'The lead was refused '
                        'before its first job.'}',
        );
        write?.call(call);
        leadWrite?.call(call);
      },
    );
    // Registered before its first job goes, so a lead's first open_agent
    // finds its run.
    _runs[id] = (
      found: found.found,
      team: frozen.team,
      job: args.job,
      selected: selected,
    );
    final opened = _openChild(
      key,
      roster,
      opening,
      'selected for team ${args.team}',
      id: id,
      named: name,
      team: (name: args.team, lead: null),
      part: teamPart(
        args.team,
        frozen.team,
        LeadRole(
          lead: name,
          others: [
            for (final child in ownChildren(roster))
              if (isLead(child.info)) child.name,
          ],
        ),
        _cwd,
      ),
      launch: launch,
      checkStarted: (conversation) {
        leadWrite = conversation.captureServed();
        return _confirmSelected(selected, 'lead', 'lead', conversation);
      },
      refused: (reason) => _refuseSelected(selected, 'lead', 'lead', reason),
    );
    selected.publish();
    final invalid = opened == null
        ? 'The attempted agent could not be opened.'
        : await opened.validated;
    if (invalid != null || !launch.committed) {
      return RunRefused(
        'Team launch $id was refused before its first job; the attempted '
        'lead is closing.',
        id: id,
        receipt: selected.receipt,
      );
    }
    final observed = (selected.receipt['roles'] as List).cast<Map>().firstWhere(
      (role) => role['role'] == 'lead',
    );
    final actual = observed['actual'] as Map?;
    return Started(
      id: id,
      name: name,
      agent: opening.agent,
      model: opening.model,
      mode: opening.mode,
      team: args.team,
      effort: actual?['effort'] as String?,
      note: observed['note'] as String?,
      receipt: selected.receipt,
    );
  }

  /// A selected run's member opened: the policy and the runtime's offer
  /// read again at admission, the member opened on the run's frozen choice,
  /// and its receipt role confirmed or refused.
  Future<OpenAnswer> _openSelectedMember(
    Caller caller,
    Child<Conversation> lead,
    _Run run,
    SelectedRun selected,
    TeamMember defined,
    SpawnArgs spawn,
    String? Function() occupied,
  ) async {
    final key = caller.key;
    final member = defined.name;
    final launch = LaunchGuard(this, key, caller);
    final policy = await _policyNow();
    final capabilities = await _capabilities(defined.agent, key);
    final invalid =
        policy.error ??
        (capabilities.error != null
            ? '$member.agent: ${capabilities.error}'
            : validateSelectedRole(
                member,
                (
                  agent: defined.agent,
                  model: defined.model,
                  effort: defined.effort,
                  mode: defined.mode,
                ),
                policy.policy!,
                _names,
                capabilities: capabilities.known,
                explicit: selected.frozen.selection.members?[member],
                member: true,
              ));
    // A competing request's admission is not this role's startup failure.
    final raced = occupied();
    if (raced != null) return Refused(raced);
    final unavailable =
        invalid ??
        (!launch.valid()
            ? 'The member request was cancelled before admission.'
            : null);
    if (unavailable != null) {
      _refuseSelected(selected, 'member', member, unavailable);
      return Refused(unavailable);
    }
    final roster = ownedBy(_roster, key);
    if (roster == null) {
      return const Refused('You are closed; you open no members');
    }
    final opened = _openChild(
      key,
      roster,
      spawn,
      'selected for team ${run.found.name}',
      named: member,
      team: (name: run.found.name, lead: lead.id),
      part: teamPart(
        run.found.name,
        run.team,
        MemberRole(member: defined, lead: lead.name),
        _cwd,
      ),
      from: MessageFrom(lead.name, reachable: true),
      parent: () => lead.conversation,
      launch: launch,
      checkStarted: (conversation) =>
          _confirmSelected(selected, 'member', member, conversation),
      refused: (reason) => _refuseSelected(selected, 'member', member, reason),
    );
    final failed = opened == null
        ? 'The attempted agent could not be opened.'
        : await opened.validated;
    if (failed != null || !launch.committed) {
      return Refused(
        '$member was refused before its first job; the attempted member is '
        'closing.',
      );
    }
    final observed = (selected.receipt['roles'] as List).cast<Map>().firstWhere(
      (role) => role['role'] == 'member' && role['name'] == member,
    );
    final actual = observed['actual'] as Map?;
    return Started(
      id: opened!.id,
      name: member,
      agent: spawn.agent,
      model: spawn.model,
      mode: spawn.mode,
      effort: actual?['effort'] as String?,
      note: observed['note'] as String?,
    );
  }

  /// The key of the child chord's id [id] names, while it is open.
  int? _keyOf(String id) =>
      _roster.children.firstWhereOrNull((each) => each.id == id)?.key;

  @override
  Future<OpenAnswer> openMember(Caller caller, MemberArgs args) async {
    if (_stale(caller)) return stale;
    final key = caller.key;
    final agent = caller.agent;
    const closed = Refused('You are closed; you open no members');
    final lead = agent == null
        ? null
        : ownedBy(
            _roster,
            key,
          )?.children.firstWhereOrNull((each) => each.id == agent);
    final run = lead == null ? null : _runs[lead.id];
    if (lead == null || run == null) return closed;
    final member = args.member;
    final defined = run.team.members.firstWhereOrNull(
      (each) => each.name == member,
    );
    if (defined == null) {
      return Refused(
        'Team ${run.found.name} has no member $member; its members are '
        '${andList([for (final each in run.team.members) each.name])}',
      );
    }
    // Why the member cannot open now: its lead closed, or it is open.
    String? occupied() {
      final roster = ownedBy(_roster, key);
      if (roster == null ||
          !roster.children.any((each) => each.id == lead.id)) {
        return closed.error;
      }
      return membersOf(roster, lead.id).any((each) => each.name == member)
          ? '$member is open; send_message reaches it'
          : null;
    }

    final open = occupied();
    if (open != null) return Refused(open);
    final spawn = SpawnArgs(
      agent: defined.agent,
      prompt: args.prompt,
      model: defined.model,
      effort: defined.effort,
      mode: defined.mode,
    );
    // Asked again after the wait: two calls for one member may both have
    // passed the first look, and the lead may have closed meanwhile.
    final refused = await _startRefusal(
      key,
      lead.conversation,
      spawn,
      'agent',
      member,
    );
    final raced = occupied();
    if (raced != null) return Refused(raced);
    final selected = run.selected;
    if (refused != null) {
      if (selected == null) return Refused(refused);
      final safe =
          '$member cannot be admitted on the selected configuration; no '
          'first job was delivered.';
      _refuseSelected(selected, 'member', member, safe);
      return Refused(safe);
    }
    if (selected != null) {
      return _openSelectedMember(
        caller,
        lead,
        run,
        selected,
        defined,
        spawn,
        occupied,
      );
    }
    final roster = ownedBy(_roster, key);
    if (roster == null) return closed;
    final opened = _openChild(
      key,
      roster,
      spawn,
      'set by team ${run.found.name}',
      named: member,
      team: (name: run.found.name, lead: lead.id),
      part: teamPart(
        run.found.name,
        run.team,
        MemberRole(member: defined, lead: lead.name),
        _cwd,
      ),
      from: MessageFrom(lead.name, reachable: true),
      parent: () => _conversationAt(lead.key),
    );
    if (opened == null) return closed;
    final started = await _effortOf(opened.placed, opened.started, spawn);
    return Started(
      id: opened.id,
      name: member,
      agent: spawn.agent,
      model: spawn.model,
      mode: spawn.mode,
      effort: started.effort,
      note: started.note,
    );
  }

  @override
  Future<Budgets>? budgets(
    Caller caller,
    List<String>? agents,
    CancellationToken cancelled,
  ) => _resources?.call(agents, (
    cwd: _cwd,
    commandOf: (agent) =>
        _names.contains(agent) ? _startOf(agent)?.agentCommand : null,
  ), cancelled);

  /// Gives up on the runtimes' reads under way, which close their
  /// sessions, as the window closes.
  void shutDown() => _offers.close();
}

/// `a, b and c`.
String _andList(List<String> names) => names.length < 2
    ? names.join()
    : '${names.take(names.length - 1).join(', ')} and ${names.last}';

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T each) test) {
    for (final each in this) {
      if (test(each)) return each;
    }
    return null;
  }

  T? lastWhereOrNull(bool Function(T each) test) {
    T? found;
    for (final each in this) {
      if (test(each)) found = each;
    }
    return found;
  }
}
