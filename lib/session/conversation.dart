/// One session and the turn in flight in it, driven for the window: it
/// opens the session, plays each prompt and the agent's updates out as
/// [ConversationEvent]s, holds the prompts sent during a turn, cancels, and
/// closes the agent. It holds no state the window draws; that is
/// `reduceApp`'s job. The original's `conversation.ts`, cut to the
/// person's prompts.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cancellation_token/cancellation_token.dart';
import 'package:clock/clock.dart';
import 'package:uuid/uuid.dart';

import '../acp/connection.dart';
import '../acp/process.dart' show StderrTail;
import '../acp/rpc.dart' show OnCancel;
import '../kept.dart';
import '../images.dart' show PastedImage;
import '../acp/schema.dart' as acp;
import 'agent_state.dart';
import 'choice.dart';
import 'config.dart';
import 'cycles.dart';
import '../cost_counts.dart';
import 'efforts.dart';
import 'initial_options.dart';
import 'modes.dart';
import '../js_trim.dart';
import 'monitors.dart';
import 'window_monitors.dart' show MonitorsKeeper;
import '../server/tools.dart'
    show
        MonitorAnswer,
        Refused,
        StartedMonitor,
        StopMonitorAnswer,
        StoppedMonitor;
import 'models.dart';
import 'parameters.dart';
import 'elicitations.dart';
import 'permissions.dart';
import 'plan_asks.dart';
import 'record.dart';
import 'replay.dart' show PastEvent, historyEntries, titled;
import 'servers.dart' show heldBackLine;
import 'session.dart';
import 'sessions.dart';
import 'sign_in.dart' show SignIn, signInOf;
import 'start_failure.dart' as failure;
import 'start_failure.dart' show StartFailure;
import 'starting.dart';
import 'turn_costs.dart';
import 'open_agents.dart' show Driven;
import 'tasks.dart'
    show
        TaskAgent,
        TaskParent,
        TaskSession,
        teamBlock,
        wrapMessage,
        wrapTeamMessage;
import 'transcript/types.dart';

/// How long the agent must be silent after an answer to have finished.
const quietMs = 1000;

/// How long the next queued prompt waits for that silence at most.
const settleLimitMs = 5000;

/// Delay before a dispatched personal steering row shows its pending label.
const steerShownMs = 500;

/// The updates after which the agent's modes, options or commands may
/// differ.
const _stateUpdates = {
  'config_option_update',
  'current_mode_update',
  'available_commands_update',
};

/// Something the window folds: a transcript action, or a fact of the
/// session's.
sealed class ConversationEvent {
  const ConversationEvent();
}

/// A transcript action, as the reducer folds it.
final class Transcribed extends ConversationEvent {
  const Transcribed(this.action);

  /// The action.
  final TranscriptAction action;
}

/// The person's command started a call of chord's for the session, as
/// `/new` opens an agent: for its record, which the command drew already.
/// Its own line, not a served one, as no call of the agent's asked for it.
final class RanTyped extends ConversationEvent {
  const RanTyped(this.turnId, this.call);

  /// The turn it came in.
  final String turnId;

  /// The call, as the command's row draws it.
  final ChordCall call;
}

/// A long-lived agent of the session's, chord's id [id], was closed while
/// the session went on: for its record, so a resume does not name it open.
final class AgentClosed extends ConversationEvent {
  const AgentClosed(this.id);

  /// chord's id for the agent.
  final String id;
}

/// One detached historical batch, published before subscribing to live updates.
final class HistoryReplayed extends ConversationEvent {
  HistoryReplayed(
    Iterable<TranscriptAction> actions, {
    required this.state,
    this.resumed,
    this.omitted = false,
    this.past,
  }) : actions = List.unmodifiable(actions);
  final List<TranscriptAction> actions;
  final AgentState state;
  final Resume? resumed;
  final bool omitted;

  /// The raw ACP past, when the session was opened to keep one.
  final List<PastEvent>? past;
}

/// A cost update of a session `/clear` or a resume let go, under its last
/// turn: kept in that session's record, so a resume counts on from it.
final class RetiredUpdate extends ConversationEvent {
  const RetiredUpdate(this.turnId, this.update);
  final String turnId;
  final acp.SessionUpdate update;
}

/// The figures of a turn of a session `/clear` or a resume let go, at its
/// end or as its cost came after: that session's, kept in its record; the
/// window shows nothing of them.
final class RetiredUsage extends ConversationEvent {
  const RetiredUsage(this.figures);
  final TurnFigures figures;
}

/// The session is open.
final class Connected extends ConversationEvent {
  const Connected(this.sessionId, this.state, {this.at});

  /// When it came up, epoch milliseconds.
  final num? at;

  /// The agent's id for the session.
  final String sessionId;

  /// What the agent said of the session as it opened.
  final AgentState state;
}

/// The session did not open.
final class ConnectFailed extends ConversationEvent {
  const ConnectFailed(this.message, {this.signIn, this.failure, this.error});

  /// Why, in the agent's or chord's words.
  final String message;

  /// The error's own message, without the words a start's failure is said
  /// in, as the original's event carries it.
  final String? error;

  /// The login the agent needs, when that is why it did not start.
  final SignIn? signIn;

  /// Why it did not start, as chord knows it.
  final StartFailure? failure;
}

/// The agent's modes, options or commands may have moved.
final class AgentStateChanged extends ConversationEvent {
  const AgentStateChanged(this.state);

  /// What the agent has said of the session now.
  final AgentState state;
}

/// A command note, replaced by id as a setting's pending step settles.
final class SettingNoted extends ConversationEvent {
  const SettingNoted(this.id, this.command, this.text, {this.failed = false});
  final String id;
  final String command;
  final String text;
  final bool failed;
}

/// A requested mode waiting for its acknowledgement, or its completed request.
final class ModePending extends ConversationEvent {
  const ModePending(this.id, {required this.pending});
  final String id;
  final bool pending;
}

/// A prompt waits behind the running turn, or behind a request between
/// turns when [afterAnswer]; told again once what it waits for changes.
final class Queued extends ConversationEvent {
  const Queued(
    this.turnId,
    this.text, {
    this.afterAnswer = false,
    this.afterCalls = false,
    this.steering = false,
    this.taken = false,
    this.refused = false,
    this.from,
  });

  /// The turn it will be.
  final String turnId;

  /// What the person typed, or the message's words.
  final String text;

  /// Who sent it, when another agent or chord did.
  final MessageFrom? from;

  /// It waits for the answer to a request asked between turns.
  final bool afterAnswer;

  /// Explicitly held for the calls open when this steer arrived.
  final bool afterCalls;

  /// Dispatched and unanswered long enough to show the pending label.
  final bool steering;

  /// Taken at dispatch, including serialization and mention resolution.
  final bool taken;

  /// Refused while its target turn still runs, with its queue place restored.
  final bool refused;
}

/// The person's queued prompts taken back, with their text, oldest first.
final class QueueWithdrawn extends ConversationEvent {
  const QueueWithdrawn(this.prompts);

  /// The prompts taken back.
  final List<QueuedPrompt> prompts;
}

/// The agent went on its own, with the end of its stderr.
final class Gone extends ConversationEvent {
  const Gone(this.reason, {this.stderrLines = const [], this.stderrCut = 0});

  /// `The agent exited.`
  final String reason;

  /// The last non-empty lines of its stderr.
  final List<String> stderrLines;

  /// How many non-empty lines came before [stderrLines].
  final int stderrCut;
}

/// The old session is retired and the replacement is starting.
final class Cleared extends ConversationEvent {
  const Cleared();
}

/// The session took the title [title] at [at]: the agent's answer, or the
/// one typed for an agent that takes none.
final class Renamed extends ConversationEvent {
  /// A rename to [title] at [at], epoch milliseconds.
  const Renamed(this.title, this.at);

  /// The title kept.
  final String title;

  /// When, epoch milliseconds.
  final num at;
}

/// A rename the session took: its title, and whether its agent took it.
typedef RenameTaken = ({String title, bool agent});

/// The conversation is closing; nothing is emitted after this.
final class Closing extends ConversationEvent {
  const Closing();
}

/// The session's monitors still running, whenever one starts, hands on an
/// event or ends, and those ended since it came up, in the order they
/// ended; the window's alone, as none is restarted on a resume.
final class MonitorsChanged extends ConversationEvent {
  const MonitorsChanged(this.running, this.ended);

  final List<RunningMonitor> running;
  final List<EndedMonitor> ended;
}

/// A prompt the person sent that waits behind the turn in flight.
final class QueuedPrompt {
  const QueuedPrompt(
    this.turnId,
    this.text, {
    this.sentPrompt,
    this.mentions = const [],
    this.held = const [],
    this.afterAnswer = false,
    this.afterCalls = false,
    this.steering = false,
    this.taken = false,
    this.place,
    this.parts = PromptParts.none,
    this.images = const [],
    this.from,
    this.team,
  });

  /// Who sent it, when another agent or chord did: a message, which Esc
  /// never takes into the box.
  final MessageFrom? from;

  /// The team part that goes ahead of a team agent's first message.
  final TeamPart? team;

  /// The draft's images that went with it, by their numbers, back in the
  /// draft if it comes back; the window's, as [held] is.
  final List<PastedImage> images;

  /// What it carries beside its text: images, resources and links.
  final PromptParts parts;

  /// Queue order retained when a dispatched steer is put back.
  final int? place;

  /// Explicit call hold, pending label and dispatch ownership of a drawn row.
  final bool afterCalls, steering, taken;

  /// Optional agent payload captured when the prompt was accepted.
  final String? sentPrompt;

  /// Literal typed mention paths, resolved by the owning session at send time.
  final List<String> mentions;

  /// UI-owned shell run IDs captured by this queued prompt.
  final List<String> held;

  /// The immutable payload sent to the agent, including held shell context.
  String get prompt => sentPrompt ?? text;

  /// The turn it will be.
  final String turnId;

  /// What the person typed.
  final String text;

  /// It waits for the answer to a request asked between turns.
  final bool afterAnswer;
}

/// How a prompt went: at once, or into the queue.
enum Delivery {
  /// Played at once.
  sent,

  /// Held behind the turn in flight or a request between turns.
  queued,
}

/// Opens the conversation's session, its traffic going to [onTraffic],
/// given up when [cancellationToken] is cancelled.
typedef OpenConversationSession =
    Future<Session> Function({
      required void Function(Traffic traffic) onTraffic,
      required CancellationToken cancellationToken,
    });

/// Opens a selected earlier session through the same owned transport path.
typedef OpenResumedConversationSession =
    Future<Session> Function(
      Resume resume, {
      required void Function(Traffic traffic) onTraffic,
      required CancellationToken cancellationToken,
    });

final class _Asked {
  _Asked(this.request, this.turnId, {required this.between});

  final PendingPermission request;
  final String turnId;
  bool between;
}

/// A form or link on screen, under the turn it was asked in.
final class _Elicited {
  _Elicited(this.request, this.turnId, {required this.between});

  final PendingElicitation request;
  final String turnId;

  /// Asked, or left open, with no turn running.
  bool between;
}

/// A wait that an abort ends at once.
final class _Quiet {
  Timer? _timer;
  Completer<void>? _done;
  var aborted = false;

  Future<void> wait(int ms) {
    if (aborted) return Future.value();
    final done = _done = Completer<void>();
    _timer = Timer(Duration(milliseconds: ms), done.complete);
    return done.future;
  }

  void abort() {
    aborted = true;
    _timer?.cancel();
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }
}

/// What each session the conversation opens is put on before it is shown.
class Starting {
  const Starting({this.model, this.mode, this.effort, this.entries = const []});

  /// A `chord acp` client's initial config options, as it sent them: each
  /// read back once the session is up and set where it is not current,
  /// beating chord's own value for the same option.
  final List<Map<String, Object?>> entries;

  /// A model, as `/model` sets it.
  final StartingValue? model;

  /// A mode, as shift+tab sets it.
  final StartingValue? mode;

  /// An effort, asked for after the model, whose own efforts the agent
  /// offers. Never required: a refusal leaves the session on the agent's own.
  final StartingValue? effort;

  /// The ids, for `session/new`'s initial values.
  InitialValues get initial =>
      (model: model?.id, effort: effort?.id, mode: mode?.id);
}

/// One session and the turn in flight in it, driven for the window.
final class Conversation implements Driven, TaskSession, MonitorsKeeper {
  /// A conversation over the session [open] opens, once [start]ed, put on
  /// [starting] before it is shown.
  Conversation(
    this._open, {
    this._recording,
    this._reopen,
    Resume? resume,
    this.starting = const Starting(),
    List<String> warnings = const [],
  }) : _selectedResume = resume,
       _warnings = List.unmodifiable(warnings);

  /// What the settings files got wrong, said before anything the session
  /// says, once.
  List<String> _warnings;

  /// What each session it opens is put on before it is shown.
  final Starting starting;
  var _startingFailures = 0;

  final OpenConversationSession _open;
  final OpenResumedConversationSession? _reopen;
  final Recording? _recording;
  Resume? _selectedResume;
  ({String agent, String sessionId})? _resumable;
  var _ready = false, _recordWarning = false;

  /// The session open now, once acquired; none before or after.
  Session? get session => _session;

  /// Whether the conversation is closing or closed: no launch from it
  /// stands any more.
  bool get closing => _closing != null;

  /// Only submitted work or a successfully reopened current main is resumable.
  ({String agent, String sessionId})? get resumable => _resumable;

  /// Where the [resumable] session's record is kept, when it has a file
  /// record: [quitRecordId] checks it on disk before the quit line names it
  /// (the owner's departure, CTUI-176).
  String? get resumableRecord => _resumableRecord;
  String? _resumableRecord;

  // Taken when the session becomes resumable: the record's path is let go
  // when it closes, before the quit line is printed.
  void _resumed(Session session) {
    _resumable = (agent: session.agent, sessionId: session.id);
    if (_recording case FileRecording(:final path?)) _resumableRecord = path;
  }

  /// Settles once the session's first prompt is in its record, flushed, so
  /// `--resume` can open it; at once for a session opened again, which it
  /// opens already.
  Future<void> recorded() => _recorded.future;
  var _recorded = Completer<void>();

  /// The record's write of what was just sent settles [recorded].
  void _flushedFirst() {
    final recorded = _recorded;
    (_recording?.flushed() ?? Future<void>.value()).then((_) {
      if (!recorded.isCompleted) recorded.complete();
    }, onError: (Object _) {});
  }

  /// The session's first prompt, as it was sent; its past's for a session
  /// opened again; none before the first.
  String? get firstPrompt => _firstPrompt;
  String? _firstPrompt;

  /// The session's title: the last rename, else the last title its agent
  /// gave it in a `session_info_update`, its past's too; none while it has
  /// none.
  String? get title => _title;

  String? _effortRefused;

  /// What the refusal of the starting effort said, for a tool's answer:
  /// `Could not start on max effort, …`; null when it took it or none was
  /// asked for.
  String? get effortRefused => _effortRefused;
  String? _title;
  final _listeners = <void Function(ConversationEvent event)>[];
  var _stderr = StderrTail();
  final _queued = <QueuedPrompt>[];

  // The session's monitors still running, by id, in start order.
  final _monitors = <String, _Monitoring>{};
  // Monitors the person stopped, off the list at once, until their end
  // has been told to the agent.
  final _ending = <String, _Monitoring>{};
  // What the session's past says of its monitors; an end adds to it.
  var _monitorsPast = MonitorsPast.none;
  // How each monitor ended since, by id, as its end's word says it.
  final _monitorsEnded = <String, String>{};
  // The monitors ended since the session came up, as the window shows them.
  var _endedMonitors = <EndedMonitor>[];
  // The last monitor id's number given out.
  var _monitorCount = 0;
  // Monitors stopping, which a close waits for to be gone. Like every
  // future here kept for a later wait, each is Kept: the wait may come from
  // another error zone than the one that began it (CTUI-114).
  final _monitorsStopping = <Kept<void>>{};
  // Monitors whose shell is still starting: counted against the limit, and
  // stopped by a close at once, before their launcher's `setsid` too, which
  // then waits for them to be gone (CTUI-156).
  var _monitorsStarting = 0;
  final _monitorsStartingRuns = <MonitorRun>{};
  final _monitorsPending = <Future<void>>{};
  // Moves on with each stop of them all, so one that was still starting
  // then is not this session's.
  var _monitorEpoch = 0;

  // Another's messages held behind the turn's calls or the person's
  // answer, not sent yet, by their turn: a clear counts them dropped.
  final _incoming = <String, MessageFrom>{};

  /// Who sent the messages queued here, the person's own left out: those a
  /// clear drops.
  List<MessageFrom> get queuedFrom => [
    for (final queued in _queued) ?queued.from,
    ..._incoming.values,
  ];
  final _permissions = <String, _Asked>{};

  // Lines to go ahead of the person's next prompt, as a stopped task's.
  final _ahead = <String>[];

  // The task agents the session started, still running or closing, by id.
  final _tasks = <String, TaskAgent>{};

  // Requests of the task agents on screen, by id, with the task that asks.
  final _foreign = <String, TaskAgent>{};

  // Of those, the requests a task asked with no turn running.
  final _foreignBetween = <String>{};

  /// Of [_foreign]'s requests, the permissions; the rest are forms and
  /// links. Kept to withdraw them by kind when their task ends first.
  final _foreignPermissions = <String>{};

  // Ended task agents' closes, which the session's own close waits for.
  final _endedTasks = <Future<void>>{};

  // The names of its tasks that have ended, by their ids, so close_agent
  // says one has ended before the window has drawn its end.
  final _endedTaskNames = <String, String>{};

  // The tasks of sessions a clear or the close let go, by id, with that
  // session: their end is that session's still.
  final _retiredTasks = <String, Session>{};

  /// Forms and links on screen, by id.
  final _elicitations = <String, _Elicited>{};
  var _stop = CancellationToken();
  var _generation = 0;
  final _retiring = <Kept<void>>[];

  /// The last session a clear or a resume let go, closed: once it settles,
  /// nothing more of it counts.
  Future<void> get retired =>
      _retiring.isEmpty ? Future.value() : _retiring.last.future;
  Future<Session?>? _opening;

  /// Each turn's own cost in this opening of the session.
  TurnCosts? _costs;

  /// The sessions let go and still closing, with what they still cost.
  final _retired = <Session, _Retired>{};

  /// Completed as the conversation closes: a retirement waits no more.
  final _quit = Completer<void>();

  /// What the transcript was told while the session started, before its
  /// past: a past replaces the transcript, so it goes first in its batch.
  List<TranscriptAction>? _early;
  Session? _session;
  ({String id, Turn turn})? _turn;
  var _lastTurnId = 'session';
  var _turns = 0;
  _Quiet? _settling;
  _Quiet? _betweenQuiet;
  var _heardAt = 0;
  Kept<void>? _closing;
  Future<void> _changes = Future.value();

  /// The session's renames, one at a time in the order asked, apart from
  /// [_changes]: a hung option change must not hold a title, nor the other
  /// way round. A session `clear` replaces starts a new one.
  Future<void> _renames = Future.value();
  var _settingIds = 0, _places = 0, _selfTurns = 0;
  String? _wentId, _sealed, _selfTurnId;

  /// The cycle the agent runs on its own, by the turn id chord gave it,
  /// until its end is marked or a turn of the person's takes it over.
  String? _cycle;

  /// The ids of the compactions the session on screen has opened.
  final _compactions = <String>{};

  /// When the last turn or cycle ended, epoch milliseconds.
  var _endedAt = 0;
  final _openCalls = <String>{};

  /// The calls the turn running announced: a plan out of any other is
  /// never shown.
  final _madeAt = <String>{};

  /// The plans on screen, waiting on the person, by id.
  final _plans = <String, ({PendingPlan request, String turnId})>{};
  final _steers = <Object>{};
  final _heldSteers = <String, QueuedPrompt>{};
  final _takenBack = <String>{};
  final _steerTimers = <Timer>{};
  Future<void> _steering = Future.value();
  var _wake = Completer<void>();

  int _now() => clock.now().millisecondsSinceEpoch;

  /// Calls [listener] with each event, in order; returns the unsubscribe.
  /// A listener that throws does not stop the others; its error goes to
  /// the zone.
  void Function() listen(void Function(ConversationEvent event) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _emit(ConversationEvent event, {bool record = true}) {
    // What a session let go still says it cost goes to its record even as
    // the window closes, and to no listener then.
    if (_closing != null) {
      // What a session let go still says it cost counts, to its record
      // and to whoever keeps the window's spend; nothing else is said.
      if (event is RetiredUpdate || event is RetiredUsage) {
        _record((r) => r.heard(event));
        for (final listener in [..._listeners]) {
          try {
            listener(event);
          } catch (error, stack) {
            Zone.current.handleUncaughtError(error, stack);
          }
        }
      }
      return;
    }
    final generation = _generation;
    // A subagent's or a task's title is its own, never the session's.
    if (event case Transcribed(
      action: UpdateAction(:final update, subagentId: null),
    )) {
      _title = titled(_title, update.toJson());
    }
    if (event case Renamed(:final title)) _title = title;
    if (event is Transcribed) _early?.add(event.action);
    if (record && event is! HistoryReplayed) _record((r) => r.heard(event));
    if (_closing == null && generation == _generation) _deliver(event);
  }

  void _record(void Function(Recording recording) body) {
    final recording = _recording;
    if (recording == null) return;
    try {
      body(recording);
    } catch (error) {
      recordingFailed("Could not keep this session's record: $error");
    }
  }

  /// A once-only local record warning, never handed back to the recorder.
  void recordingFailed(String message) {
    if (_recordWarning || _closing != null) return;
    _recordWarning = true;
    _emit(Transcribed(WarnedAction('record', message)), record: false);
  }

  void _deliver(ConversationEvent event) {
    final generation = _generation;
    for (final listener in [..._listeners]) {
      if (event is! Closing &&
          (_closing != null || generation != _generation)) {
        return;
      }
      try {
        listener(event);
      } catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
  }

  Future<Session> _acquire(int generation) {
    void traffic(Traffic traffic) {
      if (generation == _generation && traffic is StderrTraffic) {
        _stderr.add(traffic.text);
      }
    }

    final selected = _selectedResume;
    if (selected == null) {
      return _open(onTraffic: traffic, cancellationToken: _stop);
    }
    final reopen = _reopen;
    if (reopen == null) {
      return Future.error(StateError('No session reopen factory.'));
    }
    return reopen(selected, onTraffic: traffic, cancellationToken: _stop);
  }

  /// Opens the session; a second call does nothing.
  @override
  void start() {
    if (_opening != null || _closing != null) return;
    final generation = ++_generation;
    // The barrier and the warnings are taken before any listener hears
    // one, so a start or a close it makes finds this start under way.
    final warnings = _warnings;
    _warnings = const [];
    _early = [];
    _opening = _acquire(generation).then<Session?>(
      (session) {
        if (_closing == null && generation == _generation) {
          _session = session;
          // Before the starting values, as a setter may ask a permission.
          session.permissions.subscribe((request) => _asked(session, request));
          session.plans.subscribe((request) => _planned(session, request));
          session.elicitations.subscribe(
            (request) => _elicited(session, request),
          );
          _begin(session);
        }
        // The session as soon as it is acquired, so a close or a clear
        // reaches it while a starting request is still out.
        return session;
      },
      onError: (Object error) {
        if (generation == _generation) {
          _early = null;
          _emit(
            ConnectFailed(
              failure.startupWords(error),
              signIn: signInOf(error),
              failure: failure.startFailureOf(error),
              error: failure.startMessage(error),
            ),
          );
        }
        return null;
      },
    );
    // Before anything the session says: its acquisition settles later.
    for (final (index, message) in warnings.indexed) {
      if (_closing != null || generation != _generation) return;
      _emit(Transcribed(WarnedAction('warning-$index', message)));
    }
  }

  /// Puts [session] on its starting values, then readies it. The change
  /// chain's first link, so a change asked while it runs waits behind it
  /// and finds the session as the start left it.
  void _begin(Session session) {
    final applying = _changes.then((_) => _applyStarting(session));
    _changes = applying.then((_) {}, onError: (Object _) {});
    applying.then(
      (_) {
        if (_current(session)) _setUp(session);
      },
      // A start that cannot be put on what it was asked to start with
      // failed, as the original reports it; whoever opened it closes it.
      onError: (Object error) {
        if (_current(session)) {
          _emit(ConnectFailed(failure.startupWords(error)));
          // On the wrong value it does no work: its agent goes.
          session.close().ignore();
        }
      },
    );
  }

  void _setUp(Session session) {
    if (!_current(session)) return;
    final history = session.takeHistory();
    _firstPrompt ??=
        historyEntries(
              history.actions,
            ).where((entry) => entry['type'] == 'prompt').firstOrNull?['prompt']
            as String?;
    if (history.title case final title?) _title = title;
    // Ids go on from the past's, which `stop_monitor` refuses by how they
    // ended.
    _monitorsPast = monitorsPast(history.actions);
    if (session.resumed != null) {
      _resumed(session);
      // A session opened again is one --resume opens, its record or not.
      if (!_recorded.isCompleted) _recorded.complete();
    }
    // The servers its agent was not given, said afresh by every session it
    // opens, a resumed one's too, once its starting values are settled and
    // before its past; never recorded, as the next open says its own.
    if (heldBackLine(session.heldBack) case final held?) {
      _emit(Transcribed(WarnedAction(_stamp(), held)), record: false);
      // A listener may have cleared or resumed at the warning; the
      // replacement owns the early batch from here.
      if (!_current(session)) return;
    }
    // As the original: what the start said (its refusals, a permission a
    // setter asked), after the resumed notice and before the past; the past
    // replaces the transcript, so it goes first in the batch, never into the
    // record's past.
    final early = _early ?? const <TranscriptAction>[];
    _early = null;
    if (session.resumed != null ||
        history.actions.isNotEmpty ||
        history.omitted) {
      _emit(
        HistoryReplayed(
          [...early, ...pastTotals(history.actions, session.agent)],
          state: session.state,
          resumed: session.resumed,
          omitted: history.omitted,
          past: history.past,
        ),
        record: false,
      );
    }
    if (!_current(session)) return;
    _record(
      (r) => r.opened(
        RecordingSession(
          sessionId: session.id,
          agent: session.agent,
          cwd: session.cwd,
          state: session.state,
          record: session.record,
          history: session.record == null
              ? historyEntries(history.actions)
              : const [],
        ),
      ),
    );
    // A reopened session is resumable before its record has a path.
    if (_resumable != null) _resumed(session);
    if (!_current(session)) return;
    _costs = TurnCosts(costCountOf(session.agent), session.record != null, [
      // A subagent's usage is its own, never the session's baseline.
      for (final action in history.actions)
        if (action is UpdateAction && action.subagentId == null) action.update,
    ], usageCountOf(session.agent));
    session.subscribeAll(
      (update, subagentId) => subagentId == null
          ? _updated(session, update)
          : _subagentUpdated(session, update, subagentId),
    );
    if (!_current(session)) return;
    session.exited.then((_) {
      if (!_current(session)) return;
      // Nobody is left to hear them.
      unawaited(_stopMonitors());
      final end = _stderr.end();
      _emit(Transcribed(DisconnectedAction(_stamp(), at: _now())));
      if (!_current(session)) return;
      _emit(
        Gone('The agent exited.', stderrLines: end.lines, stderrCut: end.cut),
      );
    });
    // A rename `chord acp` recorded while the session was not loaded goes
    // to the agent first, where it takes one.
    if (history.pendingRename case final title? when session.takesTitles()) {
      rename(title).ignore();
    }
    if (_current(session)) {
      _ready = true;
      _emit(Connected(session.id, session.state, at: _now()));
      // A resumed session's agent hears of the monitors it left running,
      // which stopped with it, as a turn of its own; the person has the
      // past's line already.
      final left = _monitorsPast.left;
      if (left.isNotEmpty) {
        deliver(const MessageFrom('chord'), leftStoppedNote(left));
      }
    }
  }

  /// Renames the session: by `session/set_title` where the agent takes a
  /// title, whose answer is the title kept, else in chord alone, the typed
  /// title folded to one line. Settles with the title and whether the agent
  /// took it once [Renamed] is emitted; with null for a session a `clear`
  /// retired meanwhile. A refusal records nothing and fails with the
  /// agent's error.
  Future<RenameTaken?> rename(String typed) {
    final session = _session;
    if (session == null || _closing != null) {
      return Future.error(StateError('The agent has not started yet.'));
    }
    final title = typed.replaceAll(RegExp(r'\s+'), ' ').trim();
    final renamed = _renames.then((_) async {
      if (!_current(session)) return null;
      final agent = session.takesTitles();
      final String taken;
      try {
        taken = agent ? await session.setTitle(title) : title;
      } catch (_) {
        // A retired session's refusal, or its agent gone, is no one's.
        if (!_current(session)) return null;
        rethrow;
      }
      if (!_current(session)) return null;
      _emit(Renamed(taken, _now()));
      return (title: taken, agent: agent);
    });
    _renames = renamed.then((_) {}, onError: (Object _) {});
    return renamed;
  }

  /// Asks for the starting model, effort and mode, in that order; each
  /// refusal goes into the transcript after "Could not", and the session
  /// goes on with what the agent chose.
  Future<void> _applyStarting(Session session) async {
    // Its turn in the chain can come after a clear or a close retired it.
    if (!_current(session)) return;
    _effortRefused = null;
    final Starting(:model, :effort, :mode, :entries) = starting;
    // A client's entry beats chord's value for the same option.
    bool sent(String category) {
      for (final option in session.state.configOptions) {
        if (option['category'] == category) {
          return entries.any((entry) => entry['configId'] == option['id']);
        }
      }
      return false;
    }

    List<String> ids(List<({String id, String name})>? list) => [
      for (final item in list ?? const <({String id, String name})>[]) item.id,
    ];
    final asks = [
      if (model != null && !sent('model'))
        StartingAsk(
          value: model,
          what: 'on ${model.id}',
          kind: 'models',
          offered: () async => ids(_models(session)?.available),
          current: () => _models(session)?.current,
          ask: () => session.setModel(model.id),
        ),
      if (effort != null && !sent('thought_level'))
        StartingAsk(
          value: StartingValue(effort.id, from: effort.from),
          what: 'on ${effort.id} effort',
          kind: 'efforts',
          listedOnly: true,
          offered: () async =>
              ids(effortsFrom(session.state.configOptions)?.available),
          current: () => effortsFrom(session.state.configOptions)?.current,
          ask: () => _setEffort(session, effort.id),
        ),
      if (mode != null && !sent('mode'))
        StartingAsk(
          value: mode,
          what: 'in ${mode.id} mode',
          kind: 'modes',
          listedOnly: true,
          offered: () async => ids(_modes(session)?.available),
          current: () => _modes(session)?.current,
          ask: () => session.setMode(mode.id),
        ),
    ];
    for (final ask in asks) {
      if (!_current(session)) return;
      final reason = await askStarting(ask);
      // A clear or a close while it was out: the rest is nobody's to ask.
      if (!_current(session)) return;
      // A value that must be met, as the model open_agent and spawn_task
      // ask for: the agent runs on it or not at all.
      if (reason != null && ask.value.required) {
        throw StateError('Could not $reason');
      }
      if (reason != null && ask.kind == 'efforts') {
        _effortRefused = 'Could not $reason';
      }
      if (reason != null) {
        _emit(
          Transcribed(
            FailedAction(
              'starting-${++_startingFailures}',
              'Could not $reason',
            ),
          ),
        );
      }
    }
    for (final entry in entries) {
      if (!_current(session)) return;
      await _applyEntry(session, entry);
    }
  }

  /// A client's initial [entry] read back by its id once its turn comes,
  /// as the session is then: one the session does not list is dropped, one
  /// already current costs nothing, and any other goes to
  /// `session/set_config_option` as the client sent it. A refusal fails the
  /// start, and so does an agent that answers and is on another value.
  Future<void> _applyEntry(Session session, Map<String, Object?> entry) async {
    Map<String, Object?>? listed() {
      for (final option in session.state.configOptions) {
        if (option['id'] == entry['configId']) return option;
      }
      return null;
    }

    final what =
        'start with ${entry['configId']} ${entry['value']}, set by the client';
    if (listed() == null || listed()!['currentValue'] == entry['value']) return;
    try {
      await session.setConfigEntry(entry);
    } catch (error) {
      if (_current(session)) {
        throw _EntryRefused('Could not $what: ${agentMessageOf(error)}');
      }
      return;
    }
    final now = listed()?['currentValue'];
    if (_current(session) && now != null && now != entry['value']) {
      throw _EntryRefused('Could not $what: the agent is in $now');
    }
  }

  // Asked only once the agent listed efforts, so the select is there.
  Future<void> _setEffort(Session session, String id) =>
      session.setOption(effortsFrom(session.state.configOptions)!.option, id);

  AgentModels? _models(Session session) =>
      modelsFrom(session.state.configOptions, session.state.models);

  AgentModes? _modes(Session session) =>
      modesFrom(session.state.configOptions, session.state.modes);

  bool _current(Session session) =>
      identical(_session, session) && _closing == null;

  String _stamp() => _selfTurnId ?? _turn?.id ?? _cycle ?? _lastTurnId;

  /// One of a subagent's updates, folded under the turn on screen, or the
  /// last one: its work is the session's, but starts no cycle and is no
  /// mark of the session's own.
  void _subagentUpdated(
    Session session,
    acp.SessionUpdate update,
    String subagentId,
  ) {
    if (!_current(session)) return;
    _heardAt = _now();
    _emit(
      Transcribed(
        UpdateAction(
          _stamp(),
          update,
          subagentId: subagentId,
          at: update.kind == 'subagent_update' ? _now() : null,
        ),
      ),
    );
  }

  void _updated(Session session, acp.SessionUpdate update) {
    if (!_current(session)) {
      _retiredHeard(session, update);
      return;
    }
    final now = _now();
    // Silent since the last turn ended: what comes now is not its tail.
    final quiet = now - math.max(_heardAt, _endedAt) >= quietMs;
    final mark = cycleMark(update);
    final unasked = _opensUnasked(update);
    _heardAt = now;
    _beginCycle(session, update, mark, quiet);
    if (!_current(session)) return;
    _track(update);
    final turnId = _stamp();
    _emit(
      Transcribed(
        UpdateAction(
          turnId,
          update,
          unasked: unasked,
          // When a subagent's state came, which its times count from.
          at: update.kind == 'subagent_update' ? _now() : null,
        ),
      ),
    );
    // A cost that came after its turn's end, as Claude's can, is still its.
    if (!_current(session)) return;
    final late = _costs?.heard(turnId, update);
    if (late != null) _emit(Transcribed(UsageAction(late.turnId, late)));
    if (mark == CycleMark.end && _current(session)) _endCycle(session);
    if (_current(session) && _stateUpdates.contains(update.kind)) {
      _emit(AgentStateChanged(session.state));
    }
  }

  /// Whether [update] opens a compaction with nothing under way: no turn,
  /// chord's or the agent's own after a missed steer, no cycle and no wait
  /// for a turn's tail, as Claude compacts an idle session. Said once, at
  /// its first update, from chord's state and not the agent's words; a
  /// replay never comes this way.
  bool _opensUnasked(acp.SessionUpdate update) {
    if (update.kind != acp.SessionUpdateKind.compactionUpdate) return false;
    final id = update.toJson()['compactionId'];
    if (id is! String || !_compactions.add(id)) return false;
    return _turn == null &&
        _selfTurnId == null &&
        _cycle == null &&
        _settling == null;
  }

  /// Begins a cycle of the agent's own with [update], when nothing of the
  /// person's runs and the agent marks one: codebuddy's marker, or, on an
  /// agent that runs them unmarked, its work once the last turn has gone
  /// quiet. Only agents that mark a cycle's end have one.
  void _beginCycle(
    Session session,
    acp.SessionUpdate update,
    CycleMark? mark,
    bool quiet,
  ) {
    if (_cycle != null || _selfTurnId != null || !_idle()) return;
    final starts =
        mark == CycleMark.start ||
        (session.startsOwnCycles() && quiet && cycleWork.contains(update.kind));
    if (!starts) return;
    final turnId = const Uuid().v4();
    _cycle = turnId;
    _costs?.began(turnId);
    _emit(Transcribed(CycleStartedAction(turnId, _now())));
  }

  /// Ends the agent's own cycle as a turn ends, which the person is told of
  /// as a turn's end; what the agent sends after it is folded under it, as
  /// after a turn.
  void _endCycle(Session session, {bool cancelled = false}) {
    final turnId = _cycle;
    if (turnId == null) return;
    _cycle = null;
    _lastTurnId = turnId;
    _endedAt = _now();
    _emit(
      Transcribed(
        ResultAction(
          turnId,
          TurnAnswered(
            cancelled ? acp.StopReason.cancelled : acp.StopReason.endTurn,
          ),
        ),
      ),
    );
    if (!_current(session)) return;
    final figures = _costs?.ended(turnId, null, _models(session)?.current);
    if (figures != null) _emit(Transcribed(UsageAction(turnId, figures)));
  }

  void _track(acp.SessionUpdate update) {
    if (update.kind != 'tool_call' && update.kind != 'tool_call_update') return;
    final json = update.toJson();
    final id = json['toolCallId'];
    if (id is! String) return;
    final status = json['status'];
    if (status == 'completed' || status == 'failed') {
      if (_openCalls.remove(id)) _rouse();
    } else if (_turn != null &&
        (update.kind == 'tool_call' || status != null)) {
      _openCalls.add(id);
    }
    if (_turn != null) _madeAt.add(id);
  }

  void _rouse() {
    final wake = _wake;
    _wake = Completer<void>();
    if (!wake.isCompleted) wake.complete();
  }

  /// Reports the latest options without asking the agent for new settings.
  void readOptions() {
    final session = _session;
    if (session != null && _current(session)) _report(session);
  }

  void _report(Session session) {
    if (_current(session)) _emit(AgentStateChanged(session.state));
  }

  Future<void> _change(Future<void> Function(Session session) body) {
    final session = _session;
    if (session == null || !_current(session)) {
      return Future.error(StateError('The agent has not started yet.'));
    }
    final changed = _changes.then((_) async {
      if (_current(session)) await body(session);
    });
    _changes = changed.catchError((Object _) {});
    return changed;
  }

  /// Requests a mode, serialized with all other session setting changes.
  Future<void> setMode(String id) {
    final session = _session;
    if (session == null || !_current(session)) {
      return Future.error(StateError('The agent has not started yet.'));
    }
    final changed = _change((session) async {
      try {
        await session.setMode(id);
      } catch (error) {
        if (_current(session)) {
          _emit(
            Transcribed(
              FailedAction(
                'mode-${++_settingIds}',
                'Could not switch to $id mode: ${_messageOf(error)}',
              ),
            ),
          );
        }
        rethrow;
      } finally {
        _report(session);
        if (_current(session)) _emit(ModePending(id, pending: false));
      }
    });
    _emit(ModePending(id, pending: true));
    return changed;
  }

  /// Requests a model through the same per-session change chain.
  Future<void> setModel(String id) => _change((session) async {
    try {
      await session.setModel(id);
    } catch (error) {
      if (_current(session)) {
        _emit(
          Transcribed(
            FailedAction(
              'model-${++_settingIds}',
              'Could not switch to $id: ${_messageOf(error)}',
            ),
          ),
        );
      }
      rethrow;
    } finally {
      _report(session);
    }
  });

  /// Changes a config value and notes the value the agent reports afterwards.
  Future<void> setOption(String id, String value) => _change((session) async {
    final options = session.state.configOptions;
    final name = optionName(options, id);
    final noteId = 'option-${++_settingIds}';
    AgentOption? before;
    for (final o in optionsFromConfigOptions(options)) {
      if (o.id == id) before = o;
    }
    try {
      await session.setOption(id, value);
    } catch (error) {
      if (_current(session)) {
        _emit(
          SettingNoted(
            noteId,
            'config',
            'Could not set $name to ${before == null ? value : valueName(before, value)}: ${_messageOf(error)}',
            failed: true,
          ),
        );
      }
      rethrow;
    }
    _report(session);
    if (!_current(session)) return;
    for (final o in optionsFromConfigOptions(session.state.configOptions)) {
      if (o.id == id) {
        _emit(
          SettingNoted(
            noteId,
            'config',
            '${o.name} set to ${valueName(o, o.current)}',
          ),
        );
      }
    }
  });

  /// Applies a model first, then the requested effort against fresh options.
  Future<void> makeChoice(ModelChoice choice, String command) {
    final session = _session;
    if (session == null || !_current(session)) {
      return Future.error(StateError('The agent has not started yet.'));
    }
    final id = 'choice-${++_settingIds}';
    final inUse =
        modelName(
          modelsFrom(session.state.configOptions, session.state.models),
        ) ??
        '';
    final changed = _change((session) async {
      final result = await _chosen(session, choice);
      if (result != null && _current(session)) {
        final said = choiceNote(
          choice,
          result,
          session.state.configOptions,
          inUse,
        );
        _emit(SettingNoted(id, command, said.text, failed: said.failed));
      }
    });
    _emit(
      SettingNoted(
        id,
        command,
        pendingText(choice, session.state.configOptions),
      ),
    );
    return changed;
  }

  Future<ChoiceResult?> _chosen(Session session, ModelChoice choice) async {
    final model = choice.model;
    if (model != null) {
      try {
        await session.setModel(model.id);
      } catch (error) {
        return ChoiceResult(model: 'refused', reason: _messageOf(error));
      } finally {
        _report(session);
      }
      if (!_current(session)) return null;
    }
    final switched = model == null ? null : 'switched';
    if (choice.effort == null) return ChoiceResult(model: switched);
    final step = effortStep(choice, session.state.configOptions);
    if (step == null) {
      return ChoiceResult(model: switched, effort: 'not_offered');
    }
    try {
      await session.setOption(step.option, step.value);
    } catch (error) {
      return ChoiceResult(
        model: switched,
        effort: 'refused',
        option: step.name,
        reason: _messageOf(error),
      );
    } finally {
      _report(session);
    }
    return ChoiceResult(model: switched, effort: 'set');
  }

  Future<void> _commandChange(
    String command,
    Future<void> Function(
      Session session,
      void Function(String text, bool failed) note,
    )
    body,
  ) {
    final id = 'setting-${++_settingIds}';
    return _change(
      (session) => body(session, (text, failed) {
        if (_current(session)) {
          _emit(SettingNoted(id, command, text, failed: failed));
        }
      }),
    );
  }

  /// Sets an exact effort id against the options when its chain link runs.
  Future<void> setEffortById(
    String agent,
    String value,
    String command,
  ) => _commandChange(command, (session, note) async {
    final options = session.state.configOptions;
    final model = modelName(modelsFrom(options, session.state.models)) ?? '';
    final efforts = effortsFrom(options);
    final effort = effortById(options, value);
    if (effort == null) {
      note(
        efforts == null
            ? noEffortNote(agent, model)
            : '$agent offers ${efforts.available.map((e) => e.id).join(', ')} effort for $model.',
        false,
      );
      return;
    }
    final choice = ModelChoice(effort: effort);
    note(pendingText(choice, options), false);
    if (!_current(session)) return;
    final result = await _chosen(session, choice);
    if (result != null) {
      final said = choiceNote(
        choice,
        result,
        session.state.configOptions,
        model,
      );
      note(said.text, said.failed);
    }
  });

  /// Toggles an unambiguous fast select, looked up when its link runs.
  Future<void> toggleFast(String agent, [String? recorded]) => _commandChange(
    'fast',
    (session, note) async {
      final options = session.state.configOptions;
      final model = modelName(modelsFrom(options, session.state.models)) ?? '';
      final option = fastOption(options, recorded);
      final other = option == null ? null : fastToggled(option);
      if (option == null || other == null) {
        note('$agent offers no fast mode for $model.', false);
        return;
      }
      final what = '${option.name} to ${other.name}';
      note('Setting $what…', false);
      if (!_current(session)) return;
      try {
        await session.setOption(option.id, other.value);
      } catch (error) {
        note('Could not set $what: ${_messageOf(error)}', true);
        rethrow;
      } finally {
        _report(session);
      }
      String current = other.name;
      for (final o in optionsFromConfigOptions(session.state.configOptions)) {
        if (o.id == option.id) current = valueName(o, o.current);
      }
      note('Fast mode $current for $model', false);
    },
  );

  /// Sends [text] as a prompt: at once when nothing runs or waits, else
  /// into the queue. False before the session is up and once closing.
  /// [prompt] carries context without changing the typed transcript text.
  /// [mentions] snapshots typed paths, resolved only when this prompt plays.
  /// [parts] are what goes beside the text: a pasted image's block.
  @override
  bool send(
    String text, [
    String? prompt,
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
  ]) => sendTurn(
    'turn-${++_turns}',
    text,
    prompt: prompt,
    mentions: mentions,
    parts: parts,
  );

  /// [send] as turn [turnId], which the caller chose: `chord acp` binds its
  /// request to the turn before sending, as the prompt may be emitted before
  /// this returns.
  bool sendTurn(
    String turnId,
    String text, {
    String? prompt,
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
  }) {
    final session = _session;
    if (session == null || !_ready || _closing != null) return false;
    // What was held for the person's next prompt goes ahead of it.
    final ahead = [..._ahead];
    _ahead.clear();
    _enqueue(
      session,
      QueuedPrompt(
        turnId,
        text,
        sentPrompt: ahead.isEmpty
            ? prompt
            : [...ahead, prompt ?? text].join('\n\n'),
        mentions: List.unmodifiable(mentions),
        parts: parts,
      ),
    );
    return true;
  }

  /// A message that starts no turn: it goes ahead of the person's next
  /// prompt.
  void aside(MessageFrom from, String text) =>
      _ahead.add(wrapMessage(from, text));

  /// One of chord's tools served to the session: the call that asked for it
  /// is drawn by it.
  void served(ChordCall call) {
    if (_session == null || _closing != null) return;
    _emit(Transcribed(ServedAction(_stamp(), call)));
  }

  /// A writer for a receipt that comes late: through [served] while the
  /// session open now is still the one here, and into that session's own
  /// record once it is not, as after a clear, a resume or a close. None
  /// before a session is open or without a record that can take it.
  void Function(ChordCall call)? captureServed() {
    final session = _session;
    if (session == null) return null;
    final write = switch (_recording) {
      final ServedCapture capture => capture.captureServed(),
      _ => null,
    };
    final turnId = _stamp();
    if (write == null) return null;
    return (call) {
      if (_current(session) && _closing == null) {
        served(call);
      } else {
        write(turnId, call);
      }
    };
  }

  /// The person's command started [call] for the session, as `/new` does:
  /// its record keeps it, as a resume names what it opened from there.
  void ranTyped(ChordCall call) {
    if (_session == null || _closing != null) return;
    _emit(RanTyped(_stamp(), call));
  }

  /// A long-lived agent of the session's, [id], was closed while the
  /// session went on.
  void agentClosed(String id) {
    if (_session == null || _closing != null) return;
    _emit(AgentClosed(id));
  }

  /// A call served to a task's session after the task ended: kept in its
  /// record; its parent's [endedTaskServed] draws it.
  void servedEnded(ChordCall call) =>
      _record((r) => r.heard(Transcribed(ServedAction(_stamp(), call))));

  /// Where a call served to task [id] after it ended goes: its block, drawn
  /// while the session the task ran in is still the one here.
  void Function(ChordCall call) endedTaskServed(String id) {
    final session = _session;
    return (call) {
      if (identical(_session, session) && _closing == null) {
        _emit(
          Transcribed(ServedAction(_stamp(), call, subagentId: id)),
          record: false,
        );
      }
    };
  }

  /// Starts task agent [task] of the session's on [session], which reports
  /// to the task; it runs until its first turn ends, or the session's turn
  /// is interrupted, or the session closes.
  void adopt(TaskAgent task, TaskSession session) {
    _tasks[task.id] = task;
    task.begin(session);
  }

  /// A task agent of the session's, by its id, until it has ended.
  TaskAgent? task(String id) => _tasks[id];

  /// The task agents of the session still running.
  List<TaskAgent> get tasks => [
    for (final task in _tasks.values)
      if (task.running) task,
  ];

  /// The names of the session's tasks that have ended, by their ids.
  Map<String, String> get endedTasks => Map.unmodifiable(_endedTaskNames);

  /// What task agent [id] of this session does to it. Each call is dropped
  /// once the task is no longer the session's, as after a `/clear`, so an
  /// old task reaches nothing in the session that replaced its parent.
  TaskParent taskParent(String id) {
    TaskAgent? own() => _tasks[id];
    return _TaskParent(
      (event) {
        final task = own();
        if (task != null) {
          _relay(event, task);
        } else {
          _retiredTaskEnded(id, event);
        }
      },
      (from, text) {
        if (own() != null) deliver(from, text);
      },
      (from, text) {
        if (own() != null) _ahead.add(wrapMessage(from, text));
      },
      () {
        final task = own();
        if (task == null) return;
        _forget(task);
        _endedTaskNames[task.id] = task.start.name;
        final closing = task.close().catchError((Object _) {});
        _endedTasks.add(closing);
        closing.whenComplete(() => _endedTasks.remove(closing)).ignore();
      },
    );
  }

  /// The block update of a task of a session `clear` or the close let go,
  /// its ending with what it spent: that session's still, to its record and
  /// what the window keeps of it. Nothing else of the task's goes anywhere.
  void _retiredTaskEnded(String id, ConversationEvent event) {
    final session = _retiredTasks[id];
    final turnId = session == null ? null : _retired[session]?.costs.lastTurn;
    if (turnId == null) return;
    if (event case Transcribed(
      action: UpdateAction(:final update, subagentId: null),
    ) when update.kind == 'subagent_update') {
      _emit(RetiredUpdate(turnId, update));
    }
  }

  /// Lets [task] go, and the requests of its still on screen: each is
  /// withdrawn here, as an ended task can answer none, whichever came
  /// first of its turn's end and its agent's own withdrawal.
  void _forget(TaskAgent task) {
    var released = false;
    for (final MapEntry(key: request, value: asker) in [..._foreign.entries]) {
      if (identical(asker, task)) {
        _foreign.remove(request);
        released = _foreignBetween.remove(request) || released;
        final permission = _foreignPermissions.remove(request);
        if (_session != null && _closing == null) {
          _emit(
            Transcribed(
              permission
                  ? PermissionSettledAction(
                      _stamp(),
                      request,
                      const Withdrawn(),
                    )
                  : ElicitationSettledAction(
                      _stamp(),
                      request,
                      const ElicitationWithdrawn(),
                    ),
            ),
          );
        }
      }
    }
    _tasks.remove(task.id);
    if (released) _release();
  }

  /// A task agent's event, in the session's stream, under its turn.
  void _relay(ConversationEvent event, TaskAgent task) {
    if (_session == null || _closing != null) return;
    if (event is! Transcribed) return _emit(event);
    final action = event.action;
    final turnId = _stamp();
    var released = false;
    switch (action) {
      // The task answers it, whichever of its own subagents asked; one
      // asked with no turn of the session's running holds the queue as the
      // session's own would.
      case PermissionRequestedAction(wait: PermissionWait(:final id)) ||
          ElicitationRequestedAction(elicitation: ElicitationWait(:final id)):
        _foreign[id] = task;
        if (action is PermissionRequestedAction) _foreignPermissions.add(id);
        if (_turn == null) {
          _foreignBetween.add(id);
          _holdForAnswer();
        }
      case PermissionSettledAction(:final id) ||
          ElicitationSettledAction(:final id):
        _foreign.remove(id);
        _foreignPermissions.remove(id);
        released = _foreignBetween.remove(id);
      default:
    }
    // The task's work is kept in its own record; the parent's keeps the
    // block's start and end.
    final shown = switch (action) {
      UpdateAction(:final subagentId) ||
      ServedAction(:final subagentId) => subagentId != null,
      _ => false,
    };
    _emit(Transcribed(_stampedAs(action, turnId)), record: !shown);
    // Once its answer is on screen, what waited for it goes.
    if (released) _release();
  }

  /// A message from another agent, or chord: a turn of its own, wrapped so
  /// the agent sees who speaks, queued behind a running turn as a prompt
  /// is, with the team part ahead of it for a team agent's first. Null
  /// before the session is up and once closing.
  Delivery? deliver(MessageFrom from, String text, [TeamPart? team]) {
    final session = _session;
    if (session == null || !_ready || _closing != null) return null;
    return _enqueue(session, _message(from, text, team));
  }

  /// A message another agent sent with send_message: while a turn of
  /// chord's runs on an agent that takes steering, into that turn at once,
  /// or, while the turn waits on the person's answer, once they answer; a
  /// steer refused, as when the turn ended on the way, or answered with a
  /// turn of the agent's own, which is cancelled, goes as the next turn,
  /// [queued] told so. Otherwise as [deliver] sends one. Sent for a steer,
  /// as the message did not wait.
  Delivery? tell(MessageFrom from, String text, [void Function()? queued]) {
    final session = _session;
    if (session == null || !_ready || _closing != null) return null;
    final into = _steerable(session);
    if (into == null) return deliver(from, text);
    final next = _message(from, text);
    if (_waitsOnPerson()) {
      _queued.add(
        QueuedPrompt(
          next.turnId,
          next.text,
          sentPrompt: next.prompt,
          afterAnswer: true,
          from: from,
        ),
      );
      _emit(Queued(next.turnId, text, afterAnswer: true, from: from));
      return Delivery.queued;
    }
    unawaited(_steer(session, into, next, taken: false, queued: queued));
    return Delivery.sent;
  }

  /// Starts a monitor for the session's agent: its command in [cwd], each
  /// batch of its lines a message to the agent later, as is its end.
  /// Refused before the session is up, once closing, and when the shell
  /// does not start; what it was asked is checked by `monitorRefusal`
  /// first, by the caller.
  @override
  Future<MonitorAnswer> startMonitor(
    MonitorArgs args,
    String cwd, {
    RunCommand run = runMonitorCommand,
  }) async {
    if (_session == null || _closing != null) {
      return const Refused('This session has closed');
    }
    final info = MonitorInfo(
      id: 'm${_monitorsPast.last + _monitorCount + 1}',
      description: jsTrim(args.description),
      command: args.command,
      startedAt: _now(),
      timeoutMs: args.timeoutMs?.toInt() ?? defaultTimeoutMs,
    );
    // The id is taken now, so two asked at once do not share it; one that
    // does not start gives it back, as the original takes none for it.
    final count = _monitorCount += 1;
    final epoch = _monitorEpoch;
    final hooks = _Hooks(this, info);
    final pending = Completer<void>();
    _monitorsPending.add(pending.future);
    void settled() {
      _monitorsPending.remove(pending.future);
      pending.complete();
    }

    _monitorsStarting += 1;
    MonitorRun? spawned;
    final Object started;
    try {
      started = await MonitorRun.start(
        info,
        hooks,
        cwd,
        run: run,
        spawned: (run) => _monitorsStartingRuns.add(spawned = run),
      );
    } catch (_) {
      settled();
      rethrow;
    } finally {
      _monitorsStarting -= 1;
      _monitorsStartingRuns.remove(spawned);
    }
    final current = _closing == null && epoch == _monitorEpoch;
    switch (started) {
      case MonitorRun() when current:
        hooks.run = started;
        _monitors[info.id] = _Monitoring(started);
        settled();
        _showMonitors();
        return StartedMonitor(info.id, info.description, info.timeoutMs);
      // A close, a clear or the agent's exit while it started: it is not
      // this session's, and what stopped the rest waits for it too.
      case MonitorRun():
        started.stop(StoppedBy.close);
        started.ended.whenComplete(settled).ignore();
        return const Refused('This session has closed');
      // Stopped while it started, so its shell never did: gone only once its
      // launcher is.
      case (error: String _) when !current && spawned != null:
        spawned!.ended.whenComplete(settled).ignore();
        return const Refused('This session has closed');
      case (:final String error):
        if (current && _monitorCount == count) _monitorCount -= 1;
        settled();
        return Refused(error);
      default:
        settled();
        throw StateError('$started');
    }
  }

  /// The session is a fork of the agent [from]'s, which its view and record
  /// say where it parted.
  void forked(String from) {
    if (_session == null || _closing != null) return;
    _emit(
      Transcribed(ForkedAction('forked-${const Uuid().v4()}', from, _now())),
    );
  }

  /// Its monitors running and starting, which the window's limit counts.
  @override
  int get monitorsHeld => _monitors.length + _monitorsStarting;

  /// Stops subagent [id] alone, as the person asked: it reads stopping
  /// until its agent says how it ended, or goes back as it was when the
  /// stop could not be sent, which the future fails with.
  Future<void> stopSubagent(String id) async {
    final session = _session;
    if (session == null) throw StateError('the agent is not connected');
    _emit(Transcribed(SubagentStoppingAction('stop', id, true)));
    try {
      await session.stopSubagent(id);
    } catch (_) {
      _emit(Transcribed(SubagentStoppingAction('stop', id, false)));
      rethrow;
    }
  }

  /// Stops monitor [id]: the agent's own `stop_monitor`, which its answer
  /// tells it of, or the person's, which a message does.
  @override
  StopMonitorAnswer stopMonitor(String id, {StoppedBy by = StoppedBy.agent}) {
    final monitoring = _monitors[id];
    if (monitoring == null) {
      final ended = _monitorsEnded[id] ?? _monitorsPast.ended[id];
      return Refused(
        ended != null
            ? '$id already ended: $ended'
            : _monitorsPast.left.any((left) => left.id == id)
            ? '$id was running when this session was left and was not '
                  'restarted; monitor starts another'
            : 'No running monitor $id of yours; list_monitors names them',
      );
    }
    final running = monitoring.run.running;
    _monitors.remove(id);
    if (by == StoppedBy.person) {
      _ending[id] = monitoring;
    } else {
      _monitorsEnded[id] = 'stopped';
    }
    _endedMonitor(running, const MonitorStopped());
    _showMonitors();
    _stopping(monitoring.run, by);
    return StoppedMonitor(
      id,
      running.info.description,
      running.events,
      _now() - running.info.startedAt,
    );
  }

  /// The session's monitors still running, in start order.
  @override
  List<RunningMonitor> get monitors => [
    for (final monitoring in _monitors.values) monitoring.run.running,
  ];

  /// The monitors ended since the session came up, in the order they ended.
  List<EndedMonitor> get endedMonitors => List.unmodifiable(_endedMonitors);

  void _stopping(MonitorRun run, StoppedBy by) {
    run.stop(by);
    final ended = run.ended;
    final gone = Kept(ended);
    _monitorsStopping.add(gone);
    ended.whenComplete(() => _monitorsStopping.remove(gone)).ignore();
  }

  /// Stops every monitor without a word; settles once all are gone.
  Future<void> _stopMonitors() {
    _monitorEpoch += 1;
    final runs = [for (final monitoring in _monitors.values) monitoring.run];
    // Still starting: stopped now, which their start then waits out.
    for (final run in _monitorsStartingRuns) {
      run.stop(StoppedBy.close);
    }
    _monitors.clear();
    _ending.clear();
    for (final run in runs) {
      _stopping(run, StoppedBy.close);
    }
    if (runs.isNotEmpty) _showMonitors();
    return Future.wait([
      for (final gone in _monitorsStopping) gone.future,
      ..._monitorsPending,
    ]);
  }

  void _showMonitors() =>
      _emit(MonitorsChanged(monitors, endedMonitors), record: false);

  /// Keeps [monitor]'s end for the window, once: a stop's comes first, and
  /// the end that follows it only brings the last lines it carried.
  void _endedMonitor(RunningMonitor monitor, MonitorEnd end) {
    final id = monitor.info.id;
    final at = _endedMonitors.indexWhere((ended) => ended.info.id == id);
    if (at >= 0) {
      final ended = _endedMonitors[at];
      if (monitor.lastEvent case final lastEvent?) {
        _endedMonitors = [..._endedMonitors]
          ..[at] = EndedMonitor(
            ended.info,
            events: ended.events,
            lastEvent: lastEvent,
            end: ended.end,
            endedAt: ended.endedAt,
          );
      }
      return;
    }
    _endedMonitors = [
      ..._endedMonitors,
      EndedMonitor(
        monitor.info,
        events: monitor.events,
        lastEvent: monitor.lastEvent,
        end: end,
        endedAt: _now(),
      ),
    ];
  }

  /// [run]'s place in [among], if it still has one there under its id.
  _Monitoring? _monitoring(
    MonitorInfo info,
    MonitorRun? run,
    Map<String, _Monitoring> among,
  ) {
    final monitoring = among[info.id];
    return monitoring != null && identical(monitoring.run, run)
        ? monitoring
        : null;
  }

  /// A batch of a monitor's lines: into its message still queued, if one
  /// is, so a busy log never fills the queue, or else a message of its own.
  void _monitorEvent(MonitorInfo info, MonitorRun? run, EventLines lines) {
    final monitoring = _monitoring(info, run, _monitors);
    if (monitoring == null) return;
    final from = MessageFrom(
      info.description,
      monitor: (id: info.id, end: null),
    );
    if (monitoring.queued case final queued?) {
      final merged = withLines(queued.lines, lines.lines, lines.dropped);
      if (_requeue(queued.turnId, from, eventText(merged))) {
        monitoring.queued = (turnId: queued.turnId, lines: merged);
        _showMonitors();
        return;
      }
    }
    final message = _sendMessage(from, eventText(lines));
    monitoring.queued = message?.delivery == Delivery.queued
        ? (turnId: message!.turnId, lines: lines)
        : null;
    _showMonitors();
  }

  /// A monitor's end, told to its agent: the lines not handed on yet, its
  /// message still queued included, then chord's sentence, as one message.
  void _monitorEnded(
    MonitorInfo info,
    MonitorRun? run,
    MonitorEnd end,
    EventLines rest,
  ) {
    final monitoring =
        _monitoring(info, run, _monitors) ?? _monitoring(info, run, _ending);
    if (monitoring == null) return;
    _monitors.remove(info.id);
    _ending.remove(info.id);
    _monitorsEnded[info.id] = endWord(end);
    _endedMonitor(monitoring.run.running, end);
    _showMonitors();
    final from = MessageFrom(
      info.description,
      monitor: (id: info.id, end: end),
    );
    final sentence = endSentence(end, _now() - info.startedAt);
    if (monitoring.queued case final queued?
        when _requeue(
          queued.turnId,
          from,
          eventText(
            withLines(queued.lines, rest.lines, rest.dropped),
            sentence,
          ),
        )) {
      return;
    }
    _sendMessage(from, eventText(rest, sentence));
  }

  /// [deliver], with the turn the message will be.
  ({Delivery delivery, String turnId})? _sendMessage(
    MessageFrom from,
    String text,
  ) {
    final session = _session;
    if (session == null || !_ready || _closing != null) return null;
    final next = _message(from, text);
    return (delivery: _enqueue(session, next), turnId: next.turnId);
  }

  /// Rewrites message [turnId] while it is still queued, reported queued
  /// again in its place; false once it has gone to the agent.
  bool _requeue(String turnId, MessageFrom from, String text) {
    final index = _queued.indexWhere((queued) => queued.turnId == turnId);
    if (index < 0) return false;
    final old = _queued[index];
    _queued[index] = QueuedPrompt(
      turnId,
      text,
      sentPrompt: wrapMessage(from, text),
      place: old.place,
      afterAnswer: old.afterAnswer,
      from: from,
    );
    _emit(Queued(turnId, text, afterAnswer: old.afterAnswer, from: from));
    return true;
  }

  QueuedPrompt _message(MessageFrom from, String text, [TeamPart? team]) =>
      QueuedPrompt(
        const Uuid().v4(),
        text,
        sentPrompt: team == null
            ? wrapMessage(from, text)
            : wrapTeamMessage(team, from, text),
        from: from,
        team: team,
      );

  /// The team part a cleared team agent's next message carries, whatever
  /// sends it, as its first did.
  TeamPart? _firstPart;

  /// Dispatches the oldest eligible personal row into the admitted running
  /// turn, or the one of [turnId] when given, as `_chord/session/steer`
  /// steers its own prompt and not one queued ahead of it. Returns the
  /// original `sent`, `unsteerable`, or `none`, and null when not up.
  String? steerQueued([String? turnId]) {
    final session = _session;
    if (session == null || !_ready || _closing != null) return null;
    final index = _queued.indexWhere(
      (next) =>
          next.from == null &&
          !next.afterAnswer &&
          (turnId == null || next.turnId == turnId),
    );
    if (index < 0 || _turn == null) return 'none';
    if (!session.steers()) return 'unsteerable';
    final into = _steerable(session);
    if (into == null) return 'none';
    final next = _queued.removeAt(index);
    _emit(Queued(next.turnId, next.text, taken: true));
    unawaited(_steer(session, into, next));
    return 'sent';
  }

  String? _steerable(Session session) {
    final turn = _turn;
    return _current(session) &&
            turn != null &&
            _wentId == turn.id &&
            _settling == null &&
            _sealed != turn.id &&
            session.steers()
        ? turn.id
        : null;
  }

  void _putBack(QueuedPrompt next, bool refused) {
    final afterAnswer = _turn == null && _waitsBetween();
    final held = QueuedPrompt(
      next.turnId,
      next.text,
      sentPrompt: next.prompt,
      mentions: next.mentions,
      held: next.held,
      parts: next.parts,
      place: next.place,
      afterAnswer: afterAnswer,
      from: next.from,
    );
    final at = _queued.indexWhere(
      (row) => (row.place ?? double.infinity) > (next.place ?? double.infinity),
    );
    _queued.insert(at < 0 ? _queued.length : at, held);
    _emit(
      Queued(
        next.turnId,
        next.text,
        afterAnswer: afterAnswer,
        refused: refused,
        from: next.from,
      ),
    );
  }

  /// [next] into turn [into]: the person's, [taken] from the queue, back
  /// on top of it if refused; another's message, refused or missing the
  /// turn, as the next turn, [queued] told so.
  Future<void> _steer(
    Session session,
    String into,
    QueuedPrompt next, {
    bool taken = true,
    void Function()? queued,
  }) async {
    final generation = _generation;
    bool current() => _current(session) && generation == _generation;
    if (!current()) return;
    final marker = Object(), ahead = _steering;
    final awaited = session.cutsCallsOnSteer()
        ? Set<String>.of(_openCalls)
        : const <String>{};
    bool open() => awaited.any(_openCalls.contains);
    final answered = Completer<void>();
    var shown = false;
    bool? shownForAnswer;
    void show(bool answer) {
      if (shown && shownForAnswer == answer) return;
      shown = true;
      shownForAnswer = answer;
      // Esc takes back only the person's.
      if (next.from == null) _heldSteers[next.turnId] = next;
      _emit(
        Queued(
          next.turnId,
          next.text,
          afterAnswer: answer,
          afterCalls: !answer,
          from: next.from,
        ),
      );
    }

    _steers.add(marker);
    // Another's message, held until it goes out: a clear would drop it.
    if (next.from case final from?) _incoming[next.turnId] = from;
    _steering = answered.future;
    if (_steerable(session) == into && open()) show(false);
    SteerOutcome outcome;
    SubmittedContent? submitted;
    Timer? slow;
    try {
      await ahead;
      while (current() && _steerable(session) == into) {
        final answer = _waitsOnPerson();
        if (!answer && !open()) break;
        show(answer);
        await _wake.future;
      }
      _heldSteers.remove(next.turnId);
      if (_takenBack.remove(next.turnId)) return;
      if (current() && _steerable(session) == into) {
        _incoming.remove(next.turnId);
        final out = session.steer(
          next.prompt,
          mentions: next.mentions,
          parts: next.parts,
          turnId: next.turnId,
          onSubmitted: (content) {
            submitted = content;
          },
        );
        void outgoing() {
          if (current()) _emit(Queued(next.turnId, next.text, steering: true));
        }

        if (next.from != null) {
          // Another's message shows no row of its own while it goes in.
        } else if (shown) {
          outgoing();
        } else {
          late final Timer timer;
          timer = Timer(const Duration(milliseconds: steerShownMs), () {
            _steerTimers.remove(timer);
            outgoing();
          });
          slow = timer;
          _steerTimers.add(timer);
        }
        outcome = await out;
      } else {
        outcome = SteerOutcome.refused;
      }
    } catch (_) {
      outcome = SteerOutcome.refused;
    } finally {
      slow?.cancel();
      _steerTimers.remove(slow);
      _steers.remove(marker);
      _incoming.remove(next.turnId);
      if (!answered.isCompleted) answered.complete();
    }
    if (!current()) return;
    if (outcome != SteerOutcome.injected) {
      _sealed = into;
      queued?.call();
    }
    if (outcome == SteerOutcome.refused) {
      if (taken) {
        _putBack(next, _turn?.id == into);
      } else {
        _enqueue(session, next);
      }
      unawaited(_advance(session));
      return;
    }
    if (outcome == SteerOutcome.startedNewTurn) {
      // Recovery owns idle before cancel or closure observers can send again.
      _steers.add(marker);
      try {
        final own = _selfTurnId = 'self-${++_selfTurns}';
        session.cancel().ignore();
        if (!current()) return;
        _emit(Transcribed(SelfStartedAction(own, from: next.from)));
        if (!current()) return;
        final quiet = _quieten(session);
        if (taken) {
          _putBack(next, false);
        } else {
          _hold(next);
        }
        await quiet;
      } finally {
        _steers.remove(marker);
      }
      if (current()) await _advance(session);
      return;
    }
    final at = _now();
    _emit(
      Transcribed(
        PromptAction(
          next.turnId,
          next.text,
          at,
          into: into,
          from: next.from,
          team: next.team,
        ),
      ),
    );
    if (!current()) return;
    final content = submitted;
    if (content != null) {
      _resumed(session);
      _firstPrompt ??= content.prompt;
      _record(
        (r) => r.sent(
          content.turnId,
          content.prompt,
          content.images,
          content.links,
          at,
          resources: content.resources,
          into: into,
          from: next.from,
        ),
      );
      _flushedFirst();
    }
    if (current()) unawaited(_advance(session));
  }

  Delivery _enqueue(Session session, QueuedPrompt next) {
    if (_idle() && _queued.isEmpty && !_waitsBetween()) {
      unawaited(_play(session, next));
      return Delivery.sent;
    }
    _hold(next);
    return Delivery.queued;
  }

  /// Puts a prompt at the end of the queue, which shows it: with no turn
  /// running, behind a request between turns, it says it waits for the
  /// answer, as no turn starts while one waits.
  void _hold(QueuedPrompt next) {
    final held = QueuedPrompt(
      next.turnId,
      next.text,
      sentPrompt: next.prompt,
      mentions: next.mentions,
      held: next.held,
      parts: next.parts,
      place: ++_places,
      afterAnswer: _turn == null && _waitsBetween(),
      from: next.from,
    );
    _queued.add(held);
    _emit(
      Queued(
        held.turnId,
        held.text,
        afterAnswer: held.afterAnswer,
        from: held.from,
      ),
    );
  }

  /// Whether nothing holds the queue back: no turn, no wait for one's
  /// trailing updates or an unanswered steer.
  bool _idle() => _turn == null && _settling == null && _steers.isEmpty;

  /// Whether a request asked with no turn running waits on the person.
  bool _waitsBetween() =>
      _foreignBetween.isNotEmpty ||
      _permissions.values.any((asked) => asked.between) ||
      _elicitations.values.any((asked) => asked.between);

  /// Sends the next queued prompt, if nothing holds the queue back.
  Future<void> _advance(Session session) async {
    if (_current(session) &&
        _idle() &&
        !_waitsBetween() &&
        _queued.isNotEmpty) {
      await _play(session, _queued.removeAt(0));
    }
  }

  /// Puts a prompt on screen and sends it, then the next one queued, once
  /// the agent has answered.
  Future<void> _play(Session session, QueuedPrompt next) async {
    final turnId = next.turnId;
    _wentId = null;
    _sealed = null;
    _selfTurnId = null;
    // A prompt takes the agent's own cycle over, its turn in the cycle's
    // place.
    _cycle = null;
    _openCalls.clear();
    _madeAt.clear();
    Turn? submitted;
    var cancelled = false, went = false;
    final completed = Completer<TurnResult>();
    // Reserve ownership before observers can send, cancel or replace reentrantly.
    final pending = Turn(turnId, completed.future, () async {
      cancelled = true;
      await submitted?.cancel();
    });
    _turn = (id: turnId, turn: pending);
    _lastTurnId = turnId;
    _emit(
      Transcribed(
        PromptAction(
          turnId,
          next.text,
          _now(),
          from: next.from,
          team: next.team,
        ),
      ),
    );
    if (!_current(session)) {
      completed.complete(const TurnAnswered(acp.StopReason.cancelled));
      _retiredEnded(
        session,
        turnId,
        false,
        const TurnAnswered(acp.StopReason.cancelled),
      );
      return;
    }
    TurnResult result;
    try {
      if (cancelled) {
        result = const TurnAnswered(acp.StopReason.cancelled);
      } else {
        // A cleared team agent's first prompt, whatever sent it, opens with
        // its team part, as its first did; one that brings its own keeps
        // that.
        final part = next.team == null ? _firstPart : null;
        final turn = session.prompt(
          part == null ? next.prompt : '${teamBlock(part)}\n${next.prompt}',
          mentions: next.mentions,
          parts: next.parts,
          turnId: turnId,
          onSubmitted: (content) {
            if (!_current(session)) return;
            _wentId = turnId;
            went = true;
            if (part != null && identical(_firstPart, part)) _firstPart = null;
            _costs?.began(turnId);
            _resumed(session);
            _firstPrompt ??= content.prompt;
            _record(
              (r) => r.sent(
                content.turnId,
                content.prompt,
                content.images,
                content.links,
                _now(),
                resources: content.resources,
                from: next.from,
              ),
            );
            _flushedFirst();
          },
        );
        submitted = turn;
        if (cancelled) turn.cancel().ignore();
        if (_current(session) && _turn?.id == turnId) {
          _turn = (id: turnId, turn: turn);
        }
        result = await turn.result;
      }
    } catch (error) {
      result = TurnFailed(_messageOf(error));
    }
    completed.complete(result);
    if (!_current(session)) {
      _retiredEnded(session, turnId, went, result);
      return;
    }
    _sealed = turnId;
    // A plan its agent left open has nothing left to wait on.
    _cancelPlans();
    _rouse();
    _unhold();
    if (_queued.isNotEmpty && _current(session)) await _quieten(session);
    if (!_current(session)) return;
    if (_turn?.id == turnId) _turn = null;
    _endedAt = _now();
    _leftOpen(turnId);
    // A question of chord's the turn ended under has nobody to answer.
    _withdrawAsks();
    if (!_current(session)) return;
    _emit(Transcribed(ResultAction(turnId, result)));
    final usage = result is TurnAnswered ? result.usage : null;
    final figures = went
        ? _costs?.ended(
            turnId,
            usage,
            modelsFrom(
              session.state.configOptions,
              session.state.models,
            )?.current,
          )
        : usage == null
        ? null
        : TurnFigures(turnId: turnId, usage: usage);
    if (figures != null && _current(session)) {
      _emit(Transcribed(UsageAction(turnId, figures)));
    }
    await _advance(session);
  }

  /// A session let go: what it says it cost keeps it from closing until it
  /// is quiet, and counts still, as its own, kept in its record.
  void _retiredHeard(Session session, acp.SessionUpdate update) {
    final retired = _retired[session];
    if (retired == null) return;
    retired.heardAt = _now();
    final turnId = retired.costs.lastTurn;
    if (turnId == null || costReading(update) == null) return;
    _emit(RetiredUpdate(turnId, update));
    final late = retired.costs.heardLast(update);
    if (late != null) _emit(RetiredUsage(late));
  }

  /// The end of a turn of a session let go: what it cost, as that
  /// session's, and the quiet its close waits for from now.
  void _retiredEnded(
    Session session,
    String turnId,
    bool went,
    TurnResult result,
  ) {
    final retired = _retired[session];
    if (retired == null) return;
    final figures = went
        ? retired.costs.ended(
            turnId,
            result is TurnAnswered ? result.usage : null,
            modelsFrom(
              session.state.configOptions,
              session.state.models,
            )?.current,
          )
        : null;
    if (figures != null) _emit(RetiredUsage(figures));
    retired.heardAt = _now();
    retired.end();
  }

  /// Waits for a retired session's turn to end, at most [settleLimitMs],
  /// then for its quiet, at most to the same limit; no longer once the
  /// conversation closes.
  Future<void> _retirement(_Retired retiring) async {
    final giveUp = _now() + settleLimitMs;
    await _until(retiring.ended.future, settleLimitMs);
    while (!_quit.isCompleted) {
      final wait =
          [retiring.heardAt + quietMs, giveUp].reduce((a, b) => a < b ? a : b) -
          _now();
      if (wait <= 0) return;
      await _until(null, wait);
    }
  }

  /// A retired session's turn's end, which its close brings about, at most
  /// [quietMs] after it.
  Future<void> _endedOrQuiet(_Retired? retiring) {
    if (retiring == null || retiring.ended.isCompleted) return Future.value();
    final over = Completer<void>();
    final timer = Timer(const Duration(milliseconds: quietMs), () {
      if (!over.isCompleted) over.complete();
    });
    retiring.ended.future.then((_) {
      if (!over.isCompleted) over.complete();
    });
    return over.future.whenComplete(timer.cancel);
  }

  /// [done], or [ms] passing, or the conversation closing: the first.
  Future<void> _until(Future<void>? done, num ms) {
    final over = Completer<void>();
    void settle() {
      if (!over.isCompleted) over.complete();
    }

    final timer = Timer(Duration(milliseconds: ms.ceil()), settle);
    done?.then((_) => settle());
    _quit.future.then((_) => settle());
    return over.future.whenComplete(timer.cancel);
  }

  /// Waits until the agent has been quiet for [quietMs], at most
  /// [settleLimitMs]; the updates it sends meanwhile are the turn's tail.
  /// This is the original's bounded heuristic: updates carry no prompt id,
  /// so one later than the cap folds under whatever turn runs then.
  Future<void> _quieten(Session session) async {
    final settling = _settling = _Quiet();
    final giveUp = _now() + settleLimitMs;

    _heardAt = _heardAt > _now() ? _heardAt : _now();

    try {
      while (_current(session) && !settling.aborted) {
        final wait =
            [_heardAt + quietMs, giveUp].reduce((a, b) => a < b ? a : b) -
            _now();
        if (wait <= 0) break;
        await settling.wait(wait);
      }
    } finally {
      if (identical(_settling, settling)) _settling = null;
    }
  }

  /// The requests turn [turnId] ended with still open wait on the person
  /// between turns, as one asked then does: the queue holds behind them.
  void _leftOpen(String turnId) {
    var left = false;
    for (final asked in _permissions.values) {
      if (asked.turnId == turnId && !asked.between) {
        asked.between = true;
        left = true;
      }
    }
    // So does a form or link still open.
    for (final asked in _elicitations.values) {
      if (asked.turnId == turnId && !asked.between) {
        asked.between = true;
        left = true;
      }
    }
    // A task's, asked while the turn ran, waits between turns as well.
    for (final id in _foreign.keys) {
      if (_foreignBetween.add(id)) left = true;
    }
    if (left) _holdForAnswer();
  }

  /// A request between turns came: everything queued now waits for its
  /// answer, and says so.
  void _holdForAnswer() {
    final generation = _generation;
    for (final (index, queued) in [..._queued].indexed) {
      if (generation != _generation || _closing != null) return;
      if (queued.afterAnswer) continue;
      _queued[index] = QueuedPrompt(
        queued.turnId,
        queued.text,
        sentPrompt: queued.prompt,
        mentions: queued.mentions,
        held: queued.held,
        parts: queued.parts,
        place: queued.place,
        afterAnswer: true,
        from: queued.from,
      );
      _emit(
        Queued(
          queued.turnId,
          queued.text,
          afterAnswer: true,
          from: queued.from,
        ),
      );
    }
  }

  /// What waited for an answer waits, from now, for the turn's end as any
  /// prompt does; a request between turns still open holds it.
  void _unhold() {
    if (_waitsBetween()) return;
    final generation = _generation;
    for (final (index, queued) in [..._queued].indexed) {
      if (generation != _generation || _closing != null) return;
      if (!queued.afterAnswer) continue;
      _queued[index] = QueuedPrompt(
        queued.turnId,
        queued.text,
        sentPrompt: queued.prompt,
        mentions: queued.mentions,
        held: queued.held,
        parts: queued.parts,
        place: queued.place,
        from: queued.from,
      );
      _emit(Queued(queued.turnId, queued.text, from: queued.from));
    }
  }

  void _asked(Session session, PendingPermission request) {
    if (!_current(session)) {
      request.reject();
      return;
    }

    // One with no turn running, from work that outlived its turn, waits on
    // the person as one in a turn does, under the last turn.
    final between = _turn == null;
    final turnId = _stamp();

    _permissions[request.id] = _Asked(request, turnId, between: between);
    if (between) _holdForAnswer();
    if (!_current(session)) {
      request.reject();
      return;
    }
    _emit(
      Transcribed(
        PermissionRequestedAction(
          turnId,
          // One of a subagent's, on a session of its own, names it.
          request.sessionId == session.id
              ? waitFor(request)
              : waitFor(request).askedBy(request.sessionId),
          at: _now(),
          between: between,
        ),
      ),
    );

    if (!_current(session)) {
      request.reject();
      return;
    }
    // Assigned before it listens: a request withdrawn while its event was
    // heard calls back at once.
    late final OnCancel listener;
    listener = OnCancel((_) {
      listener.forget();
      if (!_current(session)) return;
      if (_permissions.remove(request.id) != null) {
        _emit(
          Transcribed(
            PermissionSettledAction(turnId, request.id, const Withdrawn()),
          ),
        );
        _release();
      }
    });
    listener.listen(request.withdrawn);
  }

  /// Withdraws chord's own questions still asked.
  final _asks = <void Function()>{};

  /// Asks the person a question of chord's own in the permission box, as
  /// the `settings` box is, during the turn: the option picked, by its id,
  /// Esc picking the `reject_once` one; or null once it is withdrawn, by
  /// [signal], the turn's end, an interrupt, a clear or the close, and at
  /// once with no turn to ask in.
  Future<String?> ask({
    String? toolCallId,
    String? title,
    String? detail,
    required List<acp.PermissionOption> options,
    SaveBox? save,
    required CancellationToken signal,
  }) {
    final session = _session;
    final turn = _turn;
    if (session == null ||
        turn == null ||
        _closing != null ||
        signal.isCancelled) {
      return Future.value();
    }
    final settled = Completer<String?>();
    final id = const Uuid().v4();
    late final OnCancel listener;
    late final void Function() withdraw;
    void finish(String? optionId) {
      if (settled.isCompleted) return;
      _asks.remove(withdraw);
      listener.forget();
      settled.complete(optionId);
    }

    withdraw = () {
      // Settled already: nothing of it is left to take back.
      if (settled.isCompleted) return;
      if (_permissions.remove(id) case final asked?) {
        _emit(
          Transcribed(
            PermissionSettledAction(asked.turnId, id, const Withdrawn()),
          ),
        );
      }
      finish(null);
      _release();
    };
    // What a client is asked to agree to, which it can see nowhere else.
    final toolCall = {
      'toolCallId': toolCallId ?? id,
      'title': ?title,
      if (detail != null)
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': detail},
          },
        ],
    };
    final request = chordsQuestion(
      id,
      acp.RequestPermissionRequest.fromJson({
        'sessionId': session.id,
        'toolCall': toolCall,
        'options': [
          for (final option in options)
            {
              'optionId': option.optionId,
              'name': option.name,
              'kind': option.kind,
            },
        ],
      }),
      withdrawn: signal,
      answered: finish,
    );
    _permissions[id] = _Asked(request, turn.id, between: false);
    _rouse();
    _asks.add(withdraw);
    // The listener [finish] forgets, so a signal kept for longer holds
    // nothing of this question once it is settled.
    listener = OnCancel((_) => withdraw())..listen(signal);
    _emit(
      Transcribed(
        PermissionRequestedAction(
          turn.id,
          PermissionWait(
            id,
            toolCallId: toolCallId,
            title: title,
            options: options,
            detail: detail,
            save: save,
          ),
          at: _now(),
        ),
      ),
    );
    return settled.future;
  }

  void _withdrawAsks() {
    for (final withdraw in [..._asks]) {
      withdraw();
    }
  }

  /// Whether a request of the agent's waits on the person's answer.
  bool _waitsOnPerson() =>
      _permissions.isNotEmpty || _elicitations.isNotEmpty || _plans.isNotEmpty;

  /// Puts a form or link on screen to wait on the person; one from a
  /// session `clear` let go is cancelled at once. One asked with no turn
  /// running waits between turns and holds the queue.
  void _elicited(Session session, PendingElicitation request) {
    if (!_current(session)) {
      request.answer(const CancelReply());
      return;
    }
    final id = request.id;
    final between = _turn == null;
    final sessionId = request.sessionId;
    final asker = between && sessionId != null && sessionId != session.id
        ? sessionId
        : null;
    final turnId = _stamp();
    final asked = _Elicited(request, turnId, between: between);
    _elicitations[id] = asked;
    _rouse();
    if (between) _holdForAnswer();
    final askedAt = _now();
    _emit(
      Transcribed(
        ElicitationRequestedAction(
          turnId,
          request.wait.asked(at: askedAt, between: between, asker: asker),
        ),
      ),
    );
    late final OnCancel listener;
    listener = OnCancel((_) {
      listener.forget();
      if (!_current(session) || !identical(_elicitations[id], asked)) return;
      _elicitations.remove(id);
      _emit(
        Transcribed(
          ElicitationSettledAction(
            turnId,
            id,
            ranOut(request.wait, _now() - askedAt)
                ? const ElicitationTimedOut()
                : const ElicitationWithdrawn(),
          ),
        ),
      );
      _release();
    });
    listener.listen(request.withdrawn);
  }

  /// Answers a form or link: accept with the values, decline, or cancel
  /// (Esc). The turn goes on; the agent decides what each means.
  @override
  void answer(String id, ElicitationReply reply) {
    final task = _foreign[id];
    if (task != null) return task.answer(id, reply);
    final asked = _elicitations.remove(id);
    if (asked == null) return;
    _emit(
      Transcribed(ElicitationSettledAction(asked.turnId, id, answerOf(reply))),
    );
    asked.request.answer(reply);
    _release();
  }

  /// The form or link [id] still waiting, as the agent asked it, for one
  /// who passes it on; none once settled.
  @override
  PendingElicitation? elicitationRequest(String id) =>
      _elicitations[id]?.request ?? _foreign[id]?.elicitationRequest(id);

  /// Puts a plan on screen to wait on the person. One from a session
  /// `clear` let go or another than the session's own, with no turn
  /// running or one the person interrupted, or out of a call the turn never
  /// announced, is answered cancelled at once, never shown and never taken.
  void _planned(Session session, PendingPlan request) {
    final PlanWait(:id, :toolCallId) = request.wait;
    final turn = _turn;
    final sessionId = request.sessionId;
    if (!_current(session) ||
        (sessionId != null && sessionId != session.id) ||
        turn == null ||
        _sealed == turn.id ||
        !_madeAt.contains(toolCallId)) {
      request.answer(const PlanCancelled());
      return;
    }
    final turnId = _stamp();
    _plans[id] = (request: request, turnId: turnId);
    _rouse();
    _emit(Transcribed(PlanRequestedAction(turnId, request.wait)));
    late final OnCancel listener;
    listener = OnCancel((_) {
      listener.forget();
      // Only this request: another session's, or a later one under the same
      // id, is not its to withdraw.
      if (!_current(session) || !identical(_plans[id]?.request, request)) {
        return;
      }
      if (_plans.remove(id) != null) {
        _emit(
          Transcribed(PlanSettledAction(turnId, id, const PlanWithdrawn())),
        );
        _release();
      }
    });
    listener.listen(request.withdrawn);
  }

  /// Answers a plan with the person's choice; cancelled when it was not
  /// theirs. The agent hears it in its own words, never a yes but theirs.
  void answerPlan(String id, PlanAnswer answer) {
    final asked = _plans.remove(id);
    if (asked == null) return;
    _emit(Transcribed(PlanSettledAction(asked.turnId, id, answer)));
    asked.request.answer(answer);
    _release();
  }

  /// Answers every plan on screen cancelled, never taken.
  void _cancelPlans() {
    for (final id in [..._plans.keys]) {
      answerPlan(id, const PlanCancelled());
    }
  }

  /// Takes a request off the screen and hands it back to be answered.
  PendingPermission? _settle(String id, PermissionAnswer answer) {
    final asked = _permissions.remove(id);
    if (asked == null) return null;
    _emit(Transcribed(PermissionSettledAction(asked.turnId, id, answer)));
    return asked.request;
  }

  /// The permission request [id] still waiting on an answer, as the agent
  /// sent it; none once settled.
  @override
  PendingPermission? permissionRequest(String id) =>
      _permissions[id]?.request ?? _foreign[id]?.permissionRequest(id);

  /// Answers a permission request with one of its options.
  @override
  void choose(String id, String optionId) {
    final task = _foreign[id];
    if (task != null) return task.choose(id, optionId);
    _settle(id, Chosen(optionId))?.resolve(optionId);
    _release();
  }

  /// Rejects a permission request, as Esc does; the turn goes on.
  @override
  void reject(String id) {
    final task = _foreign[id];
    if (task != null) return task.reject(id);
    _settle(id, const Rejected())?.reject();
    _release();
  }

  /// Every request answered: a request between turns answered lets what
  /// waited for it go.
  void _release() {
    _rouse();
    final session = _session;
    if (session == null || _closing != null || _waitsOnPerson()) {
      return;
    }
    if (_turn == null) {
      unawaited(_answeredBetween(session));
      return;
    }
    // Messages held for the answer go into the turn now.
    final into = _steerable(session);
    final held = [
      for (final queued in _queued)
        if (queued.afterAnswer && queued.from != null) queued,
    ];
    if (into == null || held.isEmpty) return;
    _queued.removeWhere((queued) => held.contains(queued));
    for (final message in held) {
      final next = QueuedPrompt(
        message.turnId,
        message.text,
        sentPrompt: message.prompt,
        from: message.from,
      );
      unawaited(_steer(session, into, next, taken: false));
    }
  }

  /// Once a request between turns is answered, what waited for it goes,
  /// after the agent has gone quiet, as after a turn's answer.
  Future<void> _answeredBetween(Session session) async {
    if (_waitsBetween()) return;
    _unhold();
    if (_queued.isEmpty) return;

    // The quiet an earlier answer started counts again from this one; any
    // other wait sends the queue on itself once it is over.
    final settling = _settling;
    if (settling != null) {
      if (!identical(settling, _betweenQuiet)) return;
      settling.abort();
    }

    final quiet = _quieten(session);
    _betweenQuiet = _settling;
    await quiet;
    await _advance(session);
  }

  /// Esc while busy: takes the person's queue back, and stops the running
  /// turn, or ends the wait for its tail at once.
  @override
  void interrupt() {
    if (_closing != null) return;

    // Messages stay, and go once the turn has ended, as after any turn.
    final withdrawn =
        [
          for (final queued in _queued)
            if (queued.from == null) queued,
          ..._heldSteers.values,
        ]..sort(
          (a, b) => (a.place ?? double.infinity).compareTo(
            b.place ?? double.infinity,
          ),
        );
    _takenBack.addAll(_heldSteers.keys);
    _heldSteers.clear();
    _queued.removeWhere((queued) => queued.from == null);
    if (withdrawn.isNotEmpty) _emit(QueueWithdrawn(withdrawn));

    // The turn's work is stopped, its task agents' with it.
    for (final task in [..._tasks.values]) {
      task.cancel(TaskStop.esc);
    }

    final turn = _turn;
    if (turn != null) _sealed = turn.id;
    // A plan goes with it, never taken: cursor's names no session, so the
    // transport cannot tie it to the cancel as it does a permission. Once
    // sealed, as answering one releases what waited on it.
    _cancelPlans();
    _rouse();
    _unhold();
    _withdrawAsks();

    // The agent's own cycle has no prompt of chord's to cancel: the
    // session is told to stop, and the cycle ends as a cancelled turn does.
    final cycle = _cycle, session = _session;
    if (turn == null && cycle != null && session != null) {
      _emit(Transcribed(CancelAction(cycle, _now())));
      // The cycle may have ended before the cancel landed.
      session.cancel().ignore();
      _endCycle(session, cancelled: true);
      return;
    }

    // The turn has answered and only waits out its trailing updates; with
    // the queue taken back, nothing is left to wait for or cancel.
    if (turn == null || _settling != null) {
      _settling?.abort();
      return;
    }

    _cancel(turn);
  }

  /// Takes one prompt back by its turn: a queued one never reaches the
  /// agent; the running one is stopped as an interrupt stops it, the queue
  /// left alone.
  void cancelPrompt(String turnId) {
    if (_closing != null) return;

    final index = _queued.indexWhere((each) => each.turnId == turnId);
    if (index >= 0) {
      final taken = _queued.removeAt(index);
      _emit(QueueWithdrawn([taken]));
      if (_queued.isEmpty) _settling?.abort();
      return;
    }

    final turn = _turn;
    if (turn?.id != turnId) return;
    _sealed = turnId;
    _cancelPlans();
    _rouse();
    _unhold();
    _withdrawAsks();
    if (_settling != null) return;
    _cancel(turn!);
  }

  void _cancel(({String id, Turn turn}) turn) {
    _emit(Transcribed(CancelAction(turn.id, _now())));
    if (_closing != null) return;
    // The turn may settle before the cancel lands; its result says so.
    turn.turn.cancel().catchError((Object _) {});
  }

  /// Retires the current session and starts a fresh one without waiting on
  /// its old change chain; late turns, settings and requests stay retired.
  /// A team agent's [firstPart] goes ahead of the fresh session's first
  /// prompt, as it went ahead of its first.
  Future<void> clear([TeamPart? firstPart]) {
    if (_opening == null || _closing != null) return Future.value();
    _firstPart = firstPart;
    return _replace(null);
  }

  /// Replaces this main through the same barrier as clear, keeping the draft policy.
  Future<void> resume(Resume selected) {
    if (_reopen == null) {
      return Future.error(StateError('No session reopen factory.'));
    }
    return _replace(selected);
  }

  Future<void> _replace(Resume? selected) {
    final opening = _opening;
    if (opening == null || _closing != null) return Future.value();
    final old = _session;
    final turn = _turn;
    final cycle = _cycle;
    // The person's own come back to the box, those held as steers too, in
    // their order; another's messages are let go, as whoever cleared
    // counts them.
    final taken =
        [
          for (final queued in _queued)
            if (queued.from == null) queued,
          ..._heldSteers.values,
        ]..sort(
          (a, b) => (a.place ?? double.infinity).compareTo(
            b.place ?? double.infinity,
          ),
        );
    final stop = _stop;
    // The replacement barrier stands before cancellation or listener code.
    final generation = ++_generation;
    _selectedResume = selected;
    _ready = false;
    _resumable = null;
    _resumableRecord = null;
    _opening = null;
    _session = null;
    _early = null;
    final retiring = old == null || _costs == null
        ? null
        : _Retired(_costs!, _heardAt);
    if (retiring != null) _retired[old!] = retiring;
    // No turn of its own to wait on: nothing more will say what it cost.
    if (turn == null) retiring?.end();
    // The agent's own cycle has no prompt to wait on: told to stop, it is
    // over now, what it said it cost with it.
    final cycleCost = old != null && turn == null && cycle != null
        ? _costs?.ended(cycle, null, _models(old)?.current)
        : null;
    if (old != null && turn == null && cycle != null) old.cancel().ignore();
    _costs = null;
    _cycle = null;
    _compactions.clear();
    _endedAt = 0;
    _turn = null;
    // The old session withdraws them as it closes; nothing is left to draw
    // them on.
    _withdrawAsks();
    _lastTurnId = 'session';
    _changes = Future.value();
    _renames = Future.value();
    _firstPrompt = null;
    _title = null;
    // The next session's first prompt is not in any record yet.
    _recorded = Completer<void>();
    _stop = CancellationToken();
    _stderr = StderrTail();
    _queued.clear();
    _resetSteering();
    _permissions.clear();
    _elicitations.clear();
    // The old session cancels them as it closes.
    _plans.clear();
    // Its task agents go with it, let go first so that nothing they say as
    // they close reaches the new session; so do the lines they left for it.
    final tasks = [..._tasks.values];
    if (old != null && retiring != null) {
      for (final task in tasks) {
        _retiredTasks[task.id] = old;
      }
    }
    _tasks.clear();
    _endedTaskNames.clear();
    _foreign.clear();
    _foreignBetween.clear();
    _foreignPermissions.clear();
    _ahead.clear();
    // A new session, whose agent started none of them and whose ids start
    // again at m1.
    final monitors = _stopMonitors();
    _monitorsPast = MonitorsPast.none;
    _monitorsEnded.clear();
    _endedMonitors = [];
    _monitorCount = 0;
    _settling?.abort();
    _settling = null;
    _betweenQuiet = null;
    _heardAt = 0;
    Future<void>? closingOld;
    final retired = opening.then((session) async {
      if (identical(session, old) && closingOld != null) {
        await closingOld;
      } else {
        await session?.close();
      }
    });
    _retiring.add(Kept(retired));
    _retiring.add(Kept(monitors));
    stop.cancel();
    old?.permissions.close();
    turn?.turn.cancel().ignore();
    // Closed once its turn has said what it cost, as the original does, or
    // after the settle limit and quiet; at once on a quit.
    if (old != null) {
      closingOld =
          (retiring == null ? Future<void>.value() : _retirement(retiring))
              .then((_) => old.close())
              // A turn its close answers still says what it cost.
              .then((_) => _endedOrQuiet(retiring))
              .whenComplete(() => _retired.remove(old));
    }
    if (taken.isNotEmpty) _emit(QueueWithdrawn(taken));
    if (_closing == null && generation == _generation) _emit(const Cleared());
    // After Cleared, so the record has it as the session it let go.
    if (cycleCost != null && _closing == null && generation == _generation) {
      _emit(RetiredUsage(cycleCost));
    }
    for (final task in tasks) {
      final closing = task.close().catchError((Object _) {});
      // The window's close waits for them, as for its ended tasks.
      _endedTasks.add(closing);
      closing.whenComplete(() {
        _endedTasks.remove(closing);
        if (identical(_retiredTasks[task.id], old)) {
          _retiredTasks.remove(task.id);
        }
      }).ignore();
    }
    if (_closing == null && generation == _generation) start();
    // Clear does not make a failed retirement a failed new session.
    return retired.catchError((Object _) {});
  }

  void _resetSteering() {
    for (final timer in _steerTimers) {
      timer.cancel();
    }
    _steerTimers.clear();
    _steers.clear();
    _heldSteers.clear();
    _takenBack.clear();
    // Messages held for a session let go are not this launch's.
    _incoming.clear();
    _steering = Future.value();
    _wentId = _sealed = _selfTurnId = null;
    _openCalls.clear();
    _madeAt.clear();
    _rouse();
  }

  /// Closes the session through the client's barrier and stop ladder;
  /// nothing is emitted after [Closing]. Idempotent.
  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing.future;

    // The barrier stands before anyone hears Closing, so a listener that
    // closes or sends as it hears it finds the conversation closing.
    // The session goes as one a clear let go does: what its running turn
    // still says it cost counts, as the original's CHD-373.
    final old = _session;
    if (old != null && _costs != null && !_retired.containsKey(old)) {
      final retiring = _retired[old] = _Retired(_costs!, _heardAt);
      if (_turn == null) retiring.end();
    }
    final done = Completer<void>();
    _closing = Kept(done.future);
    _ready = false;
    // Once closing, so no message held for an answer goes in as they go.
    _withdrawAsks();
    _record((r) => r.heard(const Closing()));
    _deliver(const Closing());
    if (!_quit.isCompleted) _quit.complete();
    _settling?.abort();
    _resetSteering();
    _stop.cancel();
    // Its task agents go with it, without a word, but for each one's
    // ending with what it spent: the closing session's still, as a cleared
    // session's is, so they are let go first and their end goes where the
    // session's last cost does.
    final running = [..._tasks.values];
    _tasks.clear();
    if (old != null) {
      for (final task in running) {
        _retiredTasks[task.id] = old;
      }
    }
    final tasks = [
      for (final task in running) task.close().catchError((Object _) {}),
      ..._endedTasks,
      // Its monitors go with it, without a word.
      _stopMonitors(),
    ];
    _foreign.clear();
    _foreignBetween.clear();
    _foreignPermissions.clear();
    () async {
      final current = () async {
        final session = await (_opening ?? Future<Session?>.value());
        await session?.close();
      }();
      try {
        await Future.wait([
          for (final retiring in _retiring) retiring.future,
          current,
          ...tasks,
        ]);
      } finally {
        await _recording?.flushed();
      }
    }().then(done.complete, onError: done.completeError);
    return done.future;
  }
}

String _messageOf(Object error) => switch (error) {
  AgentGone(:final message) => message,
  RpcException(:final message) => message,
  FormatException(:final message) => message,
  _ => '$error',
};

/// A session let go and still closing: its costs and its turn's end.
final class _Retired {
  _Retired(this.costs, this.heardAt);
  final TurnCosts costs;
  num heardAt;
  final ended = Completer<void>();
  void end() {
    if (!ended.isCompleted) ended.complete();
  }
}

/// A client's initial config option the session could not start with, in
/// the words the failed start shows.
final class _EntryRefused implements Exception {
  const _EntryRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How early, of the agent's own wait, a withdrawal still reads as the
/// wait running out: the request reached chord a moment after it was sent,
/// so chord's countdown ends a little after the agent's.
const ranOutToleranceMs = 1000;

/// Whether [wait], withdrawn after [waited] milliseconds, ran out: one with
/// a countdown withdrawn within [ranOutToleranceMs] of its end, on its own
/// clock, or after it, as that; any earlier one as a cancel.
bool ranOut(ElicitationWait wait, num waited) {
  final expires = wait is FormWait ? wait.questions?.expiresInMs : null;
  return expires != null && waited >= expires - ranOutToleranceMs;
}

/// [action] as it goes into another session's stream, under that session's
/// turn [turnId].
TranscriptAction _stampedAs(TranscriptAction action, String turnId) =>
    switch (action) {
      UpdateAction(
        :final update,
        :final at,
        :final unasked,
        :final subagentId,
      ) =>
        UpdateAction(
          turnId,
          update,
          at: at,
          unasked: unasked,
          subagentId: subagentId,
        ),
      ServedAction(:final call, :final subagentId) => ServedAction(
        turnId,
        call,
        subagentId: subagentId,
      ),
      PermissionRequestedAction(:final wait, :final at, :final between) =>
        PermissionRequestedAction(turnId, wait, at: at, between: between),
      PermissionSettledAction(:final id, :final answer) =>
        PermissionSettledAction(turnId, id, answer),
      ElicitationRequestedAction(:final elicitation) =>
        ElicitationRequestedAction(turnId, elicitation),
      ElicitationSettledAction(:final id, :final answer) =>
        ElicitationSettledAction(turnId, id, answer),
      FailedAction(:final message) => FailedAction(turnId, message),
      WarnedAction(:final message) => WarnedAction(turnId, message),
      _ => action,
    };

/// What a task does to the session that started it, as [Conversation]
/// gives it.
final class _TaskParent implements TaskParent {
  _TaskParent(this._relay, this._deliver, this._ahead, this._ended);

  final void Function(ConversationEvent event) _relay;
  final void Function(MessageFrom from, String text) _deliver, _ahead;
  final void Function() _ended;

  @override
  void relay(ConversationEvent event) => _relay(event);

  @override
  void deliver(MessageFrom from, String text) => _deliver(from, text);

  @override
  void ahead(MessageFrom from, String text) => _ahead(from, text);

  @override
  void ended() => _ended();
}

/// A running monitor, and the message of its still queued, if one is.
final class _Monitoring {
  _Monitoring(this.run);

  final MonitorRun run;
  ({String turnId, EventLines lines})? queued;
}

/// A monitor's batches and end, to the conversation that started it, by
/// the run: one stopped before a `/clear` ends after it, when the new
/// session's m1 is another.
final class _Hooks implements MonitorHooks {
  _Hooks(this._conversation, this._info);

  final Conversation _conversation;
  final MonitorInfo _info;
  MonitorRun? run;

  @override
  void event(EventLines lines) =>
      _conversation._monitorEvent(_info, run, lines);

  @override
  void ended(MonitorEnd end, EventLines rest) =>
      _conversation._monitorEnded(_info, run, end, rest);
}
