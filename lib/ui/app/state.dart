/// The window's state for M1, the original's `ui/app/state.ts` cut to what
/// the conversation's events change: where the start stands, what the
/// agent reported, the transcript and the queue. Plain Dart; the window
/// folds each event into one notifier and draws it.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart'
    show ScrollState, ScrollStep, Follow, reduceScrolled, VimState;

import '../dialogs/permission.dart' show askedPermission;
import '../prompt/images.dart';
import '../prompt/prompt.dart';
import '../prompt/search.dart';
import '../prompt/state.dart' show KeptDraft;
import '../pickers/state.dart';
import 'sessions.dart';

import '../../session/agent_state.dart';
import '../../session/sessions.dart';
import '../../session/conversation.dart';
import '../../session/transcript/reducer.dart';
import '../../session/turn_costs.dart' show TurnFigures;
import '../../session/usage.dart';
import '../../session/transcript/types.dart';
import '../../session/transcript/entries.dart' show appended, replayTranscript;
import '../start_state.dart';
import '../shortcuts/state.dart';
import '../agents/agents.dart' show AgentsView;
import '../background/state.dart';
import '../../session/monitors.dart' show EndedMonitor, RunningMonitor;

/// What the window draws of one session.
final class AppState {
  const AppState({
    this.start = StartState.idle,
    this.agent = AgentState.empty,
    this.resumed,
    this.omittedHistory = false,
    this.resumeAsked,
    this.resumePicker,
    this.transcript = Transcript.empty,
    this.queue = const [],
    this.held = const [],
    this.attended,
    this.pendingMode,
    this.quitArmed = false,
    this.closing = false,
    this.shortcuts = const ShortcutsState(),
    this.draft = '',
    this.kept = const [],
    this.bash = false,
    this.draftHeld,
    this.steerRefused,
    this.search,
    this.notes = 0,
    this.cursor = startCursor,
    this.expanded = false,
    this.requestOverflows = false,
    this.scroll = const ScrollState(following: true),
    this.spent,
    this.since,
    this.monitors = const [],
    this.endedMonitors = const [],
    this.images = const [],
    this.imageCount = 0,
    this.pasteFailed,
    this.pasteFailedUntilStarted = false,
    this.keysFailed,
    this.editorFailed,
    this.vim,
    this.theme = 'auto',
    this.themePreview,
    this.mcpPanel = false,
    this.notice,
    this.agentsFocus = false,
    this.agentCloseArmed,
    this.sessionsNote,
    this.agentsView,
    this.summaryFocus = false,
    this.backgroundView,
  });

  /// The list of the window's agents under the prompt has the keys, rather
  /// than the box: ↑ ↓ pick, `x` closes.
  final bool agentsFocus;

  /// `x` was pressed once on the busy child with this key; a second press
  /// while it holds stops and closes it.
  final int? agentCloseArmed;

  /// What a key on the agents could not do, such as ctrl+x a with none
  /// waiting, said in the status line until the draft is touched, another
  /// agent comes forward, or an armed close or quit takes its place.
  final String? sessionsNote;

  /// Where the list's lines start while its picked row, taller than the
  /// list, is read by line; none puts that row's first line in sight.
  final AgentsView? agentsView;

  /// The summary line has the `❯` while the list has the keys.
  final bool summaryFocus;

  /// The background view, while open.
  final BackgroundView? backgroundView;

  /// The images the draft may hold, by number; a prompt sends the ones
  /// whose placeholders are in its text. Kept across `/clear`, as the draft
  /// is.
  final List<PastedImage> images;

  /// The drafts ↓ set aside, oldest first, which ↑ walks before the
  /// prompts sent; the agent's own, so another agent's ↑ never brings one,
  /// and kept across sending and `/clear`.
  final List<KeptDraft> kept;

  /// The highest image number given out, so a pasted image never takes the
  /// number of one a queued or earlier prompt holds.
  final int imageCount;

  /// ctrl+v or a pasted path found no image to take, said in the status
  /// line until the draft is touched again.
  final String? pasteFailed;

  /// [pasteFailed] says the agent has not started yet, which stops being
  /// true once it has started, or failed to.
  final bool pasteFailedUntilStarted;

  /// The keybindings file's problems, counted with the first named, said
  /// in the status line until the draft is touched.
  final String? keysFailed;

  /// `/vim`: the prompt box edits as vim does, in insert or normal mode;
  /// absent while it is off.
  final VimState? vim;

  /// The `theme` setting in use: `auto` or one of the palettes' ids.
  final String theme;

  /// The theme `/theme` highlights while it is open, which the whole
  /// window previews; null while it is closed.
  final String? themePreview;

  /// Whether `/theme`'s picker is on screen: open, and no request or plan
  /// put to the person in its place, as the original's themePickerShown.
  bool get themePickerShown =>
      themePreview != null &&
      !closing &&
      !shortcuts.help &&
      (askedPermission(transcript.turn) == null || heldBack(this)) &&
      !transcript.planAsks.any((ask) => ask.answer == null);

  /// `/mcp` was asked for, until Esc closes it.
  final bool mcpPanel;

  /// A one-time notice open above the prompt, by its id: dimcode's, that
  /// it can start other agents.
  final String? notice;

  /// Whether the notice is on screen: open, and not closing. It waits
  /// behind a picker or the background view the person has open, and a
  /// permission, form, link, questions or plan asked meanwhile hides it, as
  /// it hides every picker, until answered. The window's own pickers,
  /// `/team`'s and the settings', are the window's to add.
  bool get noticeShown =>
      notice != null &&
      !closing &&
      askedPermission(transcript.turn) == null &&
      transcript.asking.isEmpty &&
      !transcript.planAsks.any((ask) => ask.answer == null) &&
      !themePickerShown &&
      !mcpShown &&
      !resumePickerShown(this) &&
      backgroundView == null;

  /// Whether `/mcp`'s panel is on screen: opened, and nothing put to the
  /// person in its place (a permission, a form, a link, questions or a
  /// plan), as the original's mcpShown; it comes back once answered.
  bool get mcpShown =>
      mcpPanel &&
      !closing &&
      askedPermission(transcript.turn) == null &&
      transcript.asking.isEmpty &&
      !transcript.planAsks.any((ask) => ask.answer == null);

  /// The theme the window is drawn in now: the one previewed while the
  /// picker is on screen, else the one in use.
  String get shownTheme => themePickerShown ? themePreview! : theme;

  /// This state with [setting] as its theme, if one is given.
  AppState withTheme(String? setting) =>
      setting == null ? this : _with(theme: setting);

  /// This state with vim mode on, in insert mode, when [on].
  AppState withVim(bool on) => on ? _with(vim: const VimState()) : this;

  /// ctrl+g's editor did not end well, said in the status line until the
  /// draft is touched again.
  final String? editorFailed;

  /// This state with [notice] said of the keybindings file, if any.
  AppState withKeysFailed(String? notice) =>
      notice == null ? this : _with(keysFailed: notice);

  /// A session starting: what the window holds once it starts the
  /// conversation.
  static const starting = AppState(
    start: StartState(phase: StartPhase.starting),
  );

  /// The most recently requested mode, while its acknowledgement waits.
  final String? pendingMode;

  /// The prompt value read by pure key decisions.
  final String draft;

  /// The editable draft is a local command, with its ! prefix owned by the mode.
  final bool bash;

  /// Identity of a current code-insertion refusal, guarding its expiry.
  final Object? draftHeld;

  /// Latest unsupported/refused steering note and its expiry identity.
  final ({int id, bool refused})? steerRefused;
  final int notes;

  /// Reverse search owns query input while the saved draft remains unchanged.
  final Search? search;
  final Cursor cursor;

  /// Whether transcript details are expanded.
  final bool expanded;

  /// Whether the active permission needs its scroll keys.
  final bool requestOverflows;

  /// The framework controller's most recently synchronized scroll facts.
  final ScrollState scroll;

  /// The panel and pending chord state.
  final ShortcutsState shortcuts;

  /// Whether the connection is closing and wheel input must be ignored.
  final bool closing;

  /// Whether the first Ctrl+C is waiting for another; Ctrl+C is the only arm.
  final bool quitArmed;

  /// The between-turns request the person explicitly took the keys into.
  final String? attended;

  /// Where the start stands, CTUI-13's phases; gone once the agent exits.
  final StartState start;

  /// What the agent reported of the session, read-only.
  final AgentState agent;

  /// Opened resume facts stay frozen when later agent titles change.
  final Resume? resumed;

  /// The opening's once-only presentation fact, never an agent/record event.
  final bool omittedHistory;

  /// Discovery ownership and its immutable, scope-specific picker snapshot.
  final Object? resumeAsked;
  final ResumePickerState? resumePicker;

  /// The session's transcript.
  final Transcript transcript;

  /// The person's prompts waiting behind the turn, oldest first.
  final List<QueuedPrompt> queue;

  /// Finished local runs waiting to precede the next sent prompt.
  final List<String> held;

  /// What the session has spent: each turn's tokens and own cost.
  final Spent? spent;

  /// When the session came up, epoch milliseconds.
  final num? since;

  /// The monitors the session's agent started that still run, in start
  /// order, and those that ended since it came up, in the order they
  /// ended.
  final List<RunningMonitor> monitors;
  final List<EndedMonitor> endedMonitors;

  AppState _with({
    StartState? start,
    AgentState? agent,
    Resume? resumed,
    bool clearResumed = false,
    bool? omittedHistory,
    Object? resumeAsked,
    bool clearResumeAsked = false,
    ResumePickerState? resumePicker,
    bool clearResumePicker = false,
    Transcript? transcript,
    List<QueuedPrompt>? queue,
    List<String>? held,
    String? attended,
    String? pendingMode,
    bool clearPendingMode = false,
    bool? quitArmed,
    bool? closing,
    ShortcutsState? shortcuts,
    String? draft,
    List<KeptDraft>? kept,
    bool? bash,
    Object? draftHeld,
    bool clearDraftHeld = false,
    ({int id, bool refused})? steerRefused,
    bool clearSteerRefused = false,
    int? notes,
    Search? search,
    bool clearSearch = false,
    Cursor? cursor,
    bool? expanded,
    bool? requestOverflows,
    ScrollState? scroll,
    Spent? spent,
    num? since,
    List<RunningMonitor>? monitors,
    List<EndedMonitor>? endedMonitors,
    List<PastedImage>? images,
    int? imageCount,
    String? pasteFailed,
    bool pasteFailedUntilStarted = false,
    bool clearPasteFailed = false,
    String? keysFailed,
    bool clearKeysFailed = false,
    String? editorFailed,
    bool clearEditorFailed = false,
    VimState? vim,
    bool clearVim = false,
    String? theme,
    String? themePreview,
    bool clearThemePreview = false,
    bool? mcpPanel,
    String? notice,
    bool clearNotice = false,
    bool? agentsFocus,
    int? agentCloseArmed,
    bool clearAgentCloseArmed = false,
    String? sessionsNote,
    bool clearSessionsNote = false,
    AgentsView? agentsView,
    bool clearAgentsView = false,
    bool? summaryFocus,
    BackgroundView? backgroundView,
    bool clearBackgroundView = false,
  }) => AppState(
    start: start ?? this.start,
    agent: agent ?? this.agent,
    resumed: clearResumed ? null : resumed ?? this.resumed,
    omittedHistory: omittedHistory ?? this.omittedHistory,
    resumeAsked: clearResumeAsked ? null : resumeAsked ?? this.resumeAsked,
    resumePicker: clearResumePicker ? null : resumePicker ?? this.resumePicker,
    transcript: transcript ?? this.transcript,
    queue: queue ?? this.queue,
    held: held ?? this.held,
    attended: attended ?? this.attended,
    pendingMode: clearPendingMode ? null : (pendingMode ?? this.pendingMode),
    quitArmed: quitArmed ?? this.quitArmed,
    closing: closing ?? this.closing,
    shortcuts: shortcuts ?? this.shortcuts,
    draft: draft ?? this.draft,
    kept: kept ?? this.kept,
    bash: bash ?? this.bash,
    draftHeld: clearDraftHeld ? null : draftHeld ?? this.draftHeld,
    steerRefused: clearSteerRefused ? null : steerRefused ?? this.steerRefused,
    notes: notes ?? this.notes,
    search: clearSearch ? null : search ?? this.search,
    cursor: cursor ?? this.cursor,
    expanded: expanded ?? this.expanded,
    requestOverflows: requestOverflows ?? this.requestOverflows,
    scroll: scroll ?? this.scroll,
    spent: spent ?? this.spent,
    since: since ?? this.since,
    monitors: monitors ?? this.monitors,
    endedMonitors: endedMonitors ?? this.endedMonitors,
    images: images ?? this.images,
    imageCount: imageCount ?? this.imageCount,
    pasteFailed: clearPasteFailed ? null : pasteFailed ?? this.pasteFailed,
    pasteFailedUntilStarted: clearPasteFailed
        ? false
        : pasteFailed != null
        ? pasteFailedUntilStarted
        : this.pasteFailedUntilStarted,
    keysFailed: clearKeysFailed ? null : keysFailed ?? this.keysFailed,
    editorFailed: clearEditorFailed ? null : editorFailed ?? this.editorFailed,
    vim: clearVim ? null : vim ?? this.vim,
    theme: theme ?? this.theme,
    themePreview: clearThemePreview ? null : themePreview ?? this.themePreview,
    mcpPanel: mcpPanel ?? this.mcpPanel,
    notice: clearNotice ? null : notice ?? this.notice,
    agentsFocus: agentsFocus ?? this.agentsFocus,
    agentCloseArmed: clearAgentCloseArmed
        ? null
        : agentCloseArmed ?? this.agentCloseArmed,
    sessionsNote: clearSessionsNote ? null : sessionsNote ?? this.sessionsNote,
    agentsView: clearAgentsView ? null : agentsView ?? this.agentsView,
    summaryFocus: summaryFocus ?? this.summaryFocus,
    backgroundView: clearBackgroundView
        ? null
        : backgroundView ?? this.backgroundView,
  );

  /// The draft was touched: what the status line said of ctrl+v or of the
  /// keybindings file goes.
  AppState _withoutFailure() =>
      pasteFailed == null &&
          keysFailed == null &&
          editorFailed == null &&
          sessionsNote == null
      ? this
      : _with(
          clearPasteFailed: true,
          clearKeysFailed: true,
          clearEditorFailed: true,
          clearSessionsNote: true,
        );

  /// The agent has started, or failed to: a note that it has not started
  /// yet goes, and any other stays until a key.
  AppState _withoutStartNotice() =>
      pasteFailedUntilStarted ? _with(clearPasteFailed: true) : this;
}

/// [spent] with a turn's [figures].
Spent _spentWith(Spent? spent, TurnFigures figures) => addTurn(
  spent,
  figures.turnId,
  figures.usage,
  SpentTurn(figures.cost, figures.model),
  figures.total,
);

/// [state] after [event]; the identical state when it changes nothing.
AppState reduceApp(AppState state, ConversationEvent event) {
  switch (event) {
    case HistoryReplayed(
      :final actions,
      state: final agent,
      :final resumed,
      :final omitted,
    ):
      final replayed = replayTranscript(actions);
      var spent = state.spent;
      for (final action in actions) {
        if (action is UsageAction) spent = _spentWith(spent, action.figures);
      }
      return state._with(
        spent: spent,
        transcript: omitted
            ? replayed.withEntries(
                appended(replayed.entries, [const HistoryOmittedEntry()]),
              )
            : replayed,
        agent: agent,
        resumed: resumed,
        clearResumed: resumed == null,
        omittedHistory: omitted,
      );
    case Transcribed(action: UsageAction(:final figures)):
      return state._with(spent: _spentWith(state.spent, figures));
    case Transcribed(:final action):
      final transcript = reduceTranscript(state.transcript, action);
      final queue = action is PromptAction
          ? _started(state.queue, action.turnId)
          : state.queue;

      if (identical(transcript, state.transcript) &&
          identical(queue, state.queue)) {
        return state;
      }
      final next = state._with(
        transcript: transcript,
        queue: queue,
        held:
            action is ShellEndedAction &&
                !identical(transcript, state.transcript)
            ? List.unmodifiable([...state.held, action.turnId])
            : state.held,
      );
      // A request that takes the keys replaces search, not its saved draft.
      final turn = transcript.turn;
      return next.search != null &&
              turn is AwaitingPermission &&
              turn.permissions.isNotEmpty &&
              !heldBack(next)
          ? next._with(clearSearch: true)
          : next;
    case Connected(:final sessionId, state: final agent, :final at):
      return state._withoutStartNotice()._with(
        start: reduceStart(state.start, SessionOpened(sessionId)),
        agent: agent,
        closing: false,
        since: at,
      );
    case ConnectFailed(:final message, :final signIn, :final failure):
      final start = reduceStart(
        state.start,
        StartFailed(message, signIn: signIn, failure: failure),
      );
      return identical(start, state.start)
          ? state
          : state._withoutStartNotice()._with(start: start);
    case AgentStateChanged(state: final agent):
      return identical(agent, state.agent) ? state : state._with(agent: agent);
    case Queued(
      :final turnId,
      :final text,
      :final afterAnswer,
      :final afterCalls,
      :final steering,
      :final taken,
      :final refused,
      :final from,
    ):
      final previous = state.queue
          .where((each) => each.turnId == turnId)
          .firstOrNull;
      final known = previous != null;
      // Queued just before its images are sent, so the draft's images
      // named in it went with it; a steer out with the agent took them.
      final queued = QueuedPrompt(
        turnId,
        text,
        afterAnswer: afterAnswer,
        afterCalls: afterCalls,
        steering: steering,
        taken: taken,
        held: previous?.held ?? state.held,
        from: from,
        images:
            previous?.images ??
            (steering ? const [] : imagesIn(text, state.images)),
      );

      final next = state._with(
        queue: UnmodifiableListView([
          for (final each in state.queue) each.turnId == turnId ? queued : each,
          if (!known) queued,
        ]),
      );
      return refused
          ? reduceWindow(next, const SteerRefusedAction(true))
          : next;
    case QueueWithdrawn(:final prompts):
      final taken = {for (final each in prompts) each.turnId};
      final queue = [
        for (final each in state.queue)
          if (!taken.contains(each.turnId)) each,
      ];

      final back = [
        for (final queued in state.queue)
          if (taken.contains(queued.turnId)) ...queued.held,
      ];
      // Their images come back with their placeholders.
      final images = [
        for (final queued in state.queue)
          if (taken.contains(queued.turnId)) ...queued.images,
      ];
      return queue.length == state.queue.length
          ? state
          : _imagesAdded(state, images)._with(
              queue: UnmodifiableListView(queue),
              held: back.isEmpty
                  ? state.held
                  : List.unmodifiable([
                      ...back,
                      ...state.held.where((id) => !back.contains(id)),
                    ]),
            );
    case Gone(:final reason, :final stderrLines, :final stderrCut):
      final start = reduceStart(
        state.start,
        AgentExited(reason, lines: stderrLines, cut: stderrCut),
      );
      return identical(start, state.start) ? state : state._with(start: start);
    case SettingNoted(:final id, :final command, :final text, :final failed):
      return state._with(
        transcript: noted(state.transcript, id, command, text, failed: failed),
      );
    case ModePending(:final id, :final pending):
      return pending
          ? state._with(pendingMode: id)
          : state.pendingMode == id
          ? state._with(clearPendingMode: true)
          : state;
    // An earlier session's, which the window keeps where it was let go.
    case RetiredUpdate() || RetiredUsage():
      return state;
    // A title is the record's and the client's; the window draws none.
    case Renamed():
      return state;
    // For the record: the command drew its call, and the list reads the
    // window's agents.
    case RanTyped() || AgentClosed():
      return state;
    case Cleared():
      // A new session: what is the window's own stays, the theme with it,
      // as the original's cleared keeps it. Vim mode stays too, in insert
      // mode with nothing pending as after a send: the original's cleared
      // drops it through initialAppState, a slip fixed here.
      return AppState(
        start: AppState.starting.start,
        expanded: state.expanded,
        theme: state.theme,
        vim: switch (state.vim) {
          final vim? => VimState(register: vim.register),
          null => null,
        },
        draft: state.draft,
        kept: state.kept,
        cursor: state.cursor,
        images: state.images,
        imageCount: state.imageCount,
      );
    // The window's background reads them; none is restarted on a resume.
    case MonitorsChanged(:final running, :final ended):
      return state._with(monitors: running, endedMonitors: ended);
    case Closing():
      return state.closing
          ? state
          : state._with(
              closing: true,
              clearResumeAsked: true,
              clearResumePicker: true,
              summaryFocus: false,
              clearBackgroundView: true,
            );
  }
}

/// [queue] with [turnId]'s prompt gone, as it is once its turn starts.
List<QueuedPrompt> _started(List<QueuedPrompt> queue, String turnId) =>
    queue.any((each) => each.turnId == turnId)
    ? UnmodifiableListView([
        for (final each in queue)
          if (each.turnId != turnId) each,
      ])
    : queue;

/// What the transcript's view does after an event.
enum ScrollEffect {
  /// Nothing.
  none,

  /// Back to the bottom, to see the reply: the person sent a prompt.
  bottom,

  /// Something was added; news while scrolled back.
  news,
}

/// The original's rule: sending a prompt brings the view back to the
/// bottom; anything else added to the transcript is news.
ScrollEffect scrollEffectOf(
  AppState before,
  AppState after,
  ConversationEvent event,
) => entriesScrollEffect(
  before.transcript.entries,
  after.transcript.entries,
  event,
);

/// [scrollEffectOf] for any session, shown or not, from its entries before
/// and after [event]: the original folds every session's scroll alike.
ScrollEffect entriesScrollEffect(
  List<Entry>? before,
  List<Entry>? after,
  ConversationEvent event,
) => switch (event) {
  Transcribed(action: PromptAction()) => ScrollEffect.bottom,
  _ when !identical(before, after) => ScrollEffect.news,
  _ => ScrollEffect.none,
};

/// Whether the session has a turn in flight, including its permission wait.
bool isBusy(AppState state) => state.transcript.turn is! Idle;

/// How long a steering refusal or unsupported-agent note remains visible.
const steerNoteMs = 3000;

/// Original status words for a supported personal steering attempt.
String steerNote(bool refused) => refused
    ? 'Not taken into the running turn · it stays queued'
    : 'This agent does not take messages into a running turn · it stays queued';

/// The form or link on screen: the oldest asked, once no permission and no
/// plan waits before it.
ElicitationWait? askedInput(Transcript transcript) =>
    askedPermission(transcript.turn) != null ||
        transcript.planAsks.any((ask) => ask.answer == null)
    ? null
    : transcript.asking.firstOrNull;

/// The request on screen when it was asked between turns: a permission, or
/// else a form or link; none otherwise.
String? betweenAsked(Transcript transcript) {
  final turn = transcript.turn;
  final permission = askedPermission(turn);
  if (permission != null) {
    return turn is AwaitingPermission && turn.between ? permission.id : null;
  }
  final input = askedInput(transcript);
  return input != null && input.between ? input.id : null;
}

/// Whether the oldest request arrived between turns and still holds no keys.
bool heldBack(AppState state) {
  final id = betweenAsked(state.transcript);
  return id != null && id != state.attended;
}

/// The plan on screen: the oldest unanswered, unless the permission shown
/// was asked before it, as the original's askedPlan.
PlanAsk? askedPlan(Transcript transcript) {
  final plan = transcript.planAsks
      .where((ask) => ask.answer == null)
      .firstOrNull;
  final permission = askedPermission(transcript.turn);
  return plan != null &&
          permission != null &&
          plan.after.contains(permission.id)
      ? null
      : plan;
}

/// Whether a form, link, questions or plan has the keys, as the original's
/// inputWithKeys: asked, and not held back between turns.
bool inputHasKeys(AppState state) =>
    !heldBack(state) &&
    (askedInput(state.transcript) != null ||
        askedPlan(state.transcript) != null);

/// Whether a request on screen, a permission or a form or link, has the
/// keys, which are then not the prompt's.
bool requestHasKeys(AppState state) =>
    (askedPermission(state.transcript.turn) != null ||
        askedInput(state.transcript) != null) &&
    !heldBack(state);

/// Takes the keys into the oldest request, as ctrl+x a asks.
AppState attendRequest(AppState state) {
  final id =
      askedPermission(state.transcript.turn)?.id ??
      betweenAsked(state.transcript);
  if (id == null) return state;
  // The keys go into the request from wherever they were: the list of
  // agents and a search let go of them.
  final left = state.agentsFocus
      ? reduceWindow(state, const AgentsFocusedAction(false))
      : state;
  return left.attended == id && left.search == null
      ? left
      : left._with(attended: id, clearSearch: true);
}

/// The original's deadline for the second Ctrl+C, owned by the live window.
const quitWindowMs = 2000;

/// An intent that changes plain window state rather than session state.
sealed class AppAction {
  const AppAction();
}

/// A local client report, appended without contacting the agent.
final class ReportShownAction extends AppAction {
  const ReportShownAction(this.id, this.rows, {this.command = 'status'});
  final String id, command;
  final List<ReportRow> rows;
}

/// Claims a fresh read; later results must still own this exact opening.
final class ResumeAskedAction extends AppAction {
  const ResumeAskedAction(this.asked);
  final Object asked;
}

/// Discovery's detached result, reduced against the current turn and owner.
final class ResumeListedAction extends AppAction {
  ResumeListedAction(
    this.asked, {
    required this.id,
    required Iterable<EarlierSession> sessions,
    required this.cwd,
    required this.agent,
    required this.now,
    this.error,
    this.cancelKey = 'Esc',
  }) : sessions = List.unmodifiable(sessions);
  final Object asked;
  final String id, cwd, agent;

  /// The key that interrupts, as a sentence starts with it; none unbound.
  final String? cancelKey;
  final List<EarlierSession> sessions;
  final num now;
  final String? error;
}

/// Remounts the other directory scope, freezing its age reference.
final class ResumeScopeToggledAction extends AppAction {
  const ResumeScopeToggledAction(this.now);
  final num now;
}

/// Leaves the saved snapshot without contacting any agent.
final class ResumePickerClosedAction extends AppAction {
  const ResumePickerClosedAction();
}

/// Waits for a second Ctrl+C before the quit deadline.
final class QuitArmedAction extends AppAction {
  const QuitArmedAction();
}

/// Ends the wait for a second Ctrl+C.
final class QuitDisarmedAction extends AppAction {
  const QuitDisarmedAction();
}

/// The list of the window's agents takes the keys, or gives them back to
/// the box; either way a close armed and a row read by line end.
final class AgentsFocusedAction extends AppAction {
  const AgentsFocusedAction(this.focused);
  final bool focused;
}

/// The list's picked row, taller than the list, is read from [view]; none
/// puts its first line in sight.
final class AgentsScrolledAction extends AppAction {
  const AgentsScrolledAction(this.view);
  final AgentsView? view;
}

/// `x` was pressed once on busy child [key].
final class AgentCloseArmedAction extends AppAction {
  const AgentCloseArmedAction(this.key);
  final int key;
}

/// The second `x` is no longer waited for.
final class AgentCloseDisarmedAction extends AppAction {
  const AgentCloseDisarmedAction();
}

/// A key on the agents could not do what it asks: [message] says why.
final class SessionsNotedAction extends AppAction {
  const SessionsNotedAction(this.message);
  final String message;
}

/// Clears draft-associated state and ends an armed quit.
final class DraftClearedAction extends AppAction {
  const DraftClearedAction();
}

/// Reduces the window's own intents without involving a widget or timer.
AppState reduceWindow(AppState state, AppAction action) => switch (action) {
  ResumeAskedAction(:final asked) =>
    state.closing ? state : state._with(resumeAsked: asked),
  ResumeListedAction() => _resumeListed(state, action),
  ResumeScopeToggledAction(:final now) =>
    state.resumePicker == null
        ? state
        : state._with(
            resumePicker: toggledResumeScope(state.resumePicker!, now),
          ),
  ResumePickerClosedAction() =>
    state.resumePicker == null ? state : state._with(clearResumePicker: true),
  SearchChangedAction(:final search) => state._with(
    search: search,
    clearSearch: search == null,
  ),
  SteerRefusedAction(:final refused) => state._with(
    notes: state.notes + 1,
    steerRefused: (id: state.notes + 1, refused: refused),
  ),
  SteerNoteGoneAction(:final id) =>
    state.steerRefused?.id == id ? state._with(clearSteerRefused: true) : state,
  DraftHeldAction(:final id) => state._with(draftHeld: id),
  DraftHeldGoneAction(:final id) =>
    identical(state.draftHeld, id) ? state._with(clearDraftHeld: true) : state,
  BashModeAction(:final on) => state.bash == on ? state : state._with(bash: on),
  ContextSentAction(:final held) =>
    state.held.any(held.contains)
        ? state._with(
            held: List.unmodifiable(
              state.held.where((id) => !held.contains(id)),
            ),
          )
        : state,
  CallTypedAction(:final id, :final command, :final call) => state._with(
    transcript: state.transcript.withEntries(
      appended(state.transcript.entries, [TypedCallEntry(id, command, call)]),
    ),
  ),
  // `/team`'s command line goes with its picker.
  TeamsListedGoneAction() => state._with(
    transcript: state.transcript.withEntries([
      for (final entry in state.transcript.entries)
        if (entry is! TeamShownEntry || entry.shown is! TeamListed) entry,
    ]),
  ),
  TeamShownAction(:final id, :final command, :final shown) => state._with(
    transcript: state.transcript.withEntries(
      appended(state.transcript.entries, [TeamShownEntry(id, command, shown)]),
    ),
  ),
  ReportShownAction(:final id, :final rows, :final command) => state._with(
    transcript: state.transcript.withEntries(
      appended(state.transcript.entries, [ReportEntry(id, command, rows)]),
    ),
  ),
  QuitArmedAction() =>
    state.quitArmed && !state.shortcuts.help
        ? state
        : state._with(
            quitArmed: true,
            shortcuts: reduceShortcuts(state.shortcuts, const HelpClosed()),
            // The warning takes the place of a note of the agents for good.
            clearSessionsNote: true,
          ),
  ShortcutsChangedAction(:final action) => _shortcutsChanged(state, action),
  // The panel would cover the draft that comes back.
  EditorOpenedAction() => _shortcutsChanged(
    state._withoutFailure(),
    const HelpClosed(),
  ),
  EditorFailedAction(:final message) => state._with(editorFailed: message),
  ThemePickerOpenedAction() => state._with(themePreview: state.theme),
  ThemePreviewedAction(:final theme) =>
    state.themePreview == null ? state : state._with(themePreview: theme),
  ThemePickerClosedAction() => state._with(clearThemePreview: true),
  McpOpenedAction() => state._with(mcpPanel: true),
  McpClosedAction() => state._with(mcpPanel: false),
  // One at a time: a second come due while one is open waits for none.
  NoticeOpenedAction(:final id) =>
    state.notice == null ? state._with(notice: id) : state,
  NoticeClosedAction() => state._with(clearNotice: true),
  ThemeChosenAction(:final theme) => state._with(
    theme: theme,
    clearThemePreview: true,
  ),
  VimToggledAction(:final on) =>
    on
        ? state._with(vim: state.vim ?? const VimState())
        : state._with(clearVim: true),
  VimChangedAction(:final vim) =>
    state.vim == null ? state : state._with(vim: vim),
  NotedAction(:final id, :final command, :final text, :final failed) =>
    state._with(
      transcript: noted(state.transcript, id, command, text, failed: failed),
    ),
  DraftEditedAction(:final text, :final cursor) =>
    state.draft == text && state.cursor == cursor
        ? state
        : state._withoutFailure()._with(draft: text, cursor: cursor),
  DraftClearedAction() =>
    state.quitArmed || state.draft.isNotEmpty || state.cursor != 0
        ? state._withoutFailure()._with(
            quitArmed: false,
            draft: '',
            cursor: startCursor,
          )
        : state._withoutFailure(),
  ImagesAddedAction(:final images) => _imagesAdded(state, images),
  DraftKeptAction() =>
    state.draft.isEmpty
        ? state
        : state._with(
            kept: List.unmodifiable([...state.kept, _keptOf(state)]),
            draft: '',
            cursor: startCursor,
            images: const [],
            bash: false,
          ),
  KeptEditedAction(:final index) =>
    index < 0 || index >= state.kept.length
        ? state
        : state._with(
            kept: List.unmodifiable([...state.kept]..[index] = _keptOf(state)),
          ),
  KeptTakenAction(:final index) =>
    index < 0 || index >= state.kept.length
        ? state
        : state._with(
            kept: List.unmodifiable([...state.kept]..removeAt(index)),
          ),
  PasteFailedAction(:final message, :final untilStarted) =>
    // Started, or failed to, before it came: not so any longer.
    untilStarted && state.start.phase != StartPhase.starting
        ? state
        : state._with(
            pasteFailed: message,
            pasteFailedUntilStarted: untilStarted,
          ),
  ImagesSentAction(:final keeping) => _imagesSent(state, keeping),
  ToggleExpandedAction() => state._with(expanded: !state.expanded),
  AttendRequestAction() => attendRequest(state),
  RequestOverflowedAction(:final overflows) =>
    state.requestOverflows == overflows
        ? state
        : state._with(requestOverflows: overflows),
  ScrollChangedAction(:final scroll) =>
    state.scroll == scroll ? state : state._with(scroll: scroll),
  TranscriptScrolledAction(:final step) => _transcriptScrolled(state, step),
  WheeledAction(:final step, :final rows) =>
    state.closing ? state : _wheeled(state, step, rows),
  QuitDisarmedAction() =>
    state.quitArmed ? state._with(quitArmed: false) : state,
  AgentsFocusedAction(:final focused) => state._with(
    agentsFocus: focused,
    summaryFocus: false,
    clearAgentCloseArmed: true,
    clearAgentsView: true,
    // The panel would sit where the list's hint is.
    shortcuts: focused
        ? reduceShortcuts(state.shortcuts, const HelpClosed())
        : null,
  ),
  SummaryFocusedAction(:final focused) =>
    state.summaryFocus == focused ? state : state._with(summaryFocus: focused),
  BackgroundChangedAction(:final action) => switch (reduceBackground(
    state.backgroundView,
    action,
  )) {
    final view when identical(view, state.backgroundView) => state,
    null => state._with(clearBackgroundView: true),
    final view => state._with(backgroundView: view),
  },
  AgentsScrolledAction(:final view) => state._with(
    agentsView: view,
    clearAgentsView: view == null,
  ),
  AgentCloseArmedAction(:final key) => state._with(
    agentCloseArmed: key,
    clearSessionsNote: true,
  ),
  AgentCloseDisarmedAction() =>
    state.agentCloseArmed == null
        ? state
        : state._with(clearAgentCloseArmed: true),
  SessionsNotedAction(:final message) => state._with(sessionsNote: message),
};

AppState _resumeListed(AppState state, ResumeListedAction action) {
  if (state.closing || !identical(state.resumeAsked, action.asked)) {
    return state;
  }
  final current = state._with(clearResumeAsked: true);
  final said =
      resumeRefusal(current.transcript, cancelKey: action.cancelKey) ??
      action.error ??
      (action.sessions.isEmpty
          ? 'No earlier ${action.agent} session to resume, here or in any other directory.'
          : null);
  if (said != null) {
    return reduceWindow(
      current,
      ReportShownAction(action.id, [
        (label: '', text: said),
      ], command: 'resume'),
    );
  }
  return current._with(
    resumePicker: ResumePickerState(
      sessions: action.sessions,
      cwd: action.cwd,
      opening: action.asked,
      openedAt: action.now,
    ),
  );
}

/// A permission with the keys suspends the saved picker snapshot.
bool resumePickerShown(AppState state) {
  final turn = state.transcript.turn;
  return state.resumePicker != null &&
      !state.closing &&
      !(turn is AwaitingPermission &&
          turn.permissions.isNotEmpty &&
          !heldBack(state));
}

/// Forwards a panel intent through the window's reducer.
/// `/theme` opens its picker on the theme in use.
final class ThemePickerOpenedAction extends AppAction {
  const ThemePickerOpenedAction();
}

/// The picker's highlight moved: the window previews [theme].
final class ThemePreviewedAction extends AppAction {
  const ThemePreviewedAction(this.theme);
  final String theme;
}

/// Esc: the theme in use before `/theme` comes back.
final class ThemePickerClosedAction extends AppAction {
  const ThemePickerClosedAction();
}

/// `/mcp` opens its panel.
final class McpOpenedAction extends AppAction {
  const McpOpenedAction();
}

/// Esc closes `/mcp`'s panel.
final class McpClosedAction extends AppAction {
  const McpClosedAction();
}

/// A one-time notice came due: [id] opens above the prompt.
final class NoticeOpenedAction extends AppAction {
  const NoticeOpenedAction(this.id);
  final String id;
}

/// The notice was answered, or Esc closed it to show again next time.
final class NoticeClosedAction extends AppAction {
  const NoticeClosedAction();
}

/// Enter: the theme highlighted is the one in use.
final class ThemeChosenAction extends AppAction {
  const ThemeChosenAction(this.theme);
  final String theme;
}

/// `/vim` turned vim mode [on] or off.
final class VimToggledAction extends AppAction {
  const VimToggledAction(this.on);
  final bool on;
}

/// A key in vim mode moved it on: its mode, a command half typed, its
/// register.
final class VimChangedAction extends AppAction {
  const VimChangedAction(this.vim);
  final VimState vim;
}

/// One of chord's own commands made a call of chord's, drawn under
/// [command] as typed.
final class CallTypedAction extends AppAction {
  const CallTypedAction(this.id, this.command, this.call);
  final String id, command;
  final ChordCall call;
}

/// `/team` showed a team, or opened its picker, under [command] as typed.
final class TeamShownAction extends AppAction {
  const TeamShownAction(this.id, this.command, this.shown);
  final String id, command;
  final TeamShown shown;
}

/// `/team`'s picker closed: the command it left in the transcript goes.
final class TeamsListedGoneAction extends AppAction {
  const TeamsListedGoneAction();
}

/// One of chord's own commands said [text] in the transcript.
final class NotedAction extends AppAction {
  const NotedAction(this.id, this.command, this.text, {this.failed = false});
  final String id, command, text;
  final bool failed;
}

/// ctrl+g handed the terminal to the editor.
final class EditorOpenedAction extends AppAction {
  const EditorOpenedAction();
}

/// The editor did not end well; the draft stays as it was.
final class EditorFailedAction extends AppAction {
  const EditorFailedAction(this.message);
  final String message;
}

final class ShortcutsChangedAction extends AppAction {
  const ShortcutsChangedAction(this.action);
  final ShortcutsAction action;
}

AppState _shortcutsChanged(AppState state, ShortcutsAction action) {
  final shortcuts = reduceShortcuts(state.shortcuts, action);
  return identical(shortcuts, state.shortcuts)
      ? state
      : state._with(shortcuts: shortcuts);
}

/// Images went into the draft, pasted or read from paths, or came back with
/// a recalled or withdrawn prompt.
final class ImagesAddedAction extends AppAction {
  const ImagesAddedAction(this.images);
  final List<PastedImage> images;
}

/// ctrl+v found no image to take, or the agent takes none; [untilStarted]
/// when it says the agent has not started yet.
final class PasteFailedAction extends AppAction {
  const PasteFailedAction(this.message, {this.untilStarted = false});
  final String message;
  final bool untilStarted;
}

/// A prompt took the draft's images; the box starts again without them, but
/// for those [keeping], a draft typed while the prompt waited, holds.
final class ImagesSentAction extends AppAction {
  const ImagesSentAction([this.keeping = '']);
  final String keeping;
}

AppState _imagesAdded(AppState state, List<PastedImage> images) {
  if (images.isEmpty) return state;
  final ids = {for (final image in images) image.id};
  return state._withoutFailure()._with(
    images: List.unmodifiable([
      ...state.images.where((image) => !ids.contains(image.id)),
      ...images,
    ]),
    imageCount: [state.imageCount, ...ids].reduce(math.max),
  );
}

AppState _imagesSent(AppState state, String keeping) {
  final kept = imagesIn(keeping, state.images);
  return kept.length == state.images.length
      ? state
      : state._with(images: List.unmodifiable(kept));
}

/// ↓ set the draft aside: it is kept whole, and the box empties.
final class DraftKeptAction extends AppAction {
  const DraftKeptAction();
}

/// Kept draft [index] left the stack: sent, or cleared while shown.
final class KeptTakenAction extends AppAction {
  const KeptTakenAction(this.index);
  final int index;
}

/// The walk moves off kept draft [index], shown: it keeps the box as it
/// stands, edited or not, in its place on the stack.
final class KeptEditedAction extends AppAction {
  const KeptEditedAction(this.index);
  final int index;
}

/// The box as it stands, kept whole: its images are the ones its
/// placeholders name.
KeptDraft _keptOf(AppState state) => KeptDraft(
  text: state.draft,
  cursor: state.cursor,
  images: List.unmodifiable(imagesIn(state.draft, state.images)),
  bash: state.bash,
);

/// Synchronizes the controller's text and cursor before pure key decisions.
final class DraftEditedAction extends AppAction {
  const DraftEditedAction(this.text, this.cursor);
  final String text;
  final Cursor cursor;
}

final class ToggleExpandedAction extends AppAction {
  const ToggleExpandedAction();
}

final class AttendRequestAction extends AppAction {
  const AttendRequestAction();
}

final class RequestOverflowedAction extends AppAction {
  const RequestOverflowedAction(this.overflows);
  final bool overflows;
}

final class ScrollChangedAction extends AppAction {
  const ScrollChangedAction(this.scroll);
  final ScrollState scroll;
}

final class TranscriptScrolledAction extends AppAction {
  const TranscriptScrolledAction(this.step);
  final ScrollStep step;
}

/// One wheel report, restricted to vertical line steps; a report merged
/// from a batch carries several.
final class WheeledAction extends AppAction {
  /// Scrolls [rows] transcript rows upward.
  const WheeledAction.up([this.rows = 1]) : step = ScrollStep.lineUp;

  /// Scrolls [rows] transcript rows downward.
  const WheeledAction.down([this.rows = 1]) : step = ScrollStep.lineDown;

  /// The existing line-scroll behavior used by this report.
  final ScrollStep step;

  /// How many times [step] applies.
  final int rows;
}

AppState _wheeled(AppState state, ScrollStep step, int rows) {
  var next = state;
  for (var i = 0; i < rows; i++) {
    next = _transcriptScrolled(next, step);
  }
  return next;
}

AppState _transcriptScrolled(AppState state, ScrollStep step) {
  final scroll = reduceScrolled(state.scroll, step, Follow.bottom);
  return identical(scroll, state.scroll) ? state : state._with(scroll: scroll);
}

/// The search query/match, or null when the original editor returns.
final class SearchChangedAction extends AppAction {
  const SearchChangedAction(this.search);
  final Search? search;
}

/// The running turn refused a steer, or the adapter offers no steering.
final class SteerRefusedAction extends AppAction {
  const SteerRefusedAction(this.refused);
  final bool refused;
}

/// Expires only the steering note whose original three-second window ended.
final class SteerNoteGoneAction extends AppAction {
  const SteerNoteGoneAction(this.id);
  final int id;
}

/// Removes exactly the held runs accepted by a sent or queued prompt.
final class ContextSentAction extends AppAction {
  ContextSentAction(Iterable<String> held) : held = Set.unmodifiable(held);
  final Set<String> held;
}

/// Enters or leaves the local-command editor without changing its draft.
final class BashModeAction extends AppAction {
  const BashModeAction(this.on);
  final bool on;
}

/// Records refusal to replace a nonempty prompt.
final class DraftHeldAction extends AppAction {
  const DraftHeldAction(this.id);
  final Object id;
}

/// The `❯` onto the background's summary line, or off it.
final class SummaryFocusedAction extends AppAction {
  const SummaryFocusedAction(this.focused);
  final bool focused;
}

/// The background view changed, as [reduceBackground] says.
final class BackgroundChangedAction extends AppAction {
  const BackgroundChangedAction(this.action);
  final BackgroundAction action;
}

/// Expires only the refusal that scheduled this action.
final class DraftHeldGoneAction extends AppAction {
  const DraftHeldGoneAction(this.id);
  final Object id;
}

/// One agent's own part of the window, swapped whole when another is
/// picked: its start, its chat, its queue and its field. The original's
/// `SessionState`; scroll is not in it, as the session's retained
/// `ScrollController` is the one place its scroll lives.
final class SessionState {
  const SessionState({
    this.start = StartState.idle,
    this.agent = AgentState.empty,
    this.resumed,
    this.omittedHistory = false,
    this.transcript = Transcript.empty,
    this.queue = const [],
    this.held = const [],
    this.attended,
    this.requestOverflows = false,
    this.pendingMode,
    this.draft = '',
    this.kept = const [],
    this.cursor = startCursor,
    this.bash = false,
    this.images = const [],
    this.imageCount = 0,
    this.spent,
    this.since,
    this.monitors = const [],
    this.endedMonitors = const [],
  });

  final StartState start;
  final AgentState agent;
  final Resume? resumed;
  final bool omittedHistory;
  final Transcript transcript;
  final List<QueuedPrompt> queue;
  final List<String> held;
  final String? attended;
  final bool requestOverflows;
  final String? pendingMode;
  final String draft;

  /// The drafts ↓ set aside, oldest first: this agent's alone.
  final List<KeptDraft> kept;
  final Cursor cursor;
  final bool bash;
  final List<PastedImage> images;
  final int imageCount;
  final Spent? spent;
  final num? since;
  final List<RunningMonitor> monitors;
  final List<EndedMonitor> endedMonitors;

  /// A session as it starts: nothing said, nothing typed.
  static const starting = SessionState(
    start: StartState(phase: StartPhase.starting),
  );
}

/// The window's own part, whichever session fills the rest: the pickers,
/// the panel, the quit, the theme, vim, the search and the notes, and the
/// front session's scroll as last synced from its controller.
final class WindowState {
  const WindowState({
    this.resumeAsked,
    this.resumePicker,
    this.quitArmed = false,
    this.closing = false,
    this.shortcuts = const ShortcutsState(),
    this.draftHeld,
    this.steerRefused,
    this.search,
    this.notes = 0,
    this.expanded = false,
    this.scroll = const ScrollState(following: true),
    this.pasteFailed,
    this.pasteFailedUntilStarted = false,
    this.keysFailed,
    this.editorFailed,
    this.vim,
    this.theme = 'auto',
    this.themePreview,
    this.mcpPanel = false,
    this.notice,
    this.agentsFocus = false,
    this.agentCloseArmed,
    this.sessionsNote,
    this.agentsView,
    this.summaryFocus = false,
    this.backgroundView,
  });

  final Object? resumeAsked;
  final ResumePickerState? resumePicker;
  final bool quitArmed;
  final bool closing;
  final ShortcutsState shortcuts;
  final Object? draftHeld;
  final ({int id, bool refused})? steerRefused;
  final Search? search;
  final int notes;
  final bool expanded;
  final ScrollState scroll;
  final String? pasteFailed;
  final bool pasteFailedUntilStarted;
  final String? keysFailed;
  final String? editorFailed;
  final VimState? vim;
  final String theme;
  final String? themePreview;
  final bool mcpPanel;
  final String? notice;
  final bool agentsFocus;
  final int? agentCloseArmed;
  final String? sessionsNote;
  final AgentsView? agentsView;
  final bool summaryFocus;
  final BackgroundView? backgroundView;
}

/// The window as [session] fills it beside [window].
AppState appStateOf(WindowState window, SessionState session) => AppState(
  start: session.start,
  agent: session.agent,
  resumed: session.resumed,
  omittedHistory: session.omittedHistory,
  transcript: session.transcript,
  queue: session.queue,
  held: session.held,
  attended: session.attended,
  requestOverflows: session.requestOverflows,
  pendingMode: session.pendingMode,
  draft: session.draft,
  kept: session.kept,
  cursor: session.cursor,
  bash: session.bash,
  images: session.images,
  imageCount: session.imageCount,
  spent: session.spent,
  since: session.since,
  monitors: session.monitors,
  endedMonitors: session.endedMonitors,
  resumeAsked: window.resumeAsked,
  resumePicker: window.resumePicker,
  quitArmed: window.quitArmed,
  closing: window.closing,
  shortcuts: window.shortcuts,
  draftHeld: window.draftHeld,
  steerRefused: window.steerRefused,
  search: window.search,
  notes: window.notes,
  expanded: window.expanded,
  scroll: window.scroll,
  pasteFailed: window.pasteFailed,
  pasteFailedUntilStarted: window.pasteFailedUntilStarted,
  keysFailed: window.keysFailed,
  editorFailed: window.editorFailed,
  vim: window.vim,
  theme: window.theme,
  themePreview: window.themePreview,
  mcpPanel: window.mcpPanel,
  notice: window.notice,
  agentsFocus: window.agentsFocus,
  agentCloseArmed: window.agentCloseArmed,
  sessionsNote: window.sessionsNote,
  agentsView: window.agentsView,
  summaryFocus: window.summaryFocus,
  backgroundView: window.backgroundView,
);

/// A session's own part of [state].
SessionState sessionOf(AppState state) => SessionState(
  start: state.start,
  agent: state.agent,
  resumed: state.resumed,
  omittedHistory: state.omittedHistory,
  transcript: state.transcript,
  queue: state.queue,
  held: state.held,
  attended: state.attended,
  requestOverflows: state.requestOverflows,
  pendingMode: state.pendingMode,
  draft: state.draft,
  kept: state.kept,
  cursor: state.cursor,
  bash: state.bash,
  images: state.images,
  imageCount: state.imageCount,
  spent: state.spent,
  since: state.since,
  monitors: state.monitors,
  endedMonitors: state.endedMonitors,
);

/// The window's own part of [state].
WindowState windowOf(AppState state) => WindowState(
  resumeAsked: state.resumeAsked,
  resumePicker: state.resumePicker,
  quitArmed: state.quitArmed,
  closing: state.closing,
  shortcuts: state.shortcuts,
  draftHeld: state.draftHeld,
  steerRefused: state.steerRefused,
  search: state.search,
  notes: state.notes,
  expanded: state.expanded,
  scroll: state.scroll,
  pasteFailed: state.pasteFailed,
  pasteFailedUntilStarted: state.pasteFailedUntilStarted,
  keysFailed: state.keysFailed,
  editorFailed: state.editorFailed,
  vim: state.vim,
  theme: state.theme,
  themePreview: state.themePreview,
  mcpPanel: state.mcpPanel,
  notice: state.notice,
  agentsFocus: state.agentsFocus,
  agentCloseArmed: state.agentCloseArmed,
  sessionsNote: state.sessionsNote,
  agentsView: state.agentsView,
  summaryFocus: state.summaryFocus,
  backgroundView: state.backgroundView,
);

/// A session closing, as its last events leave it: the live session a
/// cleared one was let go from, and what `/cost` names it by.
typedef ClosingSession = ({
  SessionState session,
  int? from,
  String name,
  String? runtime,
  bool main,
  String? team,
  String? lead,
  bool member,
});

/// A closed session's spend, kept for the window's total: what `/cost`
/// names it by, the agent's id for its session, what it spent, and the
/// task agents it started, each as its block was when it closed.
typedef KeptPart = ({
  String name,
  String? runtime,
  String? sessionId,
  Spent? spent,
  bool main,
  List<Subagent> tasks,
  String? team,
  String? lead,
  bool member,
});

/// The sessions still closing in the order the original's `/cost` reads
/// them, `Object.values` of an object keyed by session: a session's own
/// key, never negative, in ascending order, then a retired one's, under
/// its negative key, in the order it began closing. A team closed whole
/// is thus its lead, then its members as they opened.
List<ClosingSession> closingInOrder(Map<int, ClosingSession> closing) => [
  for (final key in [
    for (final key in closing.keys)
      if (key >= 0) key,
  ]..sort())
    closing[key]!,
  for (final MapEntry(:key, :value) in closing.entries)
    if (key < 0) value,
];

/// [closing]'s part, as the window keeps it once its close settles.
KeptPart keptOf(ClosingSession closing) => (
  name: closing.name,
  runtime: closing.runtime,
  sessionId: closing.session.start.sessionId,
  spent: closing.session.spent,
  main: closing.main,
  tasks: _keptTasks(closing.session.transcript),
  team: closing.team,
  lead: closing.lead,
  member: closing.member,
);

/// The task agents [transcript] holds, without their work, which no spend
/// reads: what a closed session's tasks are kept as.
List<Subagent> _keptTasks(Transcript transcript) => [
  for (final entry in transcript.entries)
    if (entry is SubagentEntry && entry.subagent.task != null)
      entry.subagent.copyWith(entries: const []),
];

/// The window with every open session's state, by its key, and the one in
/// front, whose state fills the window.
final class WindowedState {
  const WindowedState({
    required this.window,
    required this.sessions,
    required this.front,
    this.closing = const {},
    this.kept = const [],
  });

  /// A window of one session, [key], as [state] fills it.
  factory WindowedState.of(AppState state, int key) => WindowedState(
    window: windowOf(state),
    sessions: {key: sessionOf(state)},
    front: key,
  );

  final WindowState window;
  final Map<int, SessionState> sessions;
  final int front;

  /// The sessions closing, by key, as their last events leave them, with
  /// the live session a cleared one was let go from: what they spent still
  /// counts once the close settles.
  final Map<int, ClosingSession> closing;

  /// What the sessions closed spent, kept for the window's total.
  final List<KeptPart> kept;

  /// This with [state] as the window's part and the front session's own,
  /// the sessions behind, closing and kept as they were.
  WindowedState withFront(AppState state) => _with(
    window: windowOf(state),
    sessions: {...sessions, front: sessionOf(state)},
  );

  /// The window as the session in front fills it.
  AppState get frontState =>
      appStateOf(window, sessions[front] ?? const SessionState());

  WindowedState _with({
    WindowState? window,
    Map<int, SessionState>? sessions,
    int? front,
    Map<int, ClosingSession>? closing,
    List<KeptPart>? kept,
  }) => WindowedState(
    window: window ?? this.window,
    sessions: sessions ?? this.sessions,
    front: front ?? this.front,
    closing: closing ?? this.closing,
    kept: kept ?? this.kept,
  );
}

/// What changes the windowed state.
sealed class WindowedAction {
  const WindowedAction();
}

/// One of session [key]'s events, in front or not.
final class SessionHeard extends WindowedAction {
  const SessionHeard(this.key, this.event);
  final int key;
  final ConversationEvent event;
}

/// An intent on session [key], in front or not: a result that comes back
/// to the agent that asked.
final class SessionActed extends WindowedAction {
  const SessionActed(this.key, this.action);
  final int key;
  final AppAction action;
}

/// An intent on the session in front, and on the window.
final class FrontActed extends WindowedAction {
  const FrontActed(this.action);
  final AppAction action;
}

/// A long-lived agent opened under [key], as it starts; it stays behind
/// until the person picks it.
final class AgentOpened extends WindowedAction {
  const AgentOpened(this.key, {this.transcript});
  final int key;

  /// What its view opens with: a fork's, the conversation it was forked
  /// from as it stood.
  final Transcript? transcript;
}

/// Session [key] comes to the front, as it was left.
final class SessionShown extends WindowedAction {
  const SessionShown(this.key);
  final int key;
}

/// Session [key] closed, and [front] is the one in front now.
final class SessionClosed extends WindowedAction {
  const SessionClosed(this.key, this.front);
  final int key;
  final int front;
}

/// Session [key] is closing: it is held as it is, its last events still
/// taken in, until its close settles.
final class SpendClosing extends WindowedAction {
  const SpendClosing(
    this.key, {
    this.from,
    this.name = 'agent',
    this.runtime,
    this.main = false,
    this.team,
    this.lead,
    this.member = false,
  });
  final int key;

  /// Main's session a clear or a resume let go, which `/cost` counts as
  /// main's, `before /clear`.
  final bool main;

  /// A team agent's: its team's name, the lead of its run by chord's id,
  /// itself for a lead, and that it is of a run rather than an agent of
  /// main's, so `/cost` keeps it under its team.
  final String? team, lead;
  final bool member;

  /// What the window's `/cost` names it by, and the agent it ran on.
  final String name;
  final String? runtime;

  /// The session it is held from, when it goes on under [from]'s key with
  /// another, as a cleared child does; [key] is then the closing's own.
  final int? from;
}

/// An event a closing session reported after it left the window.
final class ClosingHeard extends WindowedAction {
  const ClosingHeard(this.key, this.event);
  final int key;
  final ConversationEvent event;
}

/// Session [key]'s close settled: what it spent is kept.
final class SpendClosed extends WindowedAction {
  const SpendClosed(this.key);
  final int key;
}

/// [state] after [action].
WindowedState reduceWindowed(WindowedState state, WindowedAction action) =>
    switch (action) {
      // What a session a clear let go still says, what it cost or a task of
      // its ending with what it spent, goes to the retired state that had
      // its turn, never the fresh session.
      SessionHeard(:final key, :final event) when _retiredTurn(event) != null =>
        switch (_retiredHolding(state, key, _retiredTurn(event)!)) {
          null => state,
          final retired => reduceWindowed(state, ClosingHeard(retired, event)),
        },
      SessionHeard(:final key, :final event) => _reduceIn(
        state,
        key,
        (app) => reduceApp(app, event),
      ),
      SessionActed(:final key, action: final acted) => _reduceIn(
        state,
        key,
        (app) => reduceWindow(app, acted),
      ),
      FrontActed(action: final acted) => _reduceIn(
        state,
        state.front,
        (app) => reduceWindow(app, acted),
      ),
      AgentOpened(:final key, :final transcript) => state._with(
        sessions: {
          ...state.sessions,
          key: transcript == null
              ? SessionState.starting
              : SessionState(
                  start: SessionState.starting.start,
                  transcript: transcript,
                ),
        },
      ),
      SessionShown(:final key) =>
        key == state.front || !state.sessions.containsKey(key)
            ? state
            : state._with(front: key, window: _noteGone(state.window)),
      SpendClosing(
        :final key,
        :final from,
        :final name,
        :final runtime,
        :final main,
        :final team,
        :final lead,
        :final member,
      ) =>
        switch (state.sessions[from ?? key]) {
          null => state,
          final session => state._with(
            closing: {
              ...state.closing,
              key: (
                session: session,
                from: from,
                name: name,
                runtime: runtime,
                main: main,
                team: team,
                lead: lead,
                member: member,
              ),
            },
          ),
        },
      // A retired launch's late figures and task endings go to the state
      // that had the turn, even once the live session it was let go from
      // has closed too.
      ClosingHeard(:final key, :final event)
          when _retiredTurn(event) != null &&
              _retiredHolding(state, key, _retiredTurn(event)!) != null =>
        reduceWindowed(
          state,
          ClosingHeard(
            _retiredHolding(state, key, _retiredTurn(event)!)!,
            _ownTurns(event),
          ),
        ),
      ClosingHeard(:final key, :final event) => switch (state.closing[key]) {
        null => state,
        final closing => state._with(
          closing: {
            ...state.closing,
            key: (
              from: closing.from,
              name: closing.name,
              runtime: closing.runtime,
              main: closing.main,
              team: closing.team,
              lead: closing.lead,
              member: closing.member,
              session: sessionOf(
                reduceApp(
                  appStateOf(state.window, closing.session),
                  _ownTurns(event),
                ),
              ),
            ),
          },
        ),
      },
      SpendClosed(:final key) => switch (state.closing[key]) {
        null => state,
        final closing => state._with(
          closing: {...state.closing}..remove(key),
          kept: [...state.kept, keptOf(closing)],
        ),
      },
      SessionClosed(:final key, :final front) => reduceWindowed(
        state._with(
          sessions: {...state.sessions}..remove(key),
          window: windowOf(
            reduceWindow(
              appStateOf(state.window, const SessionState()),
              const AgentCloseDisarmedAction(),
            ),
          ),
        ),
        SessionShown(front),
      ),
    };

/// [window] with no note of the agents: one said of the agent that was in
/// front is stale once another comes.
WindowState _noteGone(WindowState window) => window.sessionsNote == null
    ? window
    : windowOf(
        appStateOf(window, const SessionState())._with(clearSessionsNote: true),
      );

/// The turn of the session let go that [event] is of, when it is one of
/// what such a session still says; null for any other event.
String? _retiredTurn(ConversationEvent event) => switch (event) {
  RetiredUsage(:final figures) => figures.turnId,
  RetiredUpdate(:final turnId) => turnId,
  _ => null,
};

/// [event] as the state of the session it is of takes it: its late figures
/// and updates, a task's ending among them, under its own turn.
ConversationEvent _ownTurns(ConversationEvent event) => switch (event) {
  RetiredUsage(:final figures) => Transcribed(
    UsageAction(figures.turnId, figures),
  ),
  RetiredUpdate(:final turnId, :final update) => Transcribed(
    UpdateAction(turnId, update),
  ),
  _ => event,
};

/// The retired state let go from live session [from] that had turn
/// [turnId], by its key; null when none did.
int? _retiredHolding(WindowedState state, int from, String turnId) {
  for (final MapEntry(:key, :value) in state.closing.entries) {
    if (value.from != from) continue;
    final transcript = value.session.transcript;
    final running = switch (transcript.turn) {
      Working(:final turnId) || AwaitingPermission(:final turnId) => turnId,
      _ => null,
    };
    if (running == turnId ||
        transcript.entries.any((entry) => entry.turnId == turnId)) {
      return key;
    }
  }
  return null;
}

/// [reduce] on session [key], read with the window as the reducers read
/// it; the window takes what it changed only from the session in front, so
/// a session behind never closes a picker or a search the person has open.
WindowedState _reduceIn(
  WindowedState state,
  int key,
  AppState Function(AppState app) reduce,
) {
  final session = state.sessions[key];
  if (session == null) return state;
  final before = appStateOf(state.window, session);
  final after = reduce(before);
  if (identical(after, before)) return state;
  return state._with(
    window: key == state.front ? windowOf(after) : state.window,
    sessions: {...state.sessions, key: sessionOf(after)},
  );
}
