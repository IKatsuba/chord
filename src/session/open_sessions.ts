import type { Wait } from '../notify.ts';
import type { ConversationEvent } from './conversation.ts';
import {
  agentOf,
  attend,
  type ChildInfo,
  closeChild,
  closeTab,
  full,
  goTo,
  hear,
  movePick,
  nextTab,
  noTabs,
  openChild,
  openTab,
  pick,
  previousTab,
  shownKey,
  tabOf,
  type Tabs,
} from './tabs.ts';

/** What a tab drives: `Conversation`, or a stand-in in a test. */
export interface Driven {
  start(): void;
  close(): Promise<void>;
}

export interface OpenSessionsOptions<C extends Driven> {
  /**
   * A conversation for `agent`, not started yet, that reports through
   * `emit`, for the tab `key` names; each has its own agent process.
   */
  readonly conversation: (
    agent: string,
    emit: (event: ConversationEvent) => void,
    key: number,
  ) => C;
  /**
   * Each event a tab's conversation reports, once its wait state has taken
   * it in, and the wait it starts, if any. A closed tab's are not passed on.
   */
  readonly heard: (
    key: number,
    event: ConversationEvent,
    wait: Wait | undefined,
  ) => void;
  /**
   * Each event a closed tab's or child's conversation still reports as it
   * closes, a cancelled turn's end among them: what it spent then still
   * counts (CHD-373).
   */
  readonly closingHeard?: (key: number, event: ConversationEvent) => void;
  readonly now?: () => number;
}

/**
 * The sessions open in one window: `tabs.ts`'s state, with each tab's
 * conversation, and each long-lived child's, started when it opens and
 * closed when it closes, a tab's children with it, and its events folded
 * into its own wait state.
 */
export class OpenSessions<C extends Driven> {
  readonly #options: OpenSessionsOptions<C>;
  readonly #now: () => number;
  #tabs: Tabs<C> = noTabs();
  /**
   * Closes still under way, and those that failed, which stay until
   * `closeAll` has reported them, so it neither stops waiting early nor
   * says every agent closed when one did not.
   */
  readonly #closing = new Set<Promise<void>>();

  constructor(options: OpenSessionsOptions<C>) {
    this.#options = options;
    this.#now = options.now ?? Date.now;
  }

  get tabs(): Tabs<C> {
    return this.#tabs;
  }

  /** The conversation the prompt goes to: the front tab's pick. */
  get front(): C | undefined {
    const key = shownKey(this.#tabs);

    return key === undefined ? undefined : this.conversationOf(key);
  }

  /** The conversation of tab or child `key`; none once it has closed. */
  conversationOf(key: number): C | undefined {
    const found = agentOf(this.#tabs, key);

    return (found?.child ?? found?.tab)?.conversation;
  }

  /**
   * Opens a long-lived child in tab `tabKey`, made by `make` for its key,
   * and starts it; the pick stays where it is. None when the tab is not open
   * or has no room, and then nothing is started.
   */
  openChild(
    tabKey: number,
    info: Omit<ChildInfo, 'colour'>,
    make: (emit: (event: ConversationEvent) => void, key: number) => C,
  ): number | undefined {
    const tab = tabOf(this.#tabs, tabKey);
    const key = this.#tabs.nextKey;

    if (!tab) {
      return undefined;
    }

    const conversation = make((event) => this.#heard(key, event), key);
    const opened = openChild(this.#tabs, tabKey, info, conversation);

    if (!opened) {
      return undefined;
    }

    this.#tabs = opened.tabs;

    conversation.start();

    return key;
  }

  /**
   * Takes child `key` out of its tab at once and closes its agent; resolves
   * once the agent's process has exited.
   */
  closeChild(key: number): Promise<void> {
    const child = agentOf(this.#tabs, key)?.child;

    if (!child) {
      return Promise.resolve();
    }

    this.#tabs = closeChild(this.#tabs, key);

    return this.#closed(child.conversation.close());
  }

  /** Picks agent `key`, its tab coming to the front. */
  pick(key: number): void {
    this.#tabs = pick(this.#tabs, key);
  }

  /**
   * Moves the front tab's pick `by` rows; false when it would go above
   * `main`, which leaves it there.
   */
  movePick(by: number): boolean {
    const moved = movePick(this.#tabs, by);

    if (moved === undefined) {
      return false;
    }

    this.#tabs = moved;

    return true;
  }

  /**
   * Opens a session of `agent` at the end of the strip and brings it to the
   * front; none past the cap, and then nothing is started.
   */
  open(agent: string): number | undefined {
    if (full(this.#tabs)) {
      return undefined;
    }

    const key = this.#tabs.nextKey;
    const conversation = this.#options.conversation(
      agent,
      (event) => this.#heard(key, event),
      key,
    );
    const opened = openTab(this.#tabs, agent, conversation);

    if (!opened) {
      return undefined;
    }

    this.#tabs = opened.tabs;

    conversation.start();

    return key;
  }

  /**
   * Takes the tab out at once and closes its agent and its children's;
   * resolves once every one's process has exited.
   */
  close(key: number): Promise<void> {
    const tab = tabOf(this.#tabs, key);

    if (!tab) {
      return Promise.resolve();
    }

    this.#tabs = closeTab(this.#tabs, key);

    const closing = this.#closed(tab.conversation.close());

    if (tab.children.length === 0) {
      return closing;
    }

    const all = Promise.all([
      closing,
      ...tab.children.map((child) => this.#closed(child.conversation.close())),
    ]).then(() => {});

    // A caller that does not wait leaves no rejection unheard; `closeAll`
    // reports it.
    all.catch(() => {});

    return all;
  }

  /** Keeps `closing` for `closeAll` until it settles well. */
  #closed(closing: Promise<void>): Promise<void> {
    this.#closing.add(closing);
    closing.then(
      () => this.#closing.delete(closing),
      () => {},
    );

    return closing;
  }

  /**
   * Closes every tab at once and waits for every agent, those closed earlier
   * included; rejects with every failure once all have settled, an earlier
   * close's too, even one that failed before this was called.
   */
  async closeAll(): Promise<void> {
    for (const tab of this.#tabs.tabs) {
      void this.close(tab.key);
    }

    const closing = [...this.#closing];
    const results = await Promise.allSettled(closing);

    for (const each of closing) {
      this.#closing.delete(each);
    }

    const failures = results.flatMap((result) =>
      result.status === 'rejected' ? [result.reason] : [],
    );

    if (failures.length > 0) {
      throw new AggregateError(failures, 'Not every agent closed.');
    }
  }

  next(): void {
    this.#tabs = nextTab(this.#tabs);
  }

  previous(): void {
    this.#tabs = previousTab(this.#tabs);
  }

  /** Goes to tab `n`; false when there is no such tab. */
  goTo(n: number): boolean {
    const moved = goTo(this.#tabs, n);

    this.#tabs = moved;

    return moved.tabs[n - 1] !== undefined;
  }

  /** Goes to the tab that has waited longest; false when none waits. */
  attend(): boolean {
    const moved = attend(this.#tabs);

    if (!moved) {
      return false;
    }

    this.#tabs = moved;

    return true;
  }

  #heard(key: number, event: ConversationEvent): void {
    if (!agentOf(this.#tabs, key)) {
      this.#options.closingHeard?.(key, event);

      return;
    }

    const seen = hear(this.#tabs, key, event, this.#now());

    this.#tabs = seen.tabs;

    this.#options.heard(key, event, seen.wait);
  }
}
