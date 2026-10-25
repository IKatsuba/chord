/**
 * The window's agents: the person's session, `main`, and the long-lived
 * agents it opened, which one of them the prompt goes to, and the order
 * the ones that want the person come in (CHD-493).
 */
import { agentNameProblem } from '../agent_name.ts';
import type { Wait } from '../notify.ts';
import type { ConversationEvent } from './conversation.ts';
import { type AgentWait, heardWait, idle } from './waits.ts';

/**
 * The long-lived agents one session may have open at once, a team's lead
 * counting as one and its members as none of them: with `main`, the list
 * under the prompt holds no more than nine rows and the teams' members.
 */
export const MAX_CHILDREN = 8;

/**
 * A long-lived agent a session opened with `open_agent`, as its row in the
 * list under the prompt names it.
 */
export interface ChildInfo {
  /** chord's id for it, which `open_agent` answered. */
  readonly id: string;
  readonly name: string;
  readonly runtime: string;
  /** The model asked for; none when the runtime's own was left. */
  readonly model?: string | undefined;
  /** The mode a team file set it on; none for one the file left. */
  readonly mode?: string | undefined;
  /** The team it is of, by its file's name: set on a lead and its members. */
  readonly team?: string | undefined;
  /** A member's lead, by chord's id for it; none for any other agent. */
  readonly lead?: string | undefined;
  /**
   * Its place among the theme's agent colours: the session's children take
   * them in the order they opened, so closing one recolours none.
   */
  readonly colour: number;
  /** When it opened, epoch milliseconds. */
  readonly openedAt: number;
}

/**
 * A long-lived agent open in the window: a session the person can pick in
 * the list under the prompt, keyed as main is, from the same keys, so the
 * window keeps its state beside main's.
 */
export interface Child<C> extends ChildInfo {
  readonly key: number;
  readonly conversation: C;
  readonly wait: AgentWait;
}

/**
 * The person's session. Its key never changes: `/clear` and a `/resume`
 * pick start its next session under the same one.
 */
export interface MainAgent<C> {
  readonly key: number;
  readonly agent: string;
  readonly conversation: C;
  readonly wait: AgentWait;
}

/** The window's main session and its children. */
export interface WindowAgents<C> {
  /** The person's session; none before it starts. */
  readonly main: MainAgent<C> | undefined;
  /** Its long-lived agents, in the order they opened. */
  readonly children: readonly Child<C>[];
  /** The agent the prompt goes to: main's key, or a child's. */
  readonly picked: number;
  /**
   * The children closed, by chord's id, so a message to one answers that it
   * is closed rather than that it never was. Emptied with the session on
   * `/clear` and a `/resume` pick, after which the record says what was
   * closed (Q184).
   */
  readonly closed: readonly ChildInfo[];
  /**
   * The names of the team runs closed while the window is open, which
   * `/clear` and `/resume` leave as they are: a run's number is never given
   * again, so a name in an old message, a resumed transcript's or a record's,
   * still means the run it meant.
   */
  readonly runs: readonly string[];
  /** How many children have opened, which colours the next. */
  readonly opened: number;
  /** The key the next agent opened gets; keys are never reused. */
  readonly nextKey: number;
  /**
   * The agent `attend` last went to and its place in the attention order
   * then, kept until another is picked: going there clears an unseen reply,
   * which takes it out of the order, and the next press still has to know
   * where in the queue it stood.
   */
  readonly attended?: { readonly key: number; readonly rank: Rank } | undefined;
}

/** An agent's place in the attention order, compared field by field. */
export interface Rank {
  /** Waits on a permission or form come before unseen replies and failures. */
  readonly unseen: boolean;
  readonly since: number;
  /**
   * A tie goes to main, then to the child that opened first: keys run in
   * the order the list draws them, and stay put when one before closes.
   */
  readonly key: number;
}

export function noAgents<C>(): WindowAgents<C> {
  return {
    main: undefined,
    children: [],
    picked: 1,
    closed: [],
    runs: [],
    opened: 0,
    nextKey: 1,
  };
}

/** The window's session, picked; once, as a second call changes nothing. */
export function openMain<C>(
  agents: WindowAgents<C>,
  agent: string,
  conversation: C,
): WindowAgents<C> {
  if (agents.main !== undefined) {
    return agents;
  }

  const key = agents.nextKey;

  return {
    ...agents,
    main: { key, agent, conversation, wait: idle },
    picked: key,
    nextKey: key + 1,
  };
}

/**
 * Main, `key` naming it, or the child `key` names; none for a key that is
 * neither open.
 */
export function agentOf<C>(
  agents: WindowAgents<C>,
  key: number,
): { readonly main?: MainAgent<C>; readonly child?: Child<C> } | undefined {
  if (agents.main?.key === key) {
    return { main: agents.main };
  }

  const child = agents.children.find((each) => each.key === key);

  return child === undefined ? undefined : { child };
}

/** The key whose session fills the window; none before main starts. */
export function shownKey<C>(agents: WindowAgents<C>): number | undefined {
  return agents.main === undefined ? undefined : agents.picked;
}

/** The child the prompt goes to; none while `main` is picked. */
export function pickedChild<C>(agents: WindowAgents<C>): Child<C> | undefined {
  return agents.children.find((child) => child.key === agents.picked);
}

/** Whether `child` is a team's lead rather than a member or an M4 child. */
export function isLead(child: ChildInfo): boolean {
  return child.team !== undefined && child.lead === undefined;
}

/** The open members of the lead with chord's id `lead`, in their order. */
export function membersOf<C>(
  agents: WindowAgents<C>,
  lead: string,
): Child<C>[] {
  return agents.children.filter((child) => child.lead === lead);
}

/** One open session send_message reaches, by its name or optional child id. */
export interface MessageRecipient {
  readonly key: number;
  readonly name: string;
  readonly id?: string;
}

/**
 * Who send_message reaches from `sourceKey`: main's own children; a child's
 * parent; a lead's main, members and other leads; a member's lead and peers.
 * Only open long-lived sessions live here, never tasks or unopened runtimes.
 */
export function messageRecipients<C>(
  agents: WindowAgents<C>,
  sourceKey: number,
): readonly MessageRecipient[] {
  const { main } = agents;
  const named = ({ key, name, id }: Child<C>): MessageRecipient => ({
    key,
    name,
    id,
  });

  if (main === undefined) {
    return [];
  }

  if (sourceKey === main.key) {
    return ownChildren(agents).map(named);
  }

  const self = agents.children.find((child) => child.key === sourceKey);

  if (self === undefined) {
    return [];
  }

  const parent = { key: main.key, name: 'main' };

  if (self.team === undefined) {
    return [parent];
  }

  const lead = isLead(self)
    ? self
    : agents.children.find((child) => child.id === self.lead);

  if (lead === undefined) {
    return [];
  }

  const members = membersOf(agents, lead.id).filter((child) => child !== self);

  return self === lead
    ? [
        parent,
        ...members.map(named),
        ...ownChildren(agents)
          .filter((child) => isLead(child) && child !== self)
          .map(named),
      ]
    : [named(lead), ...members.map(named)];
}

/**
 * A child as a sentence about it names it: its own name, or a member's with
 * its run after it, `tester · bugfix 2`, while another agent of the window
 * has that name too, as two runs each have a `tester`.
 */
export function namedChild<C>(
  agents: WindowAgents<C>,
  child: ChildInfo,
): string {
  const lead =
    child.lead === undefined
      ? undefined
      : agents.children.find((each) => each.id === child.lead);
  const shared = agents.children.some(
    (each) => each.id !== child.id && each.name === child.name,
  );

  return lead !== undefined && shared
    ? `${child.name} · ${lead.name}`
    : child.name;
}

/**
 * A child's name: the one asked for, or its runtime, numbered past the first
 * (`codex`, `codex 2`), and never one another open agent of the session
 * goes by, `main` and `chord` included, as a message names its sender so.
 */
export function childName<C>(
  agents: WindowAgents<C>,
  asked: string | undefined,
  runtime: string,
): string {
  const base = asked?.trim() || runtime;
  const taken = new Set([
    'main',
    'chord',
    ...agents.children.map((c) => c.name),
  ]);

  return numbered(base, taken);
}

/**
 * A run's lead's name: the team's, numbered past the first run as a second
 * child of one runtime is (`bugfix 2`); a closed run's number is not given
 * again while the window is open, so a name in an old message still means
 * the run it meant.
 */
export function runName<C>(agents: WindowAgents<C>, team: string): string {
  return numbered(
    team,
    new Set([
      'main',
      'chord',
      ...agents.children.map((child) => child.name),
      ...agents.runs,
    ]),
  );
}

function numbered(base: string, taken: ReadonlySet<string>): string {
  const problem = agentNameProblem(base);

  if (problem !== undefined) {
    throw new Error(problem);
  }

  if (!taken.has(base)) {
    return base;
  }

  let n = 2;

  while (taken.has(`${base} ${n}`)) {
    n += 1;
  }

  return `${base} ${n}`;
}

/**
 * What chord tells a long-lived child's parent when `event` ends the child's
 * work without the parent hearing it: its agent gone, with its last words,
 * or a turn that failed while it stayed up; none for any other event. A
 * parent waiting on a report would otherwise wait for ever. `gone` is the
 * agent's last words once it has gone, as `Session.gone` reads them; a turn
 * that failed because it went is the exit's to tell.
 */
export function childEnded(
  name: string,
  event: ConversationEvent,
  gone: string | undefined,
  lead = false,
): string | undefined {
  if (event.type === 'disconnected') {
    return lead
      ? `${name}'s lead exited${
          gone ? `: ${sentence(gone)}` : ''
        }. Its members are closed; run_team starts the team again.`
      : `${name}'s agent exited${
          gone ? `: ${sentence(gone)}` : ''
        }. open_agent opens it again.`;
  }

  if (
    event.type === 'result' &&
    event.result.status === 'failed' &&
    gone === undefined
  ) {
    return `${name}'s turn failed: ${sentence(
      event.result.error.message,
    )}. It is still open; send_message reaches it.`;
  }

  return undefined;
}

/** Words that go on into chord's sentence, without a full stop of their own. */
function sentence(words: string): string {
  return words.trim().replace(/\.$/, '');
}

/**
 * Opens a child under the next key, at the end of the list, or a member
 * after its lead's last, so a team's agents stay together, with the next
 * colour; the pick stays where it is. None before main starts, or, for one
 * of main's own, with `MAX_CHILDREN` of them already open.
 */
export function openChild<C>(
  agents: WindowAgents<C>,
  info: Omit<ChildInfo, 'colour'>,
  conversation: C,
): { readonly agents: WindowAgents<C>; readonly key: number } | undefined {
  if (
    agents.main === undefined ||
    (info.lead === undefined && ownChildren(agents).length >= MAX_CHILDREN)
  ) {
    return undefined;
  }

  const key = agents.nextKey;
  const child: Child<C> = {
    ...info,
    colour: agents.opened,
    key,
    conversation,
    wait: idle,
  };
  const after =
    info.lead === undefined
      ? -1
      : agents.children.findLastIndex(
          (each) => each.id === info.lead || each.lead === info.lead,
        );
  const children =
    after === -1
      ? [...agents.children, child]
      : agents.children.toSpliced(after + 1, 0, child);

  return {
    key,
    agents: {
      ...agents,
      children,
      opened: agents.opened + 1,
      nextKey: key + 1,
    },
  };
}

/** The session's own children: those it opened, a team's lead among them. */
export function ownChildren<C>(agents: WindowAgents<C>): Child<C>[] {
  return agents.children.filter((child) => child.lead === undefined);
}

/**
 * Takes child `key` out and keeps it among the closed; a pick on it goes
 * back to `main`.
 */
export function closeChild<C>(
  agents: WindowAgents<C>,
  key: number,
): WindowAgents<C> {
  const child = agentOf(agents, key)?.child;

  if (child === undefined) {
    return agents;
  }

  const { key: _, conversation: __, wait: ___, ...info } = child;

  return {
    ...agents,
    attended: agents.attended?.key === key ? undefined : agents.attended,
    children: agents.children.filter((other) => other !== child),
    picked:
      agents.picked === key
        ? (agents.main?.key ?? agents.picked)
        : agents.picked,
    closed: [...agents.closed, info],
    runs: isLead(info) ? [...agents.runs, info.name] : agents.runs,
  };
}

/**
 * `agents` with no children closed, as a new or resumed session starts: the
 * record then says what was closed. Run names stay taken.
 */
export function forgetClosed<C>(agents: WindowAgents<C>): WindowAgents<C> {
  return agents.closed.length === 0 ? agents : { ...agents, closed: [] };
}

/** `wait` with its `✓`, `✗` or `←` seen, and its turn's end. */
function seen(wait: AgentWait): AgentWait {
  return wait.unseen === undefined && wait.ended === undefined
    ? wait
    : { ...wait, unseen: undefined, ended: undefined };
}

/** `agents` with the wait of agent `key` made `change` of it. */
function withWait<C>(
  agents: WindowAgents<C>,
  key: number,
  change: (wait: AgentWait) => AgentWait,
): WindowAgents<C> {
  return {
    ...agents,
    main:
      agents.main?.key === key
        ? { ...agents.main, wait: change(agents.main.wait) }
        : agents.main,
    children: agents.children.map((child) =>
      child.key === key ? { ...child, wait: change(child.wait) } : child,
    ),
  };
}

/**
 * A key pressed in chord: the agent shown has been looked at, so its turn's
 * end is seen. Its `✓` or `✗` is already gone, as it was shown.
 */
export function keyed<C>(agents: WindowAgents<C>): WindowAgents<C> {
  const key = shownKey(agents);
  const found = key === undefined ? undefined : agentOf(agents, key);
  const wait = (found?.child ?? found?.main)?.wait;

  return key === undefined || wait?.ended === undefined
    ? agents
    : withWait(agents, key, (each) => ({ ...each, ended: undefined }));
}

/**
 * Picks agent `key`, `main` by its key or a child by its: the transcript
 * and the prompt are that agent's, and its marks are seen.
 */
export function pick<C>(agents: WindowAgents<C>, key: number): WindowAgents<C> {
  if (agentOf(agents, key) === undefined) {
    return agents;
  }

  return { ...withWait(agents, key, seen), picked: key, attended: undefined };
}

/**
 * Moves the pick `by` rows down the list, `main` first; none when it would
 * go above `main`, which hands the focus back to the box. The last row
 * stays the last.
 */
export function movePick<C>(
  agents: WindowAgents<C>,
  by: number,
): WindowAgents<C> | undefined {
  if (agents.main === undefined) {
    return agents;
  }

  const keys = [agents.main.key, ...agents.children.map((child) => child.key)];
  const at = keys.indexOf(agents.picked) + by;

  if (at < 0) {
    return undefined;
  }

  return pick(agents, keys[Math.min(at, keys.length - 1)]!);
}

/**
 * What a notification calls agent `key`: main by its agent, a child by its
 * name, and a member with its run, `tester (bugfix)`, as the person may be
 * looking anywhere when it comes; none for a key that is not open.
 */
export function notifiedName<C>(
  agents: WindowAgents<C>,
  key: number,
): string | undefined {
  const found = agentOf(agents, key);

  if (found?.main !== undefined) {
    return found.main.agent;
  }

  const child = found?.child;

  if (child === undefined) {
    return undefined;
  }

  const lead =
    child.lead === undefined
      ? undefined
      : agents.children.find((each) => each.id === child.lead);

  return lead === undefined ? child.name : `${child.name} (${lead.name})`;
}

function compare(a: Rank, b: Rank): number {
  return (
    Number(a.unseen) - Number(b.unseen) || a.since - b.since || a.key - b.key
  );
}

/**
 * The agents that want the person, most urgent first: those that wait on a
 * permission or form, longest waiting first, then those with a reply or
 * failure not yet seen, oldest first. A message between agents wants no
 * one: the turn it starts says so.
 */
function ranked<C>(
  agents: WindowAgents<C>,
): { readonly key: number; readonly rank: Rank }[] {
  return [
    ...(agents.main === undefined ? [] : [agents.main]),
    ...agents.children,
  ]
    .flatMap(({ key, wait }) => {
      if (wait.asking) {
        return [
          {
            key,
            rank: { unseen: false, since: wait.asking.since, key },
          },
        ];
      }

      return wait.unseen && wait.unseen.kind !== 'message'
        ? [{ key, rank: { unseen: true, since: wait.unseen.since, key } }]
        : [];
    })
    .sort((a, b) => compare(a.rank, b.rank));
}

/** The keys of the agents that want the person, most urgent first. */
export function attentionOrder<C>(agents: WindowAgents<C>): number[] {
  return ranked(agents).map(({ key }) => key);
}

/**
 * Goes to the agent after the one shown in the attention order, or to the
 * first when the one shown has no place in it, round to the first after
 * the last; none when no other agent wants the person. Going from the
 * shown one's place rather than from the top is what lets pressing it
 * again reach every one: an agent waiting on a permission keeps its place
 * once shown, and one whose reply has just been seen is placed by where
 * `attend` found it.
 */
export function attend<C>(
  agents: WindowAgents<C>,
): WindowAgents<C> | undefined {
  const order = ranked(agents);
  const shown = shownKey(agents);
  const byHand = agents.attended?.key !== shown;
  const from = byHand
    ? order.find(({ key }) => key === shown)?.rank
    : agents.attended?.rank;
  const others = order.filter(({ key }) => key !== shown);
  // From an agent picked by hand, the first goes to what the status line
  // names, the longest wait behind it; the walk goes on from there (the
  // owner's Q46, CHD-431).
  const named = byHand ? others.find(({ rank }) => !rank.unseen) : undefined;
  const next =
    named ??
    (from && others.find(({ rank }) => compare(rank, from) > 0)) ??
    others[0];

  return next && { ...pick(agents, next.key), attended: next };
}

/**
 * Folds one of agent `key`'s events into its wait, and says the wait it
 * starts, if any, as `notify.ts` classes waits, shown or not.
 */
export function hear<C>(
  agents: WindowAgents<C>,
  key: number,
  event: ConversationEvent,
  now: number,
): { readonly agents: WindowAgents<C>; readonly wait?: Wait } {
  const found = agentOf(agents, key);
  const before = (found?.child ?? found?.main)?.wait;

  if (before === undefined) {
    return { agents };
  }

  const heard = heardWait(before, event, now, {
    front: shownKey(agents) === key,
  });
  const next = withWait(agents, key, () => heard.wait);

  return heard.started === undefined
    ? { agents: next }
    : { agents: next, wait: heard.started };
}

/** The window's agents once main has started. */
export type StartedAgents<C> = WindowAgents<C> & {
  readonly main: MainAgent<C>;
};

/** `agents` while `key` is main's: what a session of the window owns. */
export function ownedBy<C>(
  agents: WindowAgents<C>,
  key: number | undefined,
): StartedAgents<C> | undefined {
  return agents.main !== undefined && agents.main.key === key
    ? (agents as StartedAgents<C>)
    : undefined;
}
