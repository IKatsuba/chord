/**
 * chord's own stdout as ACP's writable side.
 */
import type {
  AnyMessage,
  JsonRpcId,
  Stream,
} from '@agentclientprotocol/sdk/unstable';

/** What a stream on stdout needs of it. */
export interface WritableOutput {
  write(chunk: Uint8Array, callback: (error?: Error | null) => void): unknown;
}

/**
 * A stream whose write settles on the output's callback, as `process.ts` wraps
 * an agent's stdin. `Writable.toWeb(process.stdout)` loses data under Bun:
 * 65,536 of 16 MiB arrived before `process.exit`. `Bun.write(Bun.stdout)` blocks
 * the loop, where a client that stops reading must not stop chord.
 */
export function outputStream(
  output: WritableOutput,
): WritableStream<Uint8Array> {
  return new WritableStream({
    write: (chunk) =>
      new Promise<void>((resolve, reject) => {
        output.write(chunk, (error) => (error ? reject(error) : resolve()));
      }),
  });
}

/** A connection's stream, and what it can say of its answers' writes. */
export interface SeenStream {
  readonly stream: Stream;
  /** The answer to this request is on its way, so `drained` waits for it. */
  expect(id: JsonRpcId): void;
  /** Settles once every expected answer is written, or none can be. */
  drained(): Promise<void>;
}

/**
 * The SDK's `close()` has no drain and drops what is queued behind it, and
 * nothing it exports tells when a message has gone: this sees each one written.
 */
export function seeingWrites(stream: Stream): SeenStream {
  const expected = new Set<JsonRpcId>();
  let settled = Promise.withResolvers<void>();

  const settleWhenEmpty = () => {
    if (expected.size === 0) {
      settled.resolve();
    }
  };

  const giveUp = () => {
    expected.clear();
    settled.resolve();
  };

  return {
    stream: {
      readable: stream.readable,
      writable: new WritableStream<AnyMessage>({
        write: async (message) => {
          const writer = stream.writable.getWriter();

          try {
            await writer.write(message);
          } catch (error) {
            giveUp();

            throw error;
          } finally {
            writer.releaseLock();
          }

          if ('id' in message && !('method' in message)) {
            expected.delete(message.id);
            settleWhenEmpty();
          }
        },
        close: async () => {
          giveUp();

          await stream.writable.close();
        },
        abort: async (reason) => {
          giveUp();

          await stream.writable.abort(reason);
        },
      }),
    },
    expect: (id) => {
      if (expected.size === 0) {
        settled = Promise.withResolvers<void>();
      }

      expected.add(id);
    },
    drained: () => {
      settleWhenEmpty();

      return settled.promise;
    },
  };
}
