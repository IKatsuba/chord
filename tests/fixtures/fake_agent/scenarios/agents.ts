/**
 * Long-lived agents: a session that opens two on the fake runtime through
 * chord's `open_agent` and messages one of them twice, the child's first
 * turn, which messages its parent twice, a session that closes one and is
 * refused when it messages it after, and sessions that open one on a long
 * instruction, or whose first turn starts a task agent, or whose agent exits
 * or turn fails in it.
 */
import process from 'node:process';
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

/** A child's pace: 20 steps, a tenth of a second by default. */
const AGENT_STEP_MS = STEP_MS * 20;

/** What `agents` opens first: the fake runtime's small model on `agentchild`. */
export const PARSER_ARGS = {
  agent: 'fake',
  model: 'fake-small',
  prompt: 'agentchild',
  name: 'parser',
};

/** What it opens second, on the runtime's own model, which asks to write. */
export const DOCS_ARGS = {
  agent: 'fake',
  prompt: 'permission',
  name: 'docs',
};

/** The parent's two messages to `parser`. */
export const MAIN_MESSAGES = [
  'I changed how a string at the end of a line is read. Run the parser ' +
    'tests now and tell me only what fails.',
  'The printer is fixed too; run the whole parser suite once more.',
] as const;

/**
 * A long instruction with markdown in it, as a parent opens a child on, so
 * the child's view has a body that folds and has weight and code in it.
 */
export const LONG_INSTRUCTION = [
  'Read AGENTS.md and docs/FEATURES.md before you start. Then:',
  '',
  '1. Fix the tokenizer so a string at the end of a line keeps its closing ' +
    'quote.',
  '2. Add two cases to `tests/parse/tokenize_test.ts`.',
  '3. Run `deno task check` in the foreground and **do not** hand back until ' +
    'it passes.',
  '',
  'Tell me only what failed, if anything.',
].join('\n');

/** What a child's last words are when its agent exits mid-turn. */
export const CRASH_WORDS =
  'fatal: out of memory reading tests/parse/fixtures/huge.json';

/** The parent's message to `docs` while `docs` waits on its permission. */
export const DOCS_MESSAGE =
  'When the README section is done, add the new flag to docs/FEATURES.md.';

/** `parser`'s two messages to its parent. */
export const CHILD_MESSAGES = [
  'Ran deno task test tests/parse: 2 failures, both in ' +
    'tests/parse/printer_test.ts.',
  'All 214 parser tests pass now.',
] as const;

/** Opens `parser` with `prompt` as its first turn, then waits on it. */
async function openParserOn(turn: Turn, prompt: string): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'open_agent', { ...PARSER_ARGS, prompt });
    await turn.say('Waiting on parser.');
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/** A call of the child's own, done after a step. */
async function work(turn: Turn, title: string, output: string): Promise<void> {
  const toolCallId = turn.callId('execute');

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title,
    kind: 'execute' satisfies acp.ToolKind,
    status: 'in_progress',
  });
  await pause(turn.signal, AGENT_STEP_MS * 10);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [{ type: 'content', content: { type: 'text', text: output } }],
  });
}

export const AGENTS = {
  // Opens `parser` and `docs`, then tells `parser` twice what changed, a
  // while apart, so the second waits behind the turn the first started.
  async agents(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await turn.say('I will open parser on the tests and docs on the README.');
      await callChord(turn, client, 'open_agent', PARSER_ARGS);
      await callChord(turn, client, 'open_agent', DOCS_ARGS);
      await pause(turn.signal, AGENT_STEP_MS * 10);

      for (const text of MAIN_MESSAGES) {
        await callChord(turn, client, 'send_message', { to: 'parser', text });
        await pause(turn.signal, AGENT_STEP_MS * 10);
      }

      await turn.say('Waiting on parser.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // Opens `docs`, which asks to write, and messages it while it waits on
  // the person, where a runtime that steers holds it for their answer.
  async agentsheld(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'open_agent', DOCS_ARGS);
      await pause(turn.signal, AGENT_STEP_MS * 10);
      await callChord(turn, client, 'send_message', {
        to: 'docs',
        text: DOCS_MESSAGE,
      });
      await turn.say('Waiting on docs.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // `parser`'s first turn: a test run, a message to its parent, another run
  // and a second message.
  async agentchild(turn) {
    const client = await chordClient(turn);

    try {
      await work(turn, '`deno task test tests/parse`', '2 failed, 212 passed');

      if (client !== undefined) {
        await callChord(turn, client, 'send_message', {
          text: CHILD_MESSAGES[0],
        });
      }

      await work(turn, '`deno task test tests/parse`', '214 passed, 0 failed');

      if (client !== undefined) {
        await callChord(turn, client, 'send_message', {
          text: CHILD_MESSAGES[1],
        });
      }

      await turn.say('I will run the parser tests on each change.');
    } finally {
      await client?.close();
    }

    return 'end_turn';
  },

  // Opens `parser` on `task`, so the child starts a task agent of its own.
  agenttask: (turn) => openParserOn(turn, 'task'),

  // Opens `parser` on a long instruction, which it answers as a message.
  agentlong: (turn) => openParserOn(turn, LONG_INSTRUCTION),

  // Opens `parser` on `crash`, whose agent exits in its first turn.
  agentexit: (turn) => openParserOn(turn, 'crash'),

  // Opens `parser` on `error`, whose first turn fails with its agent up.
  agentfail: (turn) => openParserOn(turn, 'error'),

  // A child's turn whose agent goes: a test run, its last words on stderr,
  // then the exit, with the turn never answered.
  async crash(turn) {
    await work(turn, '`deno task test tests/parse`', 'Killed');
    console.error(CRASH_WORDS);
    // Long enough for the line to reach chord before the pipe closes.
    await pause(turn.signal, AGENT_STEP_MS);
    process.exit(1);
  },

  // Closes `parser`, then messages it, which chord refuses.
  async agentclose(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'close_agent', { to: 'parser' });
      await callChord(turn, client, 'send_message', {
        to: 'parser',
        text: 'Are you still there?',
      });
      await turn.say('parser is closed, so I will run the tests myself.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
