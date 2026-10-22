/**
 * Long-lived agents: a session that opens two on the fake runtime through
 * chord's `open_agent` and messages one of them twice, the child's first
 * turn, which messages its parent twice, a session that closes one and is
 * refused when it messages it after, sessions that send one a short and a
 * long message, or long prose it sends back, as Claude and Codex do, or one
 * never opened, and sessions that open one on a long instruction, or whose
 * first turn starts a task agent, or whose agent exits or turn fails in it.
 */
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { cwds } from '../sessions.ts';
import { pause, type Play, steeredIn, type Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';

/**
 * A child's pace: 2 steps, 10 ms by default. Where an order is a gate's,
 * the pace is only how a turn's steps are spread (CHD-501).
 */
const AGENT_STEP_MS = STEP_MS * 2;

/**
 * The pace before CHD-501, 100 ms by default, kept where a wait stands for
 * something no gate says yet: a call open long enough for messages to be
 * held behind it, a moment for a child to open its call, a line's way to
 * chord before the pipe closes.
 */
const HELD_STEP_MS = STEP_MS * 20;

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
 * What `agenttitled` names the child it opens: a session title long enough
 * that its row is taller than the agents list at 80x24 (CHD-471).
 */
export const LONG_TITLE =
  'Summarise the release notes for 0.56.0 from the commits since 0.55.2, ' +
  'grouped by area, with a line for each user-facing change and a note for ' +
  'each breaking one, then draft the announcement for the forum and the ' +
  'changelog entry, and list the open questions for the owner to settle ' +
  'before the tag.';

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

/**
 * The directory, in a session's own, where `callchildgated` and
 * `agentcallgated` meet a test: `GATE_OPEN` is written once the child's
 * call is open, and the call ends only once the test writes `GATE_RELEASE`.
 */
export const GATE = '.fake-gate';
export const GATE_OPEN = 'open';
export const GATE_RELEASE = 'release';

/**
 * Until `file` is in the gate of `turn`'s session, or 10 s without it, so a
 * test that never opens it fails rather than hanging the turn (CHD-399).
 */
export async function gateOpened(turn: Turn, file: string): Promise<void> {
  const at = join(cwds.get(turn.sessionId) ?? '.', GATE, file);
  const deadline = Date.now() + 10_000;

  while (!existsSync(at) && Date.now() < deadline) {
    await pause(turn.signal, STEP_MS * 2);
  }
}

/** The mark in a gate that its session has heard `text`, told it in a message. */
export function toldMark(text: string): string {
  return `told-${createHash('sha1').update(text.trim()).digest('hex').slice(0, 12)}`;
}

/** Each message chord wrapped in a prompt, its text. */
const TOLD =
  /<message from="[^"]*"(?: monitor="[^"]*")?>\n([\s\S]*?)\n<\/message>/g;

/**
 * Marks in session `sessionId`'s gate each message `text` tells it, as it
 * hears it, a turn's prompt or steered in, so a play that told it can wait
 * until it has, rather than for a while: only where the gate is, which a
 * play that waits on it makes (CHD-501).
 */
export function heard(sessionId: string, text: string): void {
  const gate = join(cwds.get(sessionId) ?? '.', GATE);

  if (!existsSync(gate)) {
    return;
  }

  for (const [, told] of text.matchAll(TOLD)) {
    writeFileSync(join(gate, toldMark(told!)), '');
  }
}

/** Until `file` is in the gate of `turn`'s session, or the turn is stopped. */
async function gated(turn: Turn, file: string): Promise<void> {
  const at = join(cwds.get(turn.sessionId) ?? '.', GATE, file);

  while (!existsSync(at) && !turn.signal.aborted) {
    await pause(turn.signal, STEP_MS * 2);
  }
}

/** What `agentcall` tells `parser` while its call is open. */
export const HELD_MESSAGE = 'Then the docs, once the tests pass.';

/** What `agentcalltwice` tells `parser` after `HELD_MESSAGE`, in the same call. */
export const HELD_AGAIN = 'And the changelog after the docs.';

/** A short message to `parser`, sent before `LONG_MESSAGE`. */
export const SHORT_MESSAGE = 'Start on the tokenizer; the printer can wait.';

/**
 * A review sent as a message, with a numbered list, weight and code in it,
 * longer than a message's six lines at 120 columns, so the sent body folds.
 */
export const LONG_MESSAGE = [
  'CHD-1 unit 4: points 1 and 2 are good. Four things before I look again:',
  '',
  '1. The fold counts the blank line after the list; drop it, as ' +
    '`foldMessage` already does for a received message.',
  '2. `foldMessage` runs on every render; keep its lines in the same ' +
    '`useMemo` as the markdown.',
  '3. The hint names ctrl+o even when the person has rebound it; take the ' +
    'key from `useHintKey`.',
  '4. The refusal goes after the body, in the error colour, **never** folded.',
  '',
  'Commit each as its own fix, run the targeted tests, and tell me when ' +
    "the check passes and I'll look again.",
].join('\n');

/**
 * Two paragraphs of Cyrillic prose, each a few rows long at 120 columns, so
 * a message is read whole, wrapped at its words, never cut in the middle.
 */
export const PROSE_RU = [
  'Это длинное тестовое сообщение для проверки передачи текста между ' +
    'агентами. В нём нет задания на изменение кода, запуск проверок или ' +
    'работу с файлами: оно предназначено только для проверки доставки и ' +
    'отображения большого объёма текста.',
  '',
  'Представим небольшую обсерваторию на вершине холма. Каждое утро ' +
    'смотритель открывает деревянные ставни, проверяет журнал наблюдений и ' +
    'ставит чайник на старую плиту. За окном медленно расходится туман, на ' +
    'дорожке появляются первые солнечные пятна, а в саду перекликаются птицы.',
].join('\n');

/** A paragraph of ASCII prose a few rows long at 120 columns, the same way. */
export const PROSE_EN =
  'The printer is fixed, and every case in tests/parse/printer_test.ts ' +
  'passes now. The tokenizer still drops a closing quote when a string ' +
  'ends the line, so I left a failing case for it beside the others and ' +
  'wrote down what I found in the notes, with the input that shows it and ' +
  'the line in src/parse/tokenize.ts where the quote is lost.';

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
async function openParserOn(
  turn: Turn,
  prompt: string,
  name = PARSER_ARGS.name,
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'open_agent', {
      ...PARSER_ARGS,
      prompt,
      name,
    });
    await turn.say(`Waiting on ${name === PARSER_ARGS.name ? name : 'it'}.`);
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/**
 * Opens `parser` on `prompt`, which answers, and sends it `texts`, its
 * calls in `shape`'s adapter's.
 */
async function sendParser(
  turn: Turn,
  shape: 'claude' | 'codex',
  prompt = 'agentchild',
  texts: readonly string[] = [SHORT_MESSAGE, LONG_MESSAGE],
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(
      turn,
      client,
      'open_agent',
      { ...PARSER_ARGS, prompt },
      undefined,
      shape,
    );

    for (const text of texts) {
      await callChord(
        turn,
        client,
        'send_message',
        { to: 'parser', text },
        undefined,
        shape,
      );
      await pause(turn.signal, AGENT_STEP_MS * 10);
    }

    await turn.say('Waiting on parser.');
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/** `PROSE_RU` and `PROSE_EN` to the parent, in `shape`'s adapter's calls. */
async function sendProse(
  turn: Turn,
  shape: 'claude' | 'codex',
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  try {
    for (const text of [PROSE_RU, PROSE_EN]) {
      if (client !== undefined) {
        await callChord(
          turn,
          client,
          'send_message',
          { text },
          undefined,
          shape,
        );
      }
    }

    await turn.say('Both sent back.');
  } finally {
    await client?.close();
  }

  return 'end_turn';
}

/**
 * Opens `parser` on `child` and, a moment into its call, or once a gated
 * child says it is open, tells it each of `texts` in turn, so each is told
 * while that call is open.
 */
async function tellParserDuringCall(
  turn: Turn,
  texts: readonly string[],
  child = 'callchild',
): Promise<'end_turn'> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'open_agent', {
      ...PARSER_ARGS,
      prompt: child,
    });

    // The gated child says when its call is open; the other is given a moment.
    if (child === 'callchildgated') {
      await gated(turn, GATE_OPEN);
    } else {
      await pause(turn.signal, HELD_STEP_MS * 2);
    }

    for (const text of texts) {
      await callChord(turn, client, 'send_message', { to: 'parser', text });
    }

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

/**
 * One call for about three seconds, then a report that the tests pass; its
 * next step after the call waits until `untilTold` messages were steered in.
 */
async function callChild(turn: Turn, untilTold = 0): Promise<acp.StopReason> {
  const toolCallId = turn.callId('execute');

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: '`deno task test`',
    kind: 'execute',
    status: 'in_progress',
  });
  await pause(turn.signal, HELD_STEP_MS * 30);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [
      {
        type: 'content',
        content: { type: 'text', text: '214 passed, 0 failed' },
      },
    ],
  });

  await steeredIn(turn, untilTold);
  await turn.say('The tests pass.');

  return 'end_turn';
}

/**
 * Opens `docs` on `permission` and messages it: after a pause, or with
 * `gated` once `GATE_RELEASE` is in the gate (`gateOpened`).
 */
async function messageDocsAsking(
  turn: Turn,
  gated: boolean,
): Promise<acp.StopReason> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'open_agent', DOCS_ARGS);

    if (gated) {
      await gateOpened(turn, GATE_RELEASE);
    } else {
      await pause(turn.signal, AGENT_STEP_MS * 10);
    }

    await callChord(turn, client, 'send_message', {
      to: 'docs',
      text: DOCS_MESSAGE,
    });
    await turn.say('Waiting on docs.');
  } finally {
    await client.close();
  }

  return 'end_turn';
}

export const AGENTS = {
  // Opens `parser` and `docs`, then tells `parser` twice what changed,
  // the first once parser is at its first turn, the second once parser has
  // the first, so the second waits behind the turn the first started.
  async agents(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      mkdirSync(join(cwds.get(turn.sessionId) ?? '.', GATE), {
        recursive: true,
      });
      await turn.say('I will open parser on the tests and docs on the README.');
      await callChord(turn, client, 'open_agent', PARSER_ARGS);
      await callChord(turn, client, 'open_agent', DOCS_ARGS);
      await gateOpened(turn, toldMark(PARSER_ARGS.prompt));

      for (const text of MAIN_MESSAGES) {
        await callChord(turn, client, 'send_message', { to: 'parser', text });
        await gateOpened(turn, toldMark(text));
      }

      await turn.say('Waiting on parser.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // Opens `docs`, which asks to write, and messages it while it waits on
  // the person, where a runtime that steers holds it for their answer.
  agentsheld: (turn) => messageDocsAsking(turn, false),

  // As `agentsheld`, the message sent only once the test writes
  // `GATE_RELEASE` in the gate, which it does once chord shows docs
  // asking: chord has its request by then, however slow docs started
  // (CHD-399).
  agentsheldgated: (turn) => messageDocsAsking(turn, true),

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

  // Opens `parser` on `costwait`, so the child reports a cost and works on
  // until it is stopped, as one closed while busy (CHD-373).
  agentcost: (turn) => openParserOn(turn, 'costwait'),

  // Opens `parser` on a long instruction, which it answers as a message.
  agentlong: (turn) => openParserOn(turn, LONG_INSTRUCTION),

  // Opens `parser` on `crash`, whose agent exits in its first turn.
  agentexit: (turn) => openParserOn(turn, 'crash'),

  // Opens `parser` on `error`, whose first turn fails with its agent up.
  agentfail: (turn) => openParserOn(turn, 'error'),

  // Opens a child on `text` under `LONG_TITLE`, a row taller than the list.
  agenttitled: (turn) => openParserOn(turn, 'text', LONG_TITLE),

  // A child's turn whose agent goes: a test run, its last words on stderr,
  // then the exit, with the turn never answered.
  async crash(turn) {
    await work(turn, '`deno task test tests/parse`', 'Killed');
    console.error(CRASH_WORDS);
    // Long enough for the line to reach chord before the pipe closes.
    await pause(turn.signal, HELD_STEP_MS);
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

  // Opens `parser` on `callchild` and, while its call is open, tells it
  // `HELD_MESSAGE`, which a steering adapter that cuts calls holds.
  agentcall: (turn) => tellParserDuringCall(turn, [HELD_MESSAGE]),

  // As `agentcalltwice`, gated for a test: `parser` plays
  // `callchildgated`, and both messages are told only once its call is
  // open, which then stays open until the test releases it.
  agentcallgated: (turn) =>
    tellParserDuringCall(turn, [HELD_MESSAGE, HELD_AGAIN], 'callchildgated'),

  // One call open from the turn's start, `GATE_OPEN` written in the gate
  // once it is, until `GATE_RELEASE` is there, then the answer.
  async callchildgated(turn) {
    const toolCallId = turn.callId('execute');
    const gate = join(cwds.get(turn.sessionId) ?? '.', GATE);

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: '`deno task test`',
      kind: 'execute',
      status: 'in_progress',
    });
    mkdirSync(gate, { recursive: true });
    writeFileSync(join(gate, GATE_OPEN), '');
    await gated(turn, GATE_RELEASE);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: '214 passed, 0 failed' },
        },
      ],
    });
    await turn.say('The tests pass.');

    return 'end_turn';
  },

  // The same with `HELD_AGAIN` after it, both told during that one call.
  agentcalltwice: (turn) =>
    tellParserDuringCall(turn, [HELD_MESSAGE, HELD_AGAIN]),

  // One call open from the turn's start for about 3 s, long enough for a
  // message held behind it to be seen, then the answer.
  callchild: (turn) => callChild(turn),

  // As callchild, its next step after the call waiting until two messages
  // have been steered in, as a model's comes only after the tool's result.
  callchildtwo: (turn) => callChild(turn, 2),

  // A short message and a long one to `parser`, which answers: Claude's
  // calls, then Codex's, wrapped as its adapter wraps another server's.
  agentsend: (turn) => sendParser(turn, 'claude'),
  codexagentsend: (turn) => sendParser(turn, 'codex'),

  // `PROSE_RU` and `PROSE_EN` to `parser`, which sends both back: long
  // paragraphs, Cyrillic and ASCII, sent and received, as Claude and Codex.
  agentprose: (turn) =>
    sendParser(turn, 'claude', 'prosechild', [PROSE_RU, PROSE_EN]),
  codexagentprose: (turn) =>
    sendParser(turn, 'codex', 'codexprosechild', [PROSE_RU, PROSE_EN]),
  prosechild: (turn) => sendProse(turn, 'claude'),
  codexprosechild: (turn) => sendProse(turn, 'codex'),

  // `LONG_MESSAGE` to `parser`, which was never opened: chord refuses it.
  async agentsendrefused(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'send_message', {
        to: 'parser',
        text: LONG_MESSAGE,
      });
      await turn.say('parser is not open, so I will review it myself.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
