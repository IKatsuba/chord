/**
 * chord's own calls: a request chord's MCP server served, tied to the tool
 * call the agent made for it by the arguments both carry, since chord knows
 * its own calls by what it served and not by how an adapter titles them. A
 * `spawn_task` call is replaced by the task agent it started, which then
 * stands where the call stood.
 */
import { isDeepStrictEqual } from 'node:util';
import { changeSubagent } from './subagents.ts';
import type {
  ChordCall,
  ChordTool,
  Entry,
  Subagent,
  ToolCall,
  Transcript,
  TranscriptAction,
} from './types.ts';

/** `mcp__<server>__<tool>`: the server up to the next `__`, the tool the rest. */
export const MCP_TITLE = /^mcp__(.+?)__(.+)$/s;

const CHORD_TOOLS: ReadonlySet<string> = new Set<ChordTool>([
  'get_budgets',
  'list_agents',
  'list_sessions',
  'spawn_task',
  'open_agent',
  'send_message',
  'close_agent',
  'monitor',
  'stop_monitor',
  'list_monitors',
  'list_teams',
  'run_team',
  'propose_team',
]);

export function isChordTool(tool: string): tool is ChordTool {
  return CHORD_TOOLS.has(tool);
}

/**
 * The call of chord's own tools `call` asked for, served or not: the
 * request chord served for it, or else the tool and arguments read from
 * the call as the agent sent it, Codex's wrapper as chord's enrichers filed
 * it or Claude's `mcp__<server>__<tool>` title with its `rawInput`, on
 * the server the session gave chord's, `chordServer`; none for any other.
 */
export function chordCallOf(
  call: ToolCall,
  chordServer: string | undefined,
): Pick<ChordCall, 'tool' | 'input'> | undefined {
  if (call.chord !== undefined) {
    return call.chord;
  }

  const [server, tool, input] =
    call.mcp === undefined
      ? (() => {
          const [, named, wrapped = ''] =
            MCP_TITLE.exec(call.title?.trim() ?? '') ?? [];

          return [named, wrapped, call.rawInput ?? {}] as const;
        })()
      : [call.mcp.server, call.mcp.tool, call.mcp.input ?? {}];

  return chordServer !== undefined &&
    server === chordServer &&
    isChordTool(tool)
    ? { tool, input }
    : undefined;
}

/**
 * Whether `chord` is what chord served for `call`, a call not tied to one
 * yet: by the arguments both carry, as a request served is tied to its call.
 */
export function servedFor(call: ToolCall, chord: ChordCall): boolean {
  return sameCall(call, chord);
}

/**
 * A request served: tied to its call where that is already in the
 * transcript, or kept until the call comes. A subagent's, a task agent's own
 * call, is tied among its work, where its call always came first.
 */
export function served(
  state: Transcript,
  { call, subagentId }: Extract<TranscriptAction, { type: 'served' }>,
): Transcript {
  if (subagentId !== undefined) {
    const entries = changeSubagent(state.entries, subagentId, (subagent) => {
      const linked = link(subagent.entries, call);

      return linked === undefined ? subagent : { ...subagent, entries: linked };
    });

    return entries === state.entries ? state : { ...state, entries };
  }

  const linked = link(state.entries, call);

  if (linked !== undefined) {
    return { ...state, entries: linked };
  }

  // A call served again, whose call has not come yet either.
  const waiting = state.served ?? [];
  const pending = waiting.findIndex((each) => answers(call, each));

  return {
    ...state,
    served: pending < 0 ? [...waiting, call] : waiting.with(pending, call),
  };
}

/**
 * Whether `call` takes the place of `earlier`: an answer to it, served while
 * it waited on the person, or it served again, as a message that went
 * queued after all is; a call served pending itself never does.
 */
function answers(call: ChordCall, earlier: ChordCall): boolean {
  return (
    call.pending !== true &&
    earlier.asked !== undefined &&
    earlier.asked === call.asked
  );
}

/**
 * Whether an update for `toolCallId` is a `spawn_task` call's that a task
 * already stands in place of, and so draws nothing more.
 */
export function replacedCall(
  entries: readonly Entry[],
  toolCallId: string,
): boolean {
  return entries.some(
    (entry) =>
      entry.kind === 'subagent' && entry.subagent.callId === toolCallId,
  );
}

/**
 * After a call was merged: tied to a request served before it came, if one
 * with its arguments waits.
 */
export function awaitedCall(state: Transcript, toolCallId: string): Transcript {
  const waiting = state.served ?? [];
  const entry = state.entries.findLast(
    (candidate) =>
      candidate.kind === 'tool' && candidate.call.id === toolCallId,
  );

  if (
    waiting.length === 0 ||
    entry?.kind !== 'tool' ||
    entry.call.chord !== undefined
  ) {
    return state;
  }

  const call = entry.call;
  const match = waiting.findIndex((each) => sameCall(call, each));

  if (match < 0) {
    return state;
  }

  const linked = link(state.entries, waiting[match]!);

  if (linked === undefined) {
    return state;
  }

  const rest = waiting.toSpliced(match, 1);
  const { served: _, ...kept } = state;

  return {
    ...kept,
    entries: linked,
    ...(rest.length > 0 ? { served: rest } : {}),
  };
}

/**
 * Whether `call` is the one `chord` served: the arguments are the same, as
 * its `rawInput` holds them or, where the agent wrapped them, as chord's
 * enrichers filed them with the tool's name, which must be the same too;
 * which server the agent named is not read (owner, 2026-10-17, CHD-377 Q9).
 */
function sameCall(call: ToolCall, chord: ChordCall): boolean {
  if (call.chord !== undefined) {
    return false;
  }

  return call.mcp === undefined
    ? call.rawInput !== undefined &&
        isDeepStrictEqual(call.rawInput, chord.input)
    : call.mcp.tool === chord.tool &&
        isDeepStrictEqual(call.mcp.input, chord.input);
}

/**
 * `entries` with `chord` tied to its call, the latest not yet tied with the
 * same arguments, one whose title names the tool first; undefined when none
 * is there.
 */
function link(
  entries: readonly Entry[],
  chord: ChordCall,
): readonly Entry[] | undefined {
  // A call served again takes the place of what was served before.
  const waited = entries.findLastIndex(
    (entry) =>
      entry.kind === 'tool' &&
      entry.call.chord !== undefined &&
      answers(chord, entry.call.chord),
  );
  const before = entries[waited];

  if (before?.kind === 'tool') {
    return entries.with(waited, {
      ...before,
      call: { ...before.call, chord },
    });
  }

  const candidates = entries.flatMap((entry, index) =>
    entry.kind === 'tool' && sameCall(entry.call, chord) ? [index] : [],
  );
  const named = candidates.filter((index) => {
    const entry = entries[index];

    return (
      entry?.kind === 'tool' && (entry.call.title ?? '').includes(chord.tool)
    );
  });

  const index = named.at(-1) ?? candidates.at(-1);
  const entry = index === undefined ? undefined : entries[index];

  if (index === undefined || entry?.kind !== 'tool') {
    return undefined;
  }

  const task =
    chord.task === undefined
      ? undefined
      : entries.findIndex(
          (each) => each.kind === 'subagent' && each.subagent.id === chord.task,
        );
  const started = task === undefined ? undefined : entries[task];

  if (task === undefined || started?.kind !== 'subagent') {
    return entries.with(index, { ...entry, call: { ...entry.call, chord } });
  }

  // The task stands where its call stood, and takes the call's updates.
  const subagent: Subagent = { ...started.subagent, callId: entry.call.id };

  return entries
    .with(index, { kind: 'subagent', turnId: entry.turnId, subagent })
    .toSpliced(task, 1);
}
