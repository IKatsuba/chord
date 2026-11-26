import 'package:characters/characters.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';
import 'package:cancellation_token/cancellation_token.dart';

import '../../cli.dart';
import '../../editor.dart';
import '../header/resumed.dart';
import '../../session/servers.dart' show noMcpServersFlag;
import '../../session/sessions.dart'
    show
        Resume,
        EarlierSession,
        earlierSessions,
        elsewhereRefusal,
        openSessionLabel;
import '../../settings.dart' show homePath, saveEditorMode, saveTheme;
import '../../session/setting_picked_up.dart';
import '../transcript/tools/settings_row.dart' show settingsChangeOverflows;
import 'sessions.dart';
import '../../shell.dart' as shell;
import '../../session/context.dart' as shell_context;
import '../../session/leaving.dart' show owned;
import '../prompt/bash.dart';
import 'terminal.dart';
import '../../notify.dart';
import '../../images.dart';
import '../prompt/images.dart';
import '../../session/session.dart' show PromptParts;
import '../../session/waits.dart' show AgentWait;
import '../../status.dart' show programStatus;
import '../splash/splash.dart' show splashShown;
import '../splash/splash_widget.dart';
import '../../agents.dart';
import '../prompt/state.dart';
import '../prompt/command_list.dart';
import 'package:clock/clock.dart';

import '../transcript/reports.dart';
import '../../session/start_connection.dart';
import '../../session/choice.dart';
import '../../session/config.dart';
import '../../session/efforts.dart';
import '../../session/models.dart' as settings_models;
import '../../session/modes.dart' as settings_modes;
import '../pickers/mcp.dart' show chordRow;
import '../pickers/pickers.dart';
import '../pickers/state.dart';
import '../prompt/commands.dart';
import '../../session/conversation.dart';
import '../../session/transcript/types.dart' as model;
import '../dialogs/permission.dart';
import '../dialogs/permission_prompt.dart';
import '../dialogs/permission_scroll.dart';
import '../dialogs/plan_box.dart';
import '../dialogs/plan_scroll.dart';
import '../dialogs/form.dart' show fieldsOf;
import '../transcript/agents/subagents.dart'
    show askerRow, stillRunning, taskAsking;
import '../../session/transcript/subagents.dart'
    show runningSubagents, subagentPath;
import '../dialogs/asker.dart' show PickedAsker, askerOf;
import '../dialogs/form_box.dart';
import '../dialogs/questions.dart' show AskState, openAsk;
import '../dialogs/questions_box.dart';
import '../dialogs/link.dart';
import '../../session/elicitations.dart';
import '../prompt/prompt.dart';
import '../plan/plan.dart';
import '../plan/plan_rows.dart';
import '../prompt/history.dart' as history;
import '../prompt/prompt_input.dart';
import '../prompt/search.dart' as search;
import '../prompt/search_view.dart';
import '../prompt/file_list.dart';
import '../prompt/mentions.dart' as mentions;
import '../../files.dart' as files;
import '../prompt/queue.dart';
import '../prompt/queue_view.dart';
import '../header/compact.dart';
import '../transcript/compaction.dart' show inSpinner;
import '../status/facts.dart';
import '../status/status_line.dart';
import '../status/status.dart'
    show
        agentsWaitsNotice,
        betweenNotice,
        draftHeldNote,
        StatusFacts,
        vimMarks,
        WaitsNotice;
import '../status/working.dart';
import '../theme/theme.dart';
import '../start_state.dart';
import '../transcript/scroll.dart';
import '../transcript/tools/paths.dart';
import '../transcript/tools/tool.dart' show Failure;
import '../transcript/transcript.dart';
import '../transcript/agent_colours.dart';
import '../transcript/selection.dart' as selection_sources;
import '../transcript/code_pick.dart' as code_pick;
import '../../acp/rpc.dart' show RpcException;
import '../../session/window_agents.dart'
    as roster_of
    show
        agentOf,
        isLead,
        membersOf,
        messageRecipients,
        namedChild,
        shownKey,
        waitOf;
import '../../session/window_agents.dart' show Child, notifiedName;
import '../../js_trim.dart';
import '../transcript/spend.dart';
import 'rename.dart';
import 'scrolls.dart';
import 'state.dart';
import 'window_fold.dart';
import 'agents_room.dart';
import '../agents/agents.dart'
    show
        AgentRow,
        agentMark,
        agentState,
        agentsHeight,
        agentsHint,
        agentsLines,
        listMove,
        listRows,
        summaryHint;
import '../background/background.dart'
    show
        BackgroundAgent,
        BackgroundGroup,
        BackgroundItem,
        BackgroundKind,
        ItemRunning,
        backgroundItems,
        callPlace,
        callRows,
        itemSubagent,
        stoppingIn;
import '../background/summary_line.dart' show SummaryLine, summaryLineCount;
import '../background/background_view.dart' show BackgroundBox, LogScroller;
import '../background/state.dart' as background;
import '../background/view.dart' as bg;
import '../../session/monitors.dart' show StoppedBy;
import '../../session/auth_status.dart' show noAccount;
import '../../session/agents_host.dart'
    show AgentsHost, ForkRefused, Forked, newCall;
import '../../teams.dart' show Team;
import '../../session/team_command.dart'
    show
        ListedTeam,
        TeamCommand,
        TeamList,
        TeamListing,
        TeamNew,
        TeamRefused,
        TeamRunJob,
        TeamShow,
        TeamStop,
        newTeamPrompt,
        teamCommand;
import '../teams/teams.dart'
    show headlineText, messageHeadline, pickedDraft, teamWords;
import '../transcript/tools/tools.dart'
    as tool_rows
    show GuardianView, firstLine, guardianView, headline;
import '../../server/tools.dart' show Refused, Started;
import '../../session/busy.dart' show Busy, busyOf;
import '../agents/agents_view.dart' show AgentsClock, AgentsList, ChildLine;
import '../prompt/named_top.dart' show PromptAgent;
import 'keys.dart' as keys;
import 'selection.dart' as selection;
import 'closing.dart';
import 'sign_in.dart';
import 'start_failure.dart';
import '../shortcuts/bindings.dart' as keymap_file show KeyContext, actions;
import '../shortcuts/bindings.dart'
    show Keybindings, defaultKeymap, hintKey, keysOf;
import 'context.dart';
import '../shortcuts/shortcuts.dart';
import '../shortcuts/state.dart';

/// The live M1 transcript with its multiline prompt and queued messages.
class TranscriptWindow extends StatefulWidget {
  /// A launched agent's conversation and reducer state.
  TranscriptWindow({
    super.key,
    required this.launch,
    required this.connection,
    this.terminal,
    this.notifications,
    this.splash = false,
    this.readClipboard,
    this.readImage = readImageFile,
    this.copy,
    this.copyOnSelect = true,
    this.runShell = shell.runShell,
    List<MentionRecipient> recipients = const [],
    this.walkFiles = files.listFiles,
    this.matchMentions,
    this.readSessionRecords = readResumeRecords,
    this.listTeams,
    this.openUrl,
    this.scrolls,
  }) : recipients = List.unmodifiable(
         mentions.mentionRecipients(recipients, nameOf: (r) => r.name),
       );

  /// CLI-selected agent and display directory.
  final Launch launch;

  /// The owned connection; the process owner closes it after the window quits.
  final StartConnection connection;

  /// Borrowed terminal; the process owner keeps its lifecycle.
  final Terminal? terminal;

  /// Opens a link the agent asked for in the system's browser, the
  /// terminal's opener when none is given; says what went wrong.
  final Future<String?> Function(String url)? openUrl;

  /// How the terminal is told the agent waits on the person; none tells it
  /// nothing.
  final Notifications? notifications;

  /// Whether the startup splash holds the screen until the first session
  /// is up, as it does on a terminal.
  final bool splash;

  /// ctrl+v's clipboard; the terminal's, by default.
  final ClipboardReader? readClipboard;

  /// Reads the image file a pasted or typed path names.
  final ImageFileReader readImage;

  /// An injected recording/host adapter takes precedence over the terminal.
  final selection.Copy? copy;

  /// Whether a matching nonempty release automatically copies its range.
  final bool copyOnSelect;

  /// Injectable local command runner; never used by tests without an adapter.
  final shell.RunShell runShell;

  /// `@@`'s recipients for fixtures with no session; once main's session
  /// opens, the live roster of the agent in front takes their place.
  final List<MentionRecipient> recipients;

  /// An injected fresh discovery operation for deterministic completion fixtures.
  final WalkFiles walkFiles;

  /// An injected asynchronous matcher; null uses the approved owned finder.
  final MatchMentions? matchMentions;

  /// Fresh cancellable record discovery, injected by all resume window tests.
  final ReadResumeRecords readSessionRecords;

  /// The saved teams and the runs open, as `/team` and the menu's names
  /// read them; null asks the host. Injected by tests that hold a read.
  final Future<TeamListing?> Function(AgentsHost host)? listTeams;

  /// Each session's scroll controllers; the window makes its own when none
  /// is given. Either way the window disposes them as it goes.
  final SessionScrolls? scrolls;

  @override
  State<TranscriptWindow> createState() => _TranscriptWindowState();
}

class _TranscriptWindowState extends State<TranscriptWindow> {
  // Each session's transcript scroll, kept while it is open; the one in
  // front is the list's.
  late final _scrolls = widget.scrolls ?? SessionScrolls();
  late ScrollController _scroll = _scrolls.of(widget.connection.fold.front);

  /// The runtime of the agent in front, which its own reports name: a
  /// picked child's, else main's, as the original's `shownAgent`.
  String get _frontRuntime {
    final connection = widget.connection;
    final roster = connection.agents.agents;
    for (final child in roster.children) {
      if (child.key == connection.fold.front) return child.runtime;
    }
    return _mainRuntime;
  }

  /// Main's runtime, as the original's `frontAgent`: the roster's main,
  /// opened once on the agent the window started on, else that agent.
  String get _mainRuntime =>
      widget.connection.agents.agents.main?.agent ?? widget.launch.name;

  /// What the whole window has spent, for `/cost`: main, its agents, the
  /// closed ones too, and the sessions still closing as they stand.
  List<SpendPart> _windowSpend() {
    final windowed = widget.connection.fold.windowed.value;
    return windowSpend(
      widget.connection.agents.agents,
      {
        for (final MapEntry(:key, :value) in windowed.sessions.entries)
          key: SpendSession(
            sessionId: value.start.sessionId,
            spent: value.spent,
            transcript: value.transcript,
          ),
      },
      [
        for (final kept in [
          ...windowed.kept,
          for (final closing in closingInOrder(windowed.closing))
            keptOf(closing),
        ])
          KeptSpend(
            sessionId: kept.sessionId,
            lead: kept.lead,
            team: kept.team,
            part: SpendPart(
              name: kept.name,
              kind: kept.main
                  ? SpendKind.main
                  : kept.member
                  ? SpendKind.member
                  : SpendKind.agent,
              agent: kept.main ? kept.runtime : null,
              runtime: kept.main ? null : kept.runtime,
              figure: sessionFigure(kept.spent),
              parts: taskParts(kept.tasks),
              ended: true,
            ),
          ),
      ],
    );
  }

  /// The front session's conversation, which the window's intents go to,
  /// taken at the press.
  Conversation get _conversation =>
      widget.connection.agents.conversationOf(widget.connection.fold.front) ??
      widget.connection.conversation;

  /// Puts [next] in front of the list, its listener moved with it.
  void _showScroll(ScrollController next) {
    if (identical(next, _scroll)) return;
    if (!_scroll.isDisposed) _scroll.removeListener(_scrolled);
    _scroll = next..addListener(_scrolled);
    // What the window reads of the scroll is the shown session's, which a
    // controller attached again need not change to tell.
    _scrolled();
    if (mounted) setState(() {});
  }

  final _input = TextAreaController();
  final _selection = SelectionController();
  late selection.SelectionCopies _copies;
  Object _selectionSession = Object();
  final _codePick = code_pick.CodePicker();
  late selection_sources.TranscriptSources _sources =
      selection_sources.TranscriptSources(_selectionSession);
  List<Binding> _pickedBindings = const [];

  /// Whether vim mode takes [event], ahead of the box and after the
  /// window's own actions: in insert mode Esc goes to normal mode; in
  /// normal mode its keys move and edit, Enter sends, Esc does what it
  /// does without vim, and any other character is dropped.
  bool _vimKey(KeyEvent event) {
    final app = widget.connection.app.value;
    final vim = app.vim;
    if (vim == null || _splashing || _exiting || app.closing) return false;
    final live = _keyContext();
    // A picker, a request, a plan's answer, the search line or a picked
    // block has the keys, as the original's listHasKeys.
    if (!live.canEdit || _planShown || app.search != null || live.picking) {
      return false;
    }
    if (vim.mode == VimMode.normal) _standNormal();
    final escape = event.combo == KeyCombo.parse('escape');
    final value = (text: _input.text, cursor: _input.cursor);
    if (vim.mode == VimMode.insert) {
      // An open list or the panel closes on the first Esc.
      if (!escape || live.completing || app.shortcuts.help) return false;
      final left = vimEscape(vim, value);
      _dispatch(VimChangedAction(left.state));
      _input.endUndoGroup();
      if (left.value case final moved?) _input.cursor = moved.cursor;
      return true;
    }
    if (escape) {
      if (vim.pending.isEmpty) return false;
      _dispatch(VimChangedAction(vim.copyWith(pending: const [])));
      return true;
    }
    // The window's actions and its quit keys come first, as the original
    // asks its keymap before vim; Enter is the prompt's send.
    final window = context.owner.focusManager.matchKey(
      event,
      where: (b) =>
          _bound.contains(b) &&
          (b.id != null ||
              b.chord == Chord.parse('ctrl+c') ||
              b.chord == Chord.parse('ctrl+d')),
    );
    if (window.kind == KeyBindingMatchKind.exact ||
        window.kind == KeyBindingMatchKind.prefix) {
      return false;
    }
    // A chord the prompt sends on, begun or about to be, is the prompt's.
    if (context.owner.focusManager.pendingChord.isNotEmpty ||
        keysOf(_keymap, 'chat:submit').any(
          (keys) =>
              keys.first.combo == event.combo ||
              // A shifted mark is the key it names, as the prompt reads it.
              keys.first.combo == _unshifted(event)?.combo,
        )) {
      return false;
    }
    var key = vimKeyOf(event);
    // A key normal mode does not take, or takes only as any text object, is
    // read on the US layout, as the original's keyAnswer: `р` is `h`, and
    // `diц` is `diw`; after `f`, `t` or `r` the character is itself.
    if (key == null || !vimTakes(vim, key) || !vimTakesCharacter(vim)) {
      for (final reading in context.owner.focusManager.readingsOf(event)) {
        // A window key read so is the window's ahead of vim, as for a key
        // typed: ctrl+ч for ctrl+x, or ф where a file binds a.
        final window = context.owner.focusManager.matchKey(
          reading,
          where: (b) =>
              _bound.contains(b) &&
              (b.id != null ||
                  b.chord == Chord.parse('ctrl+c') ||
                  b.chord == Chord.parse('ctrl+d')),
        );
        if (window.kind == KeyBindingMatchKind.exact ||
            window.kind == KeyBindingMatchKind.prefix) {
          return false;
        }
        // A reading carries a letter's case as shift: Ш read as I is `I`.
        final read = vimKeyOf(
          reading.shift && _letter(reading.key)
              ? KeyEvent(
                  reading.key.toUpperCase(),
                  ctrl: reading.ctrl,
                  alt: reading.alt,
                  superKey: reading.superKey,
                  hyper: reading.hyper,
                  meta: reading.meta,
                )
              : reading,
        );
        if (read != null && vimTakes(vim, read)) {
          key = read;
          break;
        }
      }
    }
    if (key == null || !vimTakes(vim, key)) {
      // Normal mode types nothing, and edits only by its own keys.
      return true;
    }
    final step = vimStep(
      vim,
      value,
      key,
      atoms: (text, start, end) =>
          wholePlaceholders(text, start, end, app.images),
    );
    _dispatch(VimChangedAction(step.state));
    if (step.undo) {
      _input.undo();
      _standNormal(force: true);
    }
    if (step.state.mode == VimMode.insert) _input.beginUndoGroup();
    if (step.value case final next?) {
      if (next.text == _input.text) {
        _input.cursor = next.cursor;
      } else {
        _input.replace(next.text, next.cursor);
      }
    }
    switch (step.edge) {
      case TextAreaDirection.up:
        _moveCommand(-1);
      case TextAreaDirection.down:
        _moveCommand(1);
      case null:
    }
    return true;
  }

  /// Whether [key] is one letter, whose case shift says.
  static bool _letter(String key) =>
      key.characters.length == 1 && key.toUpperCase() != key.toLowerCase();

  /// Whether a plan's answer has the keys, as last built.
  bool _planShown = false;

  /// Normal mode stands on a character, never past a line's end, as the
  /// original's cursorOffset draws it: after a draft put in whole, from
  /// history or the editor, or an undo.
  void _standNormal({bool force = false}) {
    if (!force && widget.connection.app.value.vim?.mode != VimMode.normal) {
      return;
    }
    final chars = _input.text.characters.toList();
    final at = _input.cursor;
    if (at > 0 &&
        (at == chars.length || chars[at] == '\n') &&
        chars[at - 1] != '\n') {
      _input.cursor = at - 1;
    }
  }

  /// [action], a result that came back for [target]: to that agent, shown
  /// or not, and to no one once it was cleared or closed.
  void _toAsker(StartConnection connection, Target target, AppAction action) {
    if (!mounted ||
        !identical(widget.connection, connection) ||
        !connection.fold.isLive(target)) {
      return;
    }
    if (target.key == connection.fold.front) {
      _dispatch(action);
    } else {
      connection.fold.dispatch(SessionActed(target.key, action));
    }
  }

  /// `/clear` on a picked child: only it gets a fresh session, cleared as
  /// the person's clear so that main hears it starts afresh, as the
  /// original's `clearFront` does; why not, under the command in its view.
  void _clearPicked(AgentsHost host) {
    final connection = widget.connection;
    final key = connection.fold.front;
    host.clearByPerson(key).then((failed) {
      if (failed == null) return;
      // Taken now: the clear began a launch of its own in that view.
      _toAsker(
        connection,
        connection.fold.targetOf(key),
        NotedAction('clear-${_reportId++}', 'clear', failed, failed: true),
      );
    });
  }

  /// `/rename <title>`: the session in front renamed, its title folded to
  /// one line; one note under the command, in the renamed session's view,
  /// that says how it went.
  void _rename(String args) {
    final title = jsTrim(args.replaceAll(RegExp(r'\s+'), ' '));
    final command = ['rename', if (title.isNotEmpty) title].join(' ');
    final id = 'rename-${_reportId++}';
    final connection = widget.connection;
    final fold = connection.fold;
    final roster = connection.agents.agents;
    final child = roster_of.agentOf(roster, fold.front)?.child;
    final name = child?.name ?? 'main';
    final conversation = _conversation;
    final session = conversation.session;
    final refusal = roster_of.waitOf(roster, fold.front)?.exited == true
        ? RenameRefusal.exited
        : session == null || fold.app.value.start.phase != StartPhase.connected
        ? RenameRefusal.starting
        : session.resumed?.task == true
        ? RenameRefusal.task
        : null;
    if (refusal != null) {
      final note = refusedNote(refusal, name);
      _dispatch(NotedAction(id, command, note.text, failed: note.failed));
      return;
    }
    final agent = child?.runtime ?? _mainRuntime;
    final target = fold.target;
    void note(RenameNote said) => _toAsker(
      connection,
      target,
      NotedAction(id, command, said.text, failed: said.failed),
    );
    if (title.isEmpty) return note(unnamedNote(conversation.title));
    note(renamingNote(title));
    conversation.rename(title).then(
      (renamed) {
        if (renamed != null) {
          note(renamedNote(renamed.title, agent, renamed.agent));
        }
      },
      onError: (Object error) => note(
        refusedByAgentNote(agent, switch (error) {
          RpcException(:final message) => message,
          _ => '$error',
        }),
      ),
    );
  }

  /// `/new [agent] --name <name>`: an idle child of main, picked at once,
  /// its `open_agent` call drawn in main's view as main's own, wherever it
  /// was typed; a refusal is said under the command, where it was typed.
  void _new(String args) {
    final command = ['new', if (args.isNotEmpty) args].join(' ');
    final id = 'new-${_reportId++}';
    final connection = widget.connection;
    final target = connection.fold.target;
    final main = connection.agents.agents.main?.key;
    final mainTarget = main == null ? null : connection.fold.targetOf(main);
    void refused(String said) => _toAsker(
      connection,
      target,
      NotedAction(id, command, said, failed: true),
    );
    final host = connection.window;
    if (host is! AgentsHost) return refused('This session has closed');
    host
        .newTyped(
          args,
          show: (key) {
            if (mounted && identical(widget.connection, connection)) {
              _pickAgent(key);
            }
          },
        )
        .then((answer) {
          switch (answer) {
            case Refused(:final error):
              refused(error);
            case Started(:final agent) when mainTarget != null:
              _toAsker(
                connection,
                mainTarget,
                CallTypedAction(id, command, newCall(agent, answer)),
              );
            case _:
          }
        });
  }

  Future<TeamListing?> _listTeams(AgentsHost host) =>
      widget.listTeams?.call(host) ?? host.listTeams();

  /// Whether a team read begun for main in [target], on [connection],
  /// still belongs to the window: a clear or a resume of main since, or
  /// another session given to the window, makes it another's.
  bool _teamsReadOwned(StartConnection connection, Target? target) =>
      mounted &&
      !_exiting &&
      identical(widget.connection, connection) &&
      !connection.app.value.closing &&
      (target == null || connection.fold.isLive(target));

  /// The saved teams and the runs open, for the menu's names.
  void _readTeamNames() {
    final connection = widget.connection;
    final host = connection.window;
    if (host is! AgentsHost) return;
    final main = connection.agents.agents.main?.key;
    final target = main == null ? null : connection.fold.targetOf(main);
    // Only the latest read is applied: an older one coming back after it
    // would put back names since changed.
    final read = ++_teamNamesRead;
    _listTeams(host).then((listing) {
      if (listing == null ||
          read != _teamNamesRead ||
          !_teamsReadOwned(connection, target)) {
        return;
      }
      setState(() {
        _teamNames = (
          teams: [
            for (final listed in listing.teams)
              (name: listed.found.name, broken: listed.found.problem != null),
          ],
          runs: [for (final run in listing.runs) run.name],
        );
        _refreshMenu();
      });
      _syncCommands();
    });
  }

  /// `/team` and its forms, for main whatever is picked, as teams belong
  /// to the session the person opened; what each does is drawn in main's
  /// transcript under the command as typed.
  void _team(String args) {
    final connection = widget.connection;
    final main = connection.agents.agents.main?.key;
    final host = connection.window;
    if (main == null || host is! AgentsHost) return;
    final command = ['team', if (args.isNotEmpty) args].join(' ');
    final id = 'team-${_reportId++}';
    final target = connection.fold.targetOf(main);
    void show(AppAction action) => _toAsker(connection, target, action);
    void said(String text, {required bool failed}) => show(
      TeamShownAction(id, command, model.TeamSaid(text, failed: failed)),
    );
    final TeamCommand asked = teamCommand(args, teamWords);
    if (asked is! TeamList && connection.fold.front != main && !_teamTalked) {
      _teamTalked = true;
      _dispatch(const SessionsNotedAction('/team talks to main'));
    }
    switch (asked) {
      case TeamRefused(:final problem):
        said(problem, failed: true);
      case TeamList():
        // The picker is for main's session as it was asked: one cleared or
        // resumed meanwhile, or a later `/team`, drops this one.
        final listed = ++_teamsListed;
        _listTeams(host).then((listing) {
          if (listing == null ||
              listed != _teamsListed ||
              !_teamsReadOwned(connection, target)) {
            return;
          }
          show(TeamShownAction(id, command, const model.TeamListed()));
          _openTeams(listing);
        });
      case TeamNew(:final words):
        connection.agents.agents.main?.conversation.send(
          '/$command',
          newTeamPrompt(words),
        );
      case TeamShow(:final name):
        host.showTyped(name, _runningTeam).then((answer) {
          if (answer.shown case final shown?) {
            show(TeamShownAction(id, command, shown));
          } else {
            said(answer.refused!, failed: true);
          }
        });
      case TeamRunJob(:final name, :final job):
        host.runTyped(name, job).then((answer) {
          if (answer.ran case final call?) {
            show(CallTypedAction(id, command, call));
          } else {
            said(answer.refused!, failed: true);
          }
        });
      case TeamStop(:final name):
        host.stopTyped(name, teamWords, said);
    }
  }

  /// A running team as `/team show` catches it: each of the file's agents
  /// with its state and latest headline, there and then.
  model.ShownTeam _runningTeam(
    String file,
    Child<Conversation> lead,
    Team team,
    String job,
    List<Child<Conversation>> members,
  ) {
    final connection = widget.connection;
    final now = DateTime.now().millisecondsSinceEpoch;
    model.TeamAgentShown shown(
      String name,
      Child<Conversation>? child, {
      bool isLead = false,
    }) {
      if (child == null) {
        return model.TeamAgentShown(name: name, lead: isLead, open: false);
      }
      final row = AgentRow(
        key: child.key,
        name: child.name,
        runtime: child.runtime,
        wait: child.wait,
        failed:
            connection.fold.stateOf(child.key)?.start.phase ==
            StartPhase.failed,
      );
      final state = agentState(row, now);
      final mark = agentMark(row);
      final entries =
          connection.fold.stateOf(child.key)?.transcript.entries ??
          const <model.Entry>[];
      final latest = entries.lastWhere(
        (entry) =>
            (entry is model.UserEntry && entry.from != null) ||
            (entry is model.ToolEntry &&
                tool_rows.guardianView(entry.call) ==
                    tool_rows.GuardianView.block),
        orElse: () => const model.HistoryOmittedEntry(),
      );
      return model.TeamAgentShown(
        name: name,
        lead: isLead,
        open: true,
        state: (glyph: state.glyph, words: state.words, tone: state.tone.name),
        mark: mark == null
            ? null
            : (glyph: mark.glyph, words: mark.words, tone: mark.tone.name),
        latest: switch (latest) {
          model.ToolEntry(:final call) => () {
            final line = tool_rows.firstLine(tool_rows.headline(call));
            return headlineText(
              name: line.name,
              arg: line.arg,
              tag: line.tag ?? '',
              sent: line.sent,
            );
          }(),
          model.UserEntry(:final from?) => messageHeadline(from),
          _ => null,
        },
      );
    }

    return model.ShownTeam(
      name: lead.info.team ?? lead.name,
      file: file,
      team: team,
      running: model.TeamRunShown(
        name: lead.name,
        since: lead.info.openedAt,
        at: now,
        job: job,
        agents: [
          shown('lead', lead, isLead: true),
          for (final member in team.members)
            shown(
              member.name,
              members.where((each) => each.name == member.name).firstOrNull,
            ),
        ],
      ),
    );
  }

  void _openTeams(TeamListing listing) {
    setState(() => _teams = listing);
    _syncTeams();
  }

  void _closeTeams() {
    setState(() => _teams = null);
    _syncTeams();
    // As the original's: the picker's `› /team` goes with it.
    final connection = widget.connection;
    final main = connection.agents.agents.main?.key;
    if (main != null) {
      _toAsker(
        connection,
        connection.fold.targetOf(main),
        const TeamsListedGoneAction(),
      );
    }
  }

  void _syncTeams() {
    final app = widget.connection.app.value;
    final shown =
        _teams != null &&
        !_exiting &&
        !app.closing &&
        !app.shortcuts.help &&
        !requestHasKeys(app);
    final overlay = _overlay;
    if (shown && _teamsEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (_) {
          final listing = _teams;
          if (listing == null) return const SizedBox();
          return _furniture(
            CompositedTransformFollower(
              link: _helpLink,
              followerAnchor: Alignment.bottomLeft,
              child: TeamsPicker(
                key: ValueKey(listing),
                listing: listing,
                rows: menuRowLimit(_rows),
                room: _rows,
                columns: _columns,
                onPick: (ListedTeam found) {
                  final draft = pickedDraft(found.found);
                  if (draft == null) return;
                  _closeTeams();
                  _input.text = draft;
                  _input.cursor = endOf(draft);
                },
                onCanceled: _closeTeams,
              ),
            ),
          );
        },
      );
      _teamsEntry = entry;
      overlay.insert(entry);
    } else if (!shown && _teamsEntry != null) {
      final entry = _teamsEntry!;
      _teamsEntry = null;
      entry.remove();
      entry.dispose();
    } else {
      _teamsEntry?.markNeedsBuild();
    }
  }

  /// `/fork [name]`: the agent on screen, main or a fork, forked into a new
  /// agent beside main, picked once it is up, its view the conversation as
  /// it stood. Said under the command as typed, on the agent it was typed
  /// on, whatever is in front by then.
  void _fork(String args) {
    final command = ['fork', if (args.isNotEmpty) args].join(' ');
    final id = 'fork-${_reportId++}';
    final connection = widget.connection;
    final target = connection.fold.target;
    void said(int? from, String text, {required bool failed}) => _toAsker(
      connection,
      from == null ? target : connection.fold.targetOf(from),
      NotedAction(id, command, text, failed: failed),
    );
    final host = connection.window;
    if (host is! AgentsHost) {
      return said(null, 'This session has closed', failed: true);
    }
    host
        .forkTyped(
          args,
          busy: (key) => switch (connection.fold.stateOf(key)) {
            final state? => busyOf(state.transcript, state.queue) != null,
            null => false,
          },
          opened: (key, source) => connection.fold.dispatch(
            AgentOpened(
              key,
              transcript: connection.fold.stateOf(source)?.transcript,
            ),
          ),
          show: (key) {
            if (mounted && identical(widget.connection, connection)) {
              _pickAgent(key);
            }
          },
        )
        .then((answer) {
          switch (answer) {
            case ForkRefused(:final refused, :final from):
              said(from, refused, failed: true);
            case Forked(:final name, :final from):
              said(from, 'Forked into $name', failed: false);
            case null:
          }
        });
  }

  /// The `offeredAgents` now: the launch's, or one the `settings` tool
  /// saved since.
  late List<String>? _offered = widget.launch.offered;

  /// Whether the settings change [wait] asks about is taller than the
  /// transcript's room as last laid out: what both the box's room and its
  /// hint are worked out from.
  bool _changeOverflows(AppState app, model.PermissionWait wait) =>
      switch (_selectionSize) {
        final size? when wait.save != null => settingsChangeOverflows(
          app.transcript.entries,
          wait.save!.asked,
          size.width - 4,
          _scroll.viewRows,
        ),
        _ => false,
      };

  /// A setting the `settings` tool saved, taken up as its command would:
  /// the theme drawn, vim mode, or what `/new` lists.
  void _pickedUp(SettingPickedUp picked) {
    if (!mounted) return;
    switch (picked) {
      case ThemePickedUp(:final theme):
        _dispatch(ThemeChosenAction(theme));
      case EditorModePickedUp(:final vim):
        if ((widget.connection.app.value.vim != null) == vim) return;
        _dispatch(VimToggledAction(vim));
        if (vim) {
          _input.beginUndoGroup();
        } else {
          _input.endUndoGroup();
        }
      case OfferedAgentsPickedUp(:final offered):
        setState(() {
          _offered = offered;
          _newAgentsOf = null;
        });
    }
  }

  /// `/vim`: vim mode on or off, kept in the user's file for the next start.
  void _toggleVim() {
    final on = widget.connection.app.value.vim == null;
    final said = on
        ? 'Vim mode on: Esc for normal mode, i to insert'
        : 'Vim mode off';
    final id = 'vim-${_reportId++}';
    _dispatch(VimToggledAction(on));
    if (on) {
      _input.beginUndoGroup();
    } else {
      _input.endUndoGroup();
    }
    final file = widget.launch.settingsFile;
    if (file == null) {
      _dispatch(NotedAction(id, 'vim', said));
      return;
    }
    final connection = widget.connection;
    final target = connection.fold.target;
    saveEditorMode(file, on ? 'vim' : 'normal').then(
      (_) => _toAsker(connection, target, NotedAction(id, 'vim', said)),
      onError: (Object error) => _toAsker(
        connection,
        target,
        NotedAction(
          id,
          'vim',
          '$said, but it could not be saved to '
              '${widget.launch.shownSettingsFile ?? file}: $error; it '
              'lasts until chord quits',
          failed: true,
        ),
      ),
    );
  }

  /// Enter in `/theme`: the theme highlighted is the one in use, kept in
  /// the user's file for the next start.
  void _keepTheme(String chosen) {
    final before = widget.connection.app.value.theme;
    _dispatch(ThemeChosenAction(chosen));
    if (chosen == before) return;
    final id = 'theme-${_reportId++}';
    final said = 'Theme set to ${themeName(chosen)}';
    final file = widget.launch.settingsFile;
    if (file == null) {
      _dispatch(NotedAction(id, 'theme', said));
      return;
    }
    final connection = widget.connection;
    final target = connection.fold.target;
    saveTheme(file, chosen).then(
      (_) => _toAsker(connection, target, NotedAction(id, 'theme', said)),
      onError: (Object error) => _toAsker(
        connection,
        target,
        NotedAction(
          id,
          'theme',
          'Could not save the theme to '
              '${widget.launch.shownSettingsFile ?? file}: $error; it '
              'lasts until chord quits',
          failed: true,
        ),
      ),
    );
  }

  /// The themes drawn so far, by name and whether colour is on: one
  /// instance each, so a frame that changes none rebuilds nothing.
  final _themes = <(String, bool), ThemeData>{};

  /// The theme the window is drawn in: Auto is the one the terminal's
  /// background gave the app; a named one is its palette.
  ThemeData _themeFor(BuildContext context) {
    final shown = widget.connection.app.value.shownTheme;
    if (shown == 'auto') return Theme.of(context);
    final colour = !Theme.noColorOf(context);
    return _themes[(shown, colour)] ??= themeData(shown, colour: colour);
  }

  /// The palette of the theme drawn: Auto, with no background read here,
  /// is the one [ChordThemeScope] falls back on, by the base theme's
  /// brightness.
  Palette _palette(BuildContext context, AppState app) {
    final shown = app.shownTheme;
    final colour = !Theme.noColorOf(context);
    if (shown != 'auto') return paletteOf(shown, colour);
    return paletteOf(
      Theme.of(context).brightness == Brightness.light ? 'light' : 'dark',
      colour,
    );
  }

  /// `/theme`'s picker, floating over the transcript above the prompt.
  OverlayEntry? _themeEntry;

  /// `/mcp`'s panel, floating where `/theme`'s picker does.
  OverlayEntry? _mcpEntry;

  /// dimcode's one-time notice, floating where the pickers do.
  OverlayEntry? _noticeEntry;

  /// The rows the transcript was last given: the layer the notice and the
  /// /theme and /mcp pickers float in, above the prompt, the list and any
  /// request.
  int? _transcriptRows;

  /// Whether the notice is on screen, with the keys: it waits behind the
  /// window's own pickers, as behind the state's. The shortcuts help does
  /// not hold it back: it goes under the notice, as the original's
  /// completion slot goes under its framed picker.
  bool _noticeShown() {
    final app = widget.connection.app.value;
    return app.noticeShown && !_exiting && _teams == null && _settings == null;
  }

  /// The notice's room: the transcript's rows, or before the first layout,
  /// the window less the five rows under the layer, the prompt box and the
  /// line.
  int get _noticeRoom => _transcriptRows ?? math.max(0, _rows - 5);

  void _syncNotice() {
    final shown = _noticeShown();
    final overlay = _overlay;
    if (shown && _noticeEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (context) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            // With the shortcuts help open, the notice stands on it, as the
            // original's Overlay puts its framed picker above the completion
            // slot: one layer, no gap and no rule between them, the notice
            // keeping its rows and the help taking what is left.
            child: _helpEntry == null
                ? _notice()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _notice(),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.max(
                            0,
                            _noticeRoom - noticeRows(_noticeRoom, _columns),
                          ),
                        ),
                        child: _helpPanel(rule: false),
                      ),
                    ],
                  ),
          ),
        ),
      );
      _noticeEntry = entry;
      overlay.insert(entry);
      _helpEntry?.markNeedsBuild();
    } else if (!shown && _noticeEntry != null) {
      final entry = _noticeEntry!;
      _noticeEntry = null;
      entry.remove();
      entry.dispose();
      _helpEntry?.markNeedsBuild();
    }
  }

  Widget _notice() => NoticeBox(
    room: _noticeRoom,
    onAnswer: _noticeAnswered,
    onClose: () => _dispatch(const NoticeClosedAction()),
  );

  /// 1 dismisses the notice for good on this machine; 2 shows it again
  /// the next time it comes due.
  void _noticeAnswered(bool dismissed) {
    final notice = widget.connection.app.value.notice;
    if (dismissed && notice != null) widget.connection.notices.dismiss(notice);
    _dispatch(const NoticeClosedAction());
  }

  void _syncMcp() {
    final shown = widget.connection.app.value.mcpShown;
    final overlay = _overlay;
    if (shown && _mcpEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (context) {
          final app = widget.connection.app.value;
          final session = _conversation.session;
          return _furniture(
            CompositedTransformFollower(
              link: _helpLink,
              followerAnchor: Alignment.bottomLeft,
              child: McpPanel(
                servers: widget.launch.mcpServers,
                ignored: widget.launch.mcpIgnored,
                heldBack: session?.heldBack ?? const [],
                // The agent shown, a child by its own runtime, as the
                // original passes shownAgent.
                agent: _frontRuntime,
                windowRows: _rows,
                // The transcript's rows, which a tall draft, list or request
                // takes from; before the first layout, five rows are under
                // the layer: the prompt box and the line.
                room: _transcriptRows ?? math.max(0, _rows - 5),
                starting:
                    session == null && app.start.phase == StartPhase.starting,
                chord: widget.connection.server == null
                    ? null
                    : chordRow(
                        session?.chordServerPassed,
                        child: widget.connection.fold.front != mainKey,
                        none:
                            session?.heldBack.any(
                              (each) => each.own && each.takes.isEmpty,
                            ) ==
                            true,
                        from: session?.heldBack
                            .where((each) => each.own)
                            .firstOrNull
                            ?.from,
                      ),
                onClose: () => _dispatch(const McpClosedAction()),
              ),
            ),
          );
        },
      );
      _mcpEntry = entry;
      overlay.insert(entry);
    } else if (!shown && _mcpEntry != null) {
      final entry = _mcpEntry!;
      _mcpEntry = null;
      entry.remove();
      entry.dispose();
    }
  }

  void _syncTheme() {
    final shown = widget.connection.app.value.themePickerShown;
    final overlay = _overlay;
    if (shown && _themeEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (context) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            child: ThemePicker(
              current: widget.connection.app.value.theme,
              background: Theme.backgroundOf(context),
              // As /mcp's and the notice's: the transcript's rows.
              room: _transcriptRows ?? math.max(0, _rows - 5),
              onMove: (theme) => _dispatch(ThemePreviewedAction(theme)),
              onPick: _keepTheme,
              onCanceled: () => _dispatch(const ThemePickerClosedAction()),
            ),
          ),
        ),
      );
      _themeEntry = entry;
      overlay.insert(entry);
    } else if (!shown && _themeEntry != null) {
      final entry = _themeEntry!;
      _themeEntry = null;
      entry.remove();
      entry.dispose();
    }
  }

  /// The box emptied by a sent prompt: vim mode starts again in insert
  /// mode, keeping only its register.
  void _vimEmptied() {
    final vim = widget.connection.app.value.vim;
    if (vim == null) return;
    _dispatch(VimChangedAction(VimState(register: vim.register)));
    _input.endUndoGroup();
    _input.beginUndoGroup();
  }

  /// Set while the editor has the terminal, which is given up only once.
  bool _editing = false;

  /// ctrl+g: the draft in the user's editor; what it saves comes back with
  /// the cursor at its end, and a failure is said in the status line.
  Future<void> _openEditor() async {
    final terminal = widget.terminal;
    if (_editing || terminal == null) return;
    _editing = true;
    _clearSelection();
    _dispatch(const EditorOpenedAction());
    // What the editor gives back is the draft of the session that opened
    // it: a window since given another session or terminal drops it.
    final connection = widget.connection;
    final target = connection.fold.target;
    bool owned() =>
        mounted &&
        !_exiting &&
        identical(widget.connection, connection) &&
        identical(widget.terminal, terminal) &&
        connection.fold.isLive(target);
    final EditorEnd end;
    try {
      end = await editInEditor(_input.text, terminal: terminal);
    } catch (error) {
      if (owned()) {
        _toAsker(
          connection,
          target,
          EditorFailedAction('The editor did not start: $error'),
        );
      }
      return;
    } finally {
      _editing = false;
    }
    if (!owned()) return;
    // Another agent came in front meanwhile: the text is the draft of the
    // one that opened the editor.
    if (target.key != connection.fold.front) {
      _toAsker(connection, target, switch (end) {
        EditorText(:final text) => DraftEditedAction(text, endOf(text)),
        EditorFailed(:final message) => EditorFailedAction(message),
      });
      return;
    }
    switch (end) {
      case EditorFailed(:final message):
        _dispatch(EditorFailedAction(message));
      case EditorText(:final text):
        _play([keys.ShowDraft(text, endOf(text))]);
    }
  }

  /// The keybindings file over chord's keys.
  Keybindings get _keymap => widget.launch.keymap ?? defaultKeymap;

  /// [action]'s key as a hint names it; none when nothing is bound to it.
  String? _key(String action) => hintKey(_keymap, action);

  /// The key that interrupts, as a sentence starts with it.
  String? get _cancelKey => switch (_key('chat:cancel')) {
    final key? => capital(key),
    null => null,
  };

  /// The window's bindings as the keybindings file moved them, as last
  /// built.
  List<Binding> _bound = const [];

  /// [event] with a reported shift taken off a character that is no
  /// letter, which carries its shift in itself, as the original's
  /// keystrokeOf reads it; null for any other key.
  static KeyEvent? _unshifted(KeyEvent e) =>
      e.shift &&
          e.key.runes.length == 1 &&
          e.key.toUpperCase() == e.key.toLowerCase()
      ? KeyEvent(
          e.key,
          ctrl: e.ctrl,
          alt: e.alt,
          superKey: e.superKey,
          hyper: e.hyper,
          meta: e.meta,
        )
      : null;

  /// Whether a window binding with an action takes [event] from the prompt,
  /// as the original takes back what a bound key typed; `?` on a draft is
  /// text.
  bool _windowTakes(KeyEvent event) {
    final plain = _unshifted(event);
    return _bound.any(
      (b) =>
          b.id != null &&
          (b.chord.combos.first == event.combo ||
              b.chord.combos.first == plain?.combo) &&
          (b.id != 'help:toggle' || _input.text.isEmpty),
    );
  }

  StreamSubscription<TerminalState>? _terminalStates;
  int _selectionGeneration = 0;
  Size? _selectionSize;
  SelectionSource? _headerSource, _planSource;
  bool _clearingSelection = false;

  late MentionCompletions _mentions;
  OverlayEntry? _finderEntry;
  int _finderRoom = 0;
  bool _finderHidden = false;
  List<Binding> _mentionBindings = const [];

  bool get _mentionEnabled {
    final app = widget.connection.app.value;
    return !_exiting &&
        !app.closing &&
        !app.bash &&
        app.search == null &&
        !app.shortcuts.help &&
        !_pickerOpen &&
        app.resumePicker == null &&
        !requestHasKeys(app);
  }

  void _refreshMentions() =>
      _mentions.update(_input.text, _input.cursor, enabled: _mentionEnabled);

  /// Whether `@@` offers the live roster: once main's session has opened;
  /// before, a fixture's constructor recipients.
  bool get _rosterLive => widget.connection.agents.agents.main != null;

  /// The roster as `@@` was last given it, for the agent in front in its
  /// launch; null while the constructor's recipients are offered.
  RosterListing? _rosterListed;

  /// Who `@@` reaches from the agent in front now: from main its open
  /// children, from a child `main`; never a task, which is no roster's.
  RosterListing _rosterNow() {
    final connection = widget.connection;
    final recipients = roster_of.messageRecipients(
      connection.agents.agents,
      connection.fold.front,
    );
    return (
      session: connection.fold.target,
      names: mentions.mentionRecipients([
        for (final r in recipients) r.name,
      ], nameOf: (name) => name),
    );
  }

  /// The front, its launch or its roster changed: a match or awaited pick
  /// begun before must not complete now, unless only an equal roster came
  /// again for the same session.
  void _syncRoster() {
    if (!_rosterLive) return;
    final now = _rosterNow();
    if (!rosterResets(_rosterListed, now)) return;
    _rosterListed = now;
    _mentions.resetSession(now.names);
  }

  /// Each offered agent's colour by name; `main` has none and is drawn in
  /// the text's.
  Map<String, Color?> _mentionColours() {
    final listed = _rosterListed;
    if (listed == null) {
      return {for (final r in widget.recipients) r.name: r.color};
    }
    final colours = _agentColours(
      _palette(context, widget.connection.app.value),
    );
    return {for (final name in listed.names) name: ?colours[name]};
  }

  void _ownMentions() {
    final connection = widget.connection;
    _rosterListed = _rosterLive ? _rosterNow() : null;
    late final MentionCompletions current;
    current = MentionCompletions(
      cwd: connection.cwd,
      recipients:
          _rosterListed?.names ?? [for (final r in widget.recipients) r.name],
      walk: widget.walkFiles,
      match: widget.matchMentions,
      validatePending: () {
        bool owned() =>
            mounted &&
            !_exiting &&
            identical(current, _mentions) &&
            identical(connection, widget.connection) &&
            _mentionEnabled &&
            current.ownsInput(_input.text, _input.cursor);
        if (!owned() || !context.ensureCurrentInputGeometry()) {
          return false;
        }
        return owned() && (_finderEntry?.visible ?? false) && _finderRoom > 0;
      },
      onChoice: (choice) {
        if (!mounted ||
            _exiting ||
            !identical(current, _mentions) ||
            !identical(connection, widget.connection) ||
            !_mentionEnabled ||
            !current.ownsInput(_input.text, _input.cursor) ||
            !(_finderEntry?.visible ?? false) ||
            _finderRoom <= 0) {
          return;
        }
        if (choice.submit) {
          _submit(choice.text);
        } else {
          _input.text = choice.text;
          _input.cursor = choice.cursor;
        }
      },
    );
    _mentions = current;
    current.addListener(_mentionChanged);
    _refreshMentions();
  }

  void _mentionChanged() {
    if (!mounted || _exiting) return;
    _finderEntry?.markNeedsBuild();
    setState(() {});
  }

  void _removeFinder() {
    final entry = _finderEntry;
    _finderEntry = null;
    _finderRoom = 0;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  void _retireMentions() {
    _mentions.removeListener(_mentionChanged);
    _mentions.dispose();
    _removeFinder();
  }

  bool get _finderActive =>
      _mentionEnabled &&
      _mentions.finder != null &&
      (_finderEntry?.visible ?? false) &&
      _finderRoom > 0;
  void _finderRoomChanged(OverlayEntry? entry) {
    if (!mounted || !identical(entry, _finderEntry)) return;
    final visible = _mentionEnabled && (entry?.visible ?? false);
    _mentions.setRoom(_finderRoom, visible: visible);
    final hidden = _mentions.finder != null && (!visible || _finderRoom <= 0);
    if (_finderHidden != hidden) setState(() => _finderHidden = hidden);
  }

  void _syncFinder({bool rebuild = true}) {
    final finder = _mentions.finder;
    if (finder != null && _finderEntry == null && _overlay != null) {
      _finderRoom = 0;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        requestFocus: false,
        builder: (_) {
          final current = _mentions.finder;
          if (current == null) return const SizedBox();
          return _furniture(
            CompositedTransformFollower(
              link: _helpLink,
              opaque: !current.pendingSurface,
              followerAnchor: Alignment.bottomLeft,
              child: FileList(
                finder: current,
                windowRows: _rows,
                colors: _mentionColours(),
                isActive: () => _mentionEnabled,
                onRoom: (room) {
                  if (!mounted || !identical(entry, _finderEntry)) return;
                  if (_finderRoom != room) setState(() => _finderRoom = room);
                  _finderRoomChanged(entry);
                },
              ),
            ),
          );
        },
      );
      _finderEntry = entry;
      _overlay!.insert(entry);
    } else if (finder == null && _finderEntry != null) {
      _removeFinder();
      _mentions.setRoom(0, visible: false);
    }
    if (rebuild) _finderEntry?.markNeedsBuild();
  }

  bool _acceptMention(bool enter) {
    _refreshMentions();
    return _finderActive && _mentions.accept(enter: enter);
  }

  List<Binding> _finderBindings() => !_finderActive
      ? []
      : [
          Binding(
            'up',
            'Previous mention',
            () => _mentions.move(-1),
            id: 'autocomplete:previous',
          ),
          Binding(
            'down',
            'Next mention',
            () => _mentions.move(1),
            id: 'autocomplete:next',
          ),
          Binding(
            'tab',
            'Complete file or agent mention',
            () => _acceptMention(false),
            id: 'autocomplete:accept',
          ),
          Binding('enter', 'Add file or agent mention', () {
            if (!_acceptMention(true)) {
              _play(keys.submitSteps(_input.text, _keyContext()));
            }
          }),
          Binding(
            'esc',
            'Dismiss file or agent finder',
            _mentions.dismiss,
            id: 'autocomplete:dismiss',
          ),
        ];

  late ShellCommands _shells;
  void Function()? _forgetShells;

  // Each agent's `!` commands run under a token of its own, taken with
  // the launch they began in: their output goes to that agent, shown or
  // not, and stops once it is cleared or closed.
  final _shellTokens = <int, Object>{};
  final _shellTargets = <Object, Target>{};

  /// The front agent's token for its `!` commands.
  Object get _shellSession {
    final fold = widget.connection.fold;
    final key = fold.front;
    final token = _shellTokens[key];
    if (token != null && fold.isLive(_shellTargets[token]!)) return token;
    if (token != null) _shells.retire(token);
    final fresh = _shellTokens[key] = Object();
    _shellTargets[fresh] = fold.target;
    return fresh;
  }

  /// Agent [key]'s commands let go, as its session is cleared or closed.
  void _retireShells(int key) {
    final token = _shellTokens.remove(key);
    if (token != null) _shells.retire(token);
  }

  void _ownShells() {
    _shellTokens.clear();
    _shellTargets.clear();
    late final ShellCommands current;
    current = ShellCommands(
      runner: (command, options) => widget.runShell(command, options),
      onAction: (session, action) {
        final fold = widget.connection.fold;
        final target = _shellTargets[session];
        if (!mounted ||
            _exiting ||
            !identical(current, _shells) ||
            target == null ||
            !fold.isLive(target) ||
            widget.connection.app.value.closing) {
          return;
        }
        final event = Transcribed(action);
        if (target.key != fold.front) {
          fold.dispatch(SessionHeard(target.key, event));
          // Folded here, not heard through listenKeyed: its scroll is
          // counted here too, or the output is no news when shown again.
          _scrollHeard(target.key, event);
          return;
        }
        final app = widget.connection.app;
        app.value = reduceApp(app.value, event);
        _scrollHeard(target.key, event);
      },
    );
    _shells = current;
    _forgetShells = (widget.connection.owner ?? owned).closeOnForcedExit(
      current.close,
    );
  }

  void _closeShells() {
    final forget = _forgetShells;
    _forgetShells = null;
    // Keep the close owned until group cleanup finishes, including after unmount.
    _shells.close().whenComplete(() => forget?.call()).ignore();
  }

  selection.CopyResult _terminalCopy(String text, CancellationToken token) {
    final terminal = widget.terminal;
    if (token.isCancelled || terminal == null) {
      return const selection.CopyResult.failed('no clipboard to write to');
    }
    terminal.copyToClipboard(text);
    return const selection.CopyResult.sent();
  }

  void _copyChanged() {
    if (!mounted) return;
    if (_copies.selection.kind == selection.SelectionKind.none &&
        _selection.value.phase != SelectionPhase.none &&
        !_clearingSelection) {
      _clearingSelection = true;
      try {
        _selection.clear();
      } finally {
        _clearingSelection = false;
      }
    }
    setState(() {});
  }

  void _watchTerminal() {
    _terminalStates?.cancel();
    _terminalStates = widget.terminal?.states.listen((state) {
      _terminalAway(state != TerminalState.active);
      if (mounted && state != TerminalState.active) _replaceSelectionSession();
    });
  }

  /// Once it has given way, the splash never comes back: not for /clear's
  /// session.
  bool _splashLeft = false;

  bool get _splashing =>
      splashShown(widget.splash, _splashLeft, widget.connection.app.value);

  /// The record the terminal has, none since it was cleared.
  ProgramStatus? _statusSent;

  /// The terminal is another program's, or given back: nothing of chord's
  /// stays on it, nor is sent to it, until it is chord's again.
  bool _away = false;

  // Lent with the terminal (_terminalAway); retired as the window closes,
  // so a record that settles then writes nothing.
  late final SessionVar _sessionVar = SessionVar((value) {
    if (!mounted || _exiting || widget.connection.app.value.closing) {
      _sessionVar.retire();
      return;
    }
    widget.terminal?.setUserVariable(sessionVarName, value);
  });

  /// Tells the terminal of a wait agent [key]'s event started, naming the
  /// agent as the original's sessions do, and reports the status after it.
  void _heardWait(int key, Wait wait) {
    final terminal = widget.terminal;
    final notifications = widget.notifications;
    if (terminal != null && notifications != null) {
      final told = notificationOf(
        wait,
        notifications.channel,
        notifications.env,
        notifiedName(widget.connection.agents.agents, key) ??
            widget.launch.name,
      );
      if (told != null) {
        terminal.notify(told.message, channel: told.channel, title: told.title);
      }
    }
    _reportStatus();
  }

  /// Reports where every agent stands, only when it changed. The record
  /// names the main session, whichever is picked: by its title once it has
  /// one, else as /resume will.
  void _reportStatus() {
    final terminal = widget.terminal;
    if (terminal == null) return;
    final agents = widget.connection.agents.agents;
    final main = agents.main?.conversation;
    // The terminal hears which session `--resume` would open: one opened
    // again once it is up, else one a prompt went to. With no main session,
    // as a quit takes it away while the agents stop, it keeps what it was
    // told. Lent, what is wanted still follows the main session; nothing
    // is written until it is chord's again.
    if (main != null) _sessionVar(main.resumable?.sessionId, main.recorded());
    if (_away) return;
    final status = programStatus(
      agents,
      title: main == null
          ? null
          : main.title ?? openSessionLabel(main.firstPrompt),
    );
    if (status == _statusSent) return;
    terminal.setProgramStatus(status);
    _statusSent = status;
  }

  void _terminalAway(bool away) {
    if (away == _away) return;
    _away = away;
    _sessionVar.away = away;
    // The terminal takes the record off itself as it is lent or given back
    // (StdioTerminal's release): it is told again once it is chord's.
    if (away) {
      _statusSent = null;
    } else {
      _reportStatus();
    }
  }

  void _replaceSelectionSession() {
    _clearDraftHeld();
    _selectionSession = Object();
    _headerSource = null;
    _planSource = null;
    _sources = selection_sources.TranscriptSources(_selectionSession);
    _clearInteractions();
    _copies.replaceSession(_selectionSession);
  }

  void _releaseScroll(bool follow) {
    _scroll.release();
    if (follow) _scroll.toBottom();
  }

  void _clearSelection() {
    if (_clearingSelection ||
        (_copies.selection.kind == selection.SelectionKind.none &&
            _selection.value.phase == SelectionPhase.none)) {
      return;
    }
    _clearingSelection = true;
    try {
      final held = _copies.selection.kind == selection.SelectionKind.dragging;
      final follow = _copies.clear();
      if (held) _releaseScroll(follow);
      _selection.clear();
    } finally {
      _clearingSelection = false;
    }
  }

  void _pickChanged() {
    if (mounted && !_exiting) setState(() {});
  }

  void _endPicking() => _codePick.dispatch(const code_pick.CodePickEnded());
  void _clearInteractions() {
    _clearSelection();
    _endPicking();
  }

  code_pick.CodeCatalog? _codeCatalog() {
    if (!mounted || _exiting || widget.connection.app.value.closing) {
      return null;
    }
    final session = _selectionSession;
    final visible = _selection.visibleCodeBlocks();
    final snapshot = _selection.snapshot();
    if (snapshot == null || session != _selectionSession || _exiting) {
      return null;
    }
    final app = widget.connection.app.value, size = _selectionSize;
    if (size == null || app.closing) return null;
    _sources.retain(app.transcript.entries);
    final width = (size.width - 2).clamp(0, unbounded);
    SelectionSource sourceAt(int index) => _sources.entryAt(
      app.transcript,
      index,
      width: width,
      expanded: app.expanded,
      copyCodeBlocks: true,
      runCodeBlocks: true,
      shellStopKey: _key('chat:cancel'),
      expandKey: _key('app:toggleTranscript'),
      paths: _paths,
      agent: _frontRuntime,
    );
    final listed = code_pick.listedBlocks(app.transcript.entries, sourceAt);
    return code_pick.pickableBlocks(
      listed,
      visible,
      entryOf: _sources.indexOfCodeBlock,
      hidden: code_pick.foldedBlocks(
        app.transcript.entries,
        sourceAt,
        expanded: app.expanded,
        width: width,
      ),
    );
  }

  void _startCodePick() {
    final epoch = _codePick.epoch;
    final catalog = _codeCatalog();
    if (catalog == null || epoch != _codePick.epoch) return;
    final action = code_pick.CodePickStarted(catalog);
    final selected = code_pick.reduceCodePick(_codePick.value, action);
    if (selected != null) _selection.revealCodeBlock(selected);
    if (epoch != _codePick.epoch) return;
    _codePick.dispatch(action);
    if (selected == null) _copies.noCodeBlock();
  }

  void _moveCodePick(int by) {
    final epoch = _codePick.epoch;
    final catalog = _codeCatalog();
    if (catalog == null || epoch != _codePick.epoch) return;
    final action = code_pick.CodePickMoved(by, catalog);
    final selected = code_pick.reduceCodePick(_codePick.value, action);
    if (selected != null) _selection.revealCodeBlock(selected);
    if (epoch == _codePick.epoch) _codePick.dispatch(action);
  }

  void _copyCodePick() {
    final selected = _codePick.value, epoch = _codePick.epoch;
    if (selected == null) return;
    final catalog = _codeCatalog();
    if (catalog == null || epoch != _codePick.epoch) return;
    final target = catalog.target(selected);
    _endPicking();
    if (target != null) _copies.copyBlock(target.block.text);
  }

  void _copyCodeBlock(MarkdownCodeBlock requested) {
    final session = _selectionSession, epoch = _codePick.epoch;
    _clearSelection();
    final catalog = _codeCatalog();
    if (catalog == null ||
        session != _selectionSession ||
        epoch != _codePick.epoch) {
      return;
    }
    final block = catalog.target(requested.id)?.block;
    _endPicking();
    if (block != null && block.revision == requested.revision) {
      _copies.copyBlock(block.text);
    }
  }

  MarkdownCodeBlock? _pickedBlock() {
    final id = _codePick.value, size = _selectionSize;
    if (id == null || size == null) return null;
    final app = widget.connection.app.value;
    _sources.retain(app.transcript.entries);
    final index = _sources.indexOfCodeBlock(id);
    if (index == null) return null;
    return _sources
        .entryAt(
          app.transcript,
          index,
          width: (size.width - 2).clamp(0, unbounded),
          expanded: app.expanded,
          copyCodeBlocks: true,
          runCodeBlocks: true,
          shellStopKey: _key('chat:cancel'),
          expandKey: _key('app:toggleTranscript'),
          paths: _paths,
          agent: _frontRuntime,
        )
        .codeBlocks
        .where((block) => block.id == id)
        .firstOrNull;
  }

  void _runCodePick() {
    final selected = _codePick.value, epoch = _codePick.epoch;
    if (selected == null) return;
    final catalog = _codeCatalog();
    if (catalog == null || epoch != _codePick.epoch) return;
    final block = catalog.target(selected)?.block;
    if (block == null || !code_pick.runnableCode(block)) return;
    _endPicking();
    _putCodeInPrompt(block);
  }

  void _runCodeBlock(MarkdownCodeBlock requested) {
    final session = _selectionSession, epoch = _codePick.epoch;
    final catalog = _codeCatalog();
    if (catalog == null ||
        session != _selectionSession ||
        epoch != _codePick.epoch) {
      return;
    }
    final block = catalog.target(requested.id)?.block;
    if (block == null ||
        block.revision != requested.revision ||
        !code_pick.runnableCode(block)) {
      return;
    }
    _clearInteractions();
    _putCodeInPrompt(block);
  }

  Timer? _steerNoteTimer;
  int? _steerNoteId;
  var _steerNoteGeneration = 0;

  void _cancelSteerNoteTimer() {
    _steerNoteGeneration++;
    _steerNoteTimer?.cancel();
    _steerNoteTimer = null;
    _steerNoteId = null;
  }

  void _steerNoteChanged() {
    final connection = widget.connection;
    final app = connection.app.value;
    final note = app.steerRefused;
    if (app.closing || note == null) {
      _cancelSteerNoteTimer();
      return;
    }
    if (_steerNoteId == note.id) return;
    _cancelSteerNoteTimer();
    _steerNoteId = note.id;
    final generation = _steerNoteGeneration;
    _steerNoteTimer = Timer(const Duration(milliseconds: steerNoteMs), () {
      _steerNoteTimer = null;
      if (mounted &&
          !_exiting &&
          generation == _steerNoteGeneration &&
          identical(widget.connection, connection) &&
          connection.app.value.steerRefused?.id == note.id) {
        _dispatch(SteerNoteGoneAction(note.id));
      }
    });
  }

  Timer? _draftHeldTimer;
  void _clearDraftHeld() {
    _draftHeldTimer?.cancel();
    _draftHeldTimer = null;
    final app = widget.connection.app;
    if (app.value.draftHeld case final id?) {
      app.value = reduceWindow(app.value, DraftHeldGoneAction(id));
    }
  }

  void _putCodeInPrompt(MarkdownCodeBlock block) =>
      _play(keys.promptSteps(runCommand(block.text), _keyContext()));

  void _showDraftHeld() {
    _clearDraftHeld();
    final id = Object();
    _dispatch(DraftHeldAction(id));
    _draftHeldTimer = Timer(const Duration(milliseconds: 3000), () {
      _draftHeldTimer = null;
      if (mounted && !_exiting) _dispatch(DraftHeldGoneAction(id));
    });
  }

  String _pickHint(int width) {
    String? key(keys.CodePickCommand command) {
      final description = keys.codePickKeyDescriptions[command]!.$2;
      final binding = _pickedBindings
          .where((b) => b.description == description && b.enabled)
          .firstOrNull;
      return binding == null ? null : code_pick.pickKeyLabel(binding.chord);
    }

    final picked = _pickedBlock();
    return code_pick.pickHint(
      width: width,
      up: key(keys.CodePickCommand.previous),
      down: key(keys.CodePickCommand.next),
      copy: key(keys.CodePickCommand.copy),
      run: (picked != null && code_pick.runnableCode(picked))
          ? key(keys.CodePickCommand.run)
          : null,
      cancel: key(keys.CodePickCommand.cancel),
    );
  }

  void _selectionChanged(SelectionValue value) {
    _selectionGeneration = value.generation;
    if (_clearingSelection) return;
    // One selection on screen, as the original's: a drag that selects
    // something drops the draft's.
    if (value.phase != SelectionPhase.none &&
        value.hasText &&
        _input.hasSelection) {
      _input.cursor = _input.cursor;
    }
    if (value.phase == SelectionPhase.changing) {
      if (_copies.selection.kind != selection.SelectionKind.dragging) {
        final following = _scroll.isFollowing;
        _copies.press(following);
        _scroll.hold();
      }
    } else if (_copies.selection.kind == selection.SelectionKind.dragging) {
      final follow = _copies.release(value.text);
      _releaseScroll(follow);
    } else if (value.phase == SelectionPhase.none &&
        _copies.selection.kind != selection.SelectionKind.none) {
      _copies.clear();
    }
  }

  void _selectionFinalized(SelectionValue event) {
    if (!mounted ||
        _exiting ||
        !widget.copyOnSelect ||
        widget.connection.app.value.closing ||
        event.generation != _selectionGeneration ||
        event.generation != _selection.value.generation ||
        event.phase != SelectionPhase.finalized ||
        _copies.selection.kind != selection.SelectionKind.shown) {
      return;
    }
    _copySelection(auto: true, expectedGeneration: event.generation);
  }

  void _copySelection({bool auto = false, int? expectedGeneration}) {
    if (_exiting ||
        widget.connection.app.value.closing ||
        _copies.selection.kind != selection.SelectionKind.shown) {
      return;
    }
    final epoch = _copies.epoch, session = _selectionSession;
    final value = _selection.snapshot();
    if (value == null ||
        !value.hasText ||
        value.phase != SelectionPhase.finalized ||
        epoch != _copies.epoch ||
        session != _selectionSession ||
        expectedGeneration != null && value.generation != expectedGeneration) {
      return;
    }
    _endPicking();
    _copies.copySelection(value.text, auto: auto);
  }

  bool _captureKey(
    KeyEvent event,
    List<Binding> bindings,
    Binding selectionCopy,
  ) {
    // A key has the agent looked at, whether or not it draws.
    widget.connection.agents.keyed();
    _reportStatus();
    if (_vimKey(event)) return true;
    if (event.key == 'w' && event.ctrl && !event.alt && !event.shift) {
      final cut = keys.placeholderCutSteps(_keyContext());
      if (cut.isNotEmpty) {
        _play(cut);
        return true;
      }
    }
    // Esc is the splash's before anything of the window's: its binding
    // leaves the splash, ahead of whatever is focused behind it.
    if (_splashing && event.key == 'escape' && !event.ctrl && !event.alt) {
      bindings.singleWhere((b) => b.chord == Chord.parse('esc')).onInvoke();
      return true;
    }
    final manager = context.owner.focusManager;
    if (keys.selectionKeyCapture(
      event,
      manager: manager,
      selectionCopy: selectionCopy,
      ordinaryCtrlC: bindings.singleWhere(
        (b) => b.chord == Chord.parse('ctrl+c'),
      ),
      bindings: bindings,
      context: _keyContext,
      clearSelection: _clearSelection,
      endPicking: _endPicking,
      pickedBindings: _pickedBindings,
      closing: _exiting || widget.connection.app.value.closing,
    )) {
      return true;
    }
    if (!mounted || _exiting || widget.connection.app.value.closing) {
      return false;
    }
    if (_viewHasKeys() || _listHasKeys()) return _listKey(event);
    // A form or link with the keys takes what is typed into it; the
    // window's own bindings still reach whatever it does not bind.
    if (_inputActive) return false;
    // A shifted character that is no letter presses the key a binding names
    // without the shift, as the original's keystrokeOf reads it.
    final plain = _unshifted(event);
    if (plain != null) {
      final match = manager.matchKey(
        plain,
        where: (b) =>
            b.id != null && (b.id != 'help:toggle' || _input.text.isEmpty),
      );
      // The framework dispatches only the stroke it delivers, so the
      // unshifted one is run here; one that would begin a chord is not.
      if (match.kind == KeyBindingMatchKind.exact) {
        manager.cancelPendingChord();
        match.binding!.onInvoke();
        return true;
      }
    }
    // A character the prompt would type is taken back only for a window
    // action its key has on the US layout, as the original's keyAnswer:
    // on an empty draft the key in `?`'s place opens the panel. What the
    // prompt types is otherwise typed as it is.
    // A key bound as typed is its own, and the search line takes what types.
    if (event.char != null &&
        manager.pendingChord.isEmpty &&
        widget.connection.app.value.search == null &&
        manager.matchKey(event).kind == KeyBindingMatchKind.none) {
      for (final reading in manager.readingsOf(event)) {
        final match = manager.matchKey(
          reading,
          where: (b) =>
              b.id != null && (b.id != 'help:toggle' || _input.text.isEmpty),
        );
        if (match.kind == KeyBindingMatchKind.exact) {
          match.binding!.onInvoke();
          return true;
        }
      }
    }
    if (_finderActive &&
        context.owner.focusManager
            .matchKey(
              event,
              where: (binding) =>
                  _mentionBindings.any((b) => identical(b, binding)),
            )
            .dispatch()) {
      return true;
    }
    final live = _keyContext();
    if (live.state.search != null &&
        live.canEdit &&
        !live.picking &&
        !live.state.shortcuts.help &&
        manager.pendingChord.isEmpty) {
      if (event.char != null ||
          event.key == 'backspace' ||
          event.key == 'delete') {
        if (live.searchEnabled) {
          _play(
            keys.searchEditSteps(
              event.char ?? '',
              live,
              ctrl: event.ctrl,
              meta: event.alt || event.meta || event.superKey,
              backspace: event.key == 'backspace',
              delete: event.key == 'delete',
            ),
          );
        }
        return true;
      }
      // Window actions retain their normal matcher/chord ownership.
      if (manager.matchKey(event).kind == KeyBindingMatchKind.none) return true;
    }
    if (live.canEdit &&
        live.state.bash &&
        _input.text.isEmpty &&
        const {
          'backspace',
          'shift+backspace',
        }.contains(event.combo.toString())) {
      // Editor Actions also bind Backspace; choose the mode action through the
      // shared matcher before those bindings, preserving pending-chord policy.
      return manager
          .matchKey(
            event,
            where: (binding) =>
                binding.description == 'Leave empty bash prompt',
          )
          .dispatch();
    }
    return false;
  }

  FocusNode? _permissionFocus;
  PermissionScroll? _permissionScroll;
  String? _requestId;
  bool _answering = false;
  Timer? _quitTimer;
  int _quitGeneration = 0;
  bool _exiting = false;
  int _rows = 24;

  /// The window's columns, as last laid out.
  int _columns = 80;
  String? _startedModel;
  Resume? _resumedOpening;
  ResumedHeader? _resumedFacts;
  final _helpLink = LayerLink();
  final _panelScroll = PermissionScroll();
  OverlayState? _overlay;
  OverlayEntry? _helpEntry;
  OverlayEntry? _settingsEntry;
  SettingsPickerState? _settings;
  CommandMenuState? _menu;
  OverlayEntry? _commandEntry;

  // `/team`'s picker while it is open, over the listing it was opened on.
  TeamListing? _teams;
  OverlayEntry? _teamsEntry;

  // `/team` says once that it talks to main while a child is picked.
  bool _teamTalked = false;

  // The team names the menu offers after `/team show`, `run` or `stop`,
  // read as the draft came to a name; whether the draft was at one.
  TeamNames? _teamNames;
  bool _atTeamName = false;

  // Each read of the team names and each `/team` listing asked, counted,
  // so that only the latest one asked is applied.
  int _teamNamesRead = 0;
  int _teamsListed = 0;

  /// Whether a picker of the window's own is open over the prompt.
  bool get _pickerOpen => _settings != null || _teams != null;
  int _commandRows = 0;
  bool _commandHidden = false;
  int _reportId = 0;

  void _refreshMenu() {
    final atName = teamQuery(_input.text) != null;
    // Read when the draft comes to a team's name: a file saved meanwhile
    // counts at once.
    if (atName && !_atTeamName) _readTeamNames();
    _atTeamName = atName;
    _menu = commandMenu(
      _menu,
      _input.text,
      commandItems(widget.connection.app.value.agent.commands),
      agents: _newAgents(),
      teams: _teamNames,
    );
  }

  // `/new`'s agents, ranked once for the runtimes the host gives: the menu
  // is read on every frame it may show.
  (List<String>, List<CommandItem>)? _newAgentsOf;

  List<CommandItem> _newAgents() {
    final names = widget.connection.window?.runtimes() ?? const <String>[];
    if (_newAgentsOf case (
      final seen,
      final items,
    ) when identical(seen, names)) {
      return items;
    }
    final items = agentItems(
      names,
      widget.connection.listedAgents,
      offered: _offered,
    );
    _newAgentsOf = (names, items);
    return items;
  }

  bool get _commandShown {
    _refreshMenu();
    final app = widget.connection.app.value;
    return !_exiting &&
        !app.closing &&
        !app.bash &&
        app.search == null &&
        !app.shortcuts.help &&
        !_pickerOpen &&
        app.resumePicker == null &&
        !requestHasKeys(app) &&
        _menu != null &&
        !_menu!.dismissed &&
        _menu!.matches.isNotEmpty;
  }

  bool get _commandActive =>
      _commandShown && (_commandEntry?.visible ?? false) && _commandRows > 0;

  void _commandRoomChanged(OverlayEntry? entry) {
    if (!mounted || !identical(entry, _commandEntry)) return;
    final hidden =
        _commandShown && (!(entry?.visible ?? false) || _commandRows <= 0);
    if (_commandHidden != hidden) setState(() => _commandHidden = hidden);
  }

  void _syncCommands({bool rebuild = true}) {
    final shown = _commandShown;
    final overlay = _overlay;
    if (shown && _commandEntry == null && overlay != null) {
      _commandRows = 0;
      _commandHidden = false;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        requestFocus: false,
        builder: (_) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            child: CommandList(
              menu: _menu!,
              windowRows: _rows,
              isClosing: () => _exiting || widget.connection.app.value.closing,
              onRoom: (rows) {
                if (!mounted || !identical(entry, _commandEntry)) return;
                if (_commandRows != rows) {
                  setState(() => _commandRows = rows);
                }
                _commandRoomChanged(entry);
              },
            ),
          ),
        ),
      );
      _commandEntry = entry;
      overlay.insert(entry);
    } else if (!shown && _commandEntry != null) {
      final entry = _commandEntry!;
      _commandEntry = null;
      _commandRows = 0;
      entry.remove();
      entry.dispose();
    }
    if (rebuild) _commandEntry?.markNeedsBuild();
  }

  void _moveCommand(int by) {
    if (_finderActive) {
      _mentions.move(by);
      return;
    }
    if (_commandActive) {
      setState(() => _menu = moveCommandMenu(_menu!, by, _commandRows));
      _commandEntry?.markNeedsBuild();
    } else {
      _play(
        by < 0
            ? keys.olderSteps(_keyContext())
            : keys.newerSteps(_keyContext()),
      );
    }
  }

  /// Whether the agent takes images in a prompt; unknown until it is up.
  bool? _takesImages() {
    final app = widget.connection.app.value;
    if (app.start.phase != StartPhase.connected) return null;
    return _conversation.session?.takesImages();
  }

  /// The numbers images are given, ahead of the reducer while reads are
  /// out, so two pastes in quick succession never share one.
  int _imageIds = 0;

  /// The highest image number given out, here or in the reducer.
  int get _lastImageId =>
      math.max(_imageIds, widget.connection.app.value.imageCount);

  /// Why an image cannot go into the draft now, if it cannot.
  PasteFailedAction? _imageRefusal() => switch (_takesImages()) {
    false => PasteFailedAction('$_frontRuntime does not take images'),
    null => PasteFailedAction(
      '$_frontRuntime has not started yet',
      untilStarted: true,
    ),
    true => null,
  };

  /// ctrl+v: the clipboard's image at the cursor, as `[Image #N]`. A
  /// [quiet] one, an empty paste's, reads the clipboard first and says
  /// nothing when it holds no image.
  Future<void> _pasteImage({bool quiet = false}) async {
    final refused = _imageRefusal();
    if (refused != null && !quiet) return _dispatch(refused);
    final terminal = widget.terminal;
    final read =
        widget.readClipboard ??
        (terminal == null
            ? () async => const ImageReadFailed(
                'The clipboard cannot be read here: no terminal',
              )
            : clipboardReader(terminal));
    final connection = widget.connection;
    final target = connection.fold.target;
    final result = await read();
    if (!mounted ||
        !identical(connection, widget.connection) ||
        !connection.fold.isLive(target)) {
      return;
    }
    // Another agent came in front meanwhile: the image goes to the draft of
    // the one that asked, at its cursor.
    if (target.key != connection.fold.front) {
      if (result case ImageReadDone(:final image)) {
        final asking = connection.fold.stateOf(target.key)!;
        final id = asking.imageCount + 1;
        final next = insertImage(asking.draft, asking.cursor, id);
        connection.fold
          ..dispatch(
            SessionActed(target.key, ImagesAddedAction([pasted(image, id)])),
          )
          ..dispatch(
            SessionActed(target.key, DraftEditedAction(next.text, next.cursor)),
          );
      }
      return;
    }
    switch (result) {
      case ImageReadFailed(:final failed):
        if (!quiet) _dispatch(PasteFailedAction(failed));
      case ImageReadDone(:final image):
        // Read again: the agent may have started, or failed to, meanwhile.
        final refusedNow = _imageRefusal();
        if (refusedNow != null) return _dispatch(refusedNow);
        final id = _imageIds = _lastImageId + 1;
        final next = insertImage(_input.text, _input.cursor, id);
        _dispatch(ImagesAddedAction([pasted(image, id)]));
        _input.text = next.text;
        _input.cursor = next.cursor;
    }
  }

  /// A pasted path to an image file: the image in its place, the cursor
  /// staying after what was pasted.
  Future<void> _takePastedPaths(String draft, int end) async {
    final home = Platform.environment['HOME'];
    final connection = widget.connection;
    final target = connection.fold.target;
    final base = _lastImageId + 1;
    final first = await takeImagePaths(
      draft.substring(0, end),
      base,
      widget.readImage,
      home,
    );
    final second = await takeImagePaths(
      draft.substring(end),
      base + first.images.length,
      widget.readImage,
      home,
    );
    final images = [...first.images, ...second.images];
    // The draft moved on while the files were read; the paths stay text.
    if (!mounted ||
        !identical(connection, widget.connection) ||
        !connection.fold.isLive(target) ||
        target.key != connection.fold.front ||
        images.isEmpty ||
        _input.text != draft) {
      return;
    }
    _imageIds = math.max(_imageIds, base + images.length - 1);
    _dispatch(ImagesAddedAction(images));
    _input.text = first.text + second.text;
    _input.cursor = first.text.length;
  }

  /// Enter on a draft that names image files by path, as typed: each read
  /// and put in as `[Image #N]` before the prompt goes.
  Future<void> _sendWithPaths(String text) async {
    if (_submitting) return;
    _submitting = true;
    try {
      await _readPathsAndSend(text);
    } finally {
      _submitting = false;
    }
  }

  /// Enter is reading a prompt's image paths.
  bool _submitting = false;

  Future<void> _readPathsAndSend(String text) async {
    final home = Platform.environment['HOME'];
    final connection = widget.connection;
    // The numbers are kept before the reads, so a ctrl+v meanwhile takes
    // the one after; a path to no image leaves its number unused.
    final next = _lastImageId + 1;
    _imageIds = next - 1 + imagePathCount(text, home);
    final target = connection.fold.target;
    final taken = await takeImagePaths(text, next, widget.readImage, home);
    // A prompt is sent to the agent it was typed for, or not at all.
    if (!mounted ||
        !identical(connection, widget.connection) ||
        !connection.fold.isLive(target) ||
        target.key != connection.fold.front) {
      return;
    }
    _dispatch(ImagesAddedAction(taken.images));
    final left = _input.text == text ? '' : _input.text;
    _submit(taken.text, keeping: left, reading: true);
  }

  void _submit(String text, {String? keeping, bool reading = false}) {
    if (_exiting || widget.connection.app.value.closing) return;
    final action = submitted(text, _commandActive ? _menu!.selected : null);
    switch (action) {
      // A highlighted command sent while paths are read waits too.
      case SendSubmitted() when _submitting && !reading:
        return;
      case SendSubmitted(:final text):
        final app = widget.connection.app.value;
        final held = List<String>.of(app.held);
        final prompt = shell_context.withContext(
          heldContext(app.transcript, held),
          text,
        );
        // The images whose placeholders are in it go with it.
        final images = imagesIn(text, app.images);
        if (!_conversation.send(
          text,
          prompt,
          mentions.mentionsIn(text),
          PromptParts(images: attachmentsOf(text, app.images)),
        )) {
          return;
        }
        _dispatch(ContextSentAction(held));
        _dispatch(ImagesSentAction(keeping ?? ''));
        setState(() => _history = history.recordedWith(_history, text, images));
        // A draft typed while the paths were read stays in the box.
        if (keeping == null || keeping.isEmpty) {
          _input.clear();
          _vimEmptied();
        }
      case CompleteSubmitted(:final text):
        _input.text = text;
        _input.cursor = endOf(text);
      case LocalSubmitted(:final name, :final args):
        final command = '/$name${args.isEmpty ? '' : ' $args'}';
        setState(() => _history = history.recorded(_history, command));
        _input.clear();
        _vimEmptied();
        if (_runSetting(command)) return;
        switch (name) {
          case 'clear':
            final host = widget.connection.window;
            if (host is AgentsHost && widget.connection.fold.front != mainKey) {
              _clearPicked(host);
            } else {
              // On main, its children close with the session it lets go.
              if (host is AgentsHost) host.closeMainChildren();
              _conversation.clear().ignore();
            }
          case 'resume':
            _openResume().ignore();
          case 'help':
            _dispatch(const ShortcutsChangedAction(HelpOpened()));
          case 'exit':
            _play([const keys.Quit()]);
          case 'cost':
            final app = widget.connection.app.value;
            _dispatch(
              ReportShownAction('cost-${_reportId++}', [
                ...costReport(
                  CostFacts(
                    // The agent in front: a child's own runtime.
                    agent: _frontRuntime,
                    spent: app.spent,
                    running: runningTurn(app.transcript.turn),
                    since: app.since,
                    now: clock.now().millisecondsSinceEpoch,
                    models: settings_models.modelsFrom(
                      app.agent.configOptions,
                      app.agent.models,
                    ),
                    window: (
                      spend: _windowSpend(),
                      // Under the report's `⎿`, six columns in, inside the
                      // transcript's margins: a note never wraps.
                      width: _columns - 8,
                    ),
                  ),
                ),
              ], command: 'cost'),
            );
          case 'context':
            _dispatch(
              ReportShownAction(
                'context-${_reportId++}',
                contextReport(
                  _frontRuntime,
                  widget.connection.app.value.transcript.usage,
                ),
                command: 'context',
              ),
            );
          case 'vim':
            _toggleVim();
          case 'rename':
            _rename(args);
          case 'new':
            _new(args);
          case 'team':
            _team(args);
          case 'fork':
            _fork(args);
          case 'theme':
            _dispatch(const ThemePickerOpenedAction());
          case 'mcp':
            _dispatch(const McpOpenedAction());
          case 'status':
            final app = widget.connection.app.value;
            final front =
                widget.connection.agents.conversationOf(
                  widget.connection.fold.front,
                ) ??
                widget.connection.conversation;
            _dispatch(
              ReportShownAction(
                'status-${_reportId++}',
                statusReport(
                  app.agent,
                  agent: _frontRuntime,
                  cwd: widget.connection.cwd,
                  sessionId: app.start.sessionId,
                  fallbackMode: app.transcript.mode,
                  title: front.title,
                  account: front.session?.account ?? noAccount,
                ),
              ),
            );
        }
    }
  }

  late final _pageEntry = OverlayEntry(requestFocus: false, builder: _page);

  void _syncHelp() {
    final help = widget.connection.app.value.shortcuts.help;
    final overlay = _overlay;
    if (help && _helpEntry == null && overlay != null) {
      final entry = OverlayEntry(
        requestFocus: false,
        builder: (_) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            // Drawn under the notice, in its layer, while it shows.
            child: _noticeEntry == null ? _helpPanel() : const SizedBox(),
          ),
        ),
      );
      _helpEntry = entry;
      overlay.insert(entry);
      _noticeEntry?.markNeedsBuild();
    } else if (!help && _helpEntry != null) {
      final entry = _helpEntry!;
      _helpEntry = null;
      entry.remove();
      entry.dispose();
      _panelScroll.configure(0, 0);
      _noticeEntry?.markNeedsBuild();
    }
  }

  /// The shortcuts help; under the notice, whose frame is the layer's edge,
  /// with no [rule] of its own.
  Widget _helpPanel({bool rule = true}) => ShortcutsPanel(
    scroll: _panelScroll,
    isClosing: () => _exiting || widget.connection.app.value.closing,
    rule: rule,
    onOverflow: (overflows) {
      if (mounted && widget.connection.app.value.shortcuts.help) {
        _dispatch(ShortcutsChangedAction(PanelOverflowed(overflows)));
      }
    },
  );

  OverlayEntry? _resumeEntry;
  CancellationToken? _resumeRead;
  final _hiddenResumeLink = LayerLink();

  bool get _resumeShown {
    final app = widget.connection.app.value;
    return !_exiting &&
        resumePickerShown(app) &&
        !app.shortcuts.help &&
        _settings == null;
  }

  void _cancelResumeRead() {
    final read = _resumeRead;
    _resumeRead = null;
    read?.cancel();
  }

  void _removeResumeEntry() {
    final entry = _resumeEntry;
    _resumeEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  void _sayResume(String text) => _dispatch(
    ReportShownAction('resume-${_reportId++}', [
      (label: '', text: text),
    ], command: 'resume'),
  );

  Future<void> _openResume() async {
    if (!mounted || _exiting || widget.connection.app.value.closing) return;
    final refusal = resumeRefusal(
      widget.connection.app.value.transcript,
      cancelKey: _cancelKey,
    );
    if (refusal != null) {
      _sayResume(refusal);
      return;
    }
    _cancelResumeRead();
    final token = _resumeRead = CancellationToken();
    final asked = Object(), connection = widget.connection;
    final id = 'resume-${_reportId++}';
    // The list is for the agent it was asked of, in that launch.
    final target = connection.fold.target;
    _dispatch(ResumeAskedAction(asked));
    bool owned() =>
        mounted &&
        !_exiting &&
        !token.isCancelled &&
        identical(_resumeRead, token) &&
        identical(widget.connection, connection) &&
        connection.fold.isLive(target) &&
        connection.fold.front == target.key &&
        !connection.app.value.closing &&
        identical(connection.app.value.resumeAsked, asked);
    if (!owned()) return;
    try {
      final records = await widget.readSessionRecords(cancellationToken: token);
      if (!owned()) return;
      final sessions = earlierSessions(
        records,
        agent: _mainRuntime,
        except: connection.app.value.start.sessionId,
      );
      _resumeRead = null;
      _dispatch(
        ResumeListedAction(
          asked,
          id: id,
          sessions: sessions,
          cwd: connection.cwd,
          agent: _mainRuntime,
          now: DateTime.now().millisecondsSinceEpoch,
          cancelKey: _cancelKey,
        ),
      );
    } catch (error) {
      if (!owned()) return;
      _resumeRead = null;
      _dispatch(
        ResumeListedAction(
          asked,
          id: id,
          sessions: const [],
          cwd: connection.cwd,
          agent: _mainRuntime,
          now: DateTime.now().millisecondsSinceEpoch,
          error: 'Could not read the earlier sessions: $error',
          cancelKey: _cancelKey,
        ),
      );
    }
  }

  bool _ownsResume(ResumePickerState picker) =>
      mounted &&
      !_exiting &&
      _resumeShown &&
      identical(widget.connection.app.value.resumePicker, picker) &&
      (_resumeEntry?.visible ?? false);

  bool _resumeGeometry(ResumePickerState picker) =>
      _ownsResume(picker) &&
      context.ensureCurrentInputGeometry() &&
      _ownsResume(picker);

  void _closeResume() => _dispatch(const ResumePickerClosedAction());

  void _toggleResume(ResumePickerState picker) {
    if (!_resumeGeometry(picker)) return;
    _dispatch(ResumeScopeToggledAction(DateTime.now().millisecondsSinceEpoch));
  }

  void _pickResume(ResumePickerState picker, EarlierSession chosen) {
    if (!_resumeGeometry(picker) || !resumeChoices(picker).contains(chosen)) {
      return;
    }
    final connection = widget.connection, owner = _selectionSession;
    _closeResume();
    if (!mounted ||
        _exiting ||
        connection.app.value.closing ||
        !identical(connection, widget.connection) ||
        !identical(owner, _selectionSession)) {
      return;
    }
    // A child open now is picked, not loaded a second time; as in the
    // original, ahead of any reason a resume would be refused.
    if (_openChildren()[chosen.resume.sessionId] case final key?) {
      _pickAgent(key);
      return;
    }
    final refusal = resumeRefusal(
      connection.app.value.transcript,
      cancelKey: _cancelKey,
    );
    if (refusal != null) {
      _sayResume(refusal);
      return;
    }
    if (chosen.resume.cwd != connection.cwd) {
      _sayResume(
        elsewhereRefusal(
          chosen.resume,
          agent: _mainRuntime,
          // Overridden only for the agent the window started on, as on
          // quit.
          agentCommand: _mainRuntime == widget.launch.name
              ? widget.launch.agentCommand
              : null,
          noMcpServers:
              _mainRuntime == widget.launch.name &&
              widget.launch.noMcpServersFrom == noMcpServersFlag,
          shownCwd: homePath(chosen.resume.cwd, Platform.environment['HOME']),
        ),
      );
      return;
    }
    // Main's children go with the session it leaves, before the switch.
    if (connection.window case final AgentsHost host) {
      host.closeChildrenForResume();
    }
    connection.conversation.resume(chosen.resume).ignore();
  }

  /// The children open now, by the id of their session: `/resume` marks
  /// their rows `open now` and picks the child where one is chosen.
  Map<String, int> _openChildren() {
    final connection = widget.connection;
    return {
      for (final child in connection.agents.agents.children)
        ?connection.fold.stateOf(child.key)?.start.sessionId: child.key,
    };
  }

  void _syncResume({bool rebuild = true}) {
    final picker = widget.connection.app.value.resumePicker;
    if (picker == null || widget.connection.app.value.closing || _exiting) {
      _removeResumeEntry();
      return;
    }
    final overlay = _overlay;
    if (_resumeEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (_) {
          final current = widget.connection.app.value.resumePicker;
          if (current == null) return const SizedBox();
          final active = _resumeShown;
          return _furniture(
            CompositedTransformFollower(
              link: active ? _helpLink : _hiddenResumeLink,
              followerAnchor: Alignment.bottomLeft,
              child: ResumePicker(
                key: ValueKey((current.opening, current.everywhere)),
                picker: current,
                agent: _mainRuntime,
                home: Platform.environment['HOME'],
                open: _openChildren().keys.toSet(),
                rows: menuRowLimit(_rows),
                room: _rows,
                active: active,
                onToggleScope: () => _toggleResume(current),
                onSelected: (chosen) => _pickResume(current, chosen),
                onCanceled: () {
                  if (_resumeGeometry(current)) _closeResume();
                },
              ),
            ),
          );
        },
      );
      _resumeEntry = entry;
      overlay.insert(entry);
    }
    if (rebuild) _resumeEntry?.markNeedsBuild();
  }

  void _setSettings(SettingsPickerState? state) {
    setState(() => _settings = state);
    _refreshMentions();
    _settingsEntry?.markNeedsBuild();
    _syncSettings();
  }

  void _settingsAction(SettingsPickerAction action) {
    final state = _settings;
    final app = widget.connection.app.value;
    if (state == null ||
        _exiting ||
        !settingsSessionInitialized(app.start.phase, closing: app.closing)) {
      return;
    }
    _setSettings(
      settingsPickerChanged(
        state,
        action,
        effortsFrom(app.agent.configOptions),
      ),
    );
  }

  void _syncSettings() {
    final app = widget.connection.app.value;
    final shown =
        _settings != null &&
        settingsSessionInitialized(app.start.phase, closing: app.closing) &&
        !app.shortcuts.help &&
        !requestHasKeys(app);
    final overlay = _overlay;
    if (shown && _settingsEntry == null && overlay != null) {
      final entry = OverlayEntry(
        builder: (_) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            child: SettingsPicker(
              state: _settings!,
              agent: widget.connection.app.value.agent,
              agentName: _frontRuntime,
              windowRows: _rows,
              onAction: _settingsAction,
              onSelected: _settingPicked,
              onCanceled: _settingsBack,
            ),
          ),
        ),
      );
      _settingsEntry = entry;
      overlay.insert(entry);
    } else if (!shown && _settingsEntry != null) {
      final entry = _settingsEntry!;
      _settingsEntry = null;
      entry.remove();
      entry.dispose();
    }
  }

  void _settingsBack() {
    final state = _settings;
    _setSettings(
      state?.kind == 'config' && state?.option != null
          ? SettingsPickerState('config', from: state!.option)
          : null,
    );
  }

  void _settingPicked(String id) {
    final state = _settings;
    if (state == null) return;
    final app = widget.connection.app.value;
    if (_exiting ||
        !settingsSessionInitialized(app.start.phase, closing: app.closing)) {
      _setSettings(null);
      return;
    }
    final agent = app.agent;
    final conversation = _conversation;
    if (state.kind == 'config' && state.option == null) {
      _setSettings(SettingsPickerState('config', option: id));
      return;
    }
    _setSettings(null);
    if (state.kind == 'model') {
      final models = settings_models.modelsFrom(
        agent.configOptions,
        agent.models,
      );
      final picked = models?.available.where((m) => m.id == id).firstOrNull;
      final efforts = effortsFrom(agent.configOptions);
      final pending = state.effort;
      final effort =
          pending != null &&
              efforts?.option == pending.option &&
              pending.value != efforts?.current &&
              (efforts?.available.any((e) => e.id == pending.value) ?? false)
          ? pending
          : null;
      final model = picked != null && id != models?.current ? picked : null;
      if (model != null || effort != null) {
        conversation
            .makeChoice(ModelChoice(model: model, effort: effort), 'model')
            .ignore();
      }
    } else if (state.kind == 'effort') {
      final efforts = effortsFrom(agent.configOptions);
      final chosen = efforts?.available.where((e) => e.id == id).firstOrNull;
      if (chosen != null && id != efforts?.current) {
        conversation
            .makeChoice(
              ModelChoice(
                effort: (option: efforts!.option, value: id, name: chosen.name),
              ),
              'effort',
            )
            .ignore();
      }
    } else {
      final option = optionsFromConfigOptions(
        agent.configOptions,
      ).where((o) => o.id == state.option).firstOrNull;
      if (option != null &&
          option.current != id &&
          option.values.any((v) => v.value == id)) {
        conversation.setOption(option.id, id).ignore();
      }
    }
  }

  /// The picker `/model` or `/config` asked for while the agent started,
  /// opened once the session is up; a start that failed never opens it.
  String? _settingsAsked;

  void _openAsked() {
    final asked = _settingsAsked;
    if (asked == null) return;
    final app = widget.connection.app.value;
    if (_exiting || app.closing) {
      _settingsAsked = null;
      return;
    }
    if (!settingsSessionInitialized(app.start.phase)) return;
    _settingsAsked = null;
    _setSettings(SettingsPickerState(asked));
  }

  bool _runSetting(String text) {
    final command = typedCommand(text);
    if (command == null || !settingCommandNames.contains(command.name)) {
      return false;
    }
    final app = widget.connection.app.value;
    if (_exiting || app.closing) return true;
    if (!settingsSessionInitialized(app.start.phase)) {
      // /model and /config are kept and open once the session is up, as
      // the original's flags; /effort's efforts are not there yet, and the
      // rest need a session.
      if (command.name == 'model' || command.name == 'config') {
        _settingsAsked = command.name;
      } else if (command.name == 'effort' &&
          command.args.isEmpty &&
          effortsFrom(app.agent.configOptions) == null) {
        final model = modelName(app.agent) ?? '';
        widget.connection.app.value = reduceApp(
          app,
          SettingNoted(
            'effort-${_reportId++}',
            'effort',
            noEffortNote(_frontRuntime, model),
          ),
        );
      }
      return true;
    }
    final conversation = _conversation;
    if (command.name == 'fast') {
      conversation
          .toggleFast(_frontRuntime, findAgent(_frontRuntime)?.fastOption)
          .ignore();
    } else if (command.name == 'effort' && command.args.isNotEmpty) {
      conversation
          .setEffortById(_frontRuntime, command.args, 'effort ${command.args}')
          .ignore();
    } else if (command.name == 'effort' &&
        effortsFrom(widget.connection.app.value.agent.configOptions) == null) {
      conversation.setEffortById(_frontRuntime, '', 'effort').ignore();
    } else {
      if (command.name == 'config') conversation.readOptions();
      _setSettings(SettingsPickerState(command.name));
    }
    return true;
  }

  Widget _statusLine(AppState app, int width) => KeyHelp.builder(
    builder: (context, bindings, pending) {
      final active = [
        ..._pickedBindings,
        for (final binding in bindings)
          if (!_pickedBindings.any((pick) => pick.chord == binding.chord))
            binding,
      ];
      final theme = Theme.of(context);
      if (!app.quitArmed && pending.isNotEmpty) {
        return LeaderLine(held: pending, bindings: active);
      }
      if (!app.quitArmed && !app.closing && _codePick.value != null) {
        return Text(
          _pickHint(width),
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      }
      if (!app.quitArmed &&
          !app.closing &&
          app.editorFailed == null &&
          app.pasteFailed == null &&
          app.keysFailed == null &&
          app.steerRefused == null &&
          app.draftHeld == null &&
          _copies.note != null &&
          // A copy's note stands alone; a pick's keeps the facts beside it.
          _copies.note!.notice == null) {
        return Text(
          _copies.note!.text,
          style: _copies.note!.failed ? theme.error : theme.text,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      }
      // An armed close or quit stands alone, so the agent it names is
      // never cut for the model beside it.
      final armed =
          _closeArmedLine(app) ?? (app.quitArmed ? ctrlCArmedLine() : null);
      return StatusLine(
        facts: armed != null
            ? StatusFacts(notice: armed)
            : statusFactsOf(
                app.agent,
                app.transcript,
                // What ctrl+v found outranks the other notes, as the
                // original's failures do.
                notice: app.closing
                    ? null
                    : app.editorFailed ??
                          app.pasteFailed ??
                          app.keysFailed ??
                          (app.steerRefused == null
                              ? null
                              : steerNote(app.steerRefused!.refused)) ??
                          // Not alone: the facts stay beside it, as the original's.
                          (app.draftHeld == null ? null : draftHeldNote) ??
                          _copies.note?.notice ??
                          app.sessionsNote ??
                          // The start goes on under the prompt box, last
                          // of the notes, as the original's status line.
                          (app.start.phase == StartPhase.starting
                              ? statusLine(app.start, _frontRuntime)
                              : null),
                failed:
                    !app.closing &&
                    (app.editorFailed != null ||
                        app.pasteFailed != null ||
                        app.keysFailed != null ||
                        app.steerRefused != null ||
                        app.draftHeld != null),
                // While the list has the keys, the line says what they do.
                hint: _listHasKeys()
                    ? _summaryFocused()
                          ? summaryHint(width)
                          : agentsHint(width, _key('agents:close'))
                    : _statusHint(app),
                bash: app.bash,
                // The mark is the box's; a picked block's keys stand alone.
                vim: _codePick.value != null
                    ? null
                    : switch (app.vim?.mode) {
                        final mode? => vimMarks[mode],
                        null => null,
                      },
                cycleKey:
                    (settings_modes
                                .modesFrom(
                                  app.agent.configOptions,
                                  app.agent.modes,
                                )
                                ?.available
                                .length ??
                            0) >
                        1
                    ? _key('chat:cycleMode')
                    : null,
                waits: heldBack(app)
                    ? betweenNotice(
                        askedPermission(app.transcript.turn) == null
                            ? 'input'
                            : 'permission',
                        _key('session:attention'),
                      )
                    : _othersWaiting(),
              ),
      );
    },
  );

  String? _statusHint(AppState app) {
    if ((_finderHidden && _mentions.finder != null) ||
        (_commandHidden && _commandShown)) {
      return 'not enough space';
    }
    if (_copies.selection.kind == selection.SelectionKind.shown) {
      return 'ctrl + c to copy';
    }
    // Subagents a finished turn left at work may be out of sight, so the
    // line says so.
    if (app.transcript.turn is model.Idle) {
      final running = stillRunning(runningSubagents(app.transcript));
      if (running != null) return running;
    }
    final help = _key('help:toggle');
    if (_input.text.isEmpty && help != null) return '$help for shortcuts';
    return null;
  }

  keys.KeyContext _keyContext() => keys.KeyContext(
    state: reduceWindow(
      reduceWindow(
        widget.connection.app.value,
        DraftEditedAction(_input.text, _input.cursor),
      ),
      ScrollChangedAction(_scroll.state),
    ),
    history: _history,
    rows: _rows,
    columns: _selectionSize?.width ?? 0,
    selection: _copies.selection.kind,
    picking: _codePick.value != null,
    searchEnabled: _selectionSize != null && !_selectionSize!.isEmpty,
    splash: _splashing,
    takesImages: _takesImages(),
    home: Platform.environment['HOME'],
    submitting: _submitting,
    highlighted: _commandActive ? _menu!.selected : null,
    completing: _commandShown || (_mentionEnabled && _mentions.finder != null),
    canEdit:
        !_pickerOpen &&
        widget.connection.app.value.resumePicker == null &&
        widget.connection.app.value.themePreview == null &&
        !widget.connection.app.value.mcpShown &&
        !_noticeShown() &&
        !requestHasKeys(widget.connection.app.value) &&
        !_listHasKeys(),
    agents: _listShown(),
    listKeys: _listHasKeys(),
    onSummary: _summaryFocused(),
    viewKeys: _viewHasKeys(),
    inDetail: widget.connection.app.value.backgroundView?.detail != null,
    notePages: _planShown && _planPages,
  );

  /// Whether the background view is on screen with the keys: open, not
  /// hidden by a request asked since, and no picker or panel over it.
  bool _viewHasKeys() {
    final app = widget.connection.app.value;
    return !app.closing &&
        background.backgroundShown(app.backgroundView, app.transcript) &&
        !_pickerOpen &&
        app.resumePicker == null &&
        app.themePreview == null &&
        !app.mcpShown;
  }

  /// Where a detail and a hint taller than their room are read from.
  var _detailTop = 0, _hintTop = 0;
  ({int key, String id})? _detailOf;
  String? _hintOf;

  /// The background frame as last laid out, which the page keys scroll.
  bg.BackgroundFrame? _frame;

  /// The frame's hint: a stop's error, or its keys.
  String _backgroundSaid(AppState app, List<BackgroundItem> items) {
    final view = app.backgroundView;
    final close = _key('select:cancel');
    return bg.backgroundHint(
      view?.hint,
      bg.hintMode(items, view?.detail),
      stop: _key('agents:close'),
      close: close == null ? null : '${capital(close)} to close',
      back: close == null ? null : '${capital(close)} ← to go back',
    );
  }

  /// The background frame over [items] in a window [columns] by [rows].
  bg.BackgroundFrame _backgroundFrame(
    AppState app,
    List<BackgroundItem> items,
    int columns,
    int rows,
  ) {
    final view = app.backgroundView;
    // Another item's detail, or another error, starts from its first line.
    if (view?.detail != _detailOf) {
      _detailOf = view?.detail;
      _detailTop = 0;
    }
    if (view?.hint != _hintOf) {
      _hintOf = view?.hint;
      _hintTop = 0;
    }
    return _frame = bg.backgroundFrame(
      items,
      focus: view?.focus,
      detail: view?.detail,
      at: view == null
          ? null
          : (focus: view.focus, top: view.top, laid: view.laid),
      said: _backgroundSaid(app, items),
      hinted: view?.hint != null,
      columns: columns,
      rows: rows,
      now: AgentsClock.now(),
      detailTop: _detailTop,
      hintTop: _hintTop,
      pageUp: _key('scroll:pageUp'),
      pageDown: _key('scroll:pageDown'),
      work: _detailWork(app, items)?.subagent,
      logLines: _logLines[view?.detail],
      logTop: switch (_logScroll(view?.detail)) {
        final scroll? when !scroll.isFollowing => scroll.offset,
        _ => null,
      },
    );
  }

  /// Each task log's place, by its item, while its detail is open: kept
  /// across the view hidden by a request and a room of no rows.
  final _logScrolls = <({int key, String id}), ScrollController>{};

  /// The open detail's log's place; those of details left go.
  ScrollController? _logScroll(({int key, String id})? detail) {
    for (final ref in [..._logScrolls.keys]) {
      if (ref == detail) continue;
      // Once the frame that let its log go is laid out.
      final gone = _logScrolls.remove(ref)!;
      context.owner.afterLayout(gone.dispose);
    }
    if (detail == null) return null;
    return _logScrolls[detail] ??= ScrollController(follow: Follow.bottom);
  }

  /// Where the window pages a task's log in the view.
  final _logScroller = LogScroller();

  /// Each task log's lines as last laid out, by its item.
  final _logLines = <({int key, String id}), int>{};

  /// The work a task's open detail draws, from its owner's transcript, as
  /// its block there has it, with its owner's turn and agent.
  ({model.Subagent subagent, model.TurnState turn, String agent})? _detailWork(
    AppState app,
    List<BackgroundItem> items,
  ) {
    final ref = app.backgroundView?.detail;
    final item = ref == null
        ? null
        : items
              .where((each) => each.key == ref.key && each.id == ref.id)
              .firstOrNull;
    final owner = item == null
        ? null
        : widget.connection.fold.stateOf(item.key);
    final subagent = item == null || owner == null
        ? null
        : itemSubagent(owner.transcript.entries, item);
    if (subagent == null) return null;
    final roster = widget.connection.agents.agents;
    final child = roster.children
        .where((each) => each.key == item!.key)
        .firstOrNull;
    return (
      subagent: subagent,
      turn: owner!.transcript.turn,
      agent: child?.runtime ?? roster.main?.agent ?? widget.launch.name,
    );
  }

  /// ↑ ↓ in the background view: the `❯` [by] rows on, stopping at the
  /// ends; in a detail, to the next item's detail.
  void _moveBackground(int by) {
    final app = widget.connection.app.value;
    final view = app.backgroundView;
    if (view == null) return;
    final items = _background();
    if (view.detail case final detail?) {
      switch (bg.stepDetail(items, detail, by)) {
        case bg.DetailClosed():
          _dispatch(
            const BackgroundChangedAction(background.BackgroundClosed()),
          );
        case bg.DetailTo(:final to):
          _dispatch(BackgroundChangedAction(background.BackgroundFocused(to)));
        case null:
      }
      return;
    }
    final width = math.max(1, _columns - 4);
    final at = bg.moveView(
      items,
      (focus: view.focus, top: view.top, laid: view.laid),
      by,
      width: width,
      height: bg.backgroundRowLimit(
        _rows,
        bg.hintLines(_backgroundSaid(app, items), width).length,
      ),
      now: AgentsClock.now(),
    );
    if (at?.focus case final focus?) {
      _dispatch(
        BackgroundChangedAction(
          background.BackgroundFocused(focus, top: at!.top, laid: at.laid),
        ),
      );
    }
  }

  /// `x` in the background view: the focused item stops at once, with no
  /// confirmation, its row turning to stopped in place. A monitor stops as
  /// the person's stop, its agent told; a task's turn is cancelled, which
  /// ends it; an agent is asked to stop alone, its row stopping until its
  /// agent says it ended, and a stop that cannot be sent, or an agent that
  /// offers none, says so on the hint line. An ended one, and one already
  /// stopping, is left.
  void _stopBackground() {
    final app = widget.connection.app.value;
    final item = bg.focusedItem(_background(), app.backgroundView?.focus);
    if (item == null ||
        (item.status.group != BackgroundGroup.running &&
            item.status.group != BackgroundGroup.asking)) {
      return;
    }
    // Kept on it by its ref, so the `❯` stays on the row as it changes.
    _dispatch(
      BackgroundChangedAction(
        background.BackgroundFocused((key: item.key, id: item.id)),
      ),
    );
    final conversation = widget.connection.agents.conversationOf(item.key);
    switch (item.kind) {
      case BackgroundKind.monitor:
        conversation?.stopMonitor(item.id, by: StoppedBy.person);
      case BackgroundKind.task:
        conversation?.task(item.id)?.cancel(model.TaskStop.x);
      case BackgroundKind.agent:
        // A second x while its stop is pending does nothing.
        if (item.status case ItemRunning(stopping: true)) return;
        // Its own, so an earlier stop's late answer is never this one's.
        final token = 'stop-${++_stopTokens}';
        final connection = widget.connection;
        // A refusal that comes once the window is gone, or shows another
        // connection, is no longer this window's to say.
        void hinted(String hint) {
          if (!mounted || !identical(connection, widget.connection)) return;
          _dispatch(
            BackgroundChangedAction(background.BackgroundHinted(token, hint)),
          );
        }
        _dispatch(
          BackgroundChangedAction(
            background.BackgroundStopAsked((key: item.key, id: item.id), token),
          ),
        );
        if (!item.stoppable) {
          hinted(bg.noStopHint);
        } else {
          conversation
              ?.stopSubagent(item.id)
              .catchError((Object error) => hinted(bg.stopRefused(error)));
        }
    }
  }

  /// The stops `x` asked for so far, which number each one's token.
  var _stopTokens = 0;

  /// Enter in the background view: on a row, its detail opens; in it, the
  /// view closes, the item's owner is picked, as moving onto its row picks
  /// it, and its transcript scrolls back so that the entry that draws the
  /// call that started it is its top line, the keys going to the box. A
  /// call no longer in the transcript leaves the view as it is.
  void _goToCall() {
    final app = widget.connection.app.value;
    final view = app.backgroundView;
    final item = bg.focusedItem(_background(), view?.focus);
    if (item == null) return;
    if (view?.detail == null) {
      _dispatch(
        BackgroundChangedAction(
          background.BackgroundDetailOpened((key: item.key, id: item.id)),
        ),
      );
      return;
    }
    final owner = widget.connection.fold.stateOf(item.key);
    final place = owner == null
        ? null
        : callPlace(owner.transcript.entries, item);
    if (place == null) return;
    _dispatch(const BackgroundChangedAction(background.BackgroundClosed()));
    _dispatch(const AgentsFocusedAction(false));
    _dispatch(const AgentCloseDisarmedAction());
    _pickAgent(item.key);
    // Once the owner's transcript is laid out: its header first, then a
    // failed start's note, then the entries.
    context.owner.afterLayout(() {
      if (!mounted || widget.connection.fold.front != item.key) return;
      final failed =
          widget.connection.app.value.start.phase == StartPhase.failed;
      final index = 1 + (failed ? 1 : 0) + place.entry;
      try {
        // The call's own box on the top line, as the original's jump puts
        // its target box: a task further down a group, or a call in a
        // block's open work, by the rows into the entry its source lays
        // out at the transcript's width; past the block's gap otherwise.
        final transcript = widget.connection.fold.stateOf(item.key)!.transcript;
        final width = math.max(0, _columns - 2);
        final source = selection_sources.TranscriptSources(Object()).entryAt(
          transcript,
          place.entry,
          width: width,
          expanded: widget.connection.app.value.expanded,
          expandKey: _key('app:toggleTranscript'),
          paths: _paths,
          agent: _frontRuntime,
        );
        _scroll.jumpToAnchor(
          ListAnchor(index, callRows(transcript.entries, place, source, width)),
        );
        // Held there, not following, even where that is the end: the
        // original's jump sets following off, so the rule says what is
        // below and a later event does not scroll the call away.
        _scroll
          ..hold()
          ..release();
      } on StateError {
        // Not attached yet: nothing to scroll.
      }
    });
  }

  /// A page key in the background view: an open detail, or a hint taller
  /// than its room, scrolls a page or to an end.
  void _scrollBackground(ScrollStep step) {
    final frame = _frame;
    if (frame == null) return;
    final detail = widget.connection.app.value.backgroundView?.detail;
    // A task's log pages itself.
    if (detail != null &&
        frame.log != null &&
        !frame.errorTall &&
        _logScroller.scroll(step)) {
      return;
    }
    setState(() {
      if (detail != null && !frame.errorTall) {
        _detailTop = requestStep(
          step,
          frame.detailLines,
          frame.detailRoom,
          _detailTop,
        );
      } else {
        _hintTop = requestStep(step, frame.hintLines, frame.hintRoom, _hintTop);
      }
    });
  }

  /// Whether anything is under the status line for the list's keys: the
  /// agents, with a child, or the background's summary line.
  bool _listShown() =>
      widget.connection.agents.agents.children.isNotEmpty ||
      _background().isNotEmpty;

  /// Whether the summary line has the list's `❯`: put there, or the one
  /// stop with no agents drawn.
  bool _summaryFocused() {
    final app = widget.connection.app.value;
    return _background().isNotEmpty &&
        (app.summaryFocus || widget.connection.agents.agents.children.isEmpty);
  }

  /// The window's background: every monitor and task of `main` and its
  /// children, the item whose detail is open kept, ended or not, until the
  /// person leaves it.
  List<BackgroundItem> _background() {
    final connection = widget.connection;
    final roster = connection.agents.agents;
    final main = roster.main;
    if (main == null) return const [];
    BackgroundAgent? agentIn(int key, [({String name, int colour})? owner]) {
      final state = connection.fold.stateOf(key);
      return state == null
          ? null
          : BackgroundAgent(
              key: key,
              owner: owner,
              since: state.since,
              monitors: state.monitors,
              endedMonitors: state.endedMonitors,
              transcript: state.transcript,
              stopping: stoppingIn(state.transcript.entries),
            );
    }

    return backgroundItems([
      ?agentIn(main.key),
      for (final child in roster.children)
        ?agentIn(child.key, (name: child.name, colour: child.colour)),
    ], keep: connection.app.value.backgroundView?.detail);
  }

  /// Whether the list of the window's agents has the keys: put there, still
  /// drawn, and no picker or panel open over the prompt, as the original's
  /// agentsHaveKeys with no picker shown.
  bool _listHasKeys() {
    final app = widget.connection.app.value;
    return app.agentsFocus &&
        app.backgroundView == null &&
        !app.closing &&
        _listShown() &&
        !_pickerOpen &&
        app.resumePicker == null &&
        app.themePreview == null &&
        !app.mcpShown &&
        !_noticeShown();
  }

  /// The list's keys: one of the window's bindings, as typed or as the key
  /// in its place on another layout; any other key is taken and does
  /// nothing, so a stray one never lands in a child's prompt.
  bool _listKey(KeyEvent event) {
    final manager = context.owner.focusManager;
    for (final reading in [event, ...manager.readingsOf(event)]) {
      final match = manager.matchKey(reading, where: (b) => _bound.contains(b));
      if (match.kind != KeyBindingMatchKind.none) return match.dispatch();
      if (manager.pendingChord.isNotEmpty) break;
    }
    if (manager.pendingChord.isNotEmpty) {
      manager.cancelPendingChord();
    } else if (widget.connection.app.value.agentCloseArmed != null) {
      _dispatch(const AgentCloseDisarmedAction());
    }
    return true;
  }

  /// The list's keys held across frames, so the keys go back where they
  /// were once it lets them go.
  final _listFocus = FocusNode(debugLabel: 'agents list');
  bool _listHadKeys = false;

  /// The list's line budget as last laid out, which ↑ ↓ read it in.
  int _listLimit = 1;

  /// Each choice box's highlight by its request's id, so a box comes back
  /// where it was left after the list had the keys or another agent was in
  /// front.
  final _choiceHighlights = <String, ValueNotifier<String?>>{};
  final _linkHighlights = <String, ValueNotifier<LinkAnswer?>>{};

  /// Ends an armed close once its window passes, as the original's lapse.
  Timer? _closeTimer;

  /// The agent [key] picked: the transcript and the box are its.
  void _pickAgent(int key) {
    final connection = widget.connection;
    connection.agents.pick(key);
    connection.fold.dispatch(SessionShown(key));
  }

  /// ↑ ↓ in the list.
  void _moveAgent(int by) {
    final app = widget.connection.app.value;
    final move = listMove(
      _listed(_agentRows(), _listLimit, math.max(0, _columns - 4)),
      by,
      limit: _listLimit,
      width: math.max(0, _columns - 4),
      now: AgentsClock.now(),
      view: app.agentsView,
      summary: _background().isNotEmpty,
      onSummary: _summaryFocused(),
    );
    if (move.leave) {
      _dispatch(const AgentsFocusedAction(false));
      return;
    }
    if (move.viewed) _dispatch(AgentsScrolledAction(move.view));
    if (move.summary) {
      _dispatch(const AgentCloseDisarmedAction());
      _dispatch(const SummaryFocusedAction(true));
    }
    if (move.pick case final key?) {
      _dispatch(const AgentCloseDisarmedAction());
      _dispatch(const SummaryFocusedAction(false));
      _pickAgent(key);
    }
  }

  /// `agents:close` in the list: the picked child closes, once a second
  /// press confirms cutting a busy one short; `main` never closes.
  void _closePicked() {
    final connection = widget.connection;
    final roster = connection.agents.agents;
    final child = roster.children
        .where((each) => each.key == roster.picked)
        .firstOrNull;
    final app = connection.app.value;
    switch (agentClose(
      child: child != null,
      busy: child == null ? null : _teamBusy(child),
      armed: child != null && app.agentCloseArmed == child.key,
    )) {
      case AgentClose.note:
        _dispatch(const SessionsNotedAction(mainCloseNote));
      case AgentClose.arm:
        _dispatch(AgentCloseArmedAction(child!.key));
        _closeTimer?.cancel();
        final armed = child.key;
        _closeTimer = Timer(const Duration(milliseconds: quitWindowMs), () {
          if (mounted &&
              !_exiting &&
              widget.connection.app.value.agentCloseArmed == armed) {
            _dispatch(const AgentCloseDisarmedAction());
          }
        });
      case AgentClose.close:
        _closeTimer?.cancel();
        _dispatch(const AgentCloseDisarmedAction());
        if (connection.window case final AgentsHost host) {
          host.closeByPerson(child!.key);
        }
    }
  }

  /// ctrl+x a: the agent that waits longest on the person, then the next
  /// on each press; none says so.
  void _attend() {
    final connection = widget.connection;
    if (!connection.agents.attend()) {
      _dispatch(const SessionsNotedAction('Nothing waits on you'));
      return;
    }
    if (roster_of.shownKey(connection.agents.agents) case final key?) {
      connection.fold.dispatch(SessionShown(key));
    }
  }

  /// What the status line says of the agents not shown that want the
  /// person; none while the list has the keys, as its rows show it.
  WaitsNotice? _othersWaiting() {
    final roster = widget.connection.agents.agents;
    final main = roster.main;
    if (main == null || roster.children.isEmpty || _listHasKeys()) {
      return null;
    }
    final keys = {
      'main': main.key,
      for (final child in roster.children) child.name: child.key,
    };
    return agentsWaitsNotice(
      [
        for (final (key, name, wait) in [
          (main.key, 'main', main.wait),
          for (final child in roster.children)
            (child.key, roster_of.namedChild(roster, child.info), child.wait),
        ])
          if (key != roster.picked) (name: name, wait: wait),
      ],
      _key('session:attention'),
      taskOf: (agent) => _taskAsking(keys[agent.name], agent.wait),
    );
  }

  /// The task of session [key]'s whose request [wait] is, by the name its
  /// box gives it; none when it is no task of that session's that asks.
  String? _taskAsking(int? key, AgentWait wait) {
    final entries = key == null
        ? null
        : widget.connection.fold.stateOf(key)?.transcript.entries;
    return entries == null ? null : taskAsking(entries, wait.asking?.on);
  }

  /// What session [key] is busy with; none while it is idle.
  Busy? _busyAt(int key) {
    final state = widget.connection.fold.stateOf(key);
    return state == null ? null : busyOf(state.transcript, state.queue);
  }

  /// What [child] is busy with, or, for a lead, which closes with its
  /// members, what the first of them busy is busy with.
  Busy? _teamBusy(Child<Conversation> child) {
    final members = roster_of.isLead(child.info)
        ? roster_of.membersOf(widget.connection.agents.agents, child.id)
        : const <Child<Conversation>>[];
    for (final each in [child, ...members]) {
      if (_busyAt(each.key) case final busy?) return busy;
    }
    return null;
  }

  /// The line an armed close leaves while its child is still busy, with the
  /// key that closes it; a lead's names its members, as they close with it.
  /// None otherwise.
  String? _closeArmedLine(AppState app) {
    final armed = app.agentCloseArmed;
    final key = _key('agents:close');
    if (armed == null || key == null) return null;
    final roster = widget.connection.agents.agents;
    final child = roster.children
        .where((each) => each.key == armed)
        .firstOrNull;
    if (child == null) return null;
    final members = roster_of.isLead(child.info)
        ? roster_of.membersOf(roster, child.id)
        : const <Child<Conversation>>[];
    if (members.isNotEmpty &&
        [child, ...members].any((each) => _busyAt(each.key) != null)) {
      return teamCloseArmedLine(child.name, members.length, key);
    }
    final busy = _busyAt(child.key);
    return busy == null ? null : agentCloseArmedLine(child.name, busy, key);
  }

  void _cancelQuitTimer() {
    _quitGeneration++;
    _quitTimer?.cancel();
    _quitTimer = null;
  }

  void _dispatch(AppAction action) {
    if (action is TranscriptScrolledAction || action is WheeledAction) {
      _copies.scroll();
    }
    final before = _keyContext().state;
    final after = reduceWindow(before, action);
    widget.connection.app.value = after;
    if (!after.quitArmed) {
      _cancelQuitTimer();
    } else if (!before.quitArmed) {
      _cancelQuitTimer();
      final generation = _quitGeneration;
      final connection = widget.connection;
      _quitTimer = Timer(const Duration(milliseconds: quitWindowMs), () {
        if (mounted &&
            !_exiting &&
            generation == _quitGeneration &&
            identical(connection, widget.connection)) {
          _dispatch(const QuitDisarmedAction());
        }
      });
    }
    if (action is ReportShownAction ||
        action is ResumeListedAction &&
            !identical(before.transcript.entries, after.transcript.entries)) {
      _scroll.markNews();
    }
    _refreshMentions();
    _syncSearch();
    _syncHelp();
    _syncResume();
    _syncCommands();
    if (action is TranscriptScrolledAction || action is WheeledAction) {
      if (after.scroll.following) {
        _scroll.toBottom();
      } else {
        _scroll.jumpTo(after.scroll.offset);
      }
    }
  }

  void _wheeled(MouseEvent event) {
    if (!mounted || _exiting || widget.connection.app.value.closing) return;
    final rows = event.scrollDelta.y;
    if (rows < 0) {
      _dispatch(WheeledAction.up(-rows));
    } else if (rows > 0) {
      _dispatch(WheeledAction.down(rows));
    }
  }

  void _draftChanged() {
    if (!mounted || _loadingFront) return;
    _play(
      keys.changeSteps(
        _input.text,
        _input.cursor,
        keys.KeyContext(
          state: widget.connection.app.value,
          history: _history,
          rows: _rows,
          takesImages: _takesImages(),
          home: Platform.environment['HOME'],
        ),
      ),
    );
    _refreshMentions();
  }

  void _scrolled() {
    if (!mounted) return;
    final app = widget.connection.app;
    app.value = reduceWindow(app.value, ScrollChangedAction(_scroll.state));
  }

  void _play(List<keys.Step> steps) {
    for (final step in steps) {
      if (_exiting) return;
      switch (step) {
        case keys.CopySelection():
          _endPicking();
          _copySelection();
        case keys.StartCodePick():
          _startCodePick();
        case keys.MoveCodePick(:final by):
          _moveCodePick(by);
        case keys.CopyCodePick():
          _copyCodePick();
        case keys.ShowDraftHeld():
          _showDraftHeld();
        case keys.RunCodePick():
          _runCodePick();
        case keys.EndCodePick():
          _endPicking();
        case keys.Dispatch(:final action):
          if (action is TranscriptScrolledAction || action is WheeledAction) {
            _copies.scroll();
          }
          if (action is ToggleExpandedAction) _clearInteractions();
          _dispatch(action);
        case keys.ShowDraft(:final text, :final cursor):
          _input.text = text;
          _input.cursor = cursor;
          _standNormal();
        case keys.HistoryStep(:final history):
          setState(() => _history = history);
        case keys.Send(:final text):
          _submit(text);
        case keys.Steer():
          if (_conversation.steerQueued() == 'unsteerable') {
            _dispatch(const SteerRefusedAction(false));
          }
        case keys.CloseCompletions():
          _refreshMenu();
          if (_menu != null) _menu = dismissCommandMenu(_menu!);
          _mentions.dismiss();
          _syncCommands();
          _syncFinder();
        case keys.CompleteCommand():
          if (_commandActive && _menu!.selected != null) {
            _input.text = completion(_menu!.selected!);
            _input.cursor = endOf(_input.text);
          }
        case keys.SetMode(:final id):
          _conversation.setMode(id).ignore();
        case keys.RunShellCommand(:final command):
          _shells.run(_shellSession, command, cwd: widget.connection.cwd);
        case keys.StopShellCommand():
          _shells.stop(_shellSession);
        case keys.Interrupt():
          if (_finderActive) {
            _mentions.dismiss();
          } else if (_commandActive) {
            setState(() => _menu = dismissCommandMenu(_menu!));
            _syncCommands();
          } else {
            _conversation.interrupt();
          }
        case keys.RejectPermission(:final id):
          _conversation.reject(id);
        case keys.ChoosePermission(:final id, :final optionId):
          _conversation.choose(id, optionId);
        case keys.ScrollRequest(:final step):
          // The plan box stands only where no permission does.
          if (_planShown) {
            _planScroll?.step(step);
          } else {
            _permissionScroll?.step(step);
          }
        case keys.ScrollPanel(:final step):
          _panelScroll.step(step);
        case keys.OpenEditor():
          _openEditor().ignore();
        case keys.PasteImage(:final quiet):
          _pasteImage(quiet: quiet).ignore();
        case keys.TakePastedPaths(:final draft, :final end):
          _takePastedPaths(draft, end).ignore();
        case keys.SendWithPaths(:final text):
          _sendWithPaths(text).ignore();
        case keys.MoveAgent(:final by):
          _moveAgent(by);
        case keys.MoveBackground(:final by):
          _moveBackground(by);
        case keys.StopBackground():
          _stopBackground();
        case keys.GoToCall():
          _goToCall();
        case keys.ScrollBackground(:final step):
          _scrollBackground(step);
        case keys.CloseAgent():
          _closePicked();
        case keys.AttendSession():
          _attend();
        case keys.LeaveSplash():
          setState(() => _splashLeft = true);
        case keys.Quit():
          _cancelResumeRead();
          _removeResumeEntry();
          _retireMentions();
          _closeShells();
          _clearInteractions();
          _copies.dispose();
          _exiting = true;
          _sessionVar.retire();
          _cancelQuitTimer();
          exitApp(context);
      }
    }
  }

  void _syncPermission(model.PermissionWait? wait, bool active) {
    if (_requestId != wait?.id) {
      final oldFocus = _permissionFocus;
      final oldScroll = _permissionScroll;
      _requestId = wait?.id;

      _permissionFocus = wait == null
          ? null
          : FocusNode(debugLabel: 'permission');
      _permissionScroll = wait == null ? null : PermissionScroll();
      context.owner.afterLayout(() {
        oldFocus?.dispose();
        oldScroll?.dispose();
      });
    }
    if (_answering != active) {
      _answering = active;
      context.owner.afterLayout(() {
        if (!mounted) return;
        if (active) _permissionFocus?.requestFocus();
      });
    }
  }

  /// The form or link on screen, its keys and the form as it was left.
  (int, String)? _inputId;
  FocusNode? _inputFocus;
  FormController? _form;
  var _inputActive = false;

  /// Each pending form as the person left it, by its agent's session and
  /// its request's id: one a permission or plan covers for a while, or
  /// whose agent goes behind another, comes back as it was, as the original
  /// keeps its `filling` by id with the agent that asked.
  final _forms = <(int, String), FormController>{};

  /// Each pending question box as the person left it, by session and
  /// request id, as the original keeps its `answering`.
  final _asks = <(int, String), AskState>{};

  /// The requests still pending in any agent's session, the front's as it
  /// stands now.
  Set<(int, String)> _pendingAsks(
    int front,
    List<model.ElicitationWait> asking,
  ) => {
    for (final MapEntry(:key, :value)
        in widget.connection.fold.windowed.value.sessions.entries)
      if (key != front)
        for (final wait in value.transcript.asking) (key, wait.id),
    for (final wait in asking) (front, wait.id),
  };

  void _syncInput(
    model.ElicitationWait? input,
    bool active,
    List<model.ElicitationWait> asking,
  ) {
    final front = widget.connection.fold.front;
    final pending = _pendingAsks(front, asking);
    final settled = [
      for (final id in _forms.keys)
        if (!pending.contains(id)) id,
    ];
    _asks.removeWhere((id, _) => !pending.contains(id));
    if (settled.isNotEmpty) {
      final gone = [for (final id in settled) _forms.remove(id)!];
      context.owner.afterLayout(() {
        for (final form in gone) {
          form.dispose();
        }
      });
    }
    final inputId = input == null ? null : (front, input.id);
    if (_inputId != inputId) {
      _inputId = inputId;
      final oldFocus = _inputFocus;
      _inputFocus = input == null ? null : FocusNode(debugLabel: 'input');
      _form?.removeListener(_inputShaped);
      _form = input is model.FormWait && input.questions == null
          ? _forms[(front, input.id)] ??= FormController(
              fields: fieldsOf(input.schema),
            )
          : null;
      // Its fields change its rows, which the room counts.
      _form?.addListener(_inputShaped);
      _inputActive = false;
      context.owner.afterLayout(() => oldFocus?.dispose());
    }
    if (_inputActive != active) {
      _inputActive = active;
      context.owner.afterLayout(() {
        if (mounted && active) _inputFocus?.requestFocus();
      });
    }
  }

  void _answerLink(model.LinkWait wait, LinkAnswer answer) {
    if (answer == LinkAnswer.open) {
      (widget.openUrl ?? widget.terminal?.openUrl)?.call(wait.url).ignore();
    }
    _conversation.answer(wait.id, switch (answer) {
      LinkAnswer.open => const AcceptReply(),
      LinkAnswer.decline => const DeclineReply(),
      LinkAnswer.cancel => const CancelReply(),
    });
  }

  /// The list takes the keys as it gets them, and gives a plan box its
  /// keys back as it lets them go: the prompt, a permission, a form or a
  /// link take theirs back as they are enabled again.
  void _syncListKeys(bool listKeys, {required bool planShown}) {
    if (_listHadKeys == listKeys) return;
    _listHadKeys = listKeys;
    context.owner.afterLayout(() {
      if (!mounted || _listHadKeys != listKeys) return;
      if (listKeys) {
        _listFocus.requestFocus();
      } else if (planShown) {
        _planFocus?.requestFocus();
      }
    });
  }

  final _viewFocus = FocusNode(debugLabel: 'background view');

  /// The view's hold on the agents' clock: its times count a second at a
  /// time while it is drawn, and stand still while it is hidden or closed.
  void Function()? _viewClock;

  void _syncViewClock(bool shown) {
    if (shown && _viewClock == null) {
      _viewClock = AgentsClock.subscribe((_) {
        if (mounted) setState(() {});
      });
    } else if (!shown && _viewClock != null) {
      _viewClock!();
      _viewClock = null;
    }
  }

  bool _viewHadKeys = false;

  /// The view takes the keys as it gets them; what had them takes them
  /// back as it is enabled again.
  void _syncViewKeys(bool viewKeys) {
    if (_viewHadKeys == viewKeys) return;
    _viewHadKeys = viewKeys;
    context.owner.afterLayout(() {
      if (mounted && _viewHadKeys == viewKeys && viewKeys) {
        _viewFocus.requestFocus();
      }
    });
  }

  /// The background as last drawn, which a row leaving is read against.
  List<BackgroundItem> _shownBefore = const [];

  /// A row that leaves the view as its item ends hands the `❯` to the row
  /// that took its place, and the last to leave closes the view, as esc
  /// does.
  void _followBackground(AppState app, List<BackgroundItem> items) {
    final before = _shownBefore;
    _shownBefore = items;
    final view = app.backgroundView;
    if (view == null) return;
    final action = items.isEmpty
        ? const background.BackgroundClosed()
        : switch (bg.focusAfter(before, items, view.focus)) {
            final focus? => background.BackgroundFocused(focus),
            null => null,
          };
    // A refusal that said the focused agent offers no stop is dropped once
    // it offers one.
    final offered = bg.stopNowOffered(items, view.focus, view.hint);
    if (action == null && offered == null) return;
    context.owner.afterLayout(() {
      if (!mounted) return;
      if (action != null) _dispatch(BackgroundChangedAction(action));
      if (offered != null) {
        _dispatch(
          BackgroundChangedAction(background.BackgroundStopOffered(offered)),
        );
      }
    });
  }

  /// The plan box's keys, for the plan on screen.
  FocusNode? _planFocus;
  String? _planId;

  /// Where the plan's Note is paged from, and whether the page keys are
  /// its, for the plan on screen.
  PlanNoteScroll? _planScroll;
  bool _planPages = false;

  void _syncPlan(model.PlanAsk? plan) {
    final id = plan?.wait.id;
    if (_planId == id) return;
    _planId = id;
    final old = _planFocus;
    final oldScroll = _planScroll;
    _planFocus = plan == null ? null : FocusNode(debugLabel: 'plan');
    _planScroll = plan == null ? null : PlanNoteScroll();
    _planPages = false;
    context.owner.afterLayout(() {
      old?.dispose();
      oldScroll?.dispose();
      if (mounted && _planId == id) _planFocus?.requestFocus();
    });
  }

  final _searchFocus = FocusNode(debugLabel: 'prompt search');
  OverlayEntry? _searchEntry;
  Object? _searchIdentity;
  TextAreaLayout? _searchViewport;
  bool _searchHasKeys = false;

  void _syncSearch() {
    final app = widget.connection.app.value;
    final shown = app.search != null && !app.closing && !_exiting;
    if (shown && _searchEntry == null && _overlay != null) {
      late final OverlayEntry entry;
      entry = OverlayEntry(
        requestFocus: false,
        builder: (_) => _furniture(
          CompositedTransformFollower(
            link: _helpLink,
            followerAnchor: Alignment.bottomLeft,
            child: SearchLine(
              search: widget.connection.app.value.search ?? search.emptySearch,
            ),
          ),
        ),
      );
      _searchEntry = entry;
      _overlay!.insert(entry);
    } else if (!shown && _searchEntry != null) {
      final entry = _searchEntry!;
      _searchEntry = null;
      _searchIdentity = null;
      _searchViewport = null;
      entry.remove();
      entry.dispose();
    }
  }

  Widget _searchPrompt(AppState app, int rows) {
    final found = search.matched(app.search!, _history.prompts);
    final command = found == null ? null : bashCommand(found);
    final identity = ('search', app.search!.match);
    return SearchPrompt(
      key: ValueKey(identity),
      text: command ?? found ?? _input.text,
      cursor: found == null ? _input.cursor : endOf(command ?? found),
      query: found == null ? '' : app.search!.query,
      bash: found == null ? app.bash : command != null,
      windowRows: rows,
      onLayoutChanged: (layout) {
        if (mounted && _searchIdentity == identity) {
          setState(() => _searchViewport = layout);
        }
      },
    );
  }

  /// The window's rows that never give way: the status line, the working
  /// line, the live plan, the queue and, while it is drawn, the prompt.
  int _fixedRows(AppState app, int rows, int width, {required bool prompt}) {
    final turn = app.transcript.turn;
    final editor = !prompt
        ? 0
        : app.search != null
        ? _searchViewport?.height ?? promptRows(rows)
        : _input
              .layout(
                width: (width - 6).clamp(1, unbounded),
                maxHeight: promptRows(rows),
              )
              .height;
    final plan = app.transcript.plan.isEmpty
        ? 0
        : planRows(app.transcript.plan, planRowLimit(rows)).length +
              (turn is model.Idle ? 2 : 0);
    final queue = queueRows(app.queue, queueRowLimit(rows)).length;
    // A form or link asked between turns has the working line say so,
    // with no turn running.
    final working = turn is! model.Idle || askedInput(app.transcript) != null;
    return 1 + (working ? 2 : 0) + plan + queue + (prompt ? editor + 3 : 0);
  }

  /// The agents list as drawn under the status line: `main`, then the
  /// children in the order they opened; none while there is no child, and
  /// the list is not drawn.
  List<AgentRow> _agentRows() {
    final connection = widget.connection;
    final roster = connection.agents.agents;
    final main = roster.main;
    if (main == null || roster.children.isEmpty) return const [];
    final fold = connection.fold;
    ({String? model, String? effort, bool failed}) describe(int key) {
      final state = fold.stateOf(key);
      return (
        model: state == null ? null : modelName(state.agent),
        effort: state == null
            ? null
            : effortsFrom(state.agent.configOptions)?.current,
        failed: state?.start.phase == StartPhase.failed,
      );
    }

    final described = describe(main.key);
    return [
      AgentRow(
        key: main.key,
        name: 'main',
        runtime: main.agent,
        wait: main.wait,
        model: described.model,
        effort: described.effort,
        picked: roster.picked == main.key,
        failed: described.failed,
      ),
      for (final child in roster.children)
        () {
          final described = describe(child.key);
          final lead = roster_of.isLead(child.info);
          return AgentRow(
            key: child.key,
            name: child.name,
            // A lead reads as a team before any member is open; a fork says
            // so.
            runtime: lead
                ? 'team · ${child.runtime}'
                : child.forkedFrom == null
                ? child.runtime
                : 'fork · ${child.runtime}',
            colour: child.colour,
            team: lead
                ? child.key
                : roster.children
                      .where((each) => each.id == child.lead)
                      .firstOrNull
                      ?.key,
            wait: child.wait,
            model: described.model ?? child.info.model,
            effort: described.effort,
            picked: roster.picked == child.key,
            failed: described.failed,
          );
        }(),
    ];
  }

  /// The list under the prompt as it is drawn in [limit] lines at [width]:
  /// [rows], a team folded where their lines do not fit, so a resize may
  /// fold or unfold one.
  List<AgentRow> _listed(List<AgentRow> rows, int limit, int width) {
    final now = AgentsClock.now();
    return listRows(
      rows,
      limit: limit,
      height: (rows) => agentsHeight(rows, width: width, now: now),
    );
  }

  /// Each coloured agent's colour by name in [palette], for the
  /// transcript's messages: main has none.
  Map<String, Color> _agentColours(Palette palette) => {
    for (final row in _agentRows())
      if (agentColour(palette, row.colour) case final colour?)
        row.name: colorOf(colour),
  };

  /// A member's lead, by its name; none for any other child.
  String? _leadName(Child<Conversation> child) {
    final lead = child.lead;
    if (lead == null) return null;
    return widget.connection.agents.agents.children
        .where((each) => each.id == lead)
        .firstOrNull
        ?.name;
  }

  /// The child in front; none while main is.
  Child<Conversation>? _frontChild() {
    final connection = widget.connection;
    for (final child in connection.agents.agents.children) {
      if (child.key == connection.fold.front) return child;
    }
    return null;
  }

  /// The child in front as a box that asks names it, as the original's
  /// `childShown`: its colour from [palette], none without one; none
  /// while main is in front.
  PickedAsker? _pickedAsker([Palette? palette]) {
    final child = _frontChild();
    if (child == null) return null;
    final lead = child.lead;
    return (
      name: child.name,
      colour: switch (palette == null
          ? null
          : agentColour(palette, child.colour)) {
        final colour? => colorOf(colour),
        null => null,
      },
      team: lead == null
          ? null
          : widget.connection.agents.agents.children
                .where((each) => each.id == lead)
                .firstOrNull
                ?.name,
    );
  }

  /// The rows the list last drew, to know when another fold changes them.
  List<AgentRow> _listedRows = const [];

  /// A fold that changes what the list draws, a hidden child's wait or
  /// model, redraws the window, which a hidden session's events otherwise
  /// do not.
  void _listChanged() {
    final rows = _agentRows();
    if (_sameRows(rows, _listedRows)) return;
    _listedRows = rows;
    if (mounted) _pageEntry.markNeedsBuild();
  }

  /// The plan box's shape as it last told it, by its request's id.
  (String, PlanShape)? _planShape;

  /// The box told the window a new shape: the room is shared again.
  void _planShaped(String id, PlanShape shape) {
    if (_planShape == (id, shape)) return;
    _planShape = (id, shape);
    if (mounted) _pageEntry.markNeedsBuild();
  }

  /// A form or question box changed its own rows: the room is shared again.
  void _inputShaped() {
    if (mounted) _pageEntry.markNeedsBuild();
  }

  /// How the window's rows are shared between the transcript, the agents
  /// list and the requests on screen.
  AgentsRoom _room(
    AppState app,
    int rows,
    int width, {
    required List<AgentRow> agents,
    required model.PlanAsk? plan,
    required model.PermissionWait? wait,
    required model.ElicitationWait? input,
    required bool held,
    required bool inputActive,
    int frame = 0,
  }) {
    final attend = _key('session:attention');
    final requests = <RoomRequest>[
      if (plan != null)
        () {
          final shape = _planShape;
          final natural = planNatural(
            plan.wait,
            _frontRuntime,
            width,
            windowRows: rows,
            shape: shape != null && shape.$1 == plan.wait.id
                ? shape.$2
                : openPlanShape,
          );
          return RoomRequest(
            fixed: natural.fixed,
            natural: natural.natural,
            gives: RoomGives.withList,
          );
        }(),
      if (wait != null)
        () {
          final natural = permissionNatural(
            wait,
            width,
            windowRows: rows,
            // As the box draws it, the key that reads a change taller
            // than the transcript included.
            hint: permissionHint(
              wait,
              held: held,
              attend: attend,
              reject: _key('confirm:no'),
              pageUp: _changeOverflows(app, wait)
                  ? _key('scroll:pageUp')
                  : null,
            ),
            asker: askerText(_askerOf(app, wait)),
            picked: _pickedAsker(),
            between:
                app.transcript.turn is model.AwaitingPermission &&
                (app.transcript.turn as model.AwaitingPermission).between,
            paths: _paths,
          );
          return RoomRequest(
            fixed: natural.fixed,
            natural: natural.natural,
            gives: RoomGives.afterList,
          );
        }(),
      if (input != null)
        () {
          final natural = switch (input) {
            model.FormWait(questions: final questions?) => questionNatural(
              questions,
              _asks[(widget.connection.fold.front, input.id)] ??
                  openAsk(questions),
              width,
              windowRows: rows,
              held: held,
              hint: attend != null,
            ),
            final model.FormWait form => formNatural(
              form,
              _form?.value ?? FormData.initial(fieldsOf(form.schema)),
              width,
              windowRows: rows,
              held: held,
              hint: attend != null,
            ),
            final model.LinkWait link => linkNatural(link, width, held: held),
          };
          return RoomRequest(
            fixed: natural.fixed,
            natural: natural.natural,
            // Held, it shrinks with the list, as the original's
            // `flexShrink={held ? 1 : 0}`; with the keys, never.
            gives: held ? RoomGives.withList : RoomGives.never,
          );
        }(),
    ];
    final now = AgentsClock.now();
    return agentsRoom(
      rows: rows,
      // The summary line never gives way, as the original's flexShrink 0.
      fixed:
          _fixedRows(app, rows, width, prompt: !inputActive) +
          summaryLineCount(_background(), math.max(0, width - 4)) +
          frame,
      requests: requests,
      linesAt: (limit) => agentsLines(
        _listed(agents, limit, math.max(0, width - 4)),
        limit: limit,
        width: math.max(0, width - 4),
        focused: false,
        now: now,
      ),
    );
  }

  /// Who asks the form, question or link [wait], when a subagent or task
  /// does, as its box's heading names it.
  List<({String text, bool bold})> _inputAsker(
    AppState app,
    model.ElicitationWait wait,
  ) => wait.subagentId == null
      ? const []
      : askerOf(
          askerRow(subagentPath(app.transcript.entries, wait.subagentId!)),
        );

  /// Who asks [wait], when a subagent does.
  List<({String text, bool bold})> _askerOf(
    AppState app,
    model.PermissionWait wait,
  ) => wait.subagentId == null
      ? const []
      : askerRow(subagentPath(app.transcript.entries, wait.subagentId!));

  // The prompts sent are the window's; the walk through them, ↑ and ↓'s
  // place and the draft it began on, is each agent's, as its kept drafts
  // are: another agent's place must never name one of them.
  var _shared = const history.History();
  final _walks = <int, history.Walk?>{};

  /// The prompts sent, as the agent in front walks them.
  history.History get _history =>
      history.walkedIn(_shared, _walks[widget.connection.fold.front]);

  set _history(history.History next) {
    _shared = history.History(prompts: next.prompts, images: next.images);
    _walks[widget.connection.fold.front] = history.walkOf(next);
  }

  late PathView _paths;
  void Function()? _unlisten;

  @override
  void initState() {
    super.initState();
    _copies = selection.SelectionCopies(
      copy: (text, token) => (widget.copy ?? _terminalCopy)(text, token),
      session: _selectionSession,
    )..addListener(_copyChanged);
    _watchTerminal();
    _codePick.addListener(_pickChanged);
    _ownMentions();
    _subscribe();
    _reportStatus();
    _ownShells();
    _input.addListener(_draftChanged);
    // Vim mode kept from the last start begins in insert mode, whose typing
    // undoes as one.
    if (widget.connection.app.value.vim != null || widget.launch.vim) {
      _input.beginUndoGroup();
    }
    _scroll.addListener(_scrolled);
  }

  /// Another session came in front: its own scroll controller takes the
  /// list, where it was left.
  void _frontMoved() {
    _listChanged();
    final fold = widget.connection.fold;
    // A session closed or launched again lets its `!` commands go, however
    // it was let go.
    for (final MapEntry(:key, :value) in _shellTokens.entries.toList()) {
      if (!fold.isLive(_shellTargets[value]!)) _retireShells(key);
    }
    final front = fold.front;
    if (front != _shownKey) _shown(front);
    _syncRoster();
    // A closed session's controller goes with it, no listener left on it.
    final open = fold.windowed.value.sessions;
    for (final key in _scrolls.keys.toList()) {
      if (key != _shownKey && !open.containsKey(key)) {
        _scrolls.closed(key);
        _seenEntries.remove(key);
      }
    }
  }

  /// Session [front] came in front: the selection and a picked code block
  /// were the other session's and end; its own scroll takes the list, where
  /// it was left, and its draft the field.
  void _shown(int front) {
    final fold = widget.connection.fold;
    _shownKey = front;
    _replaceSelectionSession();
    _showScroll(_scrolls.of(front));
    // The one field holds the agent in front's draft, where it was left;
    // loading it is no edit of the agent's.
    final app = fold.app.value;
    _loadingFront = true;
    try {
      _input.text = app.draft;
      _input.cursor = app.cursor;
    } finally {
      _loadingFront = false;
    }
  }

  void Function()? _unlistenKeyed;
  void Function()? _unlistenWaits;

  /// The session whose draft and scroll the window shows.
  int _shownKey = mainKey;

  /// Each session's entries as its scroll last heard them.
  final _seenEntries = <int, List<model.Entry>>{};

  /// Session [key] heard [event]: its scroll, shown or not, follows the
  /// prompt it sent or marks what came while it was scrolled back, as the
  /// original folds every session's scroll. A session never shown has no
  /// controller yet, and starts at its end.
  void _scrollHeard(int key, ConversationEvent event) {
    final after =
        widget.connection.fold.windowed.value.sessions[key]?.transcript.entries;
    final before = _seenEntries[key];
    if (after == null) {
      _seenEntries.remove(key);
    } else {
      _seenEntries[key] = after;
    }
    final controller = _scrolls.made(key);
    if (controller == null || controller.isDisposed) return;
    applyScrollEffect(controller, entriesScrollEffect(before, after, event));
  }

  /// Set while the field is loaded from another agent's draft.
  bool _loadingFront = false;

  void _subscribe() {
    widget.connection.settingPickedUp = _pickedUp;
    widget.connection.fold.windowed.addListener(_frontMoved);
    _unlistenWaits = widget.connection.listenWaits(_heardWait);
    _unlistenKeyed = widget.connection.listenKeyed((key, event) {
      // A child in front: the prompts its clear took back return to the
      // field; one behind gets them in its own draft.
      if (event is Cleared || event is Closing) _retireShells(key);
      if (event is QueueWithdrawn && key == widget.connection.fold.front) {
        _input.text = restoredDraft(event.prompts, _input.text);
      }
      if (event is Cleared) {
        // A new session: a new controller, at its transcript's end.
        if (key == widget.connection.fold.front) {
          _replaceSelectionSession();
          _showScroll(_scrolls.cleared(key));
        } else {
          _scrolls.cleared(key);
        }
      }
      _scrollHeard(key, event);
      // A child's clear or close is a new launch under its key.
      _syncRoster();
      _reportStatus();
    });
    widget.connection.app.addListener(_steerNoteChanged);
    _steerNoteChanged();
    _seenEntries
      ..clear()
      ..addAll({
        for (final MapEntry(:key, :value)
            in widget.connection.fold.windowed.value.sessions.entries)
          key: value.transcript.entries,
      });
    _paths = pathView(widget.connection.cwd, Platform.environment['HOME']);
    _unlisten = widget.connection.listen((event) {
      _reportStatus();
      _openAsked();
      if (const {
        StartPhase.connected,
        StartPhase.failed,
      }.contains(widget.connection.app.value.start.phase)) {
        _splashLeft = true;
      }
      if (event is Cleared) {
        _cancelResumeRead();
        _removeResumeEntry();
        _retireMentions();
        _ownMentions();
        _retireShells(mainKey);
        _replaceSelectionSession();
        _startedModel = null;
        _resumedOpening = null;
        _resumedFacts = null;
        _setSettings(null);
        _settingsAsked = null;
        _menu = null;
        _commandRows = 0;
        // A new session: a new controller, at its transcript's end.
        if (widget.connection.fold.front == mainKey) {
          _showScroll(_scrolls.cleared(mainKey));
        } else {
          _scrolls.cleared(mainKey);
        }
      }
      if (event is Closing) {
        _cancelResumeRead();
        _removeResumeEntry();
        _closeShells();
        _refreshMentions();
      }
      if (event is Closing || event is Connected) _replaceSelectionSession();
      if (event is QueueWithdrawn) {
        final fold = widget.connection.fold;
        if (fold.front == mainKey) {
          _input.text = restoredDraft(event.prompts, _input.text);
        } else {
          // Main is behind: its prompts go back to its own draft.
          final draft = restoredDraft(
            event.prompts,
            fold.stateOf(mainKey)?.draft ?? '',
          );
          fold.dispatch(
            SessionActed(mainKey, DraftEditedAction(draft, draft.length)),
          );
        }
      }
      _scrollHeard(mainKey, event);
      _syncRoster();
      _refreshMentions();
    });
  }

  @override
  void didUpdateWidget(TranscriptWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      // The old terminal keeps nothing of chord's; the new one is told.
      if (!_away) oldWidget.terminal?.clearProgramStatus();
      _statusSent = null;
      _away = false;
    }
    if (oldWidget.terminal != widget.terminal ||
        oldWidget.copy != widget.copy) {
      _replaceSelectionSession();
      _watchTerminal();
    }
    if (!identical(oldWidget.connection, widget.connection)) {
      if (oldWidget.connection.settingPickedUp == _pickedUp) {
        oldWidget.connection.settingPickedUp = null;
      }
      oldWidget.connection.app.removeListener(_steerNoteChanged);
      oldWidget.connection.fold.windowed.removeListener(_frontMoved);
      _cancelSteerNoteTimer();
      _cancelResumeRead();
      _removeResumeEntry();
      _retireMentions();
      _ownMentions();
      _closeShells();
      _ownShells();
      _replaceSelectionSession();
      _cancelQuitTimer();
      _exiting = false;
      _startedModel = null;
      _resumedOpening = null;
      _resumedFacts = null;
      _unlisten?.call();
      _unlistenKeyed?.call();
      _unlistenWaits?.call();
      _subscribe();
    }
    _reportStatus();
    if (identical(oldWidget.connection, widget.connection)) {
      if (oldWidget.walkFiles != widget.walkFiles ||
          oldWidget.matchMentions != widget.matchMentions) {
        _retireMentions();
        _ownMentions();
      } else if (!_rosterLive &&
          !identical(oldWidget.recipients, widget.recipients)) {
        _mentions.replaceRecipients([
          for (final r in widget.recipients) r.name,
        ]);
      }
    }
    _refreshMentions();
  }

  @override
  void dispose() {
    _sessionVar.retire();
    if (widget.connection.settingPickedUp == _pickedUp) {
      widget.connection.settingPickedUp = null;
    }
    widget.connection.app.removeListener(_steerNoteChanged);
    widget.connection.fold.windowed.removeListener(_frontMoved);
    _cancelSteerNoteTimer();
    _retireMentions();
    _closeShells();
    // No write here: a quit after the terminal went away (its input ended)
    // disposes the window first, and a write to a hung-up terminal fails on
    // stdout's own zone. The terminal clears the record as it is given back.
    _terminalStates?.cancel();
    _copies.removeListener(_copyChanged);
    _copies.dispose();
    _codePick.removeListener(_pickChanged);
    _codePick.dispose();
    _selection.dispose();
    _cancelQuitTimer();
    _clearDraftHeld();
    _unlisten?.call();
    _unlistenKeyed?.call();
    _unlistenWaits?.call();
    _input.removeListener(_draftChanged);
    if (!_scroll.isDisposed) _scroll.removeListener(_scrolled);
    final commandEntry = _commandEntry;
    if (commandEntry != null) {
      commandEntry.remove();
      commandEntry.dispose();
    }
    _cancelResumeRead();
    _removeResumeEntry();
    final settingsEntry = _settingsEntry;
    if (settingsEntry != null) {
      settingsEntry.remove();
      settingsEntry.dispose();
    }
    final teamsEntry = _teamsEntry;
    if (teamsEntry != null) {
      teamsEntry.remove();
      teamsEntry.dispose();
    }
    final helpEntry = _helpEntry;
    if (helpEntry != null) {
      helpEntry.remove();
      helpEntry.dispose();
    }
    _themeEntry?.remove();
    _themeEntry?.dispose();
    _mcpEntry?.remove();
    _mcpEntry?.dispose();
    _noticeEntry?.remove();
    _noticeEntry?.dispose();
    _panelScroll.dispose();
    _scrolls.dispose();
    _input.dispose();
    _searchFocus.dispose();
    _searchEntry?.remove();
    _searchEntry?.dispose();
    _permissionFocus?.dispose();
    _planFocus?.dispose();
    _inputFocus?.dispose();
    for (final form in _forms.values) {
      form.dispose();
    }
    _permissionScroll?.dispose();
    _planScroll?.dispose();
    _closeTimer?.cancel();
    _listFocus.dispose();
    _viewFocus.dispose();
    for (final scroll in _logScrolls.values) {
      scroll.dispose();
    }
    _viewClock?.call();
    _viewClock = null;
    for (final highlight in [
      ..._choiceHighlights.values,
      ..._linkHighlights.values,
    ]) {
      highlight.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    // Every hint under it names the key the file binds.
    child: Keys(
      keymap: widget.launch.keymap ?? defaultKeymap,
      // The whole window in the theme in use, or the one /theme previews.
      child: ListenableBuilder(
        listenable: widget.connection.app,
        builder: (context) => Theme(
          data: _themeFor(context),
          child: ListenableBuilder(
            listenable: widget.connection.app,
            builder: (context) {
              // As the original reports after each draw: what changed since the
              // last event, such as the title a sent prompt gives, is told too.
              _reportStatus();
              _pageEntry.markNeedsBuild();
              _helpEntry?.markNeedsBuild();
              _settingsEntry?.markNeedsBuild();
              _themeEntry?.markNeedsBuild();
              _mcpEntry?.markNeedsBuild();
              _noticeEntry?.markNeedsBuild();
              _resumeEntry?.markNeedsBuild();
              _refreshMenu();
              _commandEntry?.markNeedsBuild();
              _finderEntry?.markNeedsBuild();
              _searchEntry?.markNeedsBuild();
              _mentionBindings = _finderBindings();
              final selectionCopy = keys.selectionCopyBinding(
                _keyContext,
                _play,
              );
              _pickedBindings = keys.codePickBindings(_keyContext, _play);
              final ordinaryBindings = keys.windowBindings(
                _keyContext,
                _play,
                selectionCopy: selectionCopy,
                pickedBindings: _pickedBindings,
              );
              // The file's keys over the window's: the window applies them
              // itself, so its own bindings keep who they are where it compares.
              final keymap = widget.launch.keymap?.data ?? const KeymapData();
              final written = [
                ..._mentionBindings,
                for (final binding in ordinaryBindings)
                  if (!_mentionBindings.any((m) => m.chord == binding.chord))
                    binding,
              ];
              // A key the file gives an action on screen is that action's, ahead
              // of the window's own handling of it (bash mode's ! and backspace),
              // as the original asks its keymap first.
              final taken = {
                for (final b in written)
                  if (b.id != null) ...?keymap.keysFor(b.id!),
              };
              // A list or panel open over the prompt takes every key the file
              // binds in it ahead of the window's other keys, as the original's
              // Autocomplete and Help contexts do.
              final live = keys.liveContexts(_keyContext());
              final over = {
                for (final b in _keymap.bindings)
                  if (live.contains(b.context))
                    Chord([for (final k in b.keys) k.combo]),
              };
              // A picked block's keys and the copy key are heard before every
              // context while they are live.
              bool overContext(Binding b) =>
                  switch (keymap_file.actions[b.id]?.context) {
                    final context? =>
                      live.contains(context) ||
                          context == keymap_file.KeyContext.codeBlock ||
                          context == keymap_file.KeyContext.selection,
                    null => false,
                  };
              final bindings = keymap.apply([
                for (final b in written)
                  if ((b.id != null ||
                          _mentionBindings.contains(b) ||
                          !taken.contains(b.chord)) &&
                      (overContext(b) ||
                          _mentionBindings.contains(b) ||
                          !over.contains(b.chord)))
                    b,
              ]).bindings;
              _bound = bindings;
              // The finder's bindings as the file moved them: a moved one is a
              // copy that keeps what it does.
              final finder = _mentionBindings;
              _mentionBindings = [
                for (final b in bindings)
                  if (finder.any((m) => identical(m.onInvoke, b.onInvoke))) b,
              ];
              _pickedBindings = [
                for (final b in bindings)
                  if (keys.codePickActions.containsValue(b.id)) b,
              ];
              final boundCopy =
                  bindings.where((b) => b.id == 'selection:copy').firstOrNull ??
                  selectionCopy;
              return Focus(
                canRequestFocus: false,
                onKeyCapture: (event) =>
                    _captureKey(event, bindings, boundCopy),
                onPasteCapture: (text) {
                  _clearInteractions();
                  final live = _keyContext();
                  // Normal mode takes no paste, as it types nothing.
                  if (live.state.vim?.mode == VimMode.normal &&
                      live.canEdit &&
                      live.state.search == null) {
                    return true;
                  }
                  // A bracketed paste with nothing in it: what a terminal sends
                  // for cmd+V when the clipboard holds an image and no text.
                  if (text.isEmpty) {
                    if (keys.takesImagePaste(live)) {
                      _play([const keys.PasteImage(quiet: true)]);
                    }
                    return true;
                  }
                  if (live.state.search != null &&
                      live.canEdit &&
                      !live.state.shortcuts.help) {
                    if (live.searchEnabled) {
                      _play(keys.searchEditSteps(text, live));
                    }
                    return true;
                  }
                  return false;
                },
                child: SelectionArea(
                  controller: _selection,
                  selectionStyle: chordThemeOf(context).selection,
                  onSelectionChanged: _selectionChanged,
                  onSelectionFinalized: _selectionFinalized,
                  child: Actions(
                    bindings: bindings,
                    // The lists and dialogs under the window's own keys bind
                    // the file's keys by their actions' ids.
                    child: Keymap(
                      data: keymap,
                      child: Focus(
                        focusNode: _searchFocus,
                        canRequestFocus:
                            widget.connection.app.value.search != null,
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: _wheeled,
                          child: Stack(
                            children: [
                              Overlay(initialEntries: [_pageEntry]),
                              // Under the splash the window is laid out but not
                              // drawn, so keys pressed meanwhile land in it.
                              if (_splashing)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Splash(
                                    agent: _mainRuntime,
                                    armed: widget.connection.app.value.quitArmed
                                        ? ctrlCArmedLine()
                                        : null,
                                    closing:
                                        widget.connection.app.value.closing,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _page(BuildContext context) {
    _overlay = Overlay.of(context);
    context.owner.afterLayout(() {
      if (mounted) {
        _syncSearch();
        _syncHelp();
        _syncSettings();
        _syncTeams();
        _syncTheme();
        _syncMcp();
        _syncNotice();
        _syncResume(rebuild: false);
        // Parent updates and current constraints already rebuilt this entry.
        // This lifecycle sync still creates/removes it without another pass.
        _syncCommands(rebuild: false);
        _refreshMentions();
        _syncFinder(rebuild: false);
      }
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_selectionSize != size) {
          final previous = _selectionSize;
          _selectionSize = size;
          if (previous != null) {
            context.owner.afterLayout(() {
              // Range geometry is cancelled; logical code IDs survive reflow.
              if (mounted && _selectionSize == size) _clearSelection();
            });
          }
        }
        _rows = constraints.maxHeight;
        _columns = constraints.maxWidth;
        final commandEntry = _commandEntry, finderEntry = _finderEntry;
        context.owner.afterLayout(() {
          _commandRoomChanged(commandEntry);
          _finderRoomChanged(finderEntry);
        });
        final app = widget.connection.app.value;
        final searchIdentity = app.search == null
            ? null
            : ('search', app.search!.match);
        if (_searchIdentity != searchIdentity) {
          _searchIdentity = searchIdentity;
          _searchViewport = null;
        }
        _startedModel ??= modelName(app.agent);
        final start = app.start;
        final waitShown = askedPermission(app.transcript.turn);
        // A plan ranks with the permissions, the oldest first: those
        // already waiting when it came go before it.
        final plan = app.transcript.planAsks
            .where((ask) => ask.answer == null)
            .firstOrNull;
        final planShown =
            plan != null &&
            !app.closing &&
            !(waitShown != null && plan.after.contains(waitShown.id));
        final wait = planShown ? null : waitShown;
        final held = heldBack(app);
        final agents = _listedRows = _agentRows();
        final backgroundItems = _background();
        // The list gone while it had the keys hands them back to the box; a
        // summary line gone gives the `❯` back to the agent picked.
        if (app.agentsFocus && agents.isEmpty && backgroundItems.isEmpty) {
          context.owner.afterLayout(() {
            if (mounted && widget.connection.app.value.agentsFocus) {
              _dispatch(const AgentsFocusedAction(false));
            }
          });
        } else if (app.summaryFocus && backgroundItems.isEmpty) {
          context.owner.afterLayout(() {
            if (mounted && widget.connection.app.value.summaryFocus) {
              _dispatch(const SummaryFocusedAction(false));
            }
          });
        }
        final summaryFocused = _summaryFocused();
        final listKeys = _listHasKeys();
        final viewKeys = _viewHasKeys();
        // The background view, drawn while it is shown: hidden, not
        // closed, while a request asked since stands in its place.
        final frame =
            !app.closing &&
                background.backgroundShown(app.backgroundView, app.transcript)
            ? _backgroundFrame(
                app,
                backgroundItems,
                constraints.maxWidth,
                constraints.maxHeight,
              )
            : null;
        // A row that leaves the view as its item ends hands the `❯` to the
        // row that took its place, and the last to leave closes the view.
        _followBackground(app, backgroundItems);
        _syncViewKeys(viewKeys);
        _syncViewClock(frame != null);
        // While the list or the view has the keys a box waits, its place
        // kept.
        final away = listKeys || viewKeys;
        final active = wait != null && !held && !away;
        _syncPermission(wait, active);
        _planShown = planShown;
        _syncPlan(planShown ? plan : null);
        final input = app.closing ? null : askedInput(app.transcript);
        final inputActive = input != null && !held;
        _syncInput(input, inputActive && !away, app.transcript.asking);
        _syncListKeys(listKeys, planShown: planShown);
        // ↓ from a box's last row goes into the list, where there is one.
        final leave = agents.isEmpty && backgroundItems.isEmpty
            ? null
            : () => _dispatch(const AgentsFocusedAction(true));
        final room = _room(
          app,
          constraints.maxHeight,
          constraints.maxWidth,
          agents: agents,
          plan: planShown ? plan : null,
          wait: wait,
          input: input,
          held: held,
          inputActive: inputActive,
          frame: frame?.height ?? 0,
        );
        _listLimit = room.limit;
        // The notice and the /theme and /mcp pickers float in the
        // transcript's rows, which a tall draft, list or request takes from.
        if (_transcriptRows != room.transcript) {
          _transcriptRows = room.transcript;
          context.owner.afterLayout(() {
            _noticeEntry?.markNeedsBuild();
            _helpEntry?.markNeedsBuild();
            _themeEntry?.markNeedsBuild();
            _mcpEntry?.markNeedsBuild();
          });
        }
        // The requests' rows, in the order [_room] asked them.
        final rooms = room.requests.iterator;
        int nextRoom() => (rooms..moveNext()).current;
        final planRoom = planShown ? nextRoom() : 0;
        final waitRoom = wait != null ? nextRoom() : 0;
        final inputRoom = input != null ? nextRoom() : 0;
        final searchHasKeys =
            app.search != null &&
            !active &&
            !listKeys &&
            !_pickerOpen &&
            app.resumePicker == null &&
            !app.shortcuts.help &&
            !app.closing;
        if (_searchHasKeys != searchHasKeys) {
          _searchHasKeys = searchHasKeys;
          if (searchHasKeys) {
            context.owner.afterLayout(() {
              if (mounted && _searchHasKeys) _searchFocus.requestFocus();
            });
          }
        }
        final bodyWidth = (constraints.maxWidth - 2).clamp(0, unbounded);
        // The agent by the name chord knows it, as the original's header.
        final agentName = _mainRuntime;
        if (!identical(_resumedOpening, app.resumed)) {
          _resumedOpening = app.resumed;
          _resumedFacts = app.resumed == null
              ? null
              : resumedHeader(
                  app.resumed!,
                  DateTime.now().millisecondsSinceEpoch,
                  firstPrompt: app.transcript.entries
                      .whereType<model.UserEntry>()
                      .firstOrNull
                      ?.text,
                );
        }
        final palette = _palette(context, app);
        final child = _frontChild();
        final picked = _pickedAsker(palette);
        // A child's transcript starts with its line, as the original's.
        final childModel = child == null
            ? null
            : modelName(app.agent) ?? child.info.model;
        final Object headerRevision = child != null
            ? ('child', child.key)
            : (
                widget.launch.version,
                agentName,
                widget.launch.directory,
                _startedModel,
                _resumedFacts,
                bodyWidth,
                _key('help:toggle'),
              );
        if (_headerSource?.revision != headerRevision && child != null) {
          _headerSource = selection_sources.childLineSelectionSource(
            id: ('header', _selectionSession),
            revision: headerRevision,
            previous: _headerSource,
          );
        } else if (_headerSource?.revision != headerRevision) {
          _headerSource = selection_sources.headerSelectionSource(
            id: ('header', _selectionSession),
            revision: headerRevision,
            width: bodyWidth,
            version: widget.launch.version,
            agent: agentName,
            directory: widget.launch.directory,
            model: _startedModel,
            resumed: _resumedFacts,
            previous: _headerSource,
            helpKey: _key('help:toggle'),
          );
        }
        final planRevision = (
          app.transcript.plan,
          planRowLimit(constraints.maxHeight),
          app.transcript.turn is! model.Idle,
          constraints.maxWidth,
        );
        if (_planSource?.revision != planRevision) {
          _planSource = selection_sources.livePlanSelectionSource(
            id: ('plan', _selectionSession),
            revision: planRevision,
            plan: app.transcript.plan,
            limit: planRowLimit(constraints.maxHeight),
            running: app.transcript.turn is! model.Idle,
            previous: _planSource,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              key: const ValueKey('transcript-body'),
              // A message's arrow and name in the colour of the agent at
              // its other end, as the original's agents list paints it.
              child: AgentColours(
                colours: _agentColours(palette),
                child: Transcript(
                  // Each session its own viewport, over its retained controller.
                  key: ValueKey(('transcript', _shownKey)),
                  transcript: app.transcript,
                  resumed: app.resumed != null,
                  controller: _scroll,
                  windowRows: _rows,
                  paths: _paths,
                  // A call to chord's own server reads as chord's by the name
                  // the shown session gave it.
                  chordServer:
                      (widget.connection.agents.conversationOf(_shownKey) ??
                              widget.connection.conversation)
                          .session
                          ?.chordServer,
                  agent: _frontRuntime,
                  bodyPadding: 1,
                  bindKeys: false,
                  expanded: app.expanded,
                  selectionNamespace: _selectionSession,
                  selectionSources: _sources,
                  selectedCodeBlock: _codePick.value,
                  onCopyCodeBlock: _copyCodeBlock,
                  onRunCodeBlock: _runCodeBlock,
                  shellStopKey: _key('chat:cancel'),
                  expandKey: _key('app:toggleTranscript'),
                  headerSelectionSource: _headerSource,
                  intro: start.phase == StartPhase.failed
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Failure(
                              printable(statusLine(start, _frontRuntime)!),
                            ),
                            if (start.signIn case final signIn?)
                              SignInBlock(
                                agent: _frontRuntime,
                                signIn: signIn,
                                pinned: start.failure?.pinned,
                              )
                            else if (start.failure case final failure?)
                              StartFailureBlock(
                                agent: _frontRuntime,
                                failure: failure,
                              ),
                          ],
                        )
                      : null,
                  header: child != null
                      // Not selectable, as the original's line is not.
                      ? SelectionContainer.disabled(
                          child: ChildLine(
                            name: child.name,
                            runtime: child.runtime,
                            openedAt: child.info.openedAt,
                            colour: child.colour,
                            palette: palette,
                            model: childModel,
                            forkedFrom: child.forkedFrom,
                            team: child.info.team,
                            leadName: _leadName(child),
                          ),
                        )
                      : CompactHeader(
                          version: widget.launch.version,
                          agent: agentName,
                          directory: widget.launch.directory,
                          model: _startedModel,
                          resumed: _resumedFacts,
                          selectionSource: _headerSource,
                          helpKey: _key('help:toggle'),
                        ),
                  footer: Column(
                    children: [
                      _furniture(
                        Working(
                          turn: app.transcript.turn,
                          plan: planShown,
                          input: input,
                          compacting: app.transcript.entries.any(
                            (entry) => inSpinner(entry, app.transcript.turn),
                          ),
                        ),
                      ),
                      if (app.transcript.plan.isNotEmpty)
                        Plan(
                          plan: app.transcript.plan,
                          limit: planRowLimit(constraints.maxHeight),
                          running: app.transcript.turn is! model.Idle,
                          selectionSource: _planSource,
                        ),
                      _furniture(
                        Queue(
                          queue: app.queue,
                          limit: queueRowLimit(constraints.maxHeight),
                        ),
                      ),
                      if (planShown)
                        PlanBox(
                          key: ValueKey(plan.wait.id),
                          wait: plan.wait,
                          agent: _frontRuntime,
                          focusNode: _planFocus,
                          windowRows: constraints.maxHeight,
                          maxRows: planRoom,
                          onShape: (shape) => _planShaped(plan.wait.id, shape),
                          scroll: _planScroll,
                          onOverflow: (overflows) {
                            if (mounted && _planId == plan.wait.id) {
                              _planPages = overflows;
                            }
                          },
                          away: away,
                          onLeave: leave,
                          onAnswer: (answer) =>
                              _conversation.answerPlan(plan.wait.id, answer),
                        ),
                      if (wait != null)
                        PermissionPrompt(
                          key: ValueKey(wait.id),
                          wait: wait,
                          changeOverflows: _changeOverflows(app, wait),
                          asker: wait.subagentId == null
                              ? const []
                              : askerRow(
                                  subagentPath(
                                    app.transcript.entries,
                                    wait.subagentId!,
                                  ),
                                ),
                          picked: picked,
                          windowRows: constraints.maxHeight,
                          maxRows: waitRoom,
                          scroll: _permissionScroll!,
                          isClosing: () =>
                              _exiting || widget.connection.app.value.closing,
                          focusNode: _permissionFocus,
                          between:
                              app.transcript.turn is model.AwaitingPermission &&
                              (app.transcript.turn as model.AwaitingPermission)
                                  .between,
                          held: held,
                          away: away,
                          onLeave: leave,
                          highlight: _choiceHighlights[wait.id] ??=
                              ValueNotifier(null),
                          onOverflow: (overflows) {
                            if (mounted &&
                                _requestId == wait.id &&
                                widget.connection.app.value.requestOverflows !=
                                    overflows) {
                              _dispatch(RequestOverflowedAction(overflows));
                            }
                          },
                          paths: _paths,
                          onChoose: (id) => _play(
                            keys.chooseSteps(wait.id, id, _keyContext()),
                          ),
                          onReject: () => _play(
                            keys.keySteps(Chord.parse('esc'), _keyContext()),
                          ),
                        ),
                      if (input case final model.FormWait asked
                          when asked.questions != null)
                        QuestionBox(
                          key: ValueKey(asked.id),
                          wait: asked,
                          questions: asked.questions!,
                          agent: child?.name ?? _mainRuntime,
                          asker: _inputAsker(app, asked),
                          picked: picked,
                          filled:
                              _asks[(widget.connection.fold.front, asked.id)],
                          onFill: (state) {
                            _asks[(widget.connection.fold.front, asked.id)] =
                                state;
                            _inputShaped();
                          },
                          windowRows: constraints.maxHeight,
                          focusNode: _inputFocus,
                          between: asked.between,
                          held: held,
                          attendKey: _key('session:attention'),
                          maxRows: inputRoom,
                          onAnswer: (reply) =>
                              _conversation.answer(asked.id, reply),
                          away: away,
                          onLeave: leave,
                        )
                      else if (input case final model.FormWait form)
                        FormBox(
                          key: ValueKey(form.id),
                          wait: form,
                          agent: child?.name ?? _mainRuntime,
                          asker: _inputAsker(app, form),
                          picked: picked,
                          controller: _form!,
                          windowRows: constraints.maxHeight,
                          focusNode: _inputFocus,
                          between: form.between,
                          held: held,
                          attendKey: _key('session:attention'),
                          maxRows: inputRoom,
                          onAnswer: (reply) =>
                              _conversation.answer(form.id, reply),
                          away: away,
                          onLeave: leave,
                        ),
                      if (input case final model.LinkWait link)
                        LinkBox(
                          key: ValueKey(link.id),
                          wait: link,
                          agent: child?.name ?? _mainRuntime,
                          asker: _inputAsker(app, link),
                          picked: picked,
                          focusNode: _inputFocus,
                          between: link.between,
                          held: held,
                          attendKey: _key('session:attention'),
                          maxRows: inputRoom,
                          onAnswer: (answer) => _answerLink(link, answer),
                          away: away,
                          onLeave: leave,
                          highlight: _linkHighlights[link.id] ??= ValueNotifier(
                            null,
                          ),
                        ),
                      if (frame != null)
                        Focus(
                          focusNode: _viewFocus,
                          child: BackgroundBox(
                            key: const ValueKey('background-view'),
                            frame: frame,
                            palette: palette,
                            turn: _detailWork(app, backgroundItems)?.turn,
                            agent: _detailWork(app, backgroundItems)?.agent,
                            log: _logScroller,
                            logScroll: _logScroll(app.backgroundView?.detail),
                            onLogLines: (lines) {
                              final detail = widget
                                  .connection
                                  .app
                                  .value
                                  .backgroundView
                                  ?.detail;
                              if (mounted &&
                                  detail != null &&
                                  _logLines[detail] != lines) {
                                setState(() => _logLines[detail] = lines);
                              }
                            },
                            pageUp: _key('scroll:pageUp'),
                            pageDown: _key('scroll:pageDown'),
                          ),
                        ),
                      CompositedTransformTarget(
                        link: _helpLink,
                        child: const SizedBox(height: 0),
                      ),
                      // A form or link with the keys stands in the prompt's place.
                      if (inputActive)
                        const SizedBox()
                      else if (app.search != null)
                        _searchPrompt(app, constraints.maxHeight)
                      else
                        PromptInput(
                          key: const ValueKey('draft-editor'),
                          keymap: widget.launch.keymap,
                          agent: child == null
                              ? null
                              : PromptAgent(
                                  child.name,
                                  team: _leadName(child),
                                  colour: switch (agentColour(
                                    palette,
                                    child.colour,
                                  )) {
                                    final colour? => colorOf(colour),
                                    null => null,
                                  },
                                ),
                          over: {
                            if (_commandActive || _finderActive)
                              keymap_file.KeyContext.autocomplete,
                            if (app.shortcuts.help) keymap_file.KeyContext.help,
                          },
                          chords: [
                            for (final b in _bound)
                              if (b.chord.length > 1) b.chord,
                          ],
                          enabled:
                              !active &&
                              !planShown &&
                              !inputActive &&
                              !listKeys &&
                              !viewKeys,
                          autofocus: !active && !planShown && !inputActive,
                          controller: _input,
                          windowRows: constraints.maxHeight,
                          walking: history.walking(
                            _history,
                            typedText(app.bash, _input.text),
                          ),
                          bash: app.bash,
                          completing: _commandActive || _finderActive,
                          handleContinuation: false,
                          // A key the window binds to an action is not the
                          // text area's, as the original asks its keymap
                          // first; ? on a draft is text.
                          unhandledKeys: {
                            'ctrl+c',
                            'ctrl+d',
                            for (final b in _bound)
                              if (b.id != null && b.id != 'help:toggle')
                                '${b.chord.combos.first}',
                          },
                          shouldHandleKey: (event) =>
                              !_windowTakes(event) &&
                              !((_commandActive || _finderActive) &&
                                  const {
                                    'up',
                                    'down',
                                    'tab',
                                  }.contains(event.key)) &&
                              !(event.key == '!' &&
                                  _input.text.isEmpty &&
                                  !widget.connection.app.value.bash) &&
                              !(const {
                                    'backspace',
                                    'shift+backspace',
                                  }.contains(event.combo.toString()) &&
                                  _input.text.isEmpty &&
                                  widget.connection.app.value.bash),
                          onSubmit: (text) {
                            if (!_acceptMention(true)) {
                              _play(keys.submitSteps(text, _keyContext()));
                            }
                          },
                          onOlder: () => _moveCommand(-1),
                          onNewer: () => _moveCommand(1),
                          // A press on the box gives the list's keys back to
                          // it, the child picked staying the box's.
                          onPressed: () {
                            if (widget.connection.app.value.agentsFocus) {
                              _dispatch(const AgentsFocusedAction(false));
                            }
                          },
                        ),
                      _furniture(
                        Padding(
                          key: const ValueKey('window-status'),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _statusLine(
                            app,
                            (constraints.maxWidth - 4).clamp(0, unbounded),
                          ),
                        ),
                      ),
                      if (agents.isNotEmpty || backgroundItems.isNotEmpty)
                        Focus(
                          focusNode: _listFocus,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (agents.isNotEmpty)
                                // The box is as tall as its share, though
                                // fewer lines fit the limit, as the
                                // original's list box.
                                SizedBox(
                                  key: const ValueKey('agents-list'),
                                  height: room.list,
                                  child: AgentsList(
                                    rows: _listed(
                                      agents,
                                      room.limit,
                                      math.max(0, constraints.maxWidth - 4),
                                    ),
                                    limit: room.limit,
                                    focused: listKeys && !summaryFocused,
                                    view: listKeys ? app.agentsView : null,
                                    palette: _palette(context, app),
                                  ),
                                ),
                              // The last of the area under the status line.
                              SummaryLine(
                                key: const ValueKey('background-summary'),
                                items: backgroundItems,
                                focused: listKeys && summaryFocused,
                                palette: _palette(context, app),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Widget _furniture(Widget child) => SelectionContainer.disabled(child: child);

/// Whether the list draws [a] as it drew [b]: the same agents, each in the
/// same place with the person.
bool _sameRows(List<AgentRow> a, List<AgentRow> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.key != y.key ||
        x.name != y.name ||
        x.runtime != y.runtime ||
        x.model != y.model ||
        x.effort != y.effort ||
        x.colour != y.colour ||
        !identical(x.wait, y.wait) ||
        x.picked != y.picked ||
        x.failed != y.failed ||
        x.team != y.team) {
      return false;
    }
  }
  return true;
}
