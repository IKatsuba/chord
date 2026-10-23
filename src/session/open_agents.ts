import type { Wait } from '../notify.ts';
import type { ConversationEvent } from './conversation.ts';
import {
  agentOf,
  attend,
  type ChildInfo,
  closeChild,
  forgetClosed,
  hear,
  keyed,
  movePick,
  noAgents,
  openChild,
  openMain,
  pick,
  shownKey,
  type WindowAgents,
} from './window_agents.ts';

/** What an agent of the window drives: `Conversation`, or a stand-in in a test. */
export interface Driven {
  start(): void;
  close(): Promise<void>;
}

export interface OpenAgentsOptions<C extends Driven> {
  /**
   * Main's conversation for `agent`, not started yet, that reports through
   * `emit`, under the key `key`; it has its own agent process.
   */
  readonly conversation: (
    agent: string,
    emit: (event: ConversationEvent) => void,
    key: number,
  ) => C;
  /**
   * Each event an agent's conversation reports, once its wait state has
   * taken it in, and the wait it starts, if any. A closed child's are not
   * passed on.
   */
  readonly heard: (
    key: number,
    event: ConversationEvent,
    wait: Wait | undefined,
  ) => void;
  /**
   * Each event a closed child's or main's conversation still reports as it
   * closes, a cancelled turn's end among them: what it spent then still
   * counts (CHD-373).
   */
  readonly closingHeard?: (key: number, event: ConversationEvent) => void;
  readonly now?: () => number;
}

/**
 * The window's agents open: `window_agents.ts`'s state, with main's
 * conversation and each long-lived child's, started when it opens and
 * closed when it closes, and its events folded into its own wait state.
 */
export class OpenAgents<C extends Driven> {
  readonly #options: OpenAgentsOptions<C>;
  readonly #now: () => number;
  #agents: WindowAgents<C> = noAgents();
  /**
   * Closes still under way, and those that failed, which stay until
   * `closeAll` has reported them, so it neither stops waiting early nor
   * says every agent closed when one did not.
   */
  readonly #closing = new Set<Promise<void>>();

  constructor(options: OpenAgentsOptions<C>) {
    this.#options = options;
    this.#now = options.now ?? Date.now;
  }

  get agents(): WindowAgents<C> {
    return this.#agents;
  }

  /** The conversation the prompt goes to: the picked agent's. */
  get front(): C | undefined {
    const key = shownKey(this.#agents);

    return key === undefined ? undefined : this.conversationOf(key);
  }

  /** The conversation of main or child `key`; none once it has closed. */
  conversationOf(key: number): C | undefined {
    const found = agentOf(this.#agents, key);

    return (found?.child ?? found?.main)?.conversation;
  }

  /**
   * Makes and starts main's conversation, of `agent`; once, as main's key
   * is the window's for its life. Its key, or none on a second call.
   */
  start(agent: string): number | undefined {
    if (this.#agents.main !== undefined) {
      return undefined;
    }

    const key = this.#agents.nextKey;
    const conversation = this.#options.conversation(
      agent,
      (event) => this.#heard(key, event),
      key,
    );

    this.#agents = openMain(this.#agents, agent, conversation);

    conversation.start();

    return key;
  }

  /**
   * Opens a long-lived child, made by `make` for its key, and starts it;
   * the pick stays where it is. None before main starts or with no room,
   * and then nothing is started.
   */
  openChild(
    info: Omit<ChildInfo, 'colour'>,
    make: (emit: (event: ConversationEvent) => void, key: number) => C,
  ): number | undefined {
    if (this.#agents.main === undefined) {
      return undefined;
    }

    const key = this.#agents.nextKey;
    const conversation = make((event) => this.#heard(key, event), key);
    const opened = openChild(this.#agents, info, conversation);

    if (!opened) {
      return undefined;
    }

    this.#agents = opened.agents;

    conversation.start();

    return key;
  }

  /**
   * Takes child `key` out at once and closes its agent; resolves once the
   * agent's process has exited.
   */
  closeChild(key: number): Promise<void> {
    const child = agentOf(this.#agents, key)?.child;

    if (!child) {
      return Promise.resolve();
    }

    this.#agents = closeChild(this.#agents, key);

    return this.#closed(child.conversation.close());
  }

  /** Forgets the children closed, as a new or resumed session starts. */
  forgetClosed(): void {
    this.#agents = forgetClosed(this.#agents);
  }

  /** Picks agent `key`. */
  pick(key: number): void {
    this.#agents = pick(this.#agents, key);
  }

  /**
   * Moves the pick `by` rows; false when it would go above `main`, which
   * leaves it there.
   */
  movePick(by: number): boolean {
    const moved = movePick(this.#agents, by);

    if (moved === undefined) {
      return false;
    }

    this.#agents = moved;

    return true;
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
   * Closes main and every child at once and waits for every agent, those
   * closed earlier included; rejects with every failure once all have
   * settled, an earlier close's too, even one that failed before this was
   * called.
   */
  async closeAll(): Promise<void> {
    const { main, children } = this.#agents;

    this.#agents = { ...this.#agents, main: undefined, children: [] };

    for (const each of [...(main === undefined ? [] : [main]), ...children]) {
      void this.#closed(each.conversation.close());
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

  /** A key pressed in chord: the agent shown has been looked at. */
  keyed(): void {
    this.#agents = keyed(this.#agents);
  }

  /** Goes to the agent that has waited longest; false when none waits. */
  attend(): boolean {
    const moved = attend(this.#agents);

    if (!moved) {
      return false;
    }

    this.#agents = moved;

    return true;
  }

  #heard(key: number, event: ConversationEvent): void {
    if (!agentOf(this.#agents, key)) {
      this.#options.closingHeard?.(key, event);

      return;
    }

    const seen = hear(this.#agents, key, event, this.#now());

    this.#agents = seen.agents;

    this.#options.heard(key, event, seen.wait);
  }
}
