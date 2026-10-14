/**
 * What a compaction reads as in the transcript, as Claude Code words its
 * own: `Compacting conversation…` while it runs, in the spinner when there is
 * one, then one line under it, the summary only in ctrl+o's view.
 */
import type {
  Compaction,
  Entry,
  TurnState,
} from '../../session/transcript/types.ts';

/** The words, and how they are drawn: the working line, dim, or an error. */
export interface CompactionLine {
  readonly text: string;
  readonly tone: 'running' | 'done' | 'failed';
}

/**
 * A compaction still running in the turn that is: the spinner says it, as
 * Claude Code's does, and the transcript draws nothing for it until it ends.
 * One outside a turn has no spinner, so the transcript carries it.
 */
export function inSpinner(entry: Entry, turn: TurnState): boolean {
  return (
    entry.kind === 'compaction' &&
    turn.status !== 'idle' &&
    entry.turnId === turn.turnId &&
    compactionLine(entry.compaction, false, undefined).tone === 'running'
  );
}

export function compactionLine(
  compaction: Compaction,
  /** ctrl+o's view is open, so the summary is drawn under the line. */
  expanded: boolean,
  /** The key that opens that view, named while there is a summary to see. */
  expandKey: string | undefined,
): CompactionLine {
  switch (compaction.status) {
    case 'completed': {
      const hint =
        compaction.summary.trim() !== '' &&
        !expanded &&
        expandKey !== undefined;

      return {
        text: hint
          ? `Conversation compacted (${expandKey} for history)`
          : 'Conversation compacted',
        tone: 'done',
      };
    }
    case 'failed':
      return {
        text:
          compaction.error === undefined || compaction.error.trim() === ''
            ? 'Compaction failed'
            : `Compaction failed: ${compaction.error.trim()}`,
        tone: 'failed',
      };
    case 'cancelled':
      return { text: 'Compaction cancelled', tone: 'failed' };
    // `in_progress`, or a status ACP may add later, which is not an ending.
    default:
      return { text: 'Compacting conversation…', tone: 'running' };
  }
}
