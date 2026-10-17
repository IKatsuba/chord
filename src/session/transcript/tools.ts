/**
 * A tool call, merged from its `tool_call` and every update to it, with the
 * terminals its commands ran in folded from its `_meta`.
 */
import type { SessionUpdate, ToolCallContent } from '@agentclientprotocol/sdk';
import { z } from '@zod/zod';
import { OUTPUT_LIMIT } from '../context.ts';
import { MCP_CALL } from '../enrich.ts';
import {
  EMPTY_TEXT,
  plainText,
  type TerminalText,
  writeText,
} from '../terminal_text.ts';
import type { Terminal, ToolCall, Transcript } from './types.ts';

const STATUS_ORDER: Record<string, number> = {
  pending: 0,
  in_progress: 1,
  completed: 2,
  failed: 2,
};

/**
 * Updates can arrive late, twice, or before their call: a status only moves
 * forward, and once a call has finished nothing moves it back.
 */
function nextStatus(
  current: string | undefined,
  incoming: string | undefined,
): string | undefined {
  if (incoming === undefined || current === undefined) {
    return incoming ?? current;
  }

  const from = STATUS_ORDER[current];
  const to = STATUS_ORDER[incoming];

  if (from === undefined || to === undefined) {
    return incoming;
  }

  if (from === 2 || to < from) {
    return current;
  }

  return incoming;
}

export function mergeToolCall(
  state: Transcript,
  turnId: string,
  update: Extract<
    SessionUpdate,
    { sessionUpdate: 'tool_call' | 'tool_call_update' }
  >,
): Transcript {
  const id = update.toolCallId;
  const index = state.entries.findLastIndex(
    (entry) => entry.kind === 'tool' && entry.call.id === id,
  );
  const found = state.entries[index];
  const before: ToolCall = found?.kind === 'tool' ? found.call : { id };
  const status = nextStatus(before.status, update.status ?? undefined);
  const { title, kind, locations, content, rawInput, rawOutput } = update;
  const terminals = foldTerminals(before.terminals, update);
  const mcp = mcpOf(update);
  const cut = cutOf(update);
  const call: ToolCall = {
    ...before,
    ...(title ? { title } : {}),
    ...(kind ? { kind } : {}),
    ...(status === undefined ? {} : { status }),
    ...(locations ? { locations } : {}),
    ...(content ? { content } : {}),
    ...(rawInput === undefined ? {} : { rawInput }),
    ...(rawOutput === undefined ? {} : { rawOutput }),
    ...(terminals === undefined ? {} : { terminals }),
    ...(mcp === undefined ? {} : { mcp }),
    ...(cut ? { cut } : {}),
  };

  if (found?.kind !== 'tool') {
    return {
      ...state,
      entries: [...state.entries, { kind: 'tool', turnId, call }],
    };
  }

  return {
    ...state,
    entries: state.entries.with(index, { ...found, call }),
  };
}

/**
 * Whether the update says the agent cut the call off before it ran: Claude's
 * adapter marks one a steer interrupted `_meta.claudeCode.nonExecutionKind`
 * `interrupted`.
 */
function cutOf(update: { _meta?: unknown }): true | undefined {
  const claude = record(record(update._meta).claudeCode);

  return claude.nonExecutionKind === 'interrupted' ? true : undefined;
}

function record(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

/** The MCP call chord's enrichers filed under the update's `_meta`, if any. */
function mcpOf(update: { _meta?: unknown }): ToolCall['mcp'] | undefined {
  const filed =
    typeof update._meta === 'object' && update._meta !== null
      ? (update._meta as Record<string, unknown>)[MCP_CALL]
      : undefined;

  if (typeof filed !== 'object' || filed === null) {
    return undefined;
  }

  const { server, tool, arguments: input } = filed as Record<string, unknown>;

  if (typeof tool !== 'string') {
    return undefined;
  }

  return typeof server === 'string' ? { server, tool, input } : { tool, input };
}

const TERMINAL_ID = z.object({ terminal_id: z.string() });

/**
 * The terminal fields of a tool call's `_meta`, as Codex's and Claude's
 * adapters send them; ACP v1 has no field of its own for a terminal's output.
 * Each is read alone, so one that is malformed leaves the rest.
 */
const TERMINAL_META = {
  info: TERMINAL_ID.extend({ cwd: z.string().optional() }),
  output: TERMINAL_ID.extend({ data: z.string() }),
  exit: TERMINAL_ID.extend({
    exit_code: z.number().nullish(),
    signal: z.string().nullish(),
  }),
};

/**
 * `terminals` with what `update` says of them: a terminal its content or
 * `terminal_info` names, its output grown by `terminal_output_delta` or
 * replaced by `terminal_output`, and its end by `terminal_exit`, in that
 * order, as an update may carry the last output and the exit together.
 * Undefined while no terminal was ever named.
 */
function foldTerminals(
  terminals: readonly Terminal[] | undefined,
  update: { content?: ToolCallContent[] | null; _meta?: unknown },
): readonly Terminal[] | undefined {
  const meta =
    typeof update._meta === 'object' && update._meta !== null
      ? (update._meta as Record<string, unknown>)
      : {};
  const read = <T>(schema: z.ZodType<T>, key: string): T | undefined => {
    const parsed = schema.safeParse(meta[key]);

    return parsed.success ? parsed.data : undefined;
  };

  const info = read(TERMINAL_META.info, 'terminal_info');
  const delta = read(TERMINAL_META.output, 'terminal_output_delta');
  const whole = read(TERMINAL_META.output, 'terminal_output');
  const exit = read(TERMINAL_META.exit, 'terminal_exit');
  let folded = terminals;
  const change = (id: string, next: (terminal: Terminal) => Terminal) => {
    const list = folded ?? [];
    const index = list.findIndex((terminal) => terminal.id === id);
    const terminal = list[index] ?? { id, output: '', exited: false };

    folded =
      index < 0 ? [...list, next(terminal)] : list.with(index, next(terminal));
  };

  for (const each of update.content ?? []) {
    if (each.type === 'terminal') {
      change(each.terminalId, (terminal) => terminal);
    }
  }

  if (info) {
    change(info.terminal_id, (terminal) =>
      info.cwd === undefined ? terminal : { ...terminal, cwd: info.cwd },
    );
  }

  if (whole) {
    // What it replaces goes whole, with its cursor, its open escape and
    // whatever was cut from it.
    change(whole.terminal_id, (terminal) =>
      written(terminal, EMPTY_TEXT, whole.data),
    );
  }

  if (delta) {
    change(delta.terminal_id, (terminal) =>
      written(terminal, terminal, delta.data),
    );
  }

  if (exit) {
    change(exit.terminal_id, (terminal) => ({
      ...terminal,
      exited: true,
      ...(typeof exit.exit_code === 'number'
        ? { exitCode: exit.exit_code }
        : {}),
      ...(typeof exit.signal === 'string'
        ? { signal: plainText(exit.signal) }
        : {}),
    }));
  }

  return folded;
}

/**
 * `terminal` with `data` written over `text`, its own output so far or none:
 * only the last `OUTPUT_LIMIT` characters stay, since a running command's
 * latest lines are the ones to see.
 */
function written(
  terminal: Terminal,
  text: TerminalText,
  data: string,
): Terminal {
  const {
    output: _o,
    cursor: _c,
    escape: _e,
    truncated: _t,
    ...rest
  } = terminal;

  return { ...rest, ...writeText(text, data, OUTPUT_LIMIT) };
}
