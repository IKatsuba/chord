/**
 * HTTP serving on `Bun.serve`, the one thing here a runtime does its own way.
 */

export interface ServeOptions {
  readonly hostname: string;
  /** 0 for one the system picks. */
  readonly port: number;
  /** The answer to a request whose handler threw. */
  readonly onError: (error: unknown) => Response;
}

/** A server listening, its port known. */
export interface Served {
  readonly port: number;
  /** Stops listening, and settles once every connection has closed. */
  close(): Promise<void>;
}

/** Starts listening at once; nothing is written to stdout or stderr. */
export function serve(
  options: ServeOptions,
  handler: (request: Request) => Response | Promise<Response>,
): Served {
  const server = Bun.serve({
    hostname: options.hostname,
    port: options.port,
    // Bun cuts a connection idle for 10 s by default, and an MCP stream sits
    // idle for as long as a tool waits on the person.
    idleTimeout: 0,
    // Nothing may write over the window: no stack, no error page.
    development: false,
    fetch: handler,
    error: options.onError,
  });

  return {
    // Undefined only for a server on a Unix socket.
    port: server.port!,
    close: () => server.stop(),
  };
}
