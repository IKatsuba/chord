/**
 * Replies: plain, thought first, markdown, long and slow, and a few that say
 * what reached the agent.
 */
import { once } from 'node:events';
import process from 'node:process';
import {
  MARKDOWN_LINES,
  MARKDOWN_OPEN_FENCE,
  MARKDOWN_OPEN_NESTED_FENCE,
} from '../../markdown.ts';
import { STEP_MS } from '../options.ts';
import { mcpServers } from '../sessions.ts';
import { lifetime, pause, type Play } from '../turn.ts';

/** How many items the `long` scenario's list has. */
const LONG_LINES = 200;

export const TEXT = {
  async text(turn) {
    await turn.say('Hello', ', world', '. This reply', ' came in chunks.');

    return 'end_turn';
  },

  async thought(turn) {
    await turn.think('Considering', ' the question.');
    await turn.say('Here is', ' the answer.');

    return 'end_turn';
  },

  async todos(turn) {
    await turn.say(
      `todo tools: ${process.env.CLAUDE_CODE_ENABLE_TODO_TOOLS ?? 'unset'}`,
    );

    return 'end_turn';
  },

  async mcp(turn) {
    await turn.say(
      `\`\`\`json\n${JSON.stringify(
        mcpServers.get(turn.sessionId) ?? [],
        null,
        2,
      )}\n\`\`\``,
    );

    return 'end_turn';
  },

  // A reply in markdown, streamed a line at a time, that waits inside its
  // open code fences, the top-level one and the one in a list, long enough
  // to look at.
  async markdown(turn) {
    const chunks = MARKDOWN_LINES.map((line, index) =>
      index === 0 ? line : `\n${line}`,
    );

    await turn.say(...chunks.slice(0, MARKDOWN_OPEN_FENCE));
    await pause(turn.signal, STEP_MS * 300);
    await turn.say(
      ...chunks.slice(MARKDOWN_OPEN_FENCE, MARKDOWN_OPEN_NESTED_FENCE),
    );
    await pause(turn.signal, STEP_MS * 300);
    await turn.say(...chunks.slice(MARKDOWN_OPEN_NESTED_FENCE));

    return 'end_turn';
  },

  // Graphemes of several code points right before bold and code, where
  // OpenTUI 0.5.17 started the next run a cell late for each extra one
  // (CHD-319).
  async graphemes(turn) {
    await turn.say(
      [
        'A decomposed e\u0301 **then bold** and `then code` after it.',
        '',
        '- 👩‍💻 **joined** then `code`',
        '- ⚠️ **warning** then `code`',
        '- 👍🏽 **toned** then `code`',
        '- plain **bold** then `code`',
      ].join('\n'),
    );

    return 'end_turn';
  },

  // Reports the session's cost so far, then works on until it is
  // cancelled, as a turn a person closes while it runs (CHD-373).
  async costwait(turn) {
    await turn.send({
      sessionUpdate: 'usage_update',
      used: 1200,
      size: 200000,
      cost: { amount: 0.01, currency: 'USD' },
    });
    await turn.say('Working until stopped.');
    turn.signal.throwIfAborted();
    await once(turn.signal, 'abort', { signal: lifetime.signal });
    turn.signal.throwIfAborted();

    return 'end_turn';
  },

  async slow(turn) {
    await turn.say('Working');

    for (let i = 0; i < 1000; i++) {
      await turn.say('.');
    }

    return 'end_turn';
  },

  // A numbered reply taller than any window, slow enough that a person in
  // tmux can scroll back while it still streams.
  async long(turn) {
    for (let n = 1; n <= LONG_LINES; n++) {
      await pause(turn.signal, STEP_MS * 19);
      await turn.say(
        `${
          n === 1 ? '' : '\n'
        }${n}. Line ${n} of ${LONG_LINES}, streamed one at a time.`,
      );
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
