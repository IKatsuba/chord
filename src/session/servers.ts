/**
 * Which MCP servers an agent is given (CHD-441): only those whose transport
 * its `initialize` advertises in `mcpCapabilities`, stdio always, as ACP
 * requires every agent to take it, chord's own server under the same rule;
 * and the rest, held back, with why, for the person to be told.
 */
import type { McpCapabilities, McpServer } from '@agentclientprotocol/sdk';
import { transportOf } from '../mcp.ts';

/** A server an agent was not given, and why: its transport is not taken. */
export interface HeldBack {
  /** The server's name, as it would have gone. */
  readonly server: string;
  /** The agent it was held back from, by the name chord runs it as. */
  readonly agent: string;
  /** `http`, `sse`, or another transport ACP names. */
  readonly transport: string;
  /** Its transport is not among those the agent's `initialize` advertised. */
  readonly why: 'transport not advertised';
}

/** The servers that go to an agent, in their order, and those held back. */
export interface ServersFor {
  readonly servers: McpServer[];
  readonly heldBack: HeldBack[];
  /** chord's own as it went, under the name it took; none when held back. */
  readonly chord?: McpServer;
}

/** Whether an agent advertising `capabilities` takes `transport`. */
function takes(
  capabilities: McpCapabilities | undefined,
  transport: string,
): boolean {
  switch (transport) {
    case 'stdio':
      return true;
    case 'http':
    case 'sse':
    case 'acp':
      return capabilities?.[transport] === true;
    default:
      return false;
  }
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
  const servers: McpServer[] = [];
  const heldBack: HeldBack[] = [];
  const sort = (server: McpServer): boolean => {
    const transport = transportOf(server);

    if (takes(capabilities, transport)) {
      servers.push(server);

      return true;
    }

    heldBack.push({
      server: server.name,
      agent,
      transport,
      why: 'transport not advertised',
    });

    return false;
  };

  userServers.forEach(sort);

  if (chord !== undefined) {
    const taken = new Set(servers.map((server) => server.name));
    let name = chord.name;

    for (let n = 2; taken.has(name); n++) {
      name = `${chord.name}-${n}`;
    }

    const named = { ...chord, name };

    if (sort(named)) {
      return { servers, heldBack, chord: named };
    }
  }

  return { servers, heldBack };
}
