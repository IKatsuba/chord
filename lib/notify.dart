/// How chord tells the terminal it waits on the person, from the original's
/// `notify.ts`. The bytes are the framework's `Terminal.notify`; this module
/// says which wait starts, on which channel, in which words. The original's
/// forms and session variable have no source in the port yet, so no event
/// asks for input.
library;

import 'dart:collection';

import 'package:chord_tui/chord_tui.dart'
    show NotificationChannel, tmuxPassthrough, userVariableBytes;

import 'session/conversation.dart';
import 'session/transcript/types.dart';

/// How chord tells the terminal it waits: [auto] picks for the terminal it
/// runs in, [bell] is BEL, [osc9] and [osc777] the two desktop notification
/// escapes, [off] nothing.
enum NotifChannel {
  auto,
  bell,
  osc9,
  osc777,
  off;

  /// The channel a settings value names, or null for none or another.
  static NotifChannel? named(String? name) {
    for (final channel in values) {
      if (channel.name == name) return channel;
    }
    return null;
  }
}

/// What of the environment says which terminal chord is drawing in.
final class TerminalEnv {
  const TerminalEnv({this.termProgram, this.term, this.tmux = false});

  final String? termProgram;
  final String? term;

  /// Inside tmux, which swallows an OSC it does not know.
  final bool tmux;

  @override
  bool operator ==(Object other) =>
      other is TerminalEnv &&
      other.termProgram == termProgram &&
      other.term == term &&
      other.tmux == tmux;

  @override
  int get hashCode => Object.hash(termProgram, term, tmux);
}

/// The terminal [get] reads from the environment.
TerminalEnv terminalEnv(String? Function(String name) get) => TerminalEnv(
  termProgram: get('TERM_PROGRAM'),
  term: get('TERM'),
  tmux: (get('TMUX') ?? '') != '',
);

/// Why chord started waiting on the person.
sealed class Wait {
  const Wait();
}

/// A turn ended.
final class TurnEnded extends Wait {
  const TurnEnded();

  @override
  bool operator ==(Object other) => other is TurnEnded;

  @override
  int get hashCode => (TurnEnded).hashCode;
}

/// A wait on the person's answer: a permission, or a form or link.
sealed class AskingWait extends Wait {
  const AskingWait({this.subagentId});

  /// The subagent or task that asks, when the agent itself does not.
  final String? subagentId;
}

/// A permission the agent asks, named by its [title].
final class PermissionAsk extends AskingWait {
  const PermissionAsk({this.title, super.subagentId});

  final String? title;

  @override
  bool operator ==(Object other) =>
      other is PermissionAsk &&
      other.title == title &&
      other.subagentId == subagentId;

  @override
  int get hashCode => Object.hash(title, subagentId);
}

/// A form to fill in, or a link to open when [url]; [message] is the agent's.
final class InputAsk extends AskingWait {
  const InputAsk(this.message, {this.url = false, super.subagentId});

  final String message;

  /// A link to open, usually a sign-in; a form has none.
  final bool url;

  @override
  bool operator ==(Object other) =>
      other is InputAsk &&
      other.message == message &&
      other.url == url &&
      other.subagentId == subagentId;

  @override
  int get hashCode => Object.hash(message, url, subagentId);
}

/// What the events so far say about waiting: whether the session is live
/// rather than replaying its past, the turns Esc cancelled, the prompts
/// queued to run next, the turns a monitor's event started, and the
/// requests still open.
final class Watch {
  const Watch({
    this.live = false,
    this.cancelled = const {},
    this.queued = const {},
    this.events = const {},
    this.asking = const {},
    this.lasting = const {},
    this.asked = const {},
  });

  final bool live;
  final Set<String> cancelled;
  final Set<String> queued;
  final Set<String> events;
  final Set<String> asking;

  /// Of those, those asked between turns or by a task: kept as the record of
  /// which lasted, as a turn's end leaves every request open.
  final Set<String> lasting;

  /// What each request still open asks, by its id, oldest first.
  final Map<String, AskingWait> asked;

  Watch _with({
    bool? live,
    Set<String>? cancelled,
    Set<String>? queued,
    Set<String>? events,
    Set<String>? asking,
    Set<String>? lasting,
    Map<String, AskingWait>? asked,
  }) => Watch(
    live: live ?? this.live,
    cancelled: cancelled ?? this.cancelled,
    queued: queued ?? this.queued,
    events: events ?? this.events,
    asking: asking ?? this.asking,
    lasting: lasting ?? this.lasting,
    asked: asked ?? this.asked,
  );
}

/// Nothing seen yet.
const emptyWatch = Watch();

/// The name of the terminal user variable the window keeps the main
/// session's id in, for a launcher to reopen it with `--resume`.
const sessionVarName = 'chord_session';

/// The bytes that set `chord_session` to [id], the main session's id to
/// resume, or empty for none: iTerm2's `SetUserVar`, which WezTerm takes
/// too, its value base64 so an id of any shape goes through; inside tmux,
/// through its passthrough.
String sessionVarBytes(String? id, {required bool tmux}) {
  final bytes = userVariableBytes(sessionVarName, id ?? '');
  return tmux ? tmuxPassthrough(bytes) : bytes;
}

/// What the request on screen asks, as the session's box shows it: the
/// oldest permission still open, else the oldest form or link.
AskingWait? askingNow(Watch watch) {
  final open = watch.asked.values;
  return open.whereType<PermissionAsk>().firstOrNull ?? open.firstOrNull;
}

Set<String> _adding(Set<String> set, String item) => {...set, item};
Set<String> _removing(Set<String> set, String item) => {...set}..remove(item);

/// Folds one event into the watch, and says whether it starts a wait. A turn
/// the person cancelled is not a wait they need telling of, nor is one a
/// queued prompt follows at once, nor the turns a resumed session replays,
/// nor one a monitor's event started, as a busy log would ring all day (its
/// end's turn does ring); a second request while one is open is the same
/// wait.
({Watch watch, Wait? wait}) watchWaits(Watch watch, ConversationEvent event) {
  switch (event) {
    case Connected():
      return (watch: watch._with(live: true), wait: null);
    case Cleared():
      return (watch: emptyWatch, wait: null);
    case Queued(:final turnId):
      return (
        watch: watch._with(queued: _adding(watch.queued, turnId)),
        wait: null,
      );
    case QueueWithdrawn():
      return (watch: watch._with(queued: const {}), wait: null);
    case Transcribed(:final action):
      return _watchAction(watch, action);
    default:
      return (watch: watch, wait: null);
  }
}

({Watch watch, Wait? wait}) _watchAction(Watch watch, TranscriptAction action) {
  switch (action) {
    case CancelAction(:final turnId):
      return (
        watch: watch._with(cancelled: _adding(watch.cancelled, turnId)),
        wait: null,
      );
    case PromptAction(:final turnId, :final from):
      final monitor = from?.monitor;
      return (
        watch: watch._with(
          queued: _removing(watch.queued, turnId),
          events: monitor != null && monitor.end == null
              ? _adding(watch.events, turnId)
              : null,
        ),
        wait: null,
      );
    case PermissionRequestedAction(wait: final permission, :final at):
      final wasAsking = watch.asking.isNotEmpty;
      // A task's request comes stamped with when it was asked, as one asked
      // between turns does.
      final lasts = action.between || at != null;
      final wait = PermissionAsk(
        title: permission.title,
        subagentId: permission.subagentId,
      );
      final next = watch._with(
        asking: _adding(watch.asking, permission.id),
        lasting: lasts ? _adding(watch.lasting, permission.id) : null,
        asked: LinkedHashMap.of(watch.asked)..[permission.id] = wait,
      );
      return (watch: next, wait: !watch.live || wasAsking ? null : wait);
    case ElicitationRequestedAction(:final elicitation):
      final wasAsking = watch.asking.isNotEmpty;
      final wait = InputAsk(
        elicitation.message,
        url: elicitation is LinkWait,
        subagentId: elicitation.subagentId,
      );
      final next = watch._with(
        asking: _adding(watch.asking, elicitation.id),
        lasting: elicitation.between
            ? _adding(watch.lasting, elicitation.id)
            : null,
        asked: LinkedHashMap.of(watch.asked)..[elicitation.id] = wait,
      );
      return (watch: next, wait: !watch.live || wasAsking ? null : wait);
    case PermissionSettledAction(:final id) ||
        ElicitationSettledAction(:final id):
      final asking = _removing(watch.asking, id);
      return (
        watch: watch._with(
          asking: asking,
          lasting: _removing(watch.lasting, id),
          asked: LinkedHashMap.fromEntries(
            watch.asked.entries.where((entry) => asking.contains(entry.key)),
          ),
        ),
        wait: null,
      );
    case ResultAction(:final turnId, :final result):
      // Every request still open outlives the turn.
      final next = watch._with(
        cancelled: _removing(watch.cancelled, turnId),
        events: _removing(watch.events, turnId),
      );
      final cancelled = result is TurnAnswered && result.cancelled;
      final waits =
          watch.live &&
          !watch.cancelled.contains(turnId) &&
          !watch.events.contains(turnId) &&
          !cancelled &&
          watch.queued.isEmpty;
      return (watch: next, wait: waits ? const TurnEnded() : null);
    default:
      return (watch: watch, wait: null);
  }
}

/// Terminals that show OSC 9 as a desktop notification.
bool _speaksOsc9(TerminalEnv env) =>
    const ['iTerm.app', 'WezTerm', 'ghostty'].contains(env.termProgram) ||
    const ['xterm-kitty', 'xterm-ghostty'].contains(env.term);

/// Terminals that show OSC 777 but not OSC 9.
bool _speaksOsc777(TerminalEnv env) => env.term?.startsWith('foot') ?? false;

/// The channel [NotifChannel.auto] stands for. Inside tmux it is BEL: tmux
/// drops an OSC it does not know unless `allow-passthrough` is on, which it
/// is not by default, and the terminal outside it cannot be told from the
/// environment.
NotifChannel resolveChannel(NotifChannel channel, TerminalEnv env) {
  if (channel != NotifChannel.auto) return channel;
  if (env.tmux) return NotifChannel.bell;
  return _speaksOsc9(env)
      ? NotifChannel.osc9
      : _speaksOsc777(env)
      ? NotifChannel.osc777
      : NotifChannel.bell;
}

/// What the notification says.
String waitMessage(Wait wait, String agent) => switch (wait) {
  TurnEnded() => '$agent is waiting for your input',
  InputAsk(:final message) => '$agent asks for input: $message',
  PermissionAsk(title: null) => '$agent needs your permission',
  PermissionAsk(:final title?) => '$agent needs your permission: $title',
};

/// One notification for the terminal: `Terminal.notify`'s arguments.
typedef WaitNotification = ({
  String message,
  NotificationChannel channel,
  String title,
});

/// What tells the terminal of [wait], or null for [NotifChannel.off]. OSC
/// 777's title is chord; the framework flattens the text and passes it
/// through tmux.
WaitNotification? notificationOf(
  Wait wait,
  NotifChannel channel,
  TerminalEnv env,
  String agent,
) => switch (resolveChannel(channel, env)) {
  NotifChannel.off || NotifChannel.auto => null,
  NotifChannel.bell => (
    message: '',
    channel: NotificationChannel.bell,
    title: '',
  ),
  NotifChannel.osc9 => (
    message: waitMessage(wait, agent),
    channel: NotificationChannel.osc9,
    title: '',
  ),
  NotifChannel.osc777 => (
    message: waitMessage(wait, agent),
    channel: NotificationChannel.osc777,
    title: 'chord',
  ),
};

/// How the window notifies: the channel settings chose, and the terminal.
final class Notifications {
  const Notifications({this.channel = NotifChannel.auto, required this.env});

  final NotifChannel channel;
  final TerminalEnv env;
}

/// One event in, the watch after it and the notification to give for it, if
/// any: [watchWaits] and [notificationOf] together.
({Watch watch, WaitNotification? notification}) notify(
  Watch watch,
  ConversationEvent event,
  Notifications notifications,
  String agent,
) {
  final seen = watchWaits(watch, event);
  final wait = seen.wait;
  return (
    watch: seen.watch,
    notification: wait == null
        ? null
        : notificationOf(wait, notifications.channel, notifications.env, agent),
  );
}
