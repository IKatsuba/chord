/**
 * chord's own MCP server, called as an agent calls it: through the MCP SDK's
 * client, on the URL and headers the session was given.
 */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { mcpServers } from '../sessions.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';

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
/**
 * An MCP call as codex-acp sends one: a command by its dotted name, the
 * arguments wrapped with the server and the tool in `rawInput`.
 */
export function codexCall(
  server: string,
  tool: string,
  args: Record<string, unknown>,
) {
  return {
    title: `mcp.${server}.${tool}`,
    kind: 'execute' as const,
    rawInput: { server, tool, arguments: args },
    _meta: { is_mcp_tool_call: true },
  };
}

export async function callChord(
  turn: Turn,
  client: Client,
  name: string,
  args: Record<string, unknown>,
  /** How long to wait for the answer, the SDK's 60 s if not said. */
  timeout?: number,
  /** Whose adapter's shape the call is in: Claude's, or Codex's. */
  shape: 'claude' | 'codex' = 'claude',
): Promise<string | undefined> {
  const toolCallId = turn.callId(name);

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    status: 'pending',
    ...(shape === 'claude'
      ? { title: `mcp__chord__${name}`, kind: 'other', rawInput: args }
      : codexCall('chord', name, args)),
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

/** The message `cutcalls` sends main, which its adapter cuts off. */
export const CUT_MESSAGE = [
  'CHD-393: the owner has a question on Q8, with the options for the headline:',
  '',
  '1. Draw the headline whole and wrap it.',
  '2. Cut it at the edge, as today.',
].join('\n');

/** What `cutcalls` asked `open_agent` for, which its adapter cuts off too. */
export const CUT_OPEN = { agent: 'fake', name: 'parser', prompt: 'agentchild' };

export const CHORD_TOOLS = {
  // A batch Claude's adapter cuts off as a steer interrupts it: a
  // send_message to main and an open_agent, each failed `interrupted` with
  // an empty error and nothing asked of chord's server, and a command
  // beside them cancelled with Claude Code's words for a stopped call.
  async cutcalls(turn) {
    const chord = (tool: string, input: Record<string, unknown>) => ({
      id: turn.callId(tool),
      tool,
      input,
    });
    const calls = [
      chord('send_message', { to: 'main', text: CUT_MESSAGE }),
      chord('open_agent', CUT_OPEN),
    ];
    const bash = turn.callId('bash');

    for (const { id, tool, input } of calls) {
      await turn.send({
        sessionUpdate: 'tool_call',
        toolCallId: id,
        title: `mcp__chord__${tool}`,
        kind: 'other',
        status: 'pending',
        rawInput: {},
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId: id,
        rawInput: input,
      });
    }

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: bash,
      title: '`board show CHD-377`',
      kind: 'execute',
      status: 'pending',
    });
    // The batch is in flight a moment before the steer cuts it.
    await pause(turn.signal, STEP_MS * 20);

    for (const { id, tool } of calls) {
      const error = `<tool_use_error>Error calling tool (mcp__chord__${tool}): </tool_use_error>`;

      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId: id,
        status: 'failed',
        rawOutput: error,
        content: [{ type: 'content', content: { type: 'text', text: error } }],
        _meta: { claudeCode: { nonExecutionKind: 'interrupted' } },
      });
    }

    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: bash,
      status: 'failed',
      content: [
        {
          type: 'content',
          content: {
            type: 'text',
            text: "The user doesn't want to take this action right now. STOP what you are doing and wait for the user to tell you how to proceed.",
          },
        },
      ],
      _meta: { claudeCode: { nonExecutionKind: 'cancelled' } },
    });
    await turn.say('I have stopped.');

    return 'end_turn';
  },

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
