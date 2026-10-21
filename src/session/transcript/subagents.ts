/**
 * Subagents: each an entry where its first update came among its parent's,
 * holding its own work apart from the parent's, and its state as the
 * adapters word it.
 */
import type {
  SessionUpdate,
  StateUpdate,
  SubagentUpdate,
} from '@agentclientprotocol/sdk';
import { z } from '@zod/zod';
import { TOKEN_FIELDS, type TokenUsage } from '../usage.ts';
import {
  emptyTranscript,
  type Entry,
  type ItemEnd,
  type Subagent,
  type SubagentState,
  type TaskInfo,
  type TaskSpent,
  type Transcript,
  type TranscriptAction,
} from './types.ts';

/**
 * How the reducer folds a session's own update; a subagent's work folds
 * through it too, handed in as the reducer composes this module.
 */
type ApplyUpdate = (
  state: Transcript,
  turnId: string,
  update: SessionUpdate,
  at?: number,
) => Transcript;

/**
 * A subagent's update, folded into its own work, apart from its parent's; an
 * update for a subagent the transcript does not hold is dropped rather than
 * drawn as the parent's.
 */
export function childUpdate(
  state: Transcript,
  {
    turnId,
    update,
    subagentId,
    at,
  }: Extract<TranscriptAction, { type: 'update' }>,
  applyUpdate: ApplyUpdate,
): Transcript {
  if (subagentId === undefined) {
    return state;
  }

  const entries = changeSubagent(state.entries, subagentId, (subagent) =>
    update.sessionUpdate === 'session_message'
      ? messaged(subagent, turnId, update, state.entries)
      : worked(subagent, turnId, update, at, applyUpdate),
  );

  return entries === state.entries ? state : { ...state, entries };
}

/**
 * `subagent` with a `session_message` it got upserted by its id: the first
 * is its whole task, and each later one, as a SendMessage sends it, a message
 * among its work where it came. Content left out keeps what it had; `null`
 * or none clears it, the task back to its description, the message gone.
 */
function messaged(
  subagent: Subagent,
  turnId: string,
  update: Extract<SessionUpdate, { sessionUpdate: 'session_message' }>,
  around: readonly Entry[],
): Subagent {
  const { messageId, content, senderSessionId } = update;
  const text =
    content === undefined
      ? undefined
      : (content ?? [])
          .flatMap((block) => (block.type === 'text' ? [block.text] : []))
          .join('');

  if (subagent.promptId === undefined || subagent.promptId === messageId) {
    const { prompt: before, ...rest } = subagent;
    const prompt = text === undefined ? before : text;

    return {
      ...rest,
      promptId: messageId,
      ...(prompt === undefined || prompt === '' ? {} : { prompt }),
    };
  }

  const at = subagent.entries.findIndex(
    (entry) => entry.kind === 'message' && entry.messageId === messageId,
  );
  const was = at < 0 ? undefined : subagent.entries[at];

  if (text === undefined) {
    return subagent;
  }

  if (text === '') {
    if (at < 0) {
      return subagent;
    }

    // Its plan stays where it first came among the work that is left.
    const { planAt } = subagent;

    return {
      ...subagent,
      entries: subagent.entries.toSpliced(at, 1),
      ...(planAt !== undefined && at < planAt ? { planAt: planAt - 1 } : {}),
    };
  }

  // A sender left out keeps the one known; one that is a subagent here is
  // named as its block is, and any other is the transcript's own agent.
  const sender =
    senderSessionId === undefined || senderSessionId === null
      ? undefined
      : findSubagent(around, senderSessionId);
  const from: Pick<
    Extract<Entry, { kind: 'message' }>,
    'from' | 'byAgent'
  > = sender !== undefined
    ? { from: { name: `Agent(${sender.title ?? ''})` } }
    : was?.kind === 'message' &&
        (senderSessionId === undefined || senderSessionId === null)
      ? {
          from: was.from,
          ...(was.byAgent === undefined ? {} : { byAgent: was.byAgent }),
        }
      : { from: { name: '' }, byAgent: true };
  const entry: Entry = { kind: 'message', turnId, ...from, text, messageId };

  return {
    ...subagent,
    entries:
      at < 0 ? [...subagent.entries, entry] : subagent.entries.with(at, entry),
  };
}

/**
 * `subagent` with `update` folded into its work, through the reducer that
 * folds a session's own, so its messages, calls, plan and subagents fold the
 * same way. What a subagent says of usage, modes or commands is dropped: those
 * are its parent's session's to say.
 */
function worked(
  subagent: Subagent,
  turnId: string,
  update: SessionUpdate,
  at: number | undefined,
  applyUpdate: ApplyUpdate,
): Subagent {
  const before: Transcript = {
    ...emptyTranscript,
    entries: subagent.entries,
    plan: subagent.plan,
    ...(subagent.planId === undefined ? {} : { planId: subagent.planId }),
  };
  const after = applyUpdate(before, turnId, update, at);

  if (
    after.entries === before.entries &&
    after.plan === before.plan &&
    after.planId === before.planId
  ) {
    return subagent;
  }

  const { planId: _, ...rest } = subagent;

  return {
    ...rest,
    entries: after.entries,
    plan: after.plan,
    ...(after.planId === undefined ? {} : { planId: after.planId }),
    ...(subagent.planAt === undefined && after.plan.length > 0
      ? { planAt: subagent.entries.length }
      : {}),
  };
}

/**
 * A `subagent_update`, from the session or, folded into its work, from a
 * subagent: the subagent it names changed where it stands, wherever that is,
 * or, the first time, put at the end of its parent's entries. A reopened
 * subagent comes under an id of its own and is a new one.
 */
export function mergeSubagent(
  state: Transcript,
  turnId: string,
  update: SubagentUpdate,
  at: number | undefined,
): Transcript {
  if (findSubagent(state.entries, update.sessionId)) {
    const entries = changeSubagent(
      state.entries,
      update.sessionId,
      (subagent) => patched(subagent, update, at),
    );

    return {
      ...state,
      entries: [
        ...entries,
        ...itemEndLines(state.entries, entries, state.turn),
      ],
    };
  }

  const subagent = patched(
    {
      id: update.sessionId,
      state: 'running',
      entries: [],
      plan: [],
      ...(at === undefined ? {} : { startedAt: at }),
    },
    update,
    at,
  );

  return {
    ...state,
    entries: [...state.entries, { kind: 'subagent', turnId, subagent }],
  };
}

/**
 * `subagent` patched as ACP says: a field left out is kept, `null` clears it,
 * a value replaces it. A state ACP has no word for here keeps the one it had.
 */
function patched(
  subagent: Subagent,
  update: SubagentUpdate,
  at: number | undefined,
): Subagent {
  const { title, description, capabilities } = update;
  const told = subagentStateOf(update.state);
  const next = told ?? subagent.state;
  const {
    title: _title,
    description: _description,
    endedAt,
    error: before,
    cancellable: wasCancellable,
    waiting: wasWaiting,
    offeredCancel: wasOffered,
    stopping: wasStopping,
    ...kept
  } = subagent;
  // A stop pending holds until its agent tells a state it is not at work in.
  const stopping =
    told === undefined || told === 'running' ? wasStopping : undefined;
  const waiting =
    told === undefined
      ? wasWaiting
      : update.state?.state === 'requires_action'
        ? (wasWaiting ?? (at === undefined ? {} : { since: at }))
        : undefined;
  const cancellable =
    capabilities === undefined
      ? wasCancellable
      : capabilities?.cancel !== undefined && capabilities.cancel !== null;
  const offeredCancel = wasOffered ?? (cancellable === true || undefined);
  // An untracked subagent may have worked on: its time stands at the
  // `unknown`, and runs again to the next state it is told, but not to an
  // update that tells none.
  const moved =
    subagent.state === 'running' ||
    (subagent.state === 'untracked' &&
      told !== undefined &&
      told !== 'untracked');
  const ended = next === 'running' ? undefined : moved ? at : endedAt;
  const error = told === undefined ? before : errorOf(update.state);

  // chord says a task's effort once it is up, after the block is drawn.
  const taskTold = taskOf(update);
  const spent = spentOf(update);
  const known =
    taskTold === undefined ? subagent.task : { ...subagent.task, ...taskTold };
  const task =
    known === undefined || spent === undefined ? known : { ...known, spent };

  return {
    ...kept,
    ...(task === undefined ? {} : { task }),
    state: next,
    ...(title === undefined
      ? subagent.title === undefined
        ? {}
        : { title: subagent.title }
      : title === null
        ? {}
        : { title }),
    ...(description === undefined
      ? subagent.description === undefined
        ? {}
        : { description: subagent.description }
      : description === null
        ? {}
        : { description }),
    ...(ended === undefined ? {} : { endedAt: ended }),
    ...(error === undefined ? {} : { error }),
    ...(cancellable === true ? { cancellable } : {}),
    ...(offeredCancel === true ? { offeredCancel } : {}),
    ...(stopping === undefined ? {} : { stopping }),
    ...(waiting === undefined ? {} : { waiting }),
  };
}

/**
 * Where a `subagent_update` chord sends for a task agent it started says so:
 * its name, runtime and model, which no adapter's subagent has.
 */
export const TASK_META = 'chord/task';

/** Where a task's ending `subagent_update` carries what it spent (CHD-373). */
export const TASK_SPENT_META = 'chord/spent';

/** A count of tokens: whole, and none below nothing. */
const COUNT = z.number().int().nonnegative();

/**
 * A cost as chord reads one an agent or a record gives: an amount, none
 * below nothing, in a named currency.
 */
export const COST = z.object({
  amount: z.number().nonnegative(),
  currency: z.string().min(1),
});

/** A token field: its count, or left out where it is not one. */
const FIELD = COUNT.optional().catch(undefined);

/**
 * A task's spend as its ending update carries it, which a record or an
 * agent may have bent: each part that does not read as one is left out, a
 * token count on its own, and `estimated` stands only with a cost.
 */
const SPENT = z.object({
  tokens: z
    .object({
      inputTokens: FIELD,
      outputTokens: FIELD,
      cachedReadTokens: FIELD,
      cachedWriteTokens: FIELD,
      thoughtTokens: FIELD,
      totalTokens: FIELD,
    } satisfies Record<(typeof TOKEN_FIELDS)[number], typeof FIELD>)
    .optional()
    .catch(undefined),
  cost: COST.optional().catch(undefined),
  estimated: z.literal(true).optional().catch(undefined),
});

/** What a task's ending update says it spent; none when it says nothing. */
function spentOf(update: SubagentUpdate): TaskSpent | undefined {
  const read = SPENT.safeParse(update._meta?.[TASK_SPENT_META]);

  if (!read.success) {
    return undefined;
  }

  const counts = Object.fromEntries(
    Object.entries(read.data.tokens ?? {}).filter(
      ([, count]) => count !== undefined,
    ),
  ) as TokenUsage;
  const { cost } = read.data;
  const spent: TaskSpent = {
    ...(Object.keys(counts).length === 0 ? {} : { tokens: counts }),
    ...(cost === undefined ? {} : { cost }),
    ...(cost !== undefined && read.data.estimated ? { estimated: true } : {}),
  };

  return Object.keys(spent).length === 0 ? undefined : spent;
}

/** The task a `subagent_update` describes, when chord sent it for one. */
function taskOf(update: SubagentUpdate): TaskInfo | undefined {
  const meta = update._meta?.[TASK_META];

  if (typeof meta !== 'object' || meta === null) {
    return undefined;
  }

  const { name, runtime, model, effort, workLost } = meta as Record<
    string,
    unknown
  >;

  return typeof name === 'string' && typeof runtime === 'string'
    ? {
        name,
        runtime,
        ...(typeof model === 'string' ? { model } : {}),
        ...(typeof effort === 'string' ? { effort } : {}),
        ...(workLost === true ? { workLost } : {}),
      }
    : undefined;
}

const ENDINGS: readonly string[] = [
  'completed',
  'failed',
  'cancelled',
  'disconnected',
];

/**
 * A subagent's state from ACP's state object: at work while `running` or
 * waiting on the person (`requires_action`), ended by its stop reason once
 * `idle`, untracked once `unknown`, or ended as the adapters' words say.
 * `null` and any other word say nothing.
 */
function subagentStateOf(
  state: StateUpdate | null | undefined,
): SubagentState | undefined {
  const word = state?.state;

  if (word === 'running' || word === 'requires_action') {
    return 'running';
  }

  if (word === 'unknown') {
    return 'untracked';
  }

  if (word === 'idle') {
    const reason = state?.stopReason;

    return reason === 'end_turn'
      ? 'completed'
      : reason === 'error'
        ? 'failed'
        : reason === 'cancelled'
          ? 'cancelled'
          : 'ended';
  }

  return word !== undefined && ENDINGS.includes(word)
    ? (word as SubagentState)
    : undefined;
}

/** The message of the error an `idle` with stop reason `error` carries. */
function errorOf(state: StateUpdate | null | undefined): string | undefined {
  if (state?.state !== 'idle' || state.stopReason !== 'error') {
    return undefined;
  }

  const { error } = state as { error?: { message?: unknown } | null };

  return typeof error?.message === 'string' && error.message !== ''
    ? error.message
    : undefined;
}

/**
 * Whether a subagent is a background `agent` item: one announced with
 * `capabilities.cancel`, which can be stopped alone. The rule is open with
 * the owner (Q40), so it is here alone.
 */
export function isAgentItem(subagent: Subagent): boolean {
  return subagent.task === undefined && subagent.offeredCancel === true;
}

/** An agent item's name: its short task, else its title. */
export function agentItemName(subagent: Subagent): string {
  return subagent.description ?? subagent.title ?? 'agent';
}

/** The end each state that ends an agent item says. */
const ITEM_ENDS: Partial<Record<SubagentState, ItemEnd>> = {
  completed: 'done',
  failed: 'failed',
  cancelled: 'stopped',
  ended: 'ended',
  disconnected: 'disconnected',
};

/**
 * The lines to add for the agent items that `entries` ended since
 * `before`: one each, unless the turn that announced it, `turn`'s while it
 * runs, says it in its own block (docs/design/CHD-479.md).
 */
export function itemEndLines(
  before: readonly Entry[],
  entries: readonly Entry[],
  turn: Transcript['turn'],
): Entry[] {
  return itemsIn(before).flatMap(({ subagent: was, turnId }): Entry[] => {
    const now = findSubagent(entries, was.id);
    const end = now && ITEM_ENDS[now.state];

    if (
      now === undefined ||
      end === undefined ||
      !isAgentItem(now) ||
      (was.state !== 'running' && was.state !== 'untracked') ||
      (turn.status !== 'idle' && turn.turnId === turnId)
    ) {
      return [];
    }

    return [
      {
        kind: 'item_ended',
        turnId,
        item: 'agent',
        name: agentItemName(now),
        end,
        ...(was.stopping === true && (end === 'stopped' || end === 'ended')
          ? { byPerson: true as const }
          : {}),
        ...(now.startedAt === undefined ? {} : { startedAt: now.startedAt }),
        ...(now.endedAt === undefined ? {} : { endedAt: now.endedAt }),
        ...(end === 'failed' && now.error !== undefined
          ? { error: now.error }
          : {}),
      },
    ];
  });
}

/** Every subagent among `entries`, with the turn its outermost came in. */
function itemsIn(
  entries: readonly Entry[],
  turnId?: string,
): { subagent: Subagent; turnId: string }[] {
  return entries.flatMap((entry) =>
    entry.kind === 'subagent'
      ? [
          { subagent: entry.subagent, turnId: turnId ?? entry.turnId },
          ...itemsIn(entry.subagent.entries, turnId ?? entry.turnId),
        ]
      : [],
  );
}

/** Whether a subagent is at work, as far as chord knows. */
export function isRunning(subagent: Subagent): boolean {
  return subagent.state === 'running';
}

/**
 * `entries` with every subagent among them or under them that `ends` picks,
 * those still running unless told otherwise, ended as `state`, at `at` when
 * it is known; the same array when none was.
 */
export function endRunning(
  entries: readonly Entry[],
  state: SubagentState,
  at: number | undefined,
  ends: (subagent: Subagent) => boolean = isRunning,
): readonly Entry[] {
  let changed = false;
  const next = entries.map((entry): Entry => {
    if (entry.kind !== 'subagent') {
      return entry;
    }

    const { subagent } = entry;
    const inner = endRunning(subagent.entries, state, at, ends);
    const running = ends(subagent);

    if (!running && inner === subagent.entries) {
      return entry;
    }

    changed = true;

    return {
      ...entry,
      subagent: {
        ...subagent,
        entries: inner,
        ...(running
          ? { state, ...(at === undefined ? {} : { endedAt: at }) }
          : {}),
      },
    };
  });

  return changed ? next : entries;
}

/**
 * Subagent `id` marked stopping while it runs, or, `stopping` false, its
 * stop that could not be sent taken back.
 */
export function subagentStopping(
  state: Transcript,
  id: string,
  stopping: boolean,
): Transcript {
  const entries = changeSubagent(state.entries, id, (subagent) => {
    if (stopping) {
      return subagent.state === 'running' && subagent.stopping !== true
        ? { ...subagent, stopping: true }
        : subagent;
    }

    const { stopping: _, ...rest } = subagent;

    return subagent.stopping === true ? rest : subagent;
  });

  return entries === state.entries ? state : { ...state, entries };
}

/** The subagent `id`, among `entries` or under them, at any depth. */
export function findSubagent(
  entries: readonly Entry[],
  id: string,
): Subagent | undefined {
  for (const entry of entries) {
    if (entry.kind !== 'subagent') {
      continue;
    }

    if (entry.subagent.id === id) {
      return entry.subagent;
    }

    const inner = findSubagent(entry.subagent.entries, id);

    if (inner !== undefined) {
      return inner;
    }
  }

  return undefined;
}

/**
 * `entries` with the subagent `id`, wherever it stands among them or under
 * them, changed by `change`; the same array when it is not there or did not
 * change.
 */
export function changeSubagent(
  entries: readonly Entry[],
  id: string,
  change: (subagent: Subagent) => Subagent,
): readonly Entry[] {
  for (const [index, entry] of entries.entries()) {
    if (entry.kind !== 'subagent') {
      continue;
    }

    const { subagent } = entry;

    if (subagent.id === id) {
      const next = change(subagent);

      return next === subagent
        ? entries
        : entries.with(index, { ...entry, subagent: next });
    }

    const inner = changeSubagent(subagent.entries, id, change);

    if (inner !== subagent.entries) {
      return entries.with(index, {
        ...entry,
        subagent: { ...subagent, entries: inner },
      });
    }
  }

  return entries;
}
