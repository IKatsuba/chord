/** Derive current and planned roles; no reservation or predicted spending is implied. */
import type { ActiveRun } from './budgets.ts';
import type { WindowAgents } from './window_agents.ts';
import type { AgentWait } from './waits.ts';
import type { Team } from '../teams.ts';

interface ResourceConversation {
  readonly session:
    | {
        readonly id: string;
        gone(): string | undefined;
        models(): { readonly current?: string } | undefined;
      }
    | undefined;
}

export interface ResourceTask {
  readonly id: string;
  readonly name: string;
  readonly agent: string;
  readonly model: string | null;
  readonly team: string | null;
  readonly runRef: string;
  readonly conversation: ResourceConversation;
}

function state(
  conversation: ResourceConversation,
  wait: AgentWait,
): ActiveRun['state'] {
  if (wait.exited || conversation.session?.gone() !== undefined) {
    return 'ended';
  }

  if (conversation.session === undefined) {
    return wait.ended?.failure === 'start' ? 'refused' : 'starting';
  }

  return wait.working === undefined ? 'idle' : 'working';
}

export function activeResourceRuns(
  agents: WindowAgents<ResourceConversation>,
  runs: ReadonlyMap<string, { readonly name: string; readonly team: Team }>,
  tasks: readonly ResourceTask[],
  processRef: string,
  now: number,
): ActiveRun[] {
  const active: ActiveRun[] = [];
  const common = {
    processRef,
    lastSeenAt: new Date(now).toISOString(),
    resourceRefs: [],
  };

  if (agents.main !== undefined) {
    const main = agents.main;

    active.push({
      ...common,
      runRef: `main-${main.key}`,
      sessionRef: main.conversation.session?.id ?? `starting-${main.key}`,
      team: null,
      member: 'main',
      agent: main.agent,
      model: main.conversation.session?.models()?.current ?? null,
      state: state(main.conversation, main.wait),
    });
  }

  for (const child of agents.children) {
    active.push({
      ...common,
      runRef: child.lead ?? child.id,
      sessionRef: child.conversation.session?.id ?? child.id,
      team: child.team ?? null,
      member:
        child.team !== undefined && child.lead === undefined
          ? 'lead'
          : child.name,
      agent: child.runtime,
      model:
        child.conversation.session?.models()?.current ?? child.model ?? null,
      state: state(child.conversation, child.wait),
    });

    const run = runs.get(child.id);

    if (run === undefined) {
      continue;
    }

    for (const member of run.team.members) {
      if (
        agents.children.some(
          (opened) => opened.lead === child.id && opened.name === member.name,
        )
      ) {
        continue;
      }

      const closed = agents.closed.some(
        (opened) => opened.lead === child.id && opened.name === member.name,
      );

      active.push({
        ...common,
        runRef: child.id,
        sessionRef: child.id,
        team: run.name,
        member: member.name,
        agent: member.agent,
        model: member.model ?? null,
        state: closed ? 'ended' : 'planned',
      });
    }
  }

  for (const task of tasks) {
    active.push({
      ...common,
      runRef: task.runRef,
      sessionRef: task.conversation.session?.id ?? task.id,
      team: task.team,
      member: task.name,
      agent: task.agent,
      model: task.conversation.session?.models()?.current ?? task.model,
      state:
        task.conversation.session?.gone() !== undefined
          ? 'ended'
          : task.conversation.session === undefined
            ? 'starting'
            : 'working',
    });
  }

  return active;
}
