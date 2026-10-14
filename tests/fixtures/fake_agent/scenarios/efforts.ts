/**
 * Agents started on an effort: a task and a long-lived agent on the fake
 * runtime's small model, each on an effort it offers and on one it does not,
 * and what chord's answer said of where it started; and the effort a turn
 * runs on, said from inside it.
 */
import { NO_CONFIG } from '../options.ts';
import { efforts } from '../sessions.ts';
import type { Play, Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

/** The task `taskeffort` and `taskmaxeffort` start, on `text`. */
export const EFFORT_TASK_ARGS = {
  agent: 'fake',
  model: 'fake-small',
  prompt: 'text',
  name: 'Tune the parser',
};

/** The agent `agenteffort` and `agentmaxeffort` open, on `text`. */
export const EFFORT_AGENT_ARGS = {
  agent: 'fake',
  model: 'fake-small',
  prompt: 'text',
  name: 'tuner',
};

/**
 * Calls `tool` on `effort` and says where the agent started, as the
 * answer has it: `Started on high.`, or the refusal after the effort it is
 * on.
 */
async function startOn(
  turn: Turn,
  tool: 'spawn_task' | 'open_agent',
  args: Record<string, unknown>,
  effort: string,
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    const text = await callChord(turn, client, tool, { ...args, effort });
    const answer = JSON.parse(text ?? '{}') as {
      effort?: string;
      note?: string;
    };

    await turn.say(
      `Started on ${answer.effort ?? 'no effort'}.${
        answer.note === undefined ? '' : ` ${answer.note}.`
      }`,
    );
  } finally {
    await client.close();
  }

  return 'end_turn';
}

export const EFFORTS = {
  // What the turn runs on, from inside it, so an effort asked for before the
  // prompt is shown to have reached the session the prompt came to.
  async effort(turn) {
    await turn.say(
      `Effort: ${NO_CONFIG ? 'none' : (efforts.get(turn.sessionId) ?? 'medium')}.`,
    );

    return 'end_turn';
  },

  taskeffort(turn) {
    return startOn(turn, 'spawn_task', EFFORT_TASK_ARGS, 'high');
  },

  taskmaxeffort(turn) {
    return startOn(turn, 'spawn_task', EFFORT_TASK_ARGS, 'max');
  },

  agenteffort(turn) {
    return startOn(turn, 'open_agent', EFFORT_AGENT_ARGS, 'high');
  },

  agentmaxeffort(turn) {
    return startOn(turn, 'open_agent', EFFORT_AGENT_ARGS, 'max');
  },
} satisfies Record<string, Play>;
