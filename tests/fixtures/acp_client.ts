/**
 * A client of `chord acp` that speaks raw lines, over a stream pair or a
 * process's pipes, so a test sees the wire. Not the SDK's client, which would
 * hide a malformed message.
 */
import type { JsonRpcId } from '@agentclientprotocol/sdk/unstable';
import { until } from '../session/conversation_fake.ts';

/** One message off the wire, parsed; a test reads what it expects of it. */
export interface WireMessage {
  readonly jsonrpc?: string;
  readonly id?: JsonRpcId | null;
  readonly method?: string;
  readonly params?: Record<string, unknown>;
  readonly result?: Record<string, unknown>;
  readonly error?: {
    readonly code: number;
    readonly message: string;
    readonly data?: unknown;
  };
}

export class AcpClient {
  readonly #write: (line: string) => void;
  /** Every line chord wrote, as it came, however malformed. */
  readonly lines: string[] = [];
  #open = true;
  #next = 1;

  /**
   * `write` takes what the client says; `stdout` is read to its end, and
   * `closed` then holds.
   */
  constructor(
    write: (line: string) => void,
    stdout: AsyncIterable<Uint8Array | string>,
  ) {
    this.#write = write;

    void this.#read(stdout);
  }

  async #read(stdout: AsyncIterable<Uint8Array | string>): Promise<void> {
    const decoder = new TextDecoder();
    let held = '';

    try {
      for await (const chunk of stdout) {
        held +=
          typeof chunk === 'string'
            ? chunk
            : decoder.decode(chunk, { stream: true });

        const parts = held.split('\n');

        held = parts.pop() ?? '';

        this.lines.push(...parts);
      }
    } catch {
      // A pipe the other end broke ends the reading as its end would.
    }

    // What came with no line end is on the wire all the same: a test that
    // parses every line must see it.
    held += decoder.decode();

    if (held !== '') {
      this.lines.push(held);
    }

    this.#open = false;
  }

  /** Whether the other side has closed its stdout. */
  get closed(): boolean {
    return !this.#open;
  }

  get messages(): WireMessage[] {
    return this.lines.map((line) => JSON.parse(line) as WireMessage);
  }

  /** Writes a line as it is, as a client that sends garbage would. */
  raw(line: string): void {
    this.#write(`${line}\n`);
  }

  #send(message: object): void {
    this.raw(JSON.stringify({ jsonrpc: '2.0', ...message }));
  }

  /** Sends a request without waiting; its id. */
  send(method: string, params?: object): number {
    const id = this.#next;

    this.#next += 1;

    this.#send({ id, method, ...(params === undefined ? {} : { params }) });

    return id;
  }

  /** Until the answer to `id` comes, `result` or `error`. */
  answerTo(id: JsonRpcId): Promise<WireMessage> {
    return this.until(
      (message) => message.id === id && message.method === undefined,
    );
  }

  /** Sends a request and waits for its answer. */
  request(method: string, params?: object): Promise<WireMessage> {
    return this.answerTo(this.send(method, params));
  }

  notify(method: string, params?: object): void {
    this.#send({ method, ...(params === undefined ? {} : { params }) });
  }

  /** Answers a request chord made. */
  respond(id: JsonRpcId, result: object): void {
    this.#send({ id, result });
  }

  /** Answers a request chord made with an error. */
  respondError(id: JsonRpcId, code: number, message: string): void {
    this.#send({ id, error: { code, message } });
  }

  /** The first message that holds, waiting for it. */
  async until(
    check: (message: WireMessage) => boolean,
    timeout?: number,
  ): Promise<WireMessage> {
    let found: WireMessage | undefined;

    await until(() => {
      found = this.messages.find(check);

      return found !== undefined;
    }, timeout);

    return found as WireMessage;
  }

  /** The `session/update`s heard so far, for one session or all. */
  updates(sessionId?: string): Record<string, unknown>[] {
    return this.messages.flatMap((message) =>
      message.method === 'session/update' &&
      (sessionId === undefined || message.params?.sessionId === sessionId)
        ? [message.params?.update as Record<string, unknown>]
        : [],
    );
  }

  /** The text of the agent's chunks for a session, joined. */
  said(sessionId?: string): string {
    return this.updates(sessionId)
      .filter((update) => update.sessionUpdate === 'agent_message_chunk')
      .map((update) => (update.content as { text?: string }).text ?? '')
      .join('');
  }
}

/** A client over a stream pair, for `runAcp` in this process. */
export function clientOverStreams(): {
  readonly client: AcpClient;
  /** chord's stdin. */
  readonly input: ReadableStream<Uint8Array>;
  /** chord's stdout. */
  readonly output: WritableStream<Uint8Array>;
  /** Ends chord's stdin. */
  end(): void;
} {
  const encoder = new TextEncoder();
  const stdin = new TransformStream<Uint8Array, Uint8Array>();
  const stdout = new TransformStream<Uint8Array, Uint8Array>();
  const writer = stdin.writable.getWriter();
  const client = new AcpClient(
    (line) => {
      void writer.write(encoder.encode(line)).catch(() => {});
    },
    stdout.readable as unknown as AsyncIterable<Uint8Array>,
  );

  return {
    client,
    input: stdin.readable,
    output: stdout.writable,
    end: () => {
      void writer.close().catch(() => {});
    },
  };
}
