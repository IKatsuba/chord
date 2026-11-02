/**
 * What makes a session busy, so that closing it asks for a second press: the
 * form or link it asks for, the person's own prompts behind its turn and the
 * task agents it started.
 */
import type {
  ElicitationWait,
  MessageFrom,
  Transcript,
} from './transcript/types.ts';

/** Whose a prompt held behind the turn in flight is. */
export interface QueuedFrom {
  readonly turnId: string;
  /**
   * Set on a message from another agent, or chord, which is not the
   * person's: an interrupt never puts it in the draft.
   */
  readonly from?: MessageFrom;
  /**
   * The person's steer out with the agent, unanswered for a while: Esc
   * leaves it, as it is no longer in the window's hands (CHD-378).
   */
  readonly steering?: true;
  /**
   * The person's message Tab sent into the running turn, not yet answered:
   * Esc leaves it, though its row reads as queued for a while (CHD-535).
   */
  readonly taken?: true;
}

/** The person's own prompts among `queue`, which Esc takes back. */
export function mine<Queued extends QueuedFrom>(
  queue: readonly Queued[],
): readonly Queued[] {
  return queue.filter(
    (queued) =>
      queued.from === undefined &&
      queued.steering === undefined &&
      queued.taken === undefined,
  );
}

/**
 * The form or link on screen: the oldest the turn asks for, once no
 * permission is asked, as that prompt answers first.
 */
export function askedInput(
  transcript: Transcript,
): ElicitationWait | undefined {
  return transcript.turn.status === 'awaiting_permission' ||
    (transcript.planAsks ?? []).some((ask) => ask.answer === undefined)
    ? undefined
    : transcript.asking[0];
}

/**
 * Why a session is busy, the most pressing reason first: a person is asked
 * for something, prompts wait behind the turn, task agents it started run,
 * or the turn or a bash-mode command runs. The tasks come before the turn
 * as they say more: closing would stop them too.
 */
export type Busy =
  | { readonly kind: 'permission' }
  | { readonly kind: 'input' }
  | { readonly kind: 'queued'; readonly count: number }
  | { readonly kind: 'tasks'; readonly count: number }
  | { readonly kind: 'working' };

/** How many task agents the session started are still running. */
export function runningTasks(transcript: Transcript): number {
  return transcript.entries.filter(
    (entry) =>
      entry.kind === 'subagent' &&
      entry.subagent.task !== undefined &&
      entry.subagent.state === 'running',
  ).length;
}

/** Why closing `session` would cut something short; none while it is idle. */
export function busyOf<Queued extends QueuedFrom>(session: {
  readonly transcript: Transcript;
  readonly queue: readonly Queued[];
}): Busy | undefined {
  const { transcript, queue } = session;

  if (transcript.turn.status === 'awaiting_permission') {
    return { kind: 'permission' };
  }

  if (askedInput(transcript) !== undefined) {
    return { kind: 'input' };
  }

  // The person's own; a message queued goes with the work that sent it.
  const prompts = mine(queue).length;

  if (prompts > 0) {
    return { kind: 'queued', count: prompts };
  }

  const tasks = runningTasks(transcript);

  if (tasks > 0) {
    return { kind: 'tasks', count: tasks };
  }

  // A bash-mode command the session ran is its work as much as a turn is.
  const commandRuns = transcript.entries.some(
    (entry) => entry.kind === 'shell' && entry.run.running,
  );

  return transcript.turn.status === 'idle' && !commandRuns
    ? undefined
    : { kind: 'working' };
}
