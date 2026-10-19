/**
 * An agent's own cycle: work it does with no turn of the person's running,
 * as Claude Code does when a background task ends and codebuddy with its
 * unasked turns. chord knows one only where the agent marks its end (the
 * owner's Q49, CHD-426): what marks a cycle, read off an update.
 */
import type { SessionUpdate } from '@agentclientprotocol/sdk';

/**
 * The `_claude/origin` kinds of a cycle Claude Code started on its own, as
 * claude-agent-acp 0.93.0 tells its results apart (`AUTONOMOUS_RESULT_ORIGINS`
 * in `dist/acp-agent.js`): a usage update of one ends the cycle.
 */
const AUTONOMOUS_ORIGINS: ReadonlySet<string> = new Set([
  'task-notification',
  'peer',
  'coordinator',
  'observer',
  'observer-activity',
]);

/** The `_meta` key codebuddy marks an unasked turn's start with. */
const CODEBUDDY_START = 'codebuddy.ai/unsolicitedTurn';

/** The update codebuddy ends an unasked turn with, which ACP does not have. */
const CODEBUDDY_END = 'session_end';

/**
 * What an update says of a cycle: that one starts (codebuddy's marker) or
 * ends (Claude's autonomous usage, codebuddy's `session_end`); nothing for
 * every other update.
 */
export function cycleMark(update: SessionUpdate): 'start' | 'end' | undefined {
  const kind: string = update.sessionUpdate;
  const meta = (update as { _meta?: Record<string, unknown> | null })._meta;

  if (
    kind === 'session_info_update' &&
    meta?.[CODEBUDDY_START] !== undefined &&
    meta[CODEBUDDY_START] !== null
  ) {
    return 'start';
  }

  if (kind === CODEBUDDY_END) {
    return 'end';
  }

  if (kind === 'usage_update') {
    const origin = meta?.['_claude/origin'];
    const of =
      typeof origin === 'object' && origin !== null
        ? (origin as { kind?: unknown }).kind
        : undefined;

    return typeof of === 'string' && AUTONOMOUS_ORIGINS.has(of)
      ? 'end'
      : undefined;
  }

  return undefined;
}

/**
 * The updates that are the agent at work, which start a cycle of Claude's
 * once its last turn has gone quiet; what only reports its state does not.
 */
export const CYCLE_WORK: ReadonlySet<string> = new Set([
  'agent_message_chunk',
  'agent_thought_chunk',
  'tool_call',
  'tool_call_update',
  'plan',
]);
