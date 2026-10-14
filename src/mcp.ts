/**
 * The MCP servers chord hands the agent for its sessions: read from the
 * `mcpServers` key of chord's settings files and from the working directory's
 * `.mcp.json`, checked, merged by name, and turned into ACP's `McpServer`
 * values, which go with `session/new` and `session/load`. chord only
 * reads these files; it never writes `.mcp.json` or the agent's own
 * configuration.
 */
import type { McpServer } from '@agentclientprotocol/sdk';
import { z } from '@zod/zod';
import { join } from 'node:path';
import { readFile } from 'node:fs/promises';
import { notFound } from './not_found.ts';
import type { SettingsLayer, SettingsProblem } from './settings.ts';

/** A key the entry needs is said to be missing, not of the wrong kind. */
const needed = {
  error: (issue: { input?: unknown }) =>
    issue.input === undefined ? 'missing' : undefined,
};

/**
 * A server started as a command, as `.mcp.json` writes one. Keys the entry
 * has besides these are let through: the shape is a convention other tools
 * extend, and a file shared with them must not lose its servers here.
 */
const StdioEntry = z.object({
  type: z.literal('stdio').optional(),
  command: z.string(needed).min(1),
  args: z.array(z.string()).optional(),
  env: z.record(z.string(), z.string()).optional(),
});

/** A server reached over HTTP or SSE, as `.mcp.json` writes one. */
const RemoteEntry = z.object({
  type: z.enum(['http', 'sse']),
  url: z.url({ ...needed, protocol: /^https?$/ }),
  headers: z.record(z.string(), z.string()).optional(),
});

/** The transports ACP carries, which an entry's `type` may name. */
const TRANSPORTS = ['stdio', 'http', 'sse'] as const;

type Transport = (typeof TRANSPORTS)[number];

/** A server chord passes, and the file that defined it. */
export interface DefinedServer {
  readonly server: McpServer;
  /** The file's path; the window shows it from the directory or `~`. */
  readonly from: string;
}

/**
 * What a file defined that chord did not pass: some of its servers, or all of
 * them when the file itself could not be read as servers.
 */
export interface Ignored {
  readonly from: string;
  readonly servers: number | 'all';
}

/** One file's servers, what is wrong with it, and what that cost. */
export interface ReadServers {
  readonly servers: DefinedServer[];
  readonly problems: SettingsProblem[];
  readonly ignored: Ignored[];
}

/** A file that costs itself, with what is wrong with it. */
function fileIgnored(file: string, message: string): ReadServers {
  return {
    servers: [],
    problems: [{ file, message }],
    ignored: [{ from: file, servers: 'all' }],
  };
}

const NONE: ReadServers = { servers: [], problems: [], ignored: [] };

/**
 * How the agent reaches the server: by command, or by URL. ACP has more
 * kinds than chord reads from a file, so the agent's own name is kept.
 */
export function transportOf(server: McpServer): string {
  return 'type' in server ? server.type : 'stdio';
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function keyOf(path: readonly PropertyKey[]): string {
  return path.map(String).join('.');
}

/** One entry as ACP sends it: env and headers as name and value pairs. */
function toServer(
  name: string,
  entry: z.infer<typeof StdioEntry> | z.infer<typeof RemoteEntry>,
): McpServer {
  if ('url' in entry) {
    return {
      type: entry.type,
      name,
      url: entry.url,
      headers: Object.entries(entry.headers ?? {}).map(([name, value]) => ({
        name,
        value,
      })),
    };
  }

  return {
    name,
    command: entry.command,
    args: entry.args ?? [],
    env: Object.entries(entry.env ?? {}).map(([name, value]) => ({
      name,
      value,
    })),
  };
}

/**
 * The servers in one file's `mcpServers` object, by name. An entry that is
 * wrong costs only that server: it is named with what is wrong and left out,
 * and the file's other servers still count.
 */
export function parseServers(
  file: string,
  servers: Record<string, unknown>,
): ReadServers {
  const found: DefinedServer[] = [];
  const problems: SettingsProblem[] = [];
  const ignored = (path: readonly PropertyKey[], what: string) =>
    problems.push({
      file,
      message: `"${keyOf([
        'mcpServers',
        ...path,
      ])}": ${what}; the server is ignored`,
    });

  for (const [name, entry] of Object.entries(servers)) {
    if (name.trim() === '') {
      ignored([name], 'a server needs a name');

      continue;
    }

    if (!isObject(entry)) {
      ignored([name], 'expected an object with a command or a url');

      continue;
    }

    const { type } = entry;

    if (type !== undefined && !TRANSPORTS.includes(type as Transport)) {
      ignored(
        [name, 'type'],
        `${JSON.stringify(type)} is not a transport ACP carries (${TRANSPORTS.join(
          ', ',
        )})`,
      );

      continue;
    }

    // Claude Code's own `.mcp.json` names the transport of a URL; guessing
    // between HTTP and SSE would pick wrong half the time.
    if (type === undefined && 'url' in entry && !('command' in entry)) {
      ignored(
        [name, 'type'],
        'missing; a server with a url needs "http" or "sse"',
      );

      continue;
    }

    const parsed =
      type === 'http' || type === 'sse'
        ? RemoteEntry.safeParse(entry)
        : StdioEntry.safeParse(entry);

    if (!parsed.success) {
      const issue = parsed.error.issues[0];

      ignored(
        [name, ...(issue?.path ?? [])],
        issue?.message.toLowerCase() ?? 'not a server definition',
      );

      continue;
    }

    found.push({ server: toServer(name, parsed.data), from: file });
  }

  return {
    servers: found,
    problems,
    ignored:
      problems.length === 0 ? [] : [{ from: file, servers: problems.length }],
  };
}

/**
 * A `.mcp.json`'s text. Keys other than `mcpServers` are other tools' and
 * left alone; a file without servers has none to pass. Text that is not a
 * JSON object, or servers that are not an object of them by name, cost the
 * file.
 */
export function parseMcpJson(file: string, text: string): ReadServers {
  let input: unknown;

  try {
    input = JSON.parse(text);
  } catch (error) {
    return fileIgnored(
      file,
      `not valid JSON (${
        error instanceof Error ? error.message : String(error)
      }); the file is ignored`,
    );
  }

  if (!isObject(input)) {
    return fileIgnored(file, 'not a JSON object; the file is ignored');
  }

  if (input.mcpServers === undefined) {
    return NONE;
  }

  if (!isObject(input.mcpServers)) {
    return fileIgnored(
      file,
      '"mcpServers": expected an object of servers by name; the file is ignored',
    );
  }

  return parseServers(file, input.mcpServers);
}

/** The working directory's `.mcp.json`; none there is no problem. */
export async function readMcpJson(cwd: string): Promise<ReadServers> {
  const file = join(cwd, '.mcp.json');
  let text: string;

  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if (notFound(error)) {
      return NONE;
    }

    return fileIgnored(
      file,
      `cannot be read (${
        error instanceof Error ? error.message : String(error)
      }); the file is ignored`,
    );
  }

  return parseMcpJson(file, text);
}

/**
 * Later lists win, server by server and whole: a server named again replaces
 * the earlier one, as merging a command's fields into a URL's would make
 * neither. It keeps the place it was first listed in.
 */
export function mergeServers(
  ...lists: readonly (readonly DefinedServer[])[]
): DefinedServer[] {
  const merged = new Map<string, DefinedServer>();

  for (const list of lists) {
    for (const defined of list) {
      merged.set(defined.server.name, defined);
    }
  }

  return [...merged.values()];
}

/**
 * Every server for a session in `cwd`, lowest precedence first: the user's
 * settings file, the project's `.mcp.json`, then the project's
 * `.chord/settings.json`, which is chord's own and the nearer word. The
 * problems are the servers' and `.mcp.json`'s; the settings files' other
 * problems are `loadSettings`'. What each file lost is kept for `/mcp`,
 * which is where someone looks for a server that is not there.
 */
export async function loadMcpServers({
  layers,
  cwd,
}: {
  layers: readonly SettingsLayer[];
  cwd: string;
}): Promise<ReadServers> {
  const project = join(cwd, '.chord', 'settings.json');
  const fromLayers = (layer: SettingsLayer) =>
    parseServers(layer.file, layer.settings.mcpServers ?? {});
  const user = layers.filter((layer) => layer.file !== project).map(fromLayers);
  const shared = await readMcpJson(cwd);
  const own = layers.filter((layer) => layer.file === project).map(fromLayers);
  const read = [...user, shared, ...own];

  return {
    servers: mergeServers(...read.map((each) => each.servers)),
    problems: read.flatMap((each) => each.problems),
    ignored: read.flatMap((each) => each.ignored),
  };
}
