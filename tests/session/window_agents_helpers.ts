/**
 * The window's agents as the session tests build them: main and its
 * children, the events they hear, and the agent picked.
 */
import type { ConversationEvent } from '../../src/session/conversation.ts';
import type { AgentWait } from '../../src/session/waits.ts';
import {
  agentOf,
  hear,
  noAgents,
  openChild,
  openMain,
  pick,
  type WindowAgents,
} from '../../src/session/window_agents.ts';

/**
 * The window for `agents`: main on the first, a child on each other, by
 * that name, on that runtime, the last opened picked.
 */
export function opened(...agents: string[]): WindowAgents<string> {
  const [first, ...rest] = agents;
  const started = openMain(
    noAgents<string>(),
    first!,
    `conversation of ${first}`,
  );
  const all = rest.reduce(
    (window, name) =>
      openChild(
        window,
        { id: `id-${name}`, name, runtime: name, openedAt: 0 },
        `conversation of ${name}`,
      )!.agents,
    started,
  );

  return pick(all, all.nextKey - 1);
}

/** The wait of agent `key`, main or a child. */
export function waitOf(
  agents: WindowAgents<string>,
  key: number,
): AgentWait | undefined {
  const found = agentOf(agents, key);

  return (found?.child ?? found?.main)?.wait;
}

/** Plays events into agent `key`, each a second after the last from `at`. */
export function heard(
  agents: WindowAgents<string>,
  key: number,
  events: readonly ConversationEvent[],
  at = 0,
): WindowAgents<string> {
  return events.reduce(
    (agents, event, index) =>
      hear(agents, key, event, at + index * 1000).agents,
    agents,
  );
}

export const up: ConversationEvent = { type: 'connected', sessionId: 's' };

export function prompt(turnId: string): ConversationEvent {
  return { type: 'prompt', turnId, text: 'hi', at: 0 };
}

export function asked(turnId: string, id: string): ConversationEvent {
  return {
    type: 'permission_requested',
    turnId,
    permission: { id, title: 'Write notes.txt', options: [] },
  };
}

export function settled(turnId: string, id: string): ConversationEvent {
  return {
    type: 'permission_settled',
    turnId,
    id,
    answer: { type: 'chosen', optionId: 'allow' },
  };
}

export function ended(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'completed', stopReason: 'end_turn' },
  };
}

export function failed(turnId: string): ConversationEvent {
  return {
    type: 'result',
    turnId,
    result: { status: 'failed', error: { message: 'boom' } },
  };
}

/** Agent `key` picked, as the list picks it. */
export function goTo<C>(agents: WindowAgents<C>, key: number): WindowAgents<C> {
  return pick(agents, key);
}

/** `tabs` with children `names` opened in it, in order, on codex. */
export function withChildren(
  tabs: WindowAgents<string>,
  ...names: string[]
): WindowAgents<string> {
  return names.reduce(
    (tabs, name) =>
      openChild(
        tabs,
        {
          id: `id-${name}`,
          name,
          runtime: 'codex',
          openedAt: 0,
        },
        `conversation of ${name}`,
      )!.agents,
    tabs,
  );
}

/** The window's agents as `main*`, the pick marked. */
export function list(tabs: WindowAgents<string>): string[] {
  return [{ key: tabs.main!.key, name: 'main' }, ...tabs.children].map(
    ({ key, name }) => `${name}${key === tabs.picked ? '*' : ''}`,
  );
}
