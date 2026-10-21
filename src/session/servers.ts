/**
 * Which MCP servers an agent is given (CHD-441): only those whose transport
 * its `initialize` advertises in `mcpCapabilities`, stdio always, as ACP
 * requires every agent to take it, chord's own server under the same rule;
 * and the rest, held back, with why, for the person to be told.
 */
import type { McpCapabilities, McpServer } from '@agentclientprotocol/sdk';
import { transportOf } from '../mcp.ts';

/** The transports past stdio an agent may advertise, in the order said. */
const ADVERTISED = ['http', 'sse', 'acp'] as const;

/** A server an agent was not given, and why: its transport is not taken. */
export interface HeldBack {
  /** The server's name, as it would have gone. */
  readonly server: string;
  /** The agent it was held back from, by the name chord runs it as. */
  readonly agent: string;
  /** `http`, `sse`, or another transport ACP names. */
  readonly transport: string;
  /**
   * Why: the transports the agent takes, stdio first, then `http`, `sse`
   * and `acp` as its `initialize` advertised them, this one not among them.
   */
  readonly takes: readonly string[];
  /** chord's own server, whose tools go with it. */
  readonly own?: true;
}

/** The servers that go to an agent, in their order, and those held back. */
export interface ServersFor {
  readonly servers: McpServer[];
  readonly heldBack: HeldBack[];
  /** chord's own as it went, under the name it took; none when held back. */
  readonly chord?: McpServer;
}

/**
 * The user's servers and then chord's that agent `agent` takes, by the
 * transports `capabilities` advertises. Two servers of one name leave the
 * agent to pick one, and either pick loses a server, so where a user's
 * server it is given takes chord's name, chord's goes as the first free
 * `chord-2`, `chord-3`, … and both stay reachable.
 */
export function serversFor(
  agent: string,
  capabilities: McpCapabilities | undefined,
  userServers: readonly McpServer[],
  chord?: McpServer,
): ServersFor {
  const takes = [
    'stdio',
    ...ADVERTISED.filter((transport) => capabilities?.[transport] === true),
  ];
  const servers: McpServer[] = [];
  const heldBack: HeldBack[] = [];
  const sort = (server: McpServer, own = false): boolean => {
    const transport = transportOf(server);

    if (takes.includes(transport)) {
      servers.push(server);

      return true;
    }

    heldBack.push({
      server: server.name,
      agent,
      transport,
      takes,
      ...(own ? { own: true as const } : {}),
    });

    return false;
  };

  for (const server of userServers) {
    sort(server);
  }

  if (chord !== undefined) {
    const taken = new Set(servers.map((server) => server.name));
    let name = chord.name;

    for (let n = 2; taken.has(name); n++) {
      name = `${chord.name}-${n}`;
    }

    const named = { ...chord, name };

    if (sort(named, true)) {
      return { servers, heldBack, chord: named };
    }
  }

  return { servers, heldBack };
}

/**
 * The transports an agent takes, as prose says them: `stdio and HTTP`,
 * `stdio, SSE and ACP`.
 */
export function takenWords(takes: readonly string[]): string {
  return new Intl.ListFormat('en-GB', { type: 'conjunction' }).format(
    takes.map((transport) =>
      transport === 'stdio' ? transport : transport.toUpperCase(),
    ),
  );
}

/**
 * What the person is told at a session's start of the servers its agent was
 * not given (`docs/design/CHD-441.md`): how many, to which agent, the
 * transports it takes, every one by name, chord's own first, and what
 * losing chord's own costs; none when every server went.
 */
export function heldBackLine(
  heldBack: readonly HeldBack[],
): string | undefined {
  const first = heldBack[0];

  if (first === undefined) {
    return undefined;
  }

  const { agent, takes } = first;
  const held = [
    ...heldBack.filter((each) => each.own),
    ...heldBack.filter((each) => !each.own),
  ];
  // An agent that lacks one transport holds back only servers of that one,
  // so the names go bare; lacking more, each says its own.
  const bare = ADVERTISED.length - (takes.length - 1) === 1;
  const names = held
    .map((each) => {
      const notes = [
        ...(bare ? [] : [each.transport]),
        ...(each.own ? ["chord's own"] : []),
      ];

      return notes.length === 0
        ? each.server
        : `${each.server} (${notes.join(', ')})`;
    })
    .join(', ');
  const count = held.length;
  const own = held.some((each) => each.own)
    ? ` Without ${count === 1 ? 'it' : "chord's own"}, ${agent} cannot ` +
      "start other agents or use chord's tools."
    : '';

  return (
    `${count} MCP ${count === 1 ? 'server was' : 'servers were'} not passed ` +
    `to ${agent}, which takes them over ${takenWords(takes)} only: ` +
    `${names}.${own} /mcp lists ${count === 1 ? 'it' : 'them'}.`
  );
}
