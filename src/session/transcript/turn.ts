/**
 * The turn itself: its prompt, a cancel asked for, the agent's answer that
 * settles it, and the agent going away under its subagents.
 */
import { endRunning, findSubagent, isRunning } from './subagents.ts';
import type {
  Entry,
  MessageFrom,
  PermissionWait,
  TeamPart,
  Transcript,
  TurnResult,
  TurnState,
} from './types.ts';

/**
 * A turn starts on the person's prompt, or on a message, which draws as one
 * of its own, after the team part that went ahead of it, if one did. A task
 * agent's requests asked between turns go on waiting in the new one. A
 * message put `into` a running turn starts none: it draws where it went in,
 * among that turn's work.
 */
export function prompted(
  state: Transcript,
  turnId: string,
  text: string,
  at: number,
  from?: MessageFrom,
  team?: TeamPart,
  into?: string,
): Transcript {
  const owner = into ?? turnId;
  const entry: Entry =
    from === undefined
      ? { kind: 'user', turnId: owner, text }
      : { kind: 'message', turnId: owner, from, text };
  const added: Entry[] =
    team === undefined
      ? [entry]
      : [{ kind: 'team_part', turnId: owner, part: team }, entry];

  if (into !== undefined) {
    return { ...state, entries: [...state.entries, ...added] };
  }

  const waiting =
    state.turn.status === 'awaiting_permission' ? state.turn.permissions : [];

  return {
    ...state,
    entries: [...state.entries, ...added],
    turn:
      waiting.length > 0
        ? {
            status: 'awaiting_permission',
            turnId,
            since: at,
            permissions: waiting,
          }
        : { status: 'working', turnId, since: at },
  };
}

/**
 * A cycle the agent began on its own: working, as a turn is, with nothing of
 * the person's to draw. The permissions it found waiting stay, held as they
 * were, as the person did not start it (the owner's Q48, CHD-426).
 */
export function cycleStarted(
  state: Transcript,
  turnId: string,
  at: number,
): Transcript {
  const { turn } = state;

  return {
    ...state,
    turn:
      turn.status === 'awaiting_permission' && turn.permissions.length > 0
        ? { ...turn, turnId, cycle: true }
        : { status: 'working', turnId, since: at, cycle: true },
  };
}

/**
 * The requests a turn leaves waiting as it ends: those of task agents still
 * running, which outlive it.
 */
export function taskWaits(
  state: Transcript,
  waits: readonly PermissionWait[],
): PermissionWait[] {
  return waits.filter(
    (wait) =>
      wait.subagentId !== undefined &&
      state.entries.some(
        (entry) =>
          entry.kind === 'subagent' &&
          entry.subagent.task !== undefined &&
          entry.subagent.state === 'running' &&
          (entry.subagent.id === wait.subagentId ||
            findSubagent(entry.subagent.entries, wait.subagentId!) !==
              undefined),
      ),
  );
}

export function cancelled(
  state: Transcript,
  turnId: string,
  at: number,
): Transcript {
  const { turn } = state;

  if (!isCurrent(turn, turnId) || turn.status === 'cancelling') {
    return state;
  }

  return {
    ...state,
    turn: {
      status: 'cancelling',
      turnId: turn.turnId,
      since: turn.since,
      cancelledAt: at,
    },
  };
}

export function disconnected(
  state: Transcript,
  at: number | undefined,
): Transcript {
  // An untracked one is gone with its agent too: it can no longer be at work.
  const entries = endRunning(
    state.entries,
    'disconnected',
    at,
    (subagent) => isRunning(subagent) || subagent.state === 'untracked',
  );

  return entries === state.entries ? state : { ...state, entries };
}

export function isCurrent(
  turn: TurnState,
  turnId: string,
): turn is Exclude<TurnState, { status: 'idle' }> {
  return turn.status !== 'idle' && turn.turnId === turnId;
}

export function settle(
  state: Transcript,
  turnId: string,
  result: TurnResult,
): Transcript {
  if (!isCurrent(state.turn, turnId)) {
    const ending = endingOf(turnId, result);

    return ending === undefined
      ? state
      : { ...state, entries: [...state.entries, ending] };
  }

  const { since } = state.turn;

  // A cancel stops the turn's subagents with it, as the adapters' draft
  // form does, which says so too, perhaps only after the turn's answer. One
  // that can be cancelled alone is left for its agent to report: it may live
  // on, as a background one does. Those still running after a turn that
  // ended on its own are left: they may outlive it.
  if (result.status === 'cancelled') {
    state = {
      ...state,
      entries: endRunning(
        state.entries,
        'cancelled',
        state.turn.status === 'cancelling' ? state.turn.cancelledAt : undefined,
        (subagent) => isRunning(subagent) && subagent.cancellable !== true,
      ),
    };
  }

  // A finished plan moves from above the prompt into the transcript, as the
  // turn's record of what it did; an unfinished one stays live for the next.
  const finished =
    state.plan.length > 0 &&
    state.plan.every((entry) => entry.status === 'completed');
  const ending = endingOf(turnId, result);
  const added: Entry[] = [
    ...(finished
      ? [{ kind: 'plan' as const, turnId, entries: state.plan }]
      : []),
    ...(ending === undefined ? [] : [ending]),
  ];
  // The same array when nothing is added: a new one reads as news.
  const entries =
    added.length === 0 ? state.entries : [...state.entries, ...added];

  // Every permission still open outlives the turn: a task agent's as the
  // task does, and the agent's own, which still waits on the person, now
  // between turns (the owner's Q44, CHD-158).
  const kept =
    state.turn.status === 'awaiting_permission' ? state.turn.permissions : [];
  // So does every form, question or link, the agent's own now asked between
  // turns (the owner's Q53).
  const asking = state.asking.map((wait) =>
    wait.subagentId === undefined && wait.between !== true
      ? { ...wait, between: true as const }
      : wait,
  );

  return {
    ...state,
    entries,
    plan: finished ? [] : state.plan,
    turn:
      kept.length > 0
        ? {
            status: 'awaiting_permission',
            turnId,
            since,
            permissions: kept,
            between: true,
          }
        : { status: 'idle' },
    asking,
  };
}

function endingOf(turnId: string, result: TurnResult): Entry | undefined {
  switch (result.status) {
    case 'failed':
      return {
        kind: 'error',
        turnId,
        message: result.error.message,
        ...(result.error.code === undefined ? {} : { code: result.error.code }),
      };
    case 'cancelled':
      return { kind: 'cancelled', turnId };
    case 'completed':
      return result.stopReason === 'end_turn'
        ? undefined
        : { kind: 'stopped', turnId, reason: result.stopReason };
  }
}
