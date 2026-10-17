/**
 * What a turn asks the person: a permission, waited on in the turn's status,
 * and a form or link, waited on beside it; each answer leaves its record.
 */
import { changeSubagent, findSubagent } from './subagents.ts';
import { isCurrent, taskWaits } from './turn.ts';
import type {
  ElicitationAnswer,
  ElicitationWait,
  Entry,
  PermissionAnswer,
  PermissionWait,
  Transcript,
} from './types.ts';

export function permissionRequested(
  state: Transcript,
  turnId: string,
  asked: PermissionWait,
  at = 0,
): Transcript {
  const { turn } = state;
  // A subagent's request keeps when it came, which a task's row counts from.
  const permission = asked.subagentId === undefined ? asked : { ...asked, at };

  // A task agent outlives the turn that started it, and may ask between
  // turns; the session waits on the person until it is answered.
  if (turn.status === 'idle' && taskWaits(state, [permission]).length > 0) {
    return {
      ...state,
      turn: {
        status: 'awaiting_permission',
        turnId,
        since: at,
        permissions: [permission],
        between: true,
      },
    };
  }

  if (
    turn.status === 'awaiting_permission' &&
    turn.between &&
    taskWaits(state, [permission]).length > 0 &&
    !turn.permissions.some((wait) => wait.id === permission.id)
  ) {
    return {
      ...state,
      turn: { ...turn, permissions: [...turn.permissions, permission] },
    };
  }

  if (!isCurrent(turn, turnId) || turn.status === 'cancelling') {
    return state;
  }

  const waiting = turn.status === 'awaiting_permission' ? turn.permissions : [];

  if (waiting.some((wait) => wait.id === permission.id)) {
    return state;
  }

  return {
    ...state,
    turn: {
      status: 'awaiting_permission',
      turnId,
      since: turn.since,
      permissions: [...waiting, permission],
    },
  };
}

export function permissionSettled(
  state: Transcript,
  turnId: string,
  id: string,
  answer: PermissionAnswer,
): Transcript {
  const { turn } = state;

  // Found by its id alone: a task agent's request may have been asked in an
  // earlier turn than the one it is answered in.
  if (turn.status !== 'awaiting_permission') {
    return state;
  }

  const wait = turn.permissions.find((candidate) => candidate.id === id);

  if (!wait) {
    return state;
  }

  const permissions = turn.permissions.filter((other) => other !== wait);
  const option =
    answer.type === 'chosen'
      ? wait.options.find((candidate) => candidate.optionId === answer.optionId)
      : undefined;
  // chord's own question is answered on the call that asked it.
  const entry: Entry | undefined =
    answer.type === 'withdrawn' || wait.save !== undefined
      ? undefined
      : {
          kind: 'permission',
          turnId,
          ...(wait.title === undefined ? {} : { title: wait.title }),
          ...(option === undefined ? {} : { option }),
        };
  // A subagent's answer is part of its work, not its parent's.
  const asker = wait.subagentId;
  const entries =
    entry === undefined
      ? state.entries
      : asker !== undefined && findSubagent(state.entries, asker)
        ? changeSubagent(state.entries, asker, (subagent) => ({
            ...subagent,
            entries: [...subagent.entries, entry],
          }))
        : [...state.entries, entry];

  return {
    ...state,
    entries,
    turn:
      permissions.length > 0
        ? { ...turn, permissions }
        : turn.between
          ? { status: 'idle' }
          : { status: 'working', turnId: turn.turnId, since: turn.since },
  };
}

export function elicitationRequested(
  state: Transcript,
  turnId: string,
  elicitation: ElicitationWait,
): Transcript {
  const { turn } = state;

  const outside = elicitation.subagentId !== undefined;

  if (
    (!outside && (!isCurrent(turn, turnId) || turn.status === 'cancelling')) ||
    state.asking.some((wait) => wait.id === elicitation.id)
  ) {
    return state;
  }

  return {
    ...state,
    entries: askedIn(state.entries, elicitation),
    asking: [...state.asking, elicitation],
  };
}

/**
 * `entries` with the tool call a box of questions came out of marked as
 * asked there, from when the box opens: it reads as asking while the person
 * answers, and the box's record stands in for its own lines.
 */
function askedIn(
  entries: readonly Entry[],
  wait: ElicitationWait,
): readonly Entry[] {
  const id =
    wait.mode === 'form' && wait.questions !== undefined
      ? wait.toolCallId
      : undefined;

  if (id === undefined) {
    return entries;
  }

  const mark = (list: readonly Entry[]): readonly Entry[] => {
    const index = list.findLastIndex(
      (entry) => entry.kind === 'tool' && entry.call.id === id,
    );
    const found = list[index];

    return found?.kind === 'tool'
      ? list.with(index, { ...found, call: { ...found.call, asked: true } })
      : list;
  };

  // A task's question is its own call's, among its own work: a call of the
  // session's with the same id is another.
  return wait.subagentId === undefined
    ? mark(entries)
    : changeSubagent(entries, wait.subagentId, (subagent) => {
        const marked = mark(subagent.entries);

        return marked === subagent.entries
          ? subagent
          : { ...subagent, entries: marked };
      });
}

/** The person's answer to a form or link, or its withdrawal, as a record. */
export function elicitationSettled(
  state: Transcript,
  turnId: string,
  id: string,
  answer: ElicitationAnswer,
): Transcript {
  const wait = state.asking.find((candidate) => candidate.id === id);

  if (
    !wait ||
    (wait.subagentId === undefined && !isCurrent(state.turn, turnId))
  ) {
    return state;
  }

  const entry: Entry = {
    kind: 'elicitation',
    turnId,
    wait,
    outcome: answer.type === 'withdrawn' ? 'cancelled' : answer.type,
    ...(answer.type === 'accepted' && answer.content !== undefined
      ? { content: answer.content }
      : {}),
  };

  const marked = askedIn(state.entries, wait);
  // A task's box of questions out of its own call is recorded under that
  // call, among the task's work, as the call is.
  const inTask =
    wait.subagentId !== undefined &&
    wait.mode === 'form' &&
    wait.questions !== undefined &&
    wait.toolCallId !== undefined
      ? changeSubagent(marked, wait.subagentId, (subagent) => ({
          ...subagent,
          entries: [...subagent.entries, entry],
        }))
      : marked;

  return {
    ...state,
    entries: inTask === marked ? [...marked, entry] : inTask,
    asking: state.asking.filter((other) => other !== wait),
  };
}
