/**
 * Whose monitors a call to chord's MCP server reaches, and the limit that
 * counts a tab's session and its long-lived children together.
 */
import type { MonitorStarted, MonitorStopped } from './conversation.ts';
import {
  type MonitorArgs,
  monitorRefusal,
  type RunningMonitor,
} from './monitors.ts';
import { tabOf, type Tabs } from './tabs.ts';

/** What keeps a session's monitors: its `Conversation`, or a test's. */
export interface MonitorsKeeper {
  readonly monitors: readonly RunningMonitor[];
  startMonitor(
    args: MonitorArgs,
    cwd: string,
  ): MonitorStarted | { readonly error: string };
  stopMonitor(id: string): MonitorStopped | { readonly error: string };
}

/** Who calls: the tab it is in, and the child it is, if it is one. */
export interface MonitorCaller {
  readonly key: number;
  /** A task's id; a task has no monitors. */
  readonly task?: string | undefined;
  /** A long-lived child's id. */
  readonly agent?: string | undefined;
}

const CLOSED = { error: 'This session has closed' } as const;

/**
 * The conversation whose monitors are the caller's own: the tab's, or a
 * long-lived child's; none for a task, or once it has closed.
 */
export function monitorsOwner<C>(
  tabs: Tabs<C>,
  caller: MonitorCaller,
): C | undefined {
  const tab = tabOf(tabs, caller.key);

  return caller.task !== undefined
    ? undefined
    : caller.agent !== undefined
      ? tab?.children.find((child) => child.id === caller.agent)?.conversation
      : tab?.conversation;
}

/**
 * `monitor`: started in the caller's own conversation, in `cwd`; refused
 * past the limit, which the tab's session and its children share.
 */
export function startMonitorIn<C extends MonitorsKeeper>(
  tabs: Tabs<C>,
  caller: MonitorCaller,
  args: MonitorArgs,
  cwd: string,
): MonitorStarted | { readonly error: string } {
  const owner = monitorsOwner(tabs, caller);
  const tab = tabOf(tabs, caller.key);

  if (owner === undefined || tab === undefined) {
    return CLOSED;
  }

  const running = [tab, ...tab.children].reduce(
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
  tabs: Tabs<C>,
  caller: MonitorCaller,
  id: string,
): MonitorStopped | { readonly error: string } {
  return monitorsOwner(tabs, caller)?.stopMonitor(id) ?? CLOSED;
}

/** `list_monitors`: the caller's own monitors still running. */
export function monitorsIn<C extends MonitorsKeeper>(
  tabs: Tabs<C>,
  caller: MonitorCaller,
): readonly RunningMonitor[] {
  return monitorsOwner(tabs, caller)?.monitors ?? [];
}
