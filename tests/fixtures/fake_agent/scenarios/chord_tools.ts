/**
 * chord's own MCP server, called as an agent calls it: through the MCP SDK's
 * client, on the URL and headers the session was given.
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { mcpServers } from '../sessions.ts';
import type { Play, Turn } from '../turn.ts';

/** The text of a tool's answer, or what went wrong with it. */
function textOf(result: Awaited<ReturnType<Client['callTool']>>): string {
  const blocks = Array.isArray(result.content) ? result.content : [];
  const text = blocks
    .map((block) => (block.type === 'text' ? block.text : ''))
    .join('');

  return result.isError === true ? `error: ${text}` : text;
}

/**
 * A client connected to chord's own server, as the session was given it;
 * none when it was given none.
 */
export async function chordClient(turn: Turn): Promise<Client | undefined> {
  // chord's goes after the user's, renamed `chord-<n>` when one of theirs
  // is named `chord`, so the last of those names is chord's.
  const chord = mcpServers
    .get(turn.sessionId)
    ?.findLast(
      (server) =>
        /^chord(-\d+)?$/.test(server.name) &&
        'type' in server &&
        server.type === 'http',
    );

  if (chord === undefined || !('url' in chord)) {
    return undefined;
  }

  const client = new Client({ name: 'chord-fake-agent', version: '0.0.0' });
  const headers = Object.fromEntries(
    chord.headers.map(({ name, value }) => [name, value]),
  );
  const transport = new StreamableHTTPClientTransport(new URL(chord.url), {
    requestInit: { headers },
  });

  // The SDK's own two types disagree under `exactOptionalPropertyTypes`:
  // the transport's `sessionId` may be undefined, the interface's not.
  await client.connect(transport as Parameters<Client['connect']>[0]);

  return client;
}

/**
 * One of chord's tools called as an agent calls an MCP tool: the call goes
 * out as a `tool_call`, titled as Claude's adapter titles one, with its
 * arguments, then the answer as the call's update. The answer's text, or
 * none when it was refused.
 */
export async function callChord(
  turn: Turn,
  client: Client,
  name: string,
  args: Record<string, unknown>,
  /** How long to wait for the answer, the SDK's 60 s if not said. */
  timeout?: number,
): Promise<string | undefined> {
  const toolCallId = turn.callId(name);

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: `mcp__chord__${name}`,
    kind: 'other',
    status: 'pending',
    rawInput: args,
  });

  const result = await client.callTool(
    { name, arguments: args },
    undefined,
    timeout === undefined ? undefined : { timeout, signal: turn.signal },
  );
  const text = textOf(result);
  const failed = result.isError === true;

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: failed ? 'failed' : 'completed',
    content: [
      {
        type: 'content',
        content: { type: 'text', text: failed ? text.slice(7) : text },
      },
    ],
  });

  return failed ? undefined : text;
}

export const CHORD_TOOLS = {
  // Calls `list_agents` and `list_sessions` and answers with what came back,
  // each as JSON.
  async chordtools(turn) {
    let client: Client | undefined;

    try {
      client = await chordClient(turn);

      if (client === undefined) {
        await turn.say('No chord server in this session.');

        return 'end_turn';
      }

      const agents = await client.callTool({ name: 'list_agents' });
      const sessions = await client.callTool({ name: 'list_sessions' });

      await turn.say(
        `list_agents:\n\n\`\`\`json\n${textOf(agents)}\n\`\`\`\n\n`,
        `list_sessions:\n\n\`\`\`json\n${textOf(sessions)}\n\`\`\``,
      );
    } catch (error) {
      await turn.say(
        `chord's server failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    } finally {
      await client?.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
