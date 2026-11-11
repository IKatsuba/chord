/**
 * riff's MCP servers (CHD-485, "MCP, chord's own tools, skills and
 * instructions"): the session's ACP `mcpServers`, stdio and streamable
 * HTTP (riff advertises no SSE; docs/decisions.md, CHD-610), each through an
 * `@modelcontextprotocol/sdk` client of chord's and `libfx/mcp`'s adapter.
 * chord gives each server a prefix of its own and keeps every tool's
 * original names, so the window titles a call `mcp__<server>__<tool>`;
 * where libfx would rename a tool, the server is refused, never guessed at.
 */
import type { McpServer } from '@agentclientprotocol/sdk/unstable';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import type { Transport } from '@modelcontextprotocol/sdk/shared/transport.js';
import {
  type ElicitRequest,
  ElicitRequestSchema,
  type ElicitResult,
  ElicitationCompleteNotificationSchema,
} from '@modelcontextprotocol/sdk/types.js';
import type { FxAgentHostTool } from 'libfx/node';
import { createMcpAdapter, type McpAdapter, type McpClient } from 'libfx/mcp';

/** The longest prefix chord gives a server, its `__` included. */
export const PREFIX_CHARS = 27;

/** libfx's limit on a tool's name, and the characters it keeps. */
const NAME_CHARS = 64;
const NAME = /^[A-Za-z0-9_-]+$/u;

/** How long a server has to connect and list its tools. */
export const CONNECT_MS = 30_000;

/** A tool's names as its server gave them: what the window shows. */
export interface Original {
  readonly server: string;
  readonly tool: string;
}

/** A server riff did not start, why, and what a stdio one said last. */
export interface Skipped {
  readonly name: string;
  readonly reason: string;
  /** The last lines of its stderr, when it wrote any. */
  readonly said?: string;
}

/** A stdio server that failed to start, with the tail of its stderr. */
export class StartFailure extends Error {
  constructor(
    message: string,
    readonly said: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
  }
}

/** The lines of a stderr tail a note shows at most. */
export const SAID_LINES = 5;

/** The servers a session reaches, and those it does not, with why. */
export interface McpTools {
  readonly tools: FxAgentHostTool[];
  /** Each tool's original names, by the name the model calls it. */
  readonly originals: ReadonlyMap<string, Original>;
  readonly skipped: readonly Skipped[];
  /** Closes every server's client, once. */
  close(): Promise<void>;
}

/**
 * One prefix per server, in order: its name with what libfx does not keep
 * as `_`, cut to fit, `__` after; `_2`, `_3` before the `__` on a clash.
 */
export function prefixes(names: readonly string[]): string[] {
  const taken = new Set<string>();
  const room = PREFIX_CHARS - '__'.length;

  return names.map((name) => {
    const base = name.replaceAll(/[^A-Za-z0-9_-]/gu, '_').slice(0, room);
    let prefix = `${base}__`;

    for (let suffix = 2; taken.has(prefix); suffix++) {
      const tail = `_${suffix}`;

      prefix = `${base.slice(0, room - tail.length)}${tail}__`;
    }

    taken.add(prefix);

    return prefix;
  });
}

/** The ACP title of an MCP call, as claude-agent-acp gives it. */
export function mcpTitle(original: Original): string {
  return `mcp__${original.server}__${original.tool}`;
}

/** An ACP server's transport, as the SDK makes it. */
export function transportOf(server: McpServer, cwd: string): Transport {
  if ('type' in server && server.type === 'http') {
    const headers = Object.fromEntries(
      server.headers.map((header) => [header.name, header.value]),
    );

    return new StreamableHTTPClientTransport(new URL(server.url), {
      requestInit: { headers },
    });
  }

  if ('command' in server) {
    return new StdioClientTransport({
      command: server.command,
      args: server.args,
      env: Object.fromEntries(
        server.env.map((variable) => [variable.name, variable.value]),
      ),
      cwd,
      // Kept, not shown: its tail says why a server that fails did.
      stderr: 'pipe',
    });
  }

  throw new Error(`riff takes no ${(server as { type?: string }).type} server`);
}

/**
 * Wraps `client` so the catalog libfx lists through it is kept, page by
 * page, to check the names libfx made from it.
 */
function recording(client: Connected): {
  readonly client: McpClient;
  readonly listed: { name?: unknown }[];
} {
  const listed: { name?: unknown }[] = [];

  return {
    listed,
    client: {
      listTools: async (params) => {
        const page = (await client.listTools(params)) as
          { tools?: unknown } | unknown[];
        const tools = Array.isArray(page) ? page : page.tools;

        if (Array.isArray(tools)) {
          listed.push(...(tools as { name?: unknown }[]));
        }

        return page;
      },
      callTool: (params, schema, options) =>
        client.callTool(params, schema, options),
      getServerVersion: () => client.getServerVersion?.(),
      close: () => client.close?.(),
    },
  };
}

/**
 * Why libfx's names for a server's tools are not `prefix` and the original,
 * or undefined when every one is.
 */
export function renamed(
  prefix: string,
  listed: readonly { name?: unknown }[],
  made: readonly { name: string }[],
): string | undefined {
  if (listed.length !== made.length) {
    return 'its tool list changed while it was read';
  }

  for (const [index, tool] of listed.entries()) {
    const wanted = `${prefix}${String(tool.name)}`;

    if (
      made[index]?.name !== wanted ||
      wanted.length > NAME_CHARS ||
      !NAME.test(wanted)
    ) {
      return `its tool ${JSON.stringify(tool.name)} has a name riff cannot call as it is`;
    }
  }

  return undefined;
}

/** A connected server's client, which chord closes itself. */
export type Connected = Omit<McpClient, 'close'> & {
  close(): Promise<void>;
};

/** What `connect` takes for one server; tests give their own. */
export type Connect = (
  server: McpServer,
  cwd: string,
  signal: AbortSignal,
) => Promise<Connected>;

/**
 * Where the servers' elicitations go: chord's form, through the window,
 * in the modes the window takes.
 */
export interface Elicitor {
  readonly form: boolean;
  readonly url: boolean;
  /** The person's answer, or a cancel when nobody can give one. */
  readonly elicit: (
    params: ElicitRequest['params'],
    signal: AbortSignal,
  ) => Promise<ElicitResult>;
  /** A URL elicitation the server says is done. */
  readonly complete: (elicitationId: string) => void;
}

/** The bytes of a stdio server's stderr kept for a failure's reason. */
const TAIL_CHARS = 2000;

/**
 * The SDK's client over the server's transport, connected; a stdio server
 * that fails says why with the tail of its stderr.
 */
export const connectSdk =
  (version: string, elicitor?: Elicitor): Connect =>
  async (server, cwd, signal) => {
    const form = elicitor?.form === true;
    const url = elicitor?.url === true;
    // A server asks only in the modes the window takes, or not at all.
    const client = new Client(
      { name: 'riff', version },
      form || url
        ? {
            capabilities: {
              elicitation: {
                ...(form ? { form: {} } : {}),
                ...(url ? { url: {} } : {}),
              },
            },
          }
        : {},
    );

    if (elicitor !== undefined && (form || url)) {
      client.setRequestHandler(ElicitRequestSchema, (request, extra) =>
        elicitor.elicit(request.params, extra.signal),
      );
    }

    if (elicitor !== undefined && url) {
      client.setNotificationHandler(
        ElicitationCompleteNotificationSchema,
        (notification) => {
          elicitor.complete(notification.params.elicitationId);
        },
      );
    }

    const transport = transportOf(server, cwd);
    let tail = '';

    if (transport instanceof StdioClientTransport) {
      // Read from the start, so the pipe never fills and stalls the server.
      transport.stderr?.on('data', (chunk: Buffer | string) => {
        tail = `${tail}${String(chunk)}`.slice(-TAIL_CHARS);
      });
    }

    try {
      await client.connect(transport, { signal });
    } catch (error) {
      await client.close().catch(() => {});

      const message = error instanceof Error ? error.message : String(error);

      throw new StartFailure(message, tail, { cause: error });
    }

    return client as unknown as Connected;
  };

/**
 * Every server of `servers` connected, its tools adapted under its prefix,
 * at once; a server that fails is closed and skipped with its reason.
 */
export async function openMcp(
  servers: readonly McpServer[],
  cwd: string,
  connect: Connect,
  timeout = CONNECT_MS,
): Promise<McpTools> {
  const allotted = prefixes(servers.map((server) => server.name));
  const opened = await Promise.all(
    servers.map(async (server, index) => {
      const prefix = allotted[index]!;
      const signal = AbortSignal.timeout(timeout);
      let client: Connected | undefined;

      try {
        client = await connect(server, cwd, signal);

        const wrapped = recording(client);
        const adapter = await race(
          createMcpAdapter(wrapped.client, { prefix, serverName: server.name }),
          signal,
        );
        const problem = renamed(prefix, wrapped.listed, adapter.tools);

        if (problem !== undefined) {
          await adapter.close().catch(() => {});

          return { server, reason: problem };
        }

        return { server, adapter, listed: wrapped.listed };
      } catch (error) {
        await client?.close().catch(() => {});

        return {
          server,
          reason: reasonOf(error, signal, timeout),
          said: saidOf(error),
        };
      }
    }),
  );

  const tools: FxAgentHostTool[] = [];
  const originals = new Map<string, Original>();
  const adapters: McpAdapter[] = [];
  const skipped: Skipped[] = [];

  for (const each of opened) {
    if ('reason' in each) {
      const said = 'said' in each ? each.said : undefined;

      skipped.push({
        name: each.server.name,
        reason: each.reason,
        ...(said === undefined ? {} : { said }),
      });

      continue;
    }

    // Prefixes differ, yet `a` with `b__c` and `a__b` with `c` both make
    // `a__b__c`: the later server is refused, so no name means two tools.
    const taken = each.adapter.tools.find((tool) => originals.has(tool.name));

    if (taken !== undefined) {
      const other = originals.get(taken.name)!;

      await each.adapter.close().catch(() => {});

      skipped.push({
        name: each.server.name,
        reason: `its tool ${JSON.stringify(taken.name)} has the name of server ${other.server}'s ${other.tool}`,
      });

      continue;
    }

    adapters.push(each.adapter);

    for (const [index, tool] of each.adapter.tools.entries()) {
      tools.push(tool);
      originals.set(tool.name, {
        server: each.server.name,
        tool: String(each.listed[index]?.name),
      });
    }
  }

  let closing: Promise<void> | undefined;

  return {
    tools,
    originals,
    skipped,
    close: () =>
      (closing ??= Promise.allSettled(
        adapters.map((adapter) => adapter.close()),
      ).then(() => {})),
  };
}

/** `work`, or a refusal once `signal` aborts. */
function race<T>(work: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason as Error);

    signal.throwIfAborted();
    signal.addEventListener('abort', abort, { once: true });
    work.then(resolve, reject).finally(() => {
      signal.removeEventListener('abort', abort);
    });
  });
}

function reasonOf(
  error: unknown,
  signal: AbortSignal,
  timeout: number,
): string {
  if (signal.aborted) {
    return `it did not answer within ${timeout / 1000} s`;
  }

  return error instanceof Error ? error.message : String(error);
}

/** The last few non-blank lines a failed stdio server wrote, if any. */
function saidOf(error: unknown): string | undefined {
  if (!(error instanceof StartFailure)) {
    return undefined;
  }

  const lines = error.said
    .split(/\r?\n/u)
    .map((line) => line.trimEnd())
    .filter((line) => line !== '');

  return lines.length === 0 ? undefined : lines.slice(-SAID_LINES).join('\n');
}

/** chord's note in the window for a server riff did not start. */
export function skippedNote(skipped: Skipped): string {
  const sentence = `MCP server ${skipped.name} was not started: ${skipped.reason}`;

  // Fenced, so the window keeps its lines and reads nothing in it as
  // markdown.
  return skipped.said === undefined
    ? sentence
    : `${sentence}\n\n\`\`\`\n${skipped.said}\n\`\`\``;
}
