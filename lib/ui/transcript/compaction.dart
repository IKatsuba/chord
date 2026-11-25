/// What a compaction reads as in the transcript, as Claude Code words its
/// own: `Compacting conversation…` while it runs, in the spinner when there
/// is one, then one line under it, the summary only in ctrl+o's view. One
/// the agent ran on its own says so, `while idle`. The original's
/// `ui/transcript/compaction.ts`.
library;

import '../../session/transcript/types.dart';

/// How a compaction's line is drawn: the working line, dim, or an error.
enum CompactionTone { running, done, failed }

/// A compaction's words and how they are drawn.
typedef CompactionLine = ({String text, CompactionTone tone});

/// The running turn's id, none while idle.
String? _turnIdOf(TurnState turn) => switch (turn) {
  Idle() => null,
  Working(:final turnId) ||
  AwaitingPermission(:final turnId) ||
  Cancelling(:final turnId) => turnId,
};

/// Whether [entry] is a compaction still running in the turn that is: the
/// spinner says it, as Claude Code's does, and the transcript draws nothing
/// for it until it ends. One outside a turn has no spinner, so the
/// transcript carries it. An unasked one still running when a turn starts
/// is that turn's: the agent holds the prompt behind it, so the turn is
/// compacting.
bool inSpinner(Entry entry, TurnState turn) {
  final turnId = _turnIdOf(turn);
  return entry is CompactionEntry &&
      turnId != null &&
      (entry.turnId == turnId || entry.compaction.unasked) &&
      compactionLine(entry.compaction, false, null).tone ==
          CompactionTone.running;
}

/// [compaction]'s line; [expanded] when ctrl+o's view is open, so the
/// summary is drawn under it, and [expandKey] the key that opens that
/// view, named while there is a summary to see.
CompactionLine compactionLine(
  Compaction compaction,
  bool expanded,
  String? expandKey,
) {
  final idle = compaction.unasked ? ' while idle' : '';
  switch (compaction.status) {
    case 'completed':
      final hint =
          compaction.summary.trim().isNotEmpty &&
          !expanded &&
          expandKey != null;
      return (
        text: hint
            ? 'Conversation compacted$idle ($expandKey for history)'
            : 'Conversation compacted$idle',
        tone: CompactionTone.done,
      );
    case 'failed':
      final error = compaction.error?.trim() ?? '';
      return (
        text: error.isEmpty
            ? 'Compaction failed$idle'
            : 'Compaction failed$idle: $error',
        tone: CompactionTone.failed,
      );
    case 'cancelled':
      return (text: 'Compaction cancelled$idle', tone: CompactionTone.failed);
    // `in_progress`, or a status ACP may add later, which is not an ending.
    default:
      return (
        text: 'Compacting conversation$idle…',
        tone: CompactionTone.running,
      );
  }
}
