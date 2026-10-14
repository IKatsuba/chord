/**
 * A team at work for as long as chord runs, for `scripts/memory.ts`'s
 * long-run memory check: `soak` hands team `bugfix` the job `soaklead`; the
 * lead opens `tester` and `coder` on `soakturn` and sends main `soakturn`;
 * and every `soakturn` streams a reply, a thought and a call, then sends
 * `soakturn` back to whoever sent it. Main, the lead and both members so
 * each take turn after turn, three chains through the lead, never ending.
 */
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';
import { handOver } from './teams.ts';

/** Lines in each `soakturn`'s reply. */
const SOAK_LINES = 30;

/** Who sent each session's last message, by its session, as main.ts read it. */
export const senders = new Map<string, string>();

/** Each session's turns so far, so no two replies say the same. */
const turns = new Map<string, number>();

/** A reply as an agent at work writes one: prose, a list and code. */
async function stream(turn: Turn, n: number): Promise<void> {
  await turn.think(`Turn ${n}: `, 'reading what changed ', 'since the last.');

  for (let line = 1; line <= SOAK_LINES; line++) {
    await pause(turn.signal, STEP_MS * 4);
    await turn.say(
      line === 1
        ? `## Turn ${n}\n\n`
        : line % 10 === 0
          ? `\n\`\`\`ts\nconst turn${n}Line${line} = ${n * line};\n\`\`\`\n`
          : `\n- Turn ${n}, line ${line}: **checked** \`src/parse/tokenize.ts\`.`,
    );
  }
}

/** A call that edits, its output naming the turn. */
async function call(turn: Turn, n: number): Promise<void> {
  const toolCallId = turn.callId('edit');

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: `Edit src/parse/tokenize.ts (turn ${n})`,
    kind: 'edit' satisfies acp.ToolKind,
    status: 'in_progress',
  });
  await pause(turn.signal, STEP_MS * 10);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [
      {
        type: 'content',
        content: { type: 'text', text: `Wrote ${n} lines in turn ${n}.` },
      },
    ],
  });
}

export const SOAK = {
  // Hands `bugfix` the job that starts the soak.
  soak: (turn) => handOver(turn, 'soaklead'),

  // The lead's first turn: both members and main set going.
  async soaklead(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'open_agent', {
        member: 'tester',
        prompt: 'soakturn',
      });
      await callChord(turn, client, 'open_agent', {
        member: 'coder',
        prompt: 'soakturn',
      });
      await callChord(turn, client, 'send_message', {
        to: 'main',
        text: 'soakturn',
      });
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // A turn of work, then the next one asked of whoever sent this.
  async soakturn(turn) {
    const n = (turns.get(turn.sessionId) ?? 0) + 1;
    const to = senders.get(turn.sessionId);

    turns.set(turn.sessionId, n);
    await stream(turn, n);
    await call(turn, n);

    const client = to === undefined ? undefined : await chordClient(turn);

    try {
      if (client !== undefined) {
        await callChord(turn, client, 'send_message', {
          to,
          text: 'soakturn',
        });
      }
    } finally {
      await client?.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
