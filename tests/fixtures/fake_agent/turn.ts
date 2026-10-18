/**
 * A turn as every scenario plays it: the updates it sends on its session, at
 * the agent's pace, and the ids of the calls it starts.
 */
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from './options.ts';

export type Client = acp.AgentContext;
export type Update = acp.SessionUpdate;

/** A scenario: it plays one turn and says how the turn ended. */
export type Play = (turn: Turn) => Promise<acp.StopReason>;

export function pause(signal: AbortSignal, ms = STEP_MS): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      return reject(signal.reason);
    }

    const timer = setTimeout(() => {
      signal.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(signal.reason);
    };

    signal.addEventListener('abort', onAbort, { once: true });
  });
}

/**
 * Aborted once the client has closed the connection: work that outlives
 * every turn, a background subagent or a stop held for a test, ends on it,
 * so no timer keeps the process alive after its client left.
 */
export const lifetime = new AbortController();

/** How many tool calls each session has started, to number the next one. */
const callCounts = new Map<string, number>();

/**
 * A mark for each session this process loaded or resumed rather than created.
 * An earlier process numbered that session's calls already, so a call this one
 * numbers from 1 again would take an id the session has used.
 */
export const loadMarks = new Map<string, string>();

/** Who a message chord wrapped is from, as its row names them first. */
export function senderOf(text: string): string | undefined {
  return /^<message from="([^"]*)"/.exec(text)?.[1]?.split(' · ')[0];
}

export class Turn {
  /** Token usage the turn's answer reports, as ACP's `PromptResponse.usage`. */
  usage: acp.Usage | undefined;
  /** Messages steered into the turn that its next step has not read yet. */
  readonly #steered: string[] = [];

  constructor(
    readonly client: Client,
    readonly sessionId: string,
    readonly signal: AbortSignal,
  ) {}

  /**
   * A new call's id. ACP holds a tool call id unique within its session, and a
   * client folds every update under an id into one call, so a fixed id would
   * fold a later turn's call into an earlier one.
   */
  callId(name: string): string {
    const count = (callCounts.get(this.sessionId) ?? 0) + 1;

    callCounts.set(this.sessionId, count);

    const mark = loadMarks.get(this.sessionId);

    return mark === undefined ? `${name}-${count}` : `${name}-${mark}-${count}`;
  }

  async send(update: Update): Promise<void> {
    await pause(this.signal);
    await this.read();
    await this.client.notify('session/update', {
      sessionId: this.sessionId,
      update,
    });
  }

  /**
   * A message steered into the turn: read at the turn's next step, as the
   * adapters' agents read one, or as the turn ends.
   */
  steer(text: string): void {
    this.#steered.push(text);
  }

  /** Answers each message steered in since the last step, saying whose. */
  async read(): Promise<void> {
    for (const text of this.#steered.splice(0)) {
      await this.client.notify('session/update', {
        sessionId: this.sessionId,
        update: {
          sessionUpdate: 'agent_message_chunk',
          content: {
            type: 'text',
            text: `Read the message from ${senderOf(text) ?? 'nobody'}.\n\n`,
          },
        },
      });
    }
  }

  async say(...chunks: string[]): Promise<void> {
    for (const text of chunks) {
      await this.send({
        sessionUpdate: 'agent_message_chunk',
        content: { type: 'text', text },
      });
    }
  }

  async think(...chunks: string[]): Promise<void> {
    for (const text of chunks) {
      await this.send({
        sessionUpdate: 'agent_thought_chunk',
        content: { type: 'text', text },
      });
    }
  }
}
