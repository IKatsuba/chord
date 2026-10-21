/**
 * `/mcp`: the MCP servers chord passed to the agent, one row each, laid out
 * in columns that fit the width, and what the files defined that it did not
 * pass. Nothing here says whether the agent reached
 * a server: ACP carries no word of it, and the panel says so instead.
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import type { McpServer } from '@agentclientprotocol/sdk';
import { type DefinedServer, type Ignored, transportOf } from '../../mcp.ts';
import type { HeldBack } from '../../session/servers.ts';
import { toolNames } from '../../server/tools.ts';

/** chord's own server, as `/mcp` lists it ahead of the user's. */
export interface ChordRow {
  /** Its row, with `not passed` for the URL of one the agent did not get. */
  readonly server: DefinedServer;
  readonly passed: boolean;
  /** The tools it gives the session. */
  readonly tools: readonly string[];
  /** The session is a long-lived child, whose one tool reaches `main`. */
  readonly child?: boolean;
}

/**
 * chord's row: the server the session got, or `not passed` for its URL; a
 * `child`'s gives it its child's tools.
 */
export function chordRow(
  passed: McpServer | undefined,
  child = false,
): ChordRow {
  return {
    server: {
      server: passed ?? {
        type: 'http',
        name: 'chord',
        url: 'not passed',
        headers: [],
      },
      from: 'chord itself',
    },
    passed: passed !== undefined,
    tools: toolNames(child ? 'child' : 'person'),
    ...(child ? { child } : {}),
  };
}

/** The line under the table: what chord's server gives, or why it was not passed. */
export function chordLine(row: ChordRow, agent: string): string {
  const list = (tools: readonly string[]) =>
    new Intl.ListFormat('en-GB', { type: 'conjunction' }).format(tools);
  // A child's send_message reaches main alone; its other tools are its own.
  const own = row.tools.filter((tool) => tool !== 'send_message');

  return row.passed
    ? `chord's server gives ${agent} ${
        row.child
          ? `${own.length > 0 ? `${list(own)}, and ` : ''}send_message to ` +
            'main only'
          : list(row.tools)
      }.`
    : `chord's server was not passed: ${agent} does not take MCP servers over HTTP, so it cannot start other agents.`;
}

/** One server's parts, before they are laid out. */
interface McpParts {
  readonly name: string;
  readonly transport: string;
  /** The command and its arguments, or the URL. */
  readonly target: string;
  /** The file that defined it, as the window shows paths. */
  readonly from: string;
}

/** The column titles, in the order the rows are laid out. */
export const MCP_HEADINGS: McpParts = {
  name: 'Name',
  transport: 'Transport',
  target: 'Command or URL',
  from: 'Defined in',
};

/** Between columns. */
export const MCP_GAP = 2;

/** The widest a name is drawn before the command is squeezed out. */
const MOST = 32;

/**
 * The narrowest the command or URL is squeezed to by a long path. It wraps,
 * so a narrow column costs lines, not the part that tells servers apart.
 */
const LEAST_TARGET = 16;

/** An argument with a space in it, quoted, so the line reads as typed. */
function shellWord(word: string): string {
  return /\s/.test(word) || word === '' ? JSON.stringify(word) : word;
}

/** What the server runs, or where it is. Env and headers are never shown. */
export function targetOf({ server }: DefinedServer): string {
  if ('url' in server) {
    return server.url;
  }

  // chord never reads an ACP-transport server from a file, but the type has one.
  return 'command' in server
    ? [server.command, ...server.args].map(shellWord).join(' ')
    : server.serverId;
}

function pad(text: string, width: number): string {
  return text + ' '.repeat(Math.max(0, width - stringWidth(text)));
}

/**
 * A path cut from the left, where it is least telling, and at a separator
 * where one is left, so the file's name and its directory survive whole.
 */
export function cutPath(path: string, width: number): string {
  if (stringWidth(path) <= width) {
    return path;
  }

  const cut = cliTruncate(path, Math.max(1, width), { position: 'start' });
  const separator = cut.indexOf('/', 1);

  return separator > 1 && separator < cut.length - 1
    ? `…${cut.slice(separator)}`
    : cut;
}

/**
 * A command or URL in lines of `width`, broken at spaces and else after a
 * slash, where a package's scope, a path or a URL reads as whole; only a
 * piece longer than the line is cut through. wrap-ansi breaks at spaces
 * alone and cuts a long word where the line ends, which splits
 * `@modelcontextprotocol/server-memory` mid-name.
 */
export function wrapTarget(text: string, width: number): string[] {
  const lines: string[] = [];
  let line = '';

  for (const [index, word] of text.split(' ').entries()) {
    for (const [at, piece] of word.split(/(?<=\/)/).entries()) {
      const joined =
        line === ''
          ? piece
          : `${line}${index > 0 && at === 0 ? ' ' : ''}${piece}`;

      if (stringWidth(joined) <= width || line === '') {
        line = joined;
      } else {
        lines.push(line);

        line = piece;
      }

      while (stringWidth(line) > width) {
        const head = cliTruncate(line, width + 1, { position: 'end' }).slice(
          0,
          -1,
        );

        lines.push(head);

        line = line.slice(head.length);
      }
    }
  }

  return [...lines, line];
}

/**
 * Each server as its lines, laid out in columns to fit `width`, and the
 * headings as one line laid out the same. The path takes its full width
 * first, as it is one of three files and a cut one says none of them; the
 * command or URL takes the rest and wraps inside its column, so the end of
 * `npx -y @scope/server-x`, which tells servers apart, is never cut off.
 */
export function mcpRows(
  servers: readonly DefinedServer[],
  width: number,
): { headings: string; rows: string[][] } {
  const named = servers.map((defined) => ({
    name: defined.server.name,
    transport: transportOf(defined.server),
    target: targetOf(defined),
    from: defined.from,
  }));
  const widest = (key: keyof McpParts, most = Infinity) =>
    Math.min(
      most,
      Math.max(...[MCP_HEADINGS, ...named].map((row) => stringWidth(row[key]))),
    );
  const nameWidth = widest('name', MOST);
  const transportWidth = widest('transport');
  const room = width - nameWidth - transportWidth - 3 * MCP_GAP;
  const fromWidth = Math.max(
    1,
    Math.min(widest('from'), room - Math.min(widest('target'), LEAST_TARGET)),
  );
  const wrapped = [MCP_HEADINGS, ...named].map((row) =>
    wrapTarget(row.target, Math.max(1, room - fromWidth)),
  );
  // As wide as its widest line, which wrapping may leave short of the room.
  const targetWidth = Math.max(
    ...wrapped.flat().map((line) => stringWidth(line)),
  );
  const gap = ' '.repeat(MCP_GAP);
  const laid = (row: McpParts, at: number): string[] =>
    wrapped[at]!.map((target, index) =>
      (index === 0
        ? [
            pad(cliTruncate(row.name, nameWidth), nameWidth),
            pad(row.transport, transportWidth),
            pad(target, targetWidth),
            cutPath(row.from, fromWidth),
          ]
        : [' '.repeat(nameWidth), ' '.repeat(transportWidth), target]
      )
        .join(gap)
        .trimEnd(),
    );

  return {
    headings: laid(MCP_HEADINGS, 0)[0]!,
    rows: named.map((row, index) => laid(row, index + 1)),
  };
}

/**
 * The servers that fit in `lines` lines, whole, with one line kept for
 * saying how many more there are when not all of them do. The first is
 * always shown, however many lines it wraps to.
 */
export function mcpFit(
  rows: readonly (readonly string[])[],
  lines: number,
): { shown: (readonly string[])[]; more: number } {
  if (rows.flat().length <= lines) {
    return { shown: [...rows], more: 0 };
  }

  const shown: (readonly string[])[] = [];
  let used = 0;

  for (const row of rows) {
    if (shown.length > 0 && used + row.length > lines - 1) {
      break;
    }

    shown.push(row);

    used += row.length;
  }

  return { shown, more: rows.length - shown.length };
}

/**
 * What the files lost, for `/mcp`, or nothing when they lost nothing. The
 * warnings that said why are gone once the window is cleared, so the line
 * points to when chord said it rather than to where.
 */
export function ignoredNote(ignored: readonly Ignored[]): string | undefined {
  if (ignored.length === 0) {
    return undefined;
  }

  const each = ignored.map(({ from, servers }) =>
    servers === 'all'
      ? `${from} was ignored`
      : servers === 1
        ? `1 server in ${from} was ignored`
        : `${servers} servers in ${from} were ignored`,
  );

  return `${new Intl.ListFormat('en', { type: 'conjunction' }).format(
    each,
  )}; chord said why when it started.`;
}

/**
 * How many lines of servers the panel draws before it says how many more
 * there are: the window's height less the panel's own lines and the
 * prompt's, and never fewer than three.
 */
export function mcpRowLimit(windowRows: number): number {
  return Math.max(3, windowRows - 16);
}

/**
 * The person's servers as `/mcp` lists them, each `heldBack` names (chord's
 * own aside, which has a row of its own) with `not passed` for its command
 * or URL, as chord's own reads when it was not passed (CHD-441).
 */
export function withHeldBack(
  servers: readonly DefinedServer[],
  heldBack: readonly HeldBack[],
): DefinedServer[] {
  const held = new Set(
    heldBack.filter((each) => !each.own).map((each) => each.server),
  );

  return servers.map((defined) => {
    const { server } = defined;

    if (!held.has(server.name)) {
      return defined;
    }

    return {
      ...defined,
      server:
        'url' in server
          ? { ...server, url: 'not passed' }
          : { name: server.name, command: 'not passed', args: [], env: [] },
    };
  });
}

/**
 * The paragraph under `/mcp`'s table for the person's servers its agent was
 * not given, and why; none when all of them went. chord's own has
 * `chordLine`.
 */
export function heldNote(heldBack: readonly HeldBack[]): string | undefined {
  const held = heldBack.filter((each) => !each.own);
  const first = held[0];

  if (first === undefined) {
    return undefined;
  }

  const whys = new Set(held.map((each) => each.why));
  const left = [...new Set(held.map((each) => each.transport.toUpperCase()))];
  const why =
    whys.size === 1 && whys.has('stdio only')
      ? 'takes MCP servers over stdio only'
      : `does not take MCP servers over ${left.join(' or ')}`;
  const names = new Intl.ListFormat('en', { type: 'conjunction' }).format(
    held.map((each) => each.server),
  );

  return `${names} ${held.length === 1 ? 'was' : 'were'} not passed: ${
    first.agent
  } ${why}.`;
}
