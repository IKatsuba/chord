/**
 * Prompts sent while a turn runs: what waits behind the turn, how it is drawn
 * under the working line, and the draft it becomes again when Esc interrupts.
 * The prompts themselves wait in the conversation (`src/session/conversation.ts`),
 * which sends each once the turn ahead has ended; this is what the window
 * knows of them.
 */
import type { MessageFrom } from '../../session/transcript/types.ts';
import { queuedMessage } from '../transcript/message.ts';
import type { PastedImage } from './images.ts';

/** A prompt held behind the turn in flight, by the turn it will be. */
export interface Queued {
  readonly turnId: string;
  readonly text: string;
  /**
   * The held shell runs that went with it, by id: an interrupt that takes it
   * back before it starts holds them again, so the output is not lost.
   */
  readonly held?: readonly string[];
  /** The images that went with it, back in the draft if it comes back. */
  readonly images?: readonly PastedImage[];
  /**
   * Set on a message from another agent, or chord, which is not the
   * person's: an interrupt never puts it in the draft.
   */
  readonly from?: MessageFrom;
  /**
   * A message waiting for the person's answer to go into the running turn,
   * rather than for the turn's end.
   */
  readonly afterAnswer?: true;
  /**
   * A message waiting for the running turn's open tool calls to end before
   * it goes into the turn (CHD-423).
   */
  readonly afterCalls?: true;
  /**
   * The person's steer out with the agent, unanswered for a while: Esc
   * leaves it, as it is no longer in the window's hands (CHD-378).
   */
  readonly steering?: true;
}

export type QueueRow =
  /**
   * The person's prompt; one held behind a request between turns says so
   * first, in `header` (CHD-158).
   */
  | { readonly kind: 'prompt'; readonly text: string; readonly header?: string }
  /**
   * A message, drawn after `←`: its header whole, then its text, which
   * alone is cut to the width.
   */
  | {
      readonly kind: 'message';
      readonly header: string;
      readonly text: string;
    }
  /** Prompts past the last row that fits. */
  | { readonly kind: 'more'; readonly count: number };

/** `queue` with `turnId`'s prompt gone, as it is once its turn starts. */
export function started(
  queue: readonly Queued[],
  turnId: string,
): readonly Queued[] {
  return queue.some((queued) => queued.turnId === turnId)
    ? queue.filter((queued) => queued.turnId !== turnId)
    : queue;
}

/**
 * The prompt box after an interrupt, as Claude Code leaves it: the prompts
 * that waited, oldest first, then what was being typed, a line each.
 */
export function restoredDraft(queue: readonly Queued[], draft: string): string {
  return [...mine(queue).map(({ text }) => text), draft]
    .filter((text) => text !== '')
    .join('\n');
}

/** The person's own prompts among `queue`, which Esc takes back. */
export function mine(queue: readonly Queued[]): readonly Queued[] {
  return queue.filter(
    (queued) => queued.from === undefined && queued.steering === undefined,
  );
}

/** The queue's share of a window `rows` tall, never under two rows. */
export function queueRowLimit(rows: number): number {
  return Math.max(2, Math.floor(rows / 6));
}

/**
 * The rows to draw in at most `limit`: one per prompt, its first line only,
 * marked `…` where it has more; past the limit the newest fold to
 * `… +N more`, since the oldest goes next.
 */
/** Ahead of a prompt held for the person's answer to a request. */
const AFTER_ANSWER = 'after your answer: ';
/** Ahead of a steered prompt held for the turn's open calls (CHD-378). */
const AFTER_CALLS = 'after the running calls: ';
/** Ahead of a steered prompt out with the agent, not answered yet. */
const STEERING = 'into the running turn: ';

export function queueRows(queue: readonly Queued[], limit: number): QueueRow[] {
  const rows = queue.map(
    ({ text, from, afterAnswer, afterCalls, steering }): QueueRow => {
      if (from !== undefined) {
        return {
          kind: 'message',
          ...queuedMessage(
            from,
            text,
            afterAnswer ? 'answer' : afterCalls ? 'calls' : undefined,
          ),
        };
      }

      const [first = '', ...rest] = text.split('\n');

      return {
        kind: 'prompt',
        text: rest.length > 0 ? `${first} …` : first,
        ...(steering
          ? { header: STEERING }
          : afterAnswer
            ? { header: AFTER_ANSWER }
            : afterCalls
              ? { header: AFTER_CALLS }
              : {}),
      };
    },
  );

  if (rows.length <= limit) {
    return rows;
  }

  return [
    ...rows.slice(0, limit - 1),
    { kind: 'more', count: rows.length - limit + 1 },
  ];
}
