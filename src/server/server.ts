/**
 * chord's own MCP server: one per window, on the loopback at a port the
 * system picks, over Streamable HTTP. Every session the window opens gets a
 * token of its own, which says which session calls and so which tools it
 * has; a request without a token chord gave out is refused.
 */
import type { McpServer as AcpMcpServer } from '@agentclientprotocol/sdk';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import manifest from '../../package.json' with { type: 'json' };
import { serve } from '../platform/serve.ts';
import { type Caller, registerTools } from './tools.ts';

/** The name chord's server goes to the agent under, beside the user's. */
export const SERVER_NAME = 'chord';

/** A session let in: its token, and the server entry that carries it. */
export interface Admitted {
  readonly token: string;
  /** For ACP's `mcpServers`, beside the user's. */
  readonly server: AcpMcpServer;
}

export interface ChordServer {
  readonly url: string;
  /** A token for a session of `caller`'s, until it is revoked. */
  admit(caller: Caller): Admitted;
  /** Refuses the token from now on, and ends the MCP sessions it opened. */
  revoke(token: string): void;
  /** Ends every MCP session and stops listening. */
  close(): Promise<void>;
}

/** An MCP session the agent opened, and the token it opened it with. */
interface Opened {
  readonly token: string;
  readonly transport: WebStandardStreamableHTTPServerTransport;
}

/** A JSON-RPC error with no id, as the SDK's transport answers one. */
function refused(status: number, message: string): Response {
  return Response.json(
    { jsonrpc: '2.0', error: { code: -32000, message }, id: null },
    { status },
  );
}

function bearer(request: Request): string | undefined {
  const match = /^Bearer (.+)$/.exec(
    request.headers.get('authorization') ?? '',
  );

  return match?.[1];
}

/** Starts listening at once; the URL is known when this returns. */
export function serveChord(): ChordServer {
  const callers = new Map<string, Caller>();
  const opened = new Map<string, Opened>();

  const end = (id: string) => {
    const session = opened.get(id);

    opened.delete(id);
    void session?.transport.close().catch(() => {});
  };

  const handle = async (request: Request): Promise<Response> => {
    const token = bearer(request);
    const caller = token === undefined ? undefined : callers.get(token);

    if (token === undefined || caller === undefined) {
      return refused(401, 'Unknown token');
    }

    const id = request.headers.get('mcp-session-id');

    if (id !== null) {
      const session = opened.get(id);

      if (session === undefined) {
        return refused(404, 'Session not found');
      }

      // A token opens its own sessions alone, so no session speaks as another.
      if (session.token !== token) {
        return refused(403, 'Session opened with another token');
      }

      return session.transport.handleRequest(request);
    }

    // Read here rather than through `request.clone()`, which makes Deno warn
    // on stderr, over the window, about the request's abort signal.
    const body: unknown =
      request.method === 'POST'
        ? await request.json().catch(() => undefined)
        : undefined;

    if (!isInitializeRequest(body)) {
      return refused(400, 'No session; initialize first');
    }

    const transport: WebStandardStreamableHTTPServerTransport =
      new WebStandardStreamableHTTPServerTransport({
        // Stateful: a stateless transport refuses every request after the
        // first.
        sessionIdGenerator: () => crypto.randomUUID(),
        onsessioninitialized: (sessionId) => {
          opened.set(sessionId, { token, transport });
        },
        onsessionclosed: (sessionId) => {
          opened.delete(sessionId);
        },
      });
    const server = new McpServer({
      name: SERVER_NAME,
      version: manifest.version,
    });

    registerTools(server, caller);
    await server.connect(transport);

    return transport.handleRequest(request, { parsedBody: body });
  };

  const listening = serve(
    {
      hostname: '127.0.0.1',
      port: 0,
      onError: () => refused(500, 'Internal error'),
    },
    handle,
  );
  const url = `http://127.0.0.1:${listening.port}/mcp`;

  return {
    url,
    admit: (caller) => {
      const token = crypto.randomUUID();

      callers.set(token, caller);

      return {
        token,
        server: {
          type: 'http',
          name: SERVER_NAME,
          url,
          headers: [{ name: 'Authorization', value: `Bearer ${token}` }],
        },
      };
    },
    revoke: (token) => {
      callers.delete(token);

      for (const [id, session] of opened) {
        if (session.token === token) {
          end(id);
        }
      }
    },
    close: async () => {
      callers.clear();

      for (const id of [...opened.keys()]) {
        end(id);
      }

      await listening.close();
    },
  };
}
