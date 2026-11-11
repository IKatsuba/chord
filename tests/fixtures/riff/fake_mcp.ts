/**
 * A fake MCP server for riff's tests, never a real one: `notes`, whose
 * `save_note` answers with what it saved. `serveFakeMcp` serves it over
 * streamable HTTP in the test's process; `mcp_stdio.ts` runs it on stdio.
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import { z } from '@zod/zod';
import { serve } from '../../../src/platform/serve.ts';

/** How the fake behaves: plainly, or with a tool name libfx would change. */
export type FakeMcpMode = 'ok' | 'badname';

/** The fake server, its tools registered. */
export function fakeMcpServer(
  name = 'notes',
  mode: FakeMcpMode = 'ok',
  /** Hears each call of `save_note` before it answers. */
  calls?: (title: string) => Promise<void>,
  /** One more tool's name, answering `ok`. */
  extra?: string,
): McpServer {
  const server = new McpServer({ name, version: '1.0.0' });

  server.registerTool(
    'save_note',
    {
      description: 'Saves a note.',
      inputSchema: {
        title: z.string(),
        tags: z.array(z.string()).optional(),
      },
    },
    async ({ title }) => {
      await calls?.(title);

      return { content: [{ type: 'text', text: `Saved ${title}` }] };
    },
  );

  if (extra !== undefined) {
    server.registerTool(extra, { description: 'Another tool.' }, () => ({
      content: [{ type: 'text', text: 'ok' }],
    }));
  }

  if (mode === 'badname') {
    server.registerTool(
      'list notes',
      { description: 'A name with a space.' },
      () => ({ content: [{ type: 'text', text: 'none' }] }),
    );
  }

  return server;
}

/** A fake served over streamable HTTP, and the bearer it asks for. */
export interface ServedMcp {
  readonly url: string;
  /** The Authorization headers requests arrived with. */
  readonly authorizations: readonly (string | null)[];
  close(): Promise<void>;
}

export function serveFakeMcp(
  name = 'notes',
  mode: FakeMcpMode = 'ok',
  extra?: string,
): ServedMcp {
  const authorizations: (string | null)[] = [];
  const transports = new Map<
    string,
    WebStandardStreamableHTTPServerTransport
  >();

  const listening = serve(
    {
      hostname: '127.0.0.1',
      port: 0,
      onError: () => new Response('error', { status: 500 }),
    },
    async (request) => {
      authorizations.push(request.headers.get('authorization'));

      const id = request.headers.get('mcp-session-id');
      const known = id === null ? undefined : transports.get(id);

      if (known !== undefined) {
        return known.handleRequest(request);
      }

      const body: unknown = await request.json().catch(() => undefined);

      if (!isInitializeRequest(body)) {
        return new Response('initialize first', { status: 400 });
      }

      const transport = new WebStandardStreamableHTTPServerTransport({
        sessionIdGenerator: () => crypto.randomUUID(),
        onsessioninitialized: (opened) => {
          transports.set(opened, transport);
        },
      });

      await fakeMcpServer(name, mode, undefined, extra).connect(transport);

      return transport.handleRequest(request, { parsedBody: body });
    },
  );

  return {
    url: `http://127.0.0.1:${listening.port}/mcp`,
    authorizations,
    close: async () => {
      for (const transport of transports.values()) {
        await transport.close().catch(() => {});
      }

      await listening.close();
    },
  };
}
