/** Synthetic fx ordering, independent of any model's language validation. */
import * as acp from '@agentclientprotocol/sdk';
import type { Play, Turn } from '../turn.ts';

export const FX_ERROR_NOTICE =
  'The model response used a different language than your request, and fx ' +
  'could not accept it. Retry or name the response language explicitly.';

async function shell(turn: Turn, number: number): Promise<void> {
  const toolCallId = turn.callId('shell');
  const command = `echo fixture-${number}`;

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: 'Running',
    kind: 'execute',
    status: 'pending',
    rawInput: { command },
  });
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'in_progress',
  });
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'in_progress',
    content: [
      { type: 'content', content: { type: 'text', text: 'Fixture output.' } },
    ],
  });
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [
      {
        type: 'content',
        content: {
          type: 'text',
          text: '{"session_id":null,"state":"completed","output_delta":"Fixture',
        },
      },
    ],
  });
}

export const FX = {
  async fxerror(turn) {
    await shell(turn, 1);

    for (let number = 1; number <= 5; number++) {
      const toolCallId = turn.callId('search');

      await turn.send({
        sessionUpdate: 'tool_call',
        toolCallId,
        title: 'Searching',
        kind: 'search',
        status: 'pending',
        rawInput: {
          path: `fixture-skills-${number}`,
          pattern: 'agent-browser',
        },
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'in_progress',
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'completed',
        content: [
          {
            type: 'content',
            content: {
              type: 'text',
              text: '[grep] no matches for agent-browser',
            },
          },
        ],
      });
    }

    await shell(turn, 2);
    await turn.say(FX_ERROR_NOTICE);

    throw new acp.RequestError(-32603, 'ResponseLanguageMismatch');
  },
} satisfies Record<string, Play>;
