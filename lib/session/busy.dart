/// What makes a session busy, so that closing it asks for a second press:
/// the request it puts to the person, the person's own prompts behind its
/// turn, the task agents it started, and the turn or a bash-mode command
/// running. The original's `session/busy.ts`.
library;

import 'conversation.dart' show QueuedPrompt;
import 'transcript/types.dart';

/// Why a session is busy, the most pressing reason first.
sealed class Busy {
  const Busy();
}

/// It waits for the person's permission.
final class BusyPermission extends Busy {
  const BusyPermission();
}

/// It asks the person for input: a form, questions or a link.
final class BusyInput extends Busy {
  const BusyInput();
}

/// [count] of the person's own prompts wait behind its turn.
final class BusyQueued extends Busy {
  const BusyQueued(this.count);

  final int count;
}

/// [count] task agents it started are still running.
final class BusyTasks extends Busy {
  const BusyTasks(this.count);

  final int count;
}

/// Its turn, or a bash-mode command it ran, is running.
final class BusyWorking extends Busy {
  const BusyWorking();
}

/// The person's own among [queue], which Esc takes back: no message from
/// another agent, nothing steered or taken into the turn.
List<QueuedPrompt> mine(List<QueuedPrompt> queue) => [
  for (final queued in queue)
    if (queued.from == null && !queued.steering && !queued.taken) queued,
];

/// Why closing a session with [transcript] and [queue] would cut something
/// short; none while it is idle.
Busy? busyOf(Transcript transcript, List<QueuedPrompt> queue) {
  if (transcript.turn is AwaitingPermission) return const BusyPermission();
  // A form or link is on screen once no plan waits before it, as the
  // original's askedInput.
  if (transcript.asking.isNotEmpty &&
      !transcript.planAsks.any((ask) => ask.answer == null)) {
    return const BusyInput();
  }
  final prompts = mine(queue).length;
  if (prompts > 0) return BusyQueued(prompts);
  // The tasks come before the turn as they say more: closing would stop
  // them too.
  final tasks = runningTasks(transcript);
  if (tasks > 0) return BusyTasks(tasks);
  // A bash-mode command the session ran is its work as much as a turn is.
  final command = transcript.entries.any(
    (entry) => entry is ShellEntry && entry.run.running,
  );
  return transcript.turn is Idle && !command ? null : const BusyWorking();
}

/// How many task agents the session started are still running.
int runningTasks(Transcript transcript) => [
  for (final entry in transcript.entries)
    if (entry is SubagentEntry &&
        entry.subagent.task != null &&
        entry.subagent.state == SubagentState.running)
      entry,
].length;
