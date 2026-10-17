import { emptyWatch, type Wait, type Watch, watchWaits } from '../notify.ts';
import type { ConversationEvent } from './conversation.ts';
import { senderName } from './tasks.ts';

/** At most nine, because `1`–`9` is the key that goes to one directly. */
export const MAX_TABS = 9;

/**
 * The long-lived agents one session may have open at once, a team's lead
 * counting as one and its members as none of them: with `main`, the list
 * under the prompt holds no more than the tabs' nine and the teams' members.
 */
export const MAX_CHILDREN = 8;

/** What a session waits on the person for: a permission, or a form or link. */
export type Asking = Exclude<Wait, { readonly kind: 'turn_ended' }>;

/**
 * Where one session stands with the person, as its tab and the attention
 * order read it. Times are epoch milliseconds.
 */
export interface TabWait {
  /** What `notify.ts` has folded of the session's events so far. */
  readonly watch: Watch;
  /**
   * A permission or form open in it, and since when; kept while the session
   * is in front too, as it lasts until it is answered.
   */
  readonly asking?: { readonly on: Asking; readonly since: number } | undefined;
  /**
   * A turn that ended, or failed, or an agent that never came up, while the
   * session was behind, or a message from another agent that came in then,
   * and since when; gone once the person goes to it.
   */
  readonly unseen?:
    | {
        readonly kind: 'replied' | 'failed' | 'message';
        readonly since: number;
        /** Who a message came from, by the name its row gives. */
        readonly from?: string;
        /** A failure's cause, the gravest seen since it was last looked at. */
        readonly failure?: Failure;
      }
    | undefined;
  /** When the turn running now began, while one runs. */
  readonly working?: number | undefined;
  /** Its agent has exited. */
  readonly exited?: true;
}

/**
 * What failed: the agent's process exited, the agent never came up, or a
 * turn failed with the agent still open, gravest first.
 */
export type Failure = 'exited' | 'start' | 'turn';

export const FAILURES: readonly Failure[] = ['exited', 'start', 'turn'];

/** The graver of two failures. */
function graver(a: Failure | undefined, b: Failure): Failure {
  return a !== undefined && FAILURES.indexOf(a) < FAILURES.indexOf(b) ? a : b;
}

/** A wait's failure, if it has one: an exit, while the agent is gone, first. */
export function failureOf(wait: TabWait): Failure | undefined {
  if (wait.unseen?.kind !== 'failed') {
    return undefined;
  }

  return wait.exited ? 'exited' : (wait.unseen.failure ?? 'turn');
}

export const idle: TabWait = { watch: emptyWatch };

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
 * A long-lived agent open in a session: no tab of its own, but a session
 * the person can pick in its parent's tab, keyed as a tab is, from the same
 * keys, so the window keeps its state beside the tabs'.
 */
export interface Child<C> extends ChildInfo {
  readonly key: number;
  readonly conversation: C;
  readonly wait: TabWait;
}

/**
 * One open session. `key` names it for as long as it is open; its place in
 * the strip, and so its number, moves as tabs to its left close.
 */
export interface Tab<C> {
  readonly key: number;
  readonly agent: string;
  readonly conversation: C;
  readonly wait: TabWait;
  /** Its long-lived agents, in the order they opened. */
  readonly children: readonly Child<C>[];
  /** The agent the prompt goes to: the tab's own key, or a child's. */
  readonly picked: number;
  /**
   * The children it closed, by chord's id, so a message to one answers that
   * it is closed rather than that it never was.
   */
  readonly closed: readonly ChildInfo[];
  /** How many children it has opened, which colours the next. */
  readonly opened: number;
}

/** The open sessions in the order they were opened, and the one in front. */
export interface Tabs<C> {
  readonly tabs: readonly Tab<C>[];
  /** The front tab's key; none once the last one has closed. */
  readonly front: number | undefined;
  /** The key the next tab opened gets; keys are never reused. */
  readonly nextKey: number;
  /**
   * The tab `attend` last went to and its place in the attention order then,
   * kept until another tab comes forward: going there clears an unseen reply,
   * which takes the tab out of the order, and the next press still has to
   * know where in the queue it stood.
   */
  readonly attended?: { readonly key: number; readonly rank: Rank } | undefined;
}

/** A tab's place in the attention order, compared field by field. */
export interface Rank {
  /** Waits on a permission or form come before unseen replies and failures. */
  readonly unseen: boolean;
  readonly since: number;
  /**
   * A tie goes to the tab further left. By key rather than by place: tabs
   * open at the end and never move, so keys run left to right as places do,
   * but a key stays put when a tab to its left closes, and a rank kept in
   * `attended` must still compare true after that.
   */
  readonly key: number;
}

export function noTabs<C>(): Tabs<C> {
  return { tabs: [], front: undefined, nextKey: 1 };
}

export function frontTab<C>(tabs: Tabs<C>): Tab<C> | undefined {
  return tabs.tabs.find((tab) => tab.key === tabs.front);
}

export function tabOf<C>(tabs: Tabs<C>, key: number): Tab<C> | undefined {
  return tabs.tabs.find((tab) => tab.key === key);
}

/**
 * The tab `key` names, or the tab of the child it names, with that child;
 * none for a key that is neither open.
 */
export function agentOf<C>(
  tabs: Tabs<C>,
  key: number,
): { readonly tab: Tab<C>; readonly child?: Child<C> } | undefined {
  for (const tab of tabs.tabs) {
    if (tab.key === key) {
      return { tab };
    }

    const child = tab.children.find((each) => each.key === key);

    if (child) {
      return { tab, child };
    }
  }

  return undefined;
}

/** The key whose session fills the window: the front tab's pick. */
export function shownKey<C>(tabs: Tabs<C>): number | undefined {
  return frontTab(tabs)?.picked;
}

/** The child of `tab` that the prompt goes to; none while `main` is picked. */
export function pickedChild<C>(tab: Tab<C>): Child<C> | undefined {
  return tab.children.find((child) => child.key === tab.picked);
}

/** Whether `child` is a team's lead rather than a member or an M4 child. */
export function isLead(child: ChildInfo): boolean {
  return child.team !== undefined && child.lead === undefined;
}

/** The open members of the lead with chord's id `lead`, in their order. */
export function membersOf<C>(tab: Tab<C>, lead: string): Child<C>[] {
  return tab.children.filter((child) => child.lead === lead);
}

/**
 * A child as a sentence about it names it: its own name, or a member's with
 * its run after it, `tester · bugfix 2`, while another agent of the tab has
 * that name too, as two runs each have a `tester`.
 */
export function namedChild<C>(tab: Tab<C>, child: ChildInfo): string {
  const lead =
    child.lead === undefined
      ? undefined
      : tab.children.find((each) => each.id === child.lead);
  const shared = tab.children.some(
    (each) => each.id !== child.id && each.name === child.name,
  );

  return lead !== undefined && shared
    ? `${child.name} · ${lead.name}`
    : child.name;
}

/** Each wait in the tab: its own, then its children's, in their order. */
export function waitsOf<C>(tab: Tab<C>): TabWait[] {
  return [tab.wait, ...tab.children.map((child) => child.wait)];
}

function earliest<T extends { readonly since: number }>(
  all: readonly (T | undefined)[],
): T | undefined {
  return all.reduce<T | undefined>(
    (first, each) =>
      each !== undefined && (first === undefined || each.since < first.since)
        ? each
        : first,
    undefined,
  );
}

/**
 * The tab's agents' waits as one, as its glyph and the notice of a tab
 * behind read it: the longest permission or form any agent waits on, a
 * failure before a reply, the earliest turn running. A message between its
 * agents is no wait of the tab's.
 */
export function mergedWait<C>(tab: Tab<C>): TabWait {
  const waits = waitsOf(tab);

  if (waits.length === 1) {
    return tab.wait;
  }

  const unseen = (kind: 'failed' | 'replied') =>
    earliest(
      waits.map((wait) =>
        wait.unseen?.kind === kind ? wait.unseen : undefined,
      ),
    );
  const working = waits.flatMap((wait) =>
    wait.working === undefined ? [] : [wait.working],
  );

  return {
    watch: tab.wait.watch,
    asking: earliest(waits.map((wait) => wait.asking)),
    unseen: unseen('failed') ?? unseen('replied'),
    working: working.length === 0 ? undefined : Math.min(...working),
  };
}

/**
 * The child of `tab` whose wait `mergedWait` names, the one asking longest;
 * none when it is the tab's own or nobody asks.
 */
export function askingChild<C>(tab: Tab<C>): Child<C> | undefined {
  const asking = mergedWait(tab).asking;

  return asking === undefined || asking === tab.wait.asking
    ? undefined
    : tab.children.find((child) => child.wait.asking === asking);
}

/**
 * The child of `tab` whose wait `mergedWait` names: the one asking longest,
 * or with none asking, the one whose failure is the oldest unseen; none when
 * it is the tab's own.
 */
export function waitingChild<C>(tab: Tab<C>): Child<C> | undefined {
  const asking = askingChild(tab);
  const merged = mergedWait(tab);

  if (asking !== undefined || merged.asking !== undefined) {
    return asking;
  }

  const unseen = merged.unseen;

  return unseen?.kind !== 'failed' || unseen === tab.wait.unseen
    ? undefined
    : tab.children.find((child) => child.wait.unseen === unseen);
}

/**
 * A child's name: the one asked for, or its runtime, numbered past the first
 * (`codex`, `codex 2`), and never one another open agent of the session
 * goes by, `main` and `chord` included, as a message names its sender so.
 */
export function childName<C>(
  tab: Tab<C>,
  asked: string | undefined,
  runtime: string,
): string {
  const base = asked?.trim() || runtime;
  const taken = new Set(['main', 'chord', ...tab.children.map((c) => c.name)]);

  return numbered(base, taken);
}

/**
 * A run's lead's name: the team's, numbered past the first run as a second
 * child of one runtime is (`bugfix 2`); a closed run's number is not given
 * again while the window is open, so a name in an old message still means
 * the run it meant.
 */
export function runName<C>(tab: Tab<C>, team: string): string {
  return numbered(
    team,
    new Set([
      'main',
      'chord',
      ...tab.children.map((child) => child.name),
      ...tab.closed.filter(isLead).map((child) => child.name),
    ]),
  );
}

function numbered(base: string, taken: ReadonlySet<string>): string {
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
 * Opens a child in tab `tabKey` under the next key, at the end of its
 * list, or a member after its lead's last, so a team's agents stay
 * together, with the next colour; the pick stays where it is. None for a
 * tab that is not open, or, for one of main's own, already has
 * `MAX_CHILDREN` of them.
 */
export function openChild<C>(
  tabs: Tabs<C>,
  tabKey: number,
  info: Omit<ChildInfo, 'colour'>,
  conversation: C,
): { readonly tabs: Tabs<C>; readonly key: number } | undefined {
  const tab = tabOf(tabs, tabKey);

  if (
    !tab ||
    (info.lead === undefined && ownChildren(tab).length >= MAX_CHILDREN)
  ) {
    return undefined;
  }

  const key = tabs.nextKey;
  const child: Child<C> = {
    ...info,
    colour: tab.opened,
    key,
    conversation,
    wait: idle,
  };
  const after =
    info.lead === undefined
      ? -1
      : tab.children.findLastIndex(
          (each) => each.id === info.lead || each.lead === info.lead,
        );
  const children =
    after === -1
      ? [...tab.children, child]
      : tab.children.toSpliced(after + 1, 0, child);

  return {
    key,
    tabs: {
      ...tabs,
      nextKey: key + 1,
      tabs: tabs.tabs.map((each) =>
        each === tab ? { ...tab, children, opened: tab.opened + 1 } : each,
      ),
    },
  };
}

/** The session's own children: those it opened, a team's lead among them. */
export function ownChildren<C>(tab: Tab<C>): Child<C>[] {
  return tab.children.filter((child) => child.lead === undefined);
}

/**
 * Takes child `key` out of its tab and keeps it among the closed; a pick on
 * it goes back to `main`.
 */
export function closeChild<C>(tabs: Tabs<C>, key: number): Tabs<C> {
  const found = agentOf(tabs, key);
  const child = found?.child;

  if (!found || !child) {
    return tabs;
  }

  const { tab } = found;
  const { key: _, conversation: __, wait: ___, ...info } = child;

  return {
    ...tabs,
    attended: tabs.attended?.key === key ? undefined : tabs.attended,
    tabs: tabs.tabs.map((each) =>
      each === tab
        ? {
            ...tab,
            children: tab.children.filter((other) => other !== child),
            picked: tab.picked === key ? tab.key : tab.picked,
            closed: [...tab.closed, info],
          }
        : each,
    ),
  };
}

/** `wait` with its `✓`, `✗` or `←` seen. */
function seen(wait: TabWait): TabWait {
  return wait.unseen === undefined ? wait : { ...wait, unseen: undefined };
}

/** `tab` with agent `key` picked and looked at. */
function picking<C>(tab: Tab<C>, key: number): Tab<C> {
  return {
    ...tab,
    picked: key,
    wait: key === tab.key ? seen(tab.wait) : tab.wait,
    children: tab.children.map((child) =>
      child.key === key ? { ...child, wait: seen(child.wait) } : child,
    ),
  };
}

/**
 * Picks agent `key`, `main` by the tab's own key or a child by its, and
 * puts its tab in front: the transcript and the prompt are that agent's,
 * and its marks are seen.
 */
export function pick<C>(tabs: Tabs<C>, key: number): Tabs<C> {
  const found = agentOf(tabs, key);

  if (!found) {
    return tabs;
  }

  return {
    ...tabs,
    front: found.tab.key,
    attended: undefined,
    tabs: tabs.tabs.map((tab) => (tab === found.tab ? picking(tab, key) : tab)),
  };
}

/**
 * Moves the front tab's pick `by` rows down its list, `main` first; none
 * when it would go above `main`, which hands the focus back to the box. The
 * last row stays the last.
 */
export function movePick<C>(tabs: Tabs<C>, by: number): Tabs<C> | undefined {
  const tab = frontTab(tabs);

  if (!tab) {
    return tabs;
  }

  const keys = [tab.key, ...tab.children.map((child) => child.key)];
  const at = keys.indexOf(tab.picked) + by;

  if (at < 0) {
    return undefined;
  }

  return pick(tabs, keys[Math.min(at, keys.length - 1)]!);
}

/** The tab's number, as its direct key and the strip show it; 1-based. */
export function position<C>(tabs: Tabs<C>, key: number): number | undefined {
  const index = tabs.tabs.findIndex((tab) => tab.key === key);

  return index === -1 ? undefined : index + 1;
}

/**
 * What a notification calls the session: its agent alone while it is the
 * only one, so a single session reads as it always has, and with its number
 * once there are more.
 */
export function tabName<C>(tabs: Tabs<C>, key: number): string | undefined {
  const tab = tabOf(tabs, key);

  if (!tab) {
    return undefined;
  }

  return tabs.tabs.length === 1
    ? tab.agent
    : `${tab.agent} (${position(tabs, key)})`;
}

/**
 * What a notification calls agent `key`: a tab as `tabName` does, a child by
 * its name, and a member with its run, `tester (bugfix)`, as the person may
 * be looking anywhere when it comes; none for a key that is not open.
 */
export function notifiedName<C>(
  tabs: Tabs<C>,
  key: number,
): string | undefined {
  const found = agentOf(tabs, key);
  const child = found?.child;

  if (found === undefined || child === undefined) {
    return tabName(tabs, key);
  }

  const lead =
    child.lead === undefined
      ? undefined
      : found.tab.children.find((each) => each.id === child.lead);

  return lead === undefined ? child.name : `${child.name} (${lead.name})`;
}

export function full<C>(tabs: Tabs<C>): boolean {
  return tabs.tabs.length >= MAX_TABS;
}

/**
 * A new session at the end of the strip, in front, as a tmux window opens;
 * none past the cap.
 */
export function openTab<C>(
  tabs: Tabs<C>,
  agent: string,
  conversation: C,
): { readonly tabs: Tabs<C>; readonly key: number } | undefined {
  if (full(tabs)) {
    return undefined;
  }

  const key = tabs.nextKey;

  return {
    key,
    tabs: {
      tabs: [
        ...tabs.tabs,
        {
          key,
          agent,
          conversation,
          wait: idle,
          children: [],
          picked: key,
          closed: [],
          opened: 0,
        },
      ],
      front: key,
      nextKey: key + 1,
    },
  };
}

/**
 * Puts a tab in front, on the agent picked in it. Being looked at is what
 * clears that agent's `✓` or `✗`; a `●` stays until it is answered.
 */
export function show<C>(tabs: Tabs<C>, key: number): Tabs<C> {
  const tab = tabOf(tabs, key);

  return tab ? pick(tabs, tab.picked) : tabs;
}

/**
 * Takes a tab out. The ones to its right move down a number. When it was in
 * front, the one to its left comes forward, or the one to its right when it
 * was the first, so the person stays near where they were.
 */
export function closeTab<C>(tabs: Tabs<C>, key: number): Tabs<C> {
  const index = tabs.tabs.findIndex((tab) => tab.key === key);

  if (index === -1) {
    return tabs;
  }

  const left = tabs.tabs.filter((tab) => tab.key !== key);

  if (tabs.front !== key) {
    return { ...tabs, tabs: left };
  }

  const next = left[index - 1] ?? left[index];
  const closed = { ...tabs, tabs: left, front: undefined };

  return next ? show(closed, next.key) : closed;
}

function step<C>(tabs: Tabs<C>, by: number): Tabs<C> {
  const count = tabs.tabs.length;
  const index = tabs.tabs.findIndex((tab) => tab.key === tabs.front);

  if (count === 0 || index === -1) {
    return tabs;
  }

  const next = tabs.tabs[(index + by + count) % count];

  return next ? show(tabs, next.key) : tabs;
}

/** The next tab, round to the first after the last. */
export function nextTab<C>(tabs: Tabs<C>): Tabs<C> {
  return step(tabs, 1);
}

/** The previous tab, round to the last before the first. */
export function previousTab<C>(tabs: Tabs<C>): Tabs<C> {
  return step(tabs, -1);
}

/** The tab numbered `n`; a number with no tab leaves things as they are. */
export function goTo<C>(tabs: Tabs<C>, n: number): Tabs<C> {
  const tab = tabs.tabs[n - 1];

  return tab ? show(tabs, tab.key) : tabs;
}

function compare(a: Rank, b: Rank): number {
  return (
    Number(a.unseen) - Number(b.unseen) || a.since - b.since || a.key - b.key
  );
}

/**
 * The agents that want the person, tabs and children alike, most urgent
 * first: those that wait on a permission or form, longest waiting first,
 * then those with a reply or failure not yet seen, oldest first. A message
 * between agents wants no one: the turn it starts says so.
 */
function ranked<C>(
  tabs: Tabs<C>,
): { readonly key: number; readonly rank: Rank }[] {
  return tabs.tabs
    .flatMap((tab) => [tab, ...tab.children])
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
export function attentionOrder<C>(tabs: Tabs<C>): number[] {
  return ranked(tabs).map(({ key }) => key);
}

/**
 * Goes to the tab after the one in front in the attention order, or to the
 * first when the one in front has no place in it, round to the first after
 * the last; none when no other tab wants the person. Going from the front's
 * place rather than from the top is what lets pressing it again reach every
 * one: a tab waiting on a permission keeps its place once in front, and one
 * whose reply has just been seen is placed by where `attend` found it.
 */
export function attend<C>(tabs: Tabs<C>): Tabs<C> | undefined {
  const order = ranked(tabs);
  const shown = shownKey(tabs);
  const from =
    tabs.attended?.key === shown
      ? tabs.attended?.rank
      : order.find(({ key }) => key === shown)?.rank;
  const others = order.filter(({ key }) => key !== shown);
  const next =
    (from && others.find(({ rank }) => compare(rank, from) > 0)) ?? others[0];

  return next && { ...pick(tabs, next.key), attended: next };
}

/**
 * The tab number the sessions picker opens on: the tab `attend` would go
 * to, when another one, or else the one after the tab in front, round to
 * the first.
 */
export function listStart<C>(tabs: Tabs<C>): number | undefined {
  const attended = attend(tabs)?.front;
  const key =
    attended !== undefined && attended !== tabs.front
      ? attended
      : nextTab(tabs).front;

  return key === undefined ? undefined : position(tabs, key);
}

/**
 * Folds one of a session's events into its tab's wait state, and says the
 * wait it starts, if any, as `notify.ts` classes waits, in front or not.
 */
export function hear<C>(
  tabs: Tabs<C>,
  key: number,
  event: ConversationEvent,
  now: number,
): { readonly tabs: Tabs<C>; readonly wait?: Wait } {
  const found = agentOf(tabs, key);

  if (!found) {
    return { tabs };
  }

  const { tab, child } = found;
  const before = (child ?? tab).wait;
  const watched = watchWaits(before.watch, event);
  const wait = waitAfter(before, watched.watch, event, watched.wait, now, {
    front: shownKey(tabs) === key,
  });
  const next = {
    ...tabs,
    tabs: tabs.tabs.map((each) =>
      each !== tab
        ? each
        : child === undefined
          ? { ...tab, wait }
          : {
              ...tab,
              children: tab.children.map((other) =>
                other === child ? { ...child, wait } : other,
              ),
            },
    ),
  };

  return watched.wait === undefined
    ? { tabs: next }
    : { tabs: next, wait: watched.wait };
}

function waitAfter(
  before: TabWait,
  watch: Watch,
  event: ConversationEvent,
  started: Wait | undefined,
  now: number,
  { front }: { readonly front: boolean },
): TabWait {
  if (event.type === 'cleared') {
    return idle;
  }

  const asking =
    started !== undefined && started.kind !== 'turn_ended'
      ? { on: started, since: now }
      : watch.asking.size === 0
        ? undefined
        : before.asking;
  const failed =
    event.type === 'connect_failed' ||
    (started?.kind === 'turn_ended' &&
      event.type === 'result' &&
      event.result.status === 'failed');
  const ended = failed || started?.kind === 'turn_ended';
  const from =
    (event.type === 'prompt' || event.type === 'queued') && !front
      ? event.from && senderName(event.from)
      : undefined;
  // A failure outranks a reply in the same tab, and the wait counts from the
  // first of them; the reply to a message says more than the message did.
  const exits = event.type === 'disconnected' || before.exited === true;
  const failure =
    failed || before.unseen?.kind === 'failed'
      ? graver(
          before.unseen?.failure,
          exits ? 'exited' : event.type === 'connect_failed' ? 'start' : 'turn',
        )
      : undefined;
  const unseen = front
    ? before.unseen
    : ended
      ? failure === undefined
        ? { kind: 'replied' as const, since: before.unseen?.since ?? now }
        : {
            kind: 'failed' as const,
            since: before.unseen?.since ?? now,
            failure,
          }
      : // An exit after a failed turn says the agent went, not the turn.
        exits &&
          before.unseen?.kind === 'failed' &&
          before.unseen.failure !== 'exited'
        ? { ...before.unseen, failure: 'exited' as const }
        : from !== undefined &&
            before.unseen?.kind !== 'failed' &&
            before.unseen?.kind !== 'replied'
          ? {
              kind: 'message' as const,
              from,
              since: before.unseen?.since ?? now,
            }
          : before.unseen;
  const working =
    event.type === 'prompt'
      ? (before.working ?? event.at)
      : event.type === 'result' || event.type === 'connect_failed'
        ? undefined
        : before.working;

  return {
    watch,
    asking,
    unseen,
    working,
    ...(event.type === 'disconnected' || before.exited
      ? { exited: true as const }
      : {}),
  };
}
