/**
 * CTUI-35 trial: the same server as dart/bin/server.dart, built as
 * ../chord/src/server/server.ts and tools.ts build theirs, with the original
 * @modelcontextprotocol/sdk and zod out of ../chord/node_modules.
 *
 * stdout carries one JSON line, {url, tokens: {main, task}}, and nothing else.
 * stdin takes `revoke <token>` lines; each is acknowledged on stderr as
 * `revoked <token>`.
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import { z } from '@zod/zod';

type Role = 'main' | 'task';

interface Opened {
  readonly token: string;
  readonly transport: WebStandardStreamableHTTPServerTransport;
}

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

function answer(value: unknown) {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify(value, null, 2) }],
  };
}

function refusal(message: string) {
  return { content: [{ type: 'text' as const, text: message }], isError: true };
}

function said(text: string, value: Record<string, unknown>) {
  return {
    content: [{ type: 'text' as const, text }],
    structuredContent: value,
  };
}

function registerTools(server: McpServer, role: Role): void {
  if (role === 'task') {
    server.registerTool(
      'send_message',
      {
        description: 'Sends a message to the agent that started you.',
        inputSchema: { text: z.string().describe('What to tell it') },
      },
      () => answer({ delivered: 'sent', to: 'parser' }),
    );

    return;
  }

  server.registerTool(
    'send_message',
    {
      description: 'Sends a message to a long-lived agent you opened.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
        text: z.string().describe('What to tell it'),
      },
    },
    () => answer({ delivered: 'sent', to: 'parser' }),
  );
  server.registerTool(
    'close_agent',
    {
      description: 'Closes a long-lived agent you opened.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
      },
    },
    (input) =>
      input.to === 'gone'
        ? refusal(
            'No agent gone is open in this session; list_sessions names them',
          )
        : said(`${input.to} has already ended`, { ended: input.to }),
  );
  server.registerTool(
    'clear_agent',
    {
      description: 'Clears a long-lived agent you opened.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
      },
    },
    (input) =>
      said(
        `${input.to} (id a1) has a fresh session; it knows nothing of earlier turns.`,
        { cleared: input.to, id: 'a1' },
      ),
  );
}

const callers = new Map<string, Role>([
  [crypto.randomUUID(), 'main'],
  [crypto.randomUUID(), 'task'],
]);
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

    if (session.token !== token) {
      return refused(403, 'Session opened with another token');
    }

    return session.transport.handleRequest(request);
  }

  const body: unknown =
    request.method === 'POST'
      ? await request.json().catch(() => undefined)
      : undefined;

  if (!isInitializeRequest(body)) {
    return refused(400, 'No session; initialize first');
  }

  const transport: WebStandardStreamableHTTPServerTransport =
    new WebStandardStreamableHTTPServerTransport({
      sessionIdGenerator: () => crypto.randomUUID(),
      onsessioninitialized: (sessionId) => {
        opened.set(sessionId, { token, transport });
      },
      onsessionclosed: (sessionId) => {
        opened.delete(sessionId);
      },
    });
  const server = new McpServer({ name: 'chord', version: '0.71.0' });

  registerTools(server, caller);
  await server.connect(transport);

  return transport.handleRequest(request, { parsedBody: body });
};

// As ../chord/src/platform/serve.ts.
const listening = Bun.serve({
  hostname: '127.0.0.1',
  port: 0,
  idleTimeout: 0,
  development: false,
  fetch: handle,
  error: () => refused(500, 'Internal error'),
});

const tokens = Object.fromEntries(
  [...callers].map(([token, role]) => [role, token]),
);

process.stdout.write(
  JSON.stringify({
    url: `http://127.0.0.1:${listening.port}/mcp`,
    tokens,
  }) + '\n',
);

let pending = '';

process.stdin.on('data', (chunk: Buffer) => {
  pending += chunk.toString('utf8');

  let newline: number;

  while ((newline = pending.indexOf('\n')) >= 0) {
    const [verb, token] = pending.slice(0, newline).trim().split(' ');

    pending = pending.slice(newline + 1);

    if (verb === 'revoke' && token !== undefined) {
      callers.delete(token);

      for (const [sessionId, session] of opened) {
        if (session.token === token) {
          end(sessionId);
        }
      }

      process.stderr.write(`revoked ${token}\n`);
    }
  }
});
process.stdin.on('end', () => {
  for (const sessionId of [...opened.keys()]) {
    end(sessionId);
  }

  void listening.stop(true).then(() => process.exit(0));
});
