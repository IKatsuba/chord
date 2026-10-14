/**
 * Subagents: sessions an agent opens of its own for part of a turn, each
 * announced to its parent by a `subagent_update` and then sending its own
 * updates and requests under its own id. Here, which sessions belong to the
 * one chord opened, and what the window reads of the subagents the transcript
 * holds.
 */
import type { SessionNotification } from '@agentclientprotocol/sdk';
import type {
  Entry,
  PermissionWait,
  Subagent,
  Transcript,
} from './transcript/types.ts';

/** The session chord opened, and every subagent under it so far. */
export interface SessionTree {
  readonly root: string;
  readonly subagents: ReadonlySet<string>;
}

export function sessionTree(root: string): SessionTree {
  return { root, subagents: new Set() };
}

/**
 * Where `notification` belongs in `tree`: to the session itself, to one of its
 * subagents (`subagentId`), or to neither (`heard` false), as a session chord
 * never opened. A `subagent_update` from the session or one of its subagents
 * adds the subagent it names, which ACP sends before any of that subagent's
 * own traffic.
 */
export function routed(
  tree: SessionTree,
  { sessionId, update }: SessionNotification,
): {
  readonly heard: boolean;
  readonly subagentId?: string;
  tree: SessionTree;
} {
  const own = sessionId === tree.root;

  if (!own && !tree.subagents.has(sessionId)) {
    return { heard: false, tree };
  }

  const grown =
    update.sessionUpdate === 'subagent_update' &&
    typeof update.sessionId === 'string' &&
    update.sessionId !== tree.root &&
    !tree.subagents.has(update.sessionId)
      ? { ...tree, subagents: new Set([...tree.subagents, update.sessionId]) }
      : tree;

  return own
    ? { heard: true, tree: grown }
    : { heard: true, subagentId: sessionId, tree: grown };
}

/** Every subagent among `entries` and under them, parents before children. */
export function subagentsIn(entries: readonly Entry[]): Subagent[] {
  return entries.flatMap((entry) =>
    entry.kind === 'subagent'
      ? [entry.subagent, ...subagentsIn(entry.subagent.entries)]
      : [],
  );
}

/**
 * How many of the session's subagents, at any depth, are still at work: the
 * window says so once the turn that started them has ended.
 */
export function runningSubagents(transcript: Transcript): number {
  return subagentsIn(transcript.entries).filter(
    (subagent) => subagent.state === 'running',
  ).length;
}

/**
 * The subagents from the session down to `id`, outermost first, so a request
 * from a subagent's own subagent can name the whole way to it; empty when the
 * transcript holds no such subagent.
 */
export function subagentPath(
  entries: readonly Entry[],
  id: string,
): Subagent[] {
  for (const entry of entries) {
    if (entry.kind !== 'subagent') {
      continue;
    }

    if (entry.subagent.id === id) {
      return [entry.subagent];
    }

    const inner = subagentPath(entry.subagent.entries, id);

    if (inner.length > 0) {
      return [entry.subagent, ...inner];
    }
  }

  return [];
}

/**
 * The permission request the turn waits on for tool call `toolCallId` of the
 * subagent `subagentId`, or of the session itself when that is undefined.
 */
export function waitingOn(
  transcript: Transcript,
  subagentId: string | undefined,
  toolCallId: string,
): PermissionWait | undefined {
  const { turn } = transcript;

  return turn.status === 'awaiting_permission'
    ? turn.permissions.find(
        (wait) =>
          wait.toolCallId === toolCallId && wait.subagentId === subagentId,
      )
    : undefined;
}
