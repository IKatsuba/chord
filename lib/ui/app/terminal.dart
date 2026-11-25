/// Session-scoped terminal interactions, independent of widgets and drawing.
library;

import 'dart:async';

import '../../shell.dart';
import '../../files.dart' as files;
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord_tui/chord_tui.dart' show ChangeNotifier;
import '../prompt/mentions.dart';
import '../prompt/commands.dart' show visibleRange;
import '../prompt/state.dart' show FileFinder, MentionChoice;
import '../../session/transcript/types.dart';

final class _RunningShell {
  _RunningShell(this.id);
  final String id;
  ShellProcess? process;
  final done = Completer<void>();
  var stopped = false;
  void stop() {
    stopped = true;
    process?.stop();
  }
}

/// Owns at most one local command per session and rejects retired callbacks.
final class ShellCommands {
  ShellCommands({required this.onAction, this.runner = runShell});
  final void Function(Object session, TranscriptAction action) onAction;
  final RunShell runner;
  final _running = <Object, _RunningShell>{};
  final _endings = <Future<void>>{};
  var _ids = 0, _closed = false;
  Future<void>? _closing;

  /// Starts one command; a running or closed session cannot start a second.
  bool run(Object session, String command, {required String cwd}) {
    if (_closed || _running.containsKey(session)) return false;
    final active = _RunningShell('shell-${++_ids}');
    _running[session] = active;
    _endings.add(active.done.future);
    void finished() {
      _endings.remove(active.done.future);
      if (!active.done.isCompleted) active.done.complete();
    }

    bool current() => !_closed && identical(_running[session], active);
    onAction(session, ShellStartedAction(active.id, command));
    if (!current()) {
      finished();
      return false;
    }
    final ShellProcess process;
    try {
      process = runner(
        command,
        ShellOptions(
          cwd: cwd,
          onOutput: (stream, text) {
            if (current()) {
              onAction(
                session,
                ShellOutputAction(
                  active.id,
                  stream == ShellStream.stderr,
                  text,
                ),
              );
            }
          },
        ),
      );
    } catch (error) {
      if (current()) {
        _running.remove(session);
        onAction(session, ShellEndedAction(active.id, error: '$error'));
      }
      finished();
      return true;
    }
    active.process = process;
    if (!current() || active.stopped) process.stop();
    unawaited(
      process.ended
          .then((end) {
            if (!current()) return;
            _running.remove(session);
            onAction(
              session,
              ShellEndedAction(
                active.id,
                code: end.code,
                stopped: end.stopped,
                error: end.error,
              ),
            );
          })
          .whenComplete(finished),
    );
    return true;
  }

  /// Stops the current command while retaining its output and ending delivery.
  void stop(Object session) => _running[session]?.stop();

  /// Clear or session replacement stops its old command and retires its callbacks.
  void retire(Object session) => _running.remove(session)?.stop();

  /// Stops every owned run, suppresses late actions and awaits their cleanup.
  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    _closed = true;
    final running = _running.values.toList();
    _running.clear();
    for (final active in running) {
      active.stop();
    }
    Future.wait(
      _endings.toList(),
    ).then((_) => done.complete(), onError: done.completeError);
    return done.future;
  }
}

/// One listing of the `@@` roster: the session it was listed for, as
/// its key and launch, and the names it offered.
typedef RosterListing = ({Object session, List<String> names});

/// Whether listing [now] after [before] starts a new completion session:
/// always for another session or launch, as equal names there are another
/// agent's; within one only when the names changed, so a roster update
/// that leaves them as they were keeps a match in progress.
bool rosterResets(RosterListing? before, RosterListing now) {
  if (before == null || before.session != now.session) return true;
  final a = before.names, b = now.names;
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

/// A cancellable current-directory walk, injected by deterministic fixtures.
typedef WalkFiles =
    Future<List<String>> Function(
      String cwd, {
      CancellationToken? cancellationToken,
    });

/// The original async fzf operation; null means superseded rather than empty.
typedef MatchMentions =
    Future<List<String>?> Function(List<String> names, String query);

/// Owns one prompt's discovery, scoring, slow marker and awaited current pick.
final class MentionCompletions extends ChangeNotifier {
  MentionCompletions({
    required this.cwd,
    required this.onChoice,
    this.validatePending,
    this.walk = files.listFiles,
    this.match,
    List<String> recipients = const [],
  }) : _recipientInput = recipients,
       _recipients = List.unmodifiable(recipients.toSet());
  final String cwd;
  final void Function(MentionChoice choice) onChoice;

  /// Synchronizes current pending surface geometry before a result replaces it.
  final bool Function()? validatePending;
  final WalkFiles walk;
  final MatchMentions? match;
  List<String> _recipientInput, _recipients;
  List<String>? _files, _names, _matchedNames;
  List<String> _matches = const [];
  MentionMatcher _matcher = MentionMatcher();
  String _draft = '';
  int _cursor = 0, _generation = 0, _matchGeneration = 0;
  Mention? _mention;
  bool _enabled = true, _dismissed = false, _openFile = false;
  bool _pending = false, _searching = false, _moved = false;
  int _highlighted = 0, _top = 0, _room = 0;
  bool _visible = false;
  ({String query, List<String> names})? _matchKey;
  ({int generation, bool enter, Object request})? _awaited;
  CancellationToken? _walking;
  Timer? _slow;

  /// Current geometry intent, including empty pending work with no drawn rows.
  FileFinder? get finder {
    final mention = _mention;
    if (!_enabled || _dismissed || mention == null || _names == null) {
      return null;
    }
    final agent = mention is AgentMention;
    if (!agent && _matches.isEmpty && !_pending && !_searching) return null;
    return FileFinder(
      mention: mention,
      files: _matches,
      highlighted: _highlighted.clamp(0, (_matches.length - 1).clamp(0, 100)),
      top: _top,
      pending: _pending,
      searching: _searching,
      empty: agent && _matches.isEmpty
          ? (_names!.isEmpty ? 'No agents to mention' : 'No matching agents')
          : null,
    );
  }

  /// Guards a choice against an editor update not yet drawn by the window.
  bool ownsInput(String draft, int cursor) =>
      !isDisposed && _draft == draft && _cursor == cursor;

  /// Whether real current rows can take navigation through Actions.
  bool get navigable =>
      _visible && _room > 0 && (finder?.files.isNotEmpty ?? false);

  /// Replacing a roster invalidates old matches and any pending acceptance.
  void replaceRecipients(List<String> names) {
    if (isDisposed || identical(names, _recipientInput)) return;
    _recipientInput = names;
    _recipients = List.unmodifiable(names.toSet());
    _generation++;
    _awaited = null;
    if (_mention is AgentMention) {
      _syncMatch();
      notifyListeners();
    }
  }

  /// Another session's roster, or its new launch: whatever was matched or
  /// awaited began for the session before and must not complete here, so
  /// the matches, the awaited pick and the highlight go even when [names]
  /// equal the old ones; two children both offer `main`.
  void resetSession(List<String> names) {
    if (isDisposed) return;
    _recipientInput = names;
    _recipients = List.unmodifiable(names.toSet());
    _generation++;
    _awaited = null;
    _matchKey = null;
    _matchedNames = null;
    _matches = const [];
    _highlighted = 0;
    _top = 0;
    _moved = false;
    _syncMatch();
    notifyListeners();
  }

  /// Typing, cursor movement and modal/session ownership invalidate waits.
  void update(String draft, int cursor, {bool enabled = true}) {
    if (isDisposed ||
        (_draft == draft && _cursor == cursor && _enabled == enabled)) {
      return;
    }
    if (_draft != draft || _cursor != cursor) _dismissed = false;
    _draft = draft;
    _cursor = cursor;
    _enabled = enabled;
    _generation++;
    _awaited = null;
    _mention = enabled ? completionAt(draft, cursor) : null;
    _syncOpening();
    _syncMatch();
    notifyListeners();
  }

  void _syncOpening() {
    final open =
        _enabled &&
        !_dismissed &&
        _mention != null &&
        _mention is! AgentMention;
    if (open == _openFile) return;
    _openFile = open;
    _walking?.cancel();
    _walking = null;
    if (!open) return;
    final token = CancellationToken();
    _walking = token;
    Future<List<String>> read() async =>
        walk(cwd, cancellationToken: token).asCancellable(token);
    read().then(
      (found) {
        if (isDisposed ||
            token.isCancelled ||
            !identical(token, _walking) ||
            !_openFile) {
          return;
        }
        _walking = null;
        _files = List.unmodifiable(found);
        _generation++;
        _awaited = null;
        _syncMatch();
        notifyListeners();
      },
      onError: (Object _) {
        if (identical(token, _walking)) _walking = null;
      },
    );
  }

  void _syncMatch() {
    final mention = _mention;
    final names = mention is AgentMention ? _recipients : _files;
    _names = names;
    if (!_enabled || _dismissed || mention == null || names == null) {
      _matchGeneration++;
      _matchKey = null;
      _pending = false;
      _searching = false;
      _slow?.cancel();
      _slow = null;
      _matcher.dispose();
      _matcher = MentionMatcher();
      return;
    }
    final key = (query: mention.query, names: names);
    if (_matchKey == key) return;
    _matchKey = key;
    final generation = ++_matchGeneration;
    _slow?.cancel();
    _slow = null;
    _searching = false;
    if (!identical(_matchedNames, names)) {
      _matches = firstFiles(names);
      _highlighted = 0;
      _top = 0;
    }
    _pending =
        mention.query.isNotEmpty && !(mention is AgentMention && names.isEmpty);
    _moved = false;
    if (mention.query.isEmpty) {
      _matches = firstFiles(names);
      _highlighted = 0;
      _top = 0;
    }
    if (!_pending && mention.query.isNotEmpty) {
      _matches = const [];
      _matcher.dispose();
      _matcher = MentionMatcher();
      return;
    }
    bool current() =>
        !isDisposed &&
        generation == _matchGeneration &&
        _matchKey == key &&
        !_dismissed &&
        _enabled;
    if (_pending && mention is! AgentMention) {
      _slow = Timer(const Duration(milliseconds: 150), () {
        if (current() && _pending) {
          _searching = true;
          notifyListeners();
        }
      });
    }
    Future<List<String>?> score() async =>
        (match ?? _matcher.match)(names, mention.query);
    score().then(
      (found) {
        if (!current() || found == null) return;
        final awaited = _awaited;
        final eligible =
            awaited != null &&
            awaited.generation == _generation &&
            _visible &&
            _room > 0 &&
            (validatePending?.call() ?? true);
        // Synchronization can edit, replace or dispose this prompt owner.
        if (!current()) return;
        final accepted =
            eligible &&
            _awaited == awaited &&
            awaited.generation == _generation &&
            _visible &&
            _room > 0;
        _slow?.cancel();
        _slow = null;
        _pending = false;
        _searching = false;
        _moved = false;
        _matchedNames = names;
        _matches = List.unmodifiable(found);
        _highlighted = 0;
        _top = 0;
        _awaited = null;
        notifyListeners();
        if (!accepted ||
            !current() ||
            awaited.generation != _generation ||
            !_visible ||
            _room <= 0) {
          return;
        }
        if (_matches.isNotEmpty) {
          _choose(_matches.first);
        } else if (awaited.enter) {
          onChoice(MentionChoice(_draft, _cursor, submit: true));
        }
      },
      onError: (Object _) {
        if (!current()) return;
        _slow?.cancel();
        _slow = null;
        _pending = false;
        _searching = false;
        _matches = const [];
        _awaited = null;
        notifyListeners();
      },
    );
  }

  /// Receives actual linked room, never a fabricated row from pending geometry.
  void setRoom(int rows, {required bool visible}) {
    if (isDisposed) return;
    _room = rows;
    _visible = visible;
    if (!visible || rows <= 0) _awaited = null;
  }

  /// Up/Down clamp, retain the current row, and permit immediate pending picks.
  void move(int by) {
    if (!navigable) return;
    _highlighted = (_highlighted + by).clamp(0, _matches.length - 1);
    _moved = true;
    final rows = finder!.choiceRows(_room);
    _top = visibleRange(_matches.length, _highlighted, rows, _top).start;
    notifyListeners();
  }

  /// Returns true only for a real pick or an owned positive-room pending wait.
  bool accept({required bool enter}) {
    if (isDisposed || !_visible || _room <= 0 || finder == null) return false;
    if (_pending && !_moved) {
      _awaited = (generation: _generation, enter: enter, request: Object());
      return true;
    }
    if (_matches.isEmpty) return false;
    _awaited = null;
    _choose(_matches[_highlighted.clamp(0, _matches.length - 1)]);
    return true;
  }

  void _choose(String path) {
    final mention = _mention;
    if (mention == null) return;
    final inserted = mention is AgentMention
        ? insertAgentMention(_draft, _cursor, mention, path)
        : insertMention(_draft, _cursor, mention, path);
    onChoice(MentionChoice(inserted.text, inserted.cursor));
  }

  /// Esc changes no text and permits no acceptance until another edit/trigger.
  void dismiss() {
    if (isDisposed || _dismissed) return;
    _dismissed = true;
    _generation++;
    _awaited = null;
    _syncOpening();
    _syncMatch();
    notifyListeners();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _walking?.cancel();
    _slow?.cancel();
    _matcher.dispose();
    _awaited = null;
    super.dispose();
  }
}

/// Tells the terminal the main session's id to resume, in its user variable
/// `chord_session`, as the id changes: empty while there is none, the id
/// once its `recorded` settles, as `--resume` can open it then; an equal
/// value is not sent again. While the terminal is lent ([away]) nothing is
/// written and nothing counts as told; the value still wanted goes when it
/// comes back. Once [retire]d, as chord exits, nothing more is written.
final class SessionVar {
  /// [write] sets the variable, an empty value for none.
  SessionVar(this._write);
  final void Function(String value) _write;

  // What the terminal was last told, none before the first; what it should
  // be told, as a later id or none overtakes a write pending; what came due
  // while it was lent.
  String? _told, _wanted, _pending, _missed;
  var _away = false, _retired = false;

  void _tell(String value) {
    if (_retired || _told == value) return;
    if (_away) {
      _missed = value;
      return;
    }
    _write(value);
    // A write the window dropped as it went retired this; it told nothing.
    if (!_retired) _told = value;
  }

  /// Whether the terminal is lent; given back, it is told the value still
  /// wanted that came due meanwhile.
  set away(bool away) {
    _away = away;
    if (away) return;
    final missed = _missed;
    _missed = null;
    if (missed != null && missed == _wanted) _tell(missed);
  }

  /// Nothing more is written, a write pending included: the window is
  /// going.
  void retire() => _retired = true;

  /// The main session is now [id], none for null, writable once [recorded]
  /// settles.
  void call(String? id, Future<void> recorded) {
    final value = id ?? '';
    _wanted = value;
    if (value.isEmpty) {
      _tell('');
      return;
    }
    if (_pending == value) return;
    _pending = value;
    recorded.then((_) {
      if (_pending == value) _pending = null;
      if (_wanted == value) _tell(value);
    }, onError: (Object _) {});
  }
}
