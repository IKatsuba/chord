/**
 * Where each agent of the window stands with the person: what it asks,
 * what of it is not yet seen, whether it works, as the agents list, the
 * status line, the attention order and notifications read it (CHD-493).
 */
import {
  askingNow,
  type AskingWait,
  emptyWatch,
  type Wait,
  type Watch,
  watchWaits,
} from '../notify.ts';
import type { ConversationEvent } from './conversation.ts';
import { senderName } from './tasks.ts';

/** What a session waits on the person for: a permission, or a form or link. */
export type Asking = AskingWait;

/**
 * Where one agent stands with the person, as the agents list and the
 * attention order read it. Times are epoch milliseconds.
 */
export interface AgentWait {
  /** What `notify.ts` has folded of the session's events so far. */
  readonly watch: Watch;
  /**
   * A permission or form open in it, and since when; kept while the agent
   * is shown too, as it lasts until it is answered.
   */
  readonly asking?: { readonly on: Asking; readonly since: number } | undefined;
  /**
   * A turn that ended, or failed, or an agent that never came up, while the
   * agent was not shown, or a message from another agent that came in then,
   * and since when; gone once the person goes to it.
   */
  readonly unseen?:
    | {
        readonly kind: 'replied' | 'failed' | 'message';
        readonly since: number;
        /** Who a message came from, by the name its row gives. */
        readonly from?: string;
        /** A failure's cause, the gravest seen since it was last looked at. */
        readonly failure?: Failure;
        /**
         * When the first failure came, which a failed turn counts its time
         * from; `since` is the first news of any kind, for the order.
         */
        readonly failedAt?: number;
        /**
         * When the newest reply came, which its age counts from (CHD-364),
         * apart from `since`, which orders the news.
         */
        readonly repliedAt?: number;
      }
    | undefined;
  /**
   * A turn that ended or failed, or an agent that never came up, in front or
   * not, as the terminal's status reports it (CHD-382): gone once the person
   * goes to the agent, presses a key while it is shown, or its next turn
   * starts. `failure` as `unseen`'s is.
   */
  readonly ended?: { readonly failure?: Failure } | undefined;
  /** When the turn running now began, while one runs. */
  readonly working?: number | undefined;
  /**
   * When its agent last stopped working: its turn's or own cycle's end,
   * else when it came up, which an idle agent's time counts from (CHD-471).
   */
  readonly stopped?: number | undefined;
  /** Its agent has exited. */
  readonly exited?: true;
}

/**
 * What failed: the agent's process exited, the agent never came up, or a
 * turn failed with the agent still open, gravest first.
 */
export type Failure = 'exited' | 'start' | 'turn';

export const FAILURES: readonly Failure[] = ['exited', 'start', 'turn'];

/** The graver of two failures. */
function graver(a: Failure | undefined, b: Failure): Failure {
  return a !== undefined && FAILURES.indexOf(a) < FAILURES.indexOf(b) ? a : b;
}

/** When a wait's reply came, which `replied … ago` counts from. */
export function repliedSince(wait: AgentWait): number | undefined {
  return wait.unseen?.kind === 'replied'
    ? (wait.unseen.repliedAt ?? wait.unseen.since)
    : undefined;
}

/** When a wait's failure came, which a failed turn counts its time from. */
export function failedSince(wait: AgentWait): number | undefined {
  return wait.unseen?.kind === 'failed'
    ? (wait.unseen.failedAt ?? wait.unseen.since)
    : undefined;
}

/** A wait's failure, if it has one: an exit, while the agent is gone, first. */
export function failureOf(wait: AgentWait): Failure | undefined {
  if (wait.unseen?.kind !== 'failed') {
    return undefined;
  }

  return wait.exited ? 'exited' : (wait.unseen.failure ?? 'turn');
}

export const idle: AgentWait = { watch: emptyWatch };

/**
 * Folds one of an agent's events into its wait, `front` while it is the
 * one shown, and says the wait it starts, if any, as `notify.ts` classes
 * waits.
 */
export function heardWait(
  before: AgentWait,
  event: ConversationEvent,
  now: number,
  { front }: { readonly front: boolean },
): { readonly wait: AgentWait; readonly started?: Wait } {
  const watched = watchWaits(before.watch, event);
  const wait = waitAfter(before, watched.watch, event, watched.wait, now, {
    front,
  });

  return watched.wait === undefined
    ? { wait }
    : { wait, started: watched.wait };
}

function waitAfter(
  before: AgentWait,
  watch: Watch,
  event: ConversationEvent,
  started: Wait | undefined,
  now: number,
  { front }: { readonly front: boolean },
): AgentWait {
  if (event.type === 'cleared') {
    return idle;
  }

  const asking =
    started !== undefined && started.kind !== 'turn_ended'
      ? { on: started, since: now }
      : watch.asking.size === 0 || before.asking === undefined
        ? undefined
        : // Still waiting since it began, on whichever request is the oldest
          // still open: the one answered may have been another's (CHD-431).
          { ...before.asking, on: askingNow(watch) ?? before.asking.on };
  // An exit is news even with no turn running: the agent is gone.
  const failed =
    event.type === 'connect_failed' ||
    event.type === 'disconnected' ||
    (started?.kind === 'turn_ended' &&
      event.type === 'result' &&
      event.result.status === 'failed');
  const ended = failed || started?.kind === 'turn_ended';
  const from =
    (event.type === 'prompt' || event.type === 'queued') && !front
      ? event.from && senderName(event.from)
      : undefined;
  // A failure outranks a reply of the same agent, and the wait counts from the
  // first of them; the reply to a message says more than the message did.
  const exits = event.type === 'disconnected' || before.exited === true;
  const failure =
    failed || before.unseen?.kind === 'failed'
      ? graver(
          before.unseen?.failure,
          exits ? 'exited' : event.type === 'connect_failed' ? 'start' : 'turn',
        )
      : undefined;
  const unseen = front
    ? before.unseen
    : ended
      ? failure === undefined
        ? {
            kind: 'replied' as const,
            since: before.unseen?.since ?? now,
            // The newest reply: a reply has no first to look into.
            repliedAt: now,
          }
        : {
            kind: 'failed' as const,
            since: before.unseen?.since ?? now,
            failure,
            failedAt:
              before.unseen?.kind === 'failed'
                ? (before.unseen.failedAt ?? before.unseen.since)
                : now,
          }
      : from !== undefined &&
          before.unseen?.kind !== 'failed' &&
          before.unseen?.kind !== 'replied'
        ? {
            kind: 'message' as const,
            from,
            since: before.unseen?.since ?? now,
          }
        : before.unseen;
  const failedNow = failed
    ? exits
      ? 'exited'
      : event.type === 'connect_failed'
        ? 'start'
        : 'turn'
    : undefined;
  const endedFailure =
    failedNow === undefined
      ? before.ended?.failure
      : graver(before.ended?.failure, failedNow);
  // The next turn's start leaves the last one's end behind.
  const endedNow =
    event.type === 'prompt' || event.type === 'cycle_started'
      ? undefined
      : ended
        ? endedFailure === undefined
          ? {}
          : { failure: endedFailure }
        : before.ended;
  // A cycle of the agent's own works as a turn does (CHD-426).
  const working =
    event.type === 'prompt' || event.type === 'cycle_started'
      ? (before.working ?? event.at)
      : event.type === 'result' || event.type === 'connect_failed'
        ? undefined
        : before.working;
  const stopped =
    before.working !== undefined && working === undefined
      ? now
      : event.type === 'connected' && before.stopped === undefined
        ? now
        : before.stopped;

  return {
    watch,
    asking,
    unseen,
    ...(endedNow === undefined ? {} : { ended: endedNow }),
    working,
    ...(stopped === undefined ? {} : { stopped }),
    // A connection after an exit is the agent up again: an exit the
    // session's past replays on resume, or one before a restart, is not
    // what the agent does now (CHD-510).
    ...(event.type === 'disconnected' ||
    (before.exited === true && event.type !== 'connected')
      ? { exited: true as const }
      : {}),
  };
}
