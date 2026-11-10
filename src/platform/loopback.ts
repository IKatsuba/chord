/** A sign-in callback must be reachable on both loopback address families. */
import { serve, type Served, type ServeOptions } from './serve.ts';

export class LoopbackPortTaken extends Error {
  constructor(readonly port: number) {
    super(`Loopback port ${port} is taken by another program.`);

    this.name = 'LoopbackPortTaken';
  }
}

export interface LoopbackOptions {
  readonly port: number;
  readonly path: string;
  /** The attempt owns cancellation, including its deadline and leaving. */
  readonly signal: AbortSignal;
  /** A rejected OAuth state answers the browser without ending the wait. */
  readonly callback: (request: Request) => Promise<{
    readonly response: Response;
    readonly finish: boolean;
  }>;
}

type Listen = (
  options: ServeOptions,
  handler: (request: Request) => Response | Promise<Response>,
) => Served;

const codeOf = (error: unknown) =>
  error !== null && typeof error === 'object' && 'code' in error
    ? error.code
    : undefined;

/** Binds before the caller may show or open the provider's address. */
export async function loopback(
  options: LoopbackOptions,
  listen: Listen = serve,
): Promise<Served> {
  options.signal.throwIfAborted();

  const servers: Served[] = [];
  let closing: Promise<void> | undefined;
  const close = (): Promise<void> => {
    options.signal.removeEventListener('abort', abort);

    closing ??= Promise.all(servers.map((server) => server.close())).then(
      () => {},
    );

    return closing;
  };

  const abort = () => {
    void close();
  };

  const handler = async (request: Request) => {
    if (
      options.signal.aborted ||
      request.method !== 'GET' ||
      new URL(request.url).pathname !== options.path
    ) {
      return new Response('Not found.', { status: 404 });
    }

    const result = await options.callback(request);

    if (result.finish) {
      // Do not await this request's own connection closing in its handler.
      void close();
    }

    return result.response;
  };

  const bind = (hostname: string, port: number) =>
    listen(
      {
        hostname,
        port,
        onError: () => new Response('Sign-in failed.', { status: 500 }),
      },
      handler,
    );

  try {
    const v4 = bind('127.0.0.1', options.port);

    servers.push(v4);

    try {
      servers.push(bind('::1', v4.port));
    } catch (error) {
      if (
        !['EAFNOSUPPORT', 'EADDRNOTAVAIL', 'EPROTONOSUPPORT'].includes(
          String(codeOf(error)),
        )
      ) {
        await v4.close();

        servers.length = 0;

        throw error;
      }
    }

    options.signal.addEventListener('abort', abort, { once: true });

    if (options.signal.aborted) {
      await close();
      options.signal.throwIfAborted();
    }

    return { port: v4.port, close };
  } catch (error) {
    await close();

    if (codeOf(error) === 'EADDRINUSE') {
      throw new LoopbackPortTaken(options.port);
    }

    throw error;
  }
}
