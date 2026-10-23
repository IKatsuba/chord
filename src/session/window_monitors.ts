/**
 * Whose monitors a call to chord's MCP server reaches, and the limit that
 * counts main and its long-lived children together.
 */
import type { MonitorStarted, MonitorStopped } from './conversation.ts';
import {
  type MonitorArgs,
  monitorRefusal,
  type RunningMonitor,
} from './monitors.ts';
import type { WindowAgents } from './window_agents.ts';

/** What keeps a session's monitors: its `Conversation`, or a test's. */
export interface MonitorsKeeper {
  readonly monitors: readonly RunningMonitor[];
  startMonitor(
    args: MonitorArgs,
    cwd: string,
  ): MonitorStarted | { readonly error: string };
  stopMonitor(id: string): MonitorStopped | { readonly error: string };
}

/** Who calls: main, by its key, or the child it is, if it is one. */
export interface MonitorCaller {
  readonly key: number;
  /** A task's id; a task has no monitors. */
  readonly task?: string | undefined;
  /** A long-lived child's id. */
  readonly agent?: string | undefined;
}

const CLOSED = { error: 'This session has closed' } as const;

/**
 * The conversation whose monitors are the caller's own: main's, or a
 * long-lived child's; none for a task, or a caller whose session has closed.
 */
export function monitorsOwner<C>(
  agents: WindowAgents<C>,
  caller: MonitorCaller,
): C | undefined {
  if (caller.task !== undefined || agents.main?.key !== caller.key) {
    return undefined;
  }

  return caller.agent !== undefined
    ? agents.children.find((child) => child.id === caller.agent)?.conversation
    : agents.main.conversation;
}

/**
 * `monitor`: started in the caller's own conversation, in `cwd`; refused
 * past the limit, which main and its children share.
 */
export function startMonitorIn<C extends MonitorsKeeper>(
  agents: WindowAgents<C>,
  caller: MonitorCaller,
  args: MonitorArgs,
  cwd: string,
): MonitorStarted | { readonly error: string } {
  const owner = monitorsOwner(agents, caller);

  if (owner === undefined || agents.main === undefined) {
    return CLOSED;
  }

  const running = [agents.main, ...agents.children].reduce(
    (sum, { conversation }) => sum + conversation.monitors.length,
    0,
  );
  const refused = monitorRefusal(args, running);

  return refused === undefined
    ? owner.startMonitor(args, cwd)
    : { error: refused };
}

/** `stop_monitor`: only the caller's own monitor `id`. */
export function stopMonitorIn<C extends MonitorsKeeper>(
  agents: WindowAgents<C>,
  caller: MonitorCaller,
  id: string,
): MonitorStopped | { readonly error: string } {
  return monitorsOwner(agents, caller)?.stopMonitor(id) ?? CLOSED;
}

/** `list_monitors`: the caller's own monitors still running. */
export function monitorsIn<C extends MonitorsKeeper>(
  agents: WindowAgents<C>,
  caller: MonitorCaller,
): readonly RunningMonitor[] {
  return monitorsOwner(agents, caller)?.monitors ?? [];
}
