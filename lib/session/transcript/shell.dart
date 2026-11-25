import '../context.dart' as context;
import 'entries.dart';
import 'types.dart';

/// Folds one local shell action without changing the agent's turn.
Transcript reduceShell(Transcript state, TranscriptAction action) {
  if (action is ShellStartedAction) {
    return state.withEntries(
      appended(state.entries, [
        ShellEntry(
          action.turnId,
          ShellRun(command: action.command, running: true),
        ),
      ]),
    );
  }
  if (action is ShellReplayedAction) {
    return state.withEntries(
      appended(state.entries, [ShellEntry(action.turnId, action.run)]),
    );
  }
  final at = state.entries.indexWhere(
    (entry) => entry is ShellEntry && entry.turnId == action.turnId,
  );
  if (at < 0) return state;
  final entry = state.entries[at] as ShellEntry, run = entry.run;
  if (!run.running) return state;
  ShellRun next;
  if (action is ShellOutputAction) {
    final kept = action.stderr ? run.stderr : run.stdout;
    final room = (context.outputLimit - kept.length).clamp(
      0,
      context.outputLimit,
    );
    final text =
        kept + action.text.substring(0, action.text.length.clamp(0, room));
    next = ShellRun(
      command: run.command,
      running: true,
      stdout: action.stderr ? run.stdout : text,
      stderr: action.stderr ? text : run.stderr,
      code: run.code,
      stopped: run.stopped,
      error: run.error,
      truncated: run.truncated || action.text.length > room || room == 0,
    );
  } else if (action is ShellEndedAction) {
    next = ShellRun(
      command: run.command,
      stdout: run.stdout,
      stderr: run.stderr,
      running: false,
      code: action.code ?? run.code,
      stopped: action.stopped || run.stopped,
      error: action.error ?? run.error,
      truncated: run.truncated,
    );
  } else {
    return state;
  }
  return state.withEntries(
    replacedAt(state.entries, at, ShellEntry(entry.turnId, next)),
  );
}
