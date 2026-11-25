// Closing an agent of the session's and quitting: the status line's words
// while the second press is waited for, as the original's
// src/ui/app/closing.ts.
import '../../session/busy.dart';

/// What the agent is doing, after its name.
String _doing(Busy busy) => switch (busy) {
  BusyPermission() => 'waits for your permission',
  BusyInput() => 'asks for input',
  BusyQueued(:final count) =>
    'has $count ${count == 1 ? 'prompt' : 'prompts'} queued',
  BusyTasks(:final count) =>
    'has $count task ${count == 1 ? 'agent' : 'agents'} running',
  BusyWorking() => 'is working',
};

/// The line a first `x` on a busy child in the list leaves: `parser is
/// working · x again to stop it and close`; [key] is the one bound to
/// `agents:close`.
String agentCloseArmedLine(String name, Busy busy, String key) =>
    '$name ${_doing(busy)} · $key again to stop it and close';

/// The status line while Ctrl+C waits for the second press.
String ctrlCArmedLine() => 'Press ctrl+c again to quit';

/// What the status line says of `agents:close` on `main`, which it never
/// closes.
const mainCloseNote = 'main is the session · ctrl+d quits';

/// What `agents:close` in the list does to the agent picked.
enum AgentClose {
  /// `main` is picked: nothing closes, and [mainCloseNote] says why.
  note,

  /// A busy child, not yet armed: a second press is waited for.
  arm,

  /// The child closes.
  close,
}

/// `agents:close` on the picked agent: a [child] or `main`, [busy] as its
/// session is, [armed] when the press before was on this child.
AgentClose agentClose({
  required bool child,
  required Busy? busy,
  required bool armed,
}) => !child
    ? AgentClose.note
    : busy != null && !armed
    ? AgentClose.arm
    : AgentClose.close;

/// The line a first `x` on a busy team's lead leaves, its members closing
/// with it: `bugfix and its 3 members are working · x again to stop them
/// and close`.
String teamCloseArmedLine(String name, int members, String key) =>
    '$name and its ${members == 1 ? 'member' : '$members members'} are '
    'working · $key again to stop them and close';
