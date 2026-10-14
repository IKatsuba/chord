import type { AnyMessage, Stream } from '@agentclientprotocol/sdk';

/**
 * One thing that crossed between chord and the agent: a JSON-RPC message
 * either way, as the relay left it, or what the agent wrote to stderr.
 */
export type Traffic =
  | { readonly from: 'agent'; readonly message: AnyMessage }
  | { readonly from: 'chord'; readonly message: AnyMessage }
  | { readonly from: 'stderr'; readonly text: string };

/**
 * What may stand between the agent and the rest of chord on the wire, as an
 * ACP proxy would: it hears each message chord sends, and turns each one the
 * agent sends into the messages chord reads in its place, in order.
 */
export interface Relay {
  fromChord(message: AnyMessage): void;
  fromAgent(message: AnyMessage): readonly AnyMessage[];
}

/**
 * `stream` with `relay` on it: chord's messages pass as written, once the
 * relay has heard them; the agent's are what the relay makes of them.
 */
export function relayStream(stream: Stream, relay: Relay): Stream {
  const writer = stream.writable.getWriter();

  return {
    readable: stream.readable.pipeThrough(
      new TransformStream<AnyMessage, AnyMessage>({
        transform(message, controller) {
          for (const each of relay.fromAgent(message)) {
            controller.enqueue(each);
          }
        },
      }),
    ),
    writable: new WritableStream<AnyMessage>({
      write(message) {
        relay.fromChord(message);

        return writer.write(message);
      },
      close: () => writer.close(),
      abort: (reason) => writer.abort(reason),
    }),
  };
}

/**
 * Hands every message on `stream` to `onTraffic` as it crosses, in wire order,
 * before the SDK sees it, so an update sent ahead of a reply reaches the
 * subscriber before the reply's promise settles.
 *
 * The agent's notifications stop here. The subscriber has them already,
 * and the SDK would only check them against its schema: an update of a kind it
 * does not know fails that check, and it says so on the console, under the
 * window. `$/cancel_request` still goes through, as the SDK acts on it.
 */
export function tapStream(
  stream: Stream,
  onTraffic: (traffic: Traffic) => void,
): Stream {
  const writer = stream.writable.getWriter();

  return {
    readable: stream.readable.pipeThrough(
      new TransformStream<AnyMessage, AnyMessage>({
        transform(message, controller) {
          onTraffic({ from: 'agent', message });

          if (forSdk(message)) {
            controller.enqueue(message);
          }
        },
      }),
    ),
    writable: new WritableStream<AnyMessage>({
      write(message) {
        onTraffic({ from: 'chord', message });

        return writer.write(message);
      },
      close: () => writer.close(),
      abort: (reason) => writer.abort(reason),
    }),
  };
}

/** Requests and responses, which the SDK answers and matches; not updates. */
function forSdk(message: AnyMessage): boolean {
  return (
    'id' in message ||
    ('method' in message && message.method === '$/cancel_request')
  );
}
