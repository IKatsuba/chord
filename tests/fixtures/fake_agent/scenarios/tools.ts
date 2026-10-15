/**
 * Tool calls: a read, calls as a screen shows them, calls out of order,
 * edits with their diffs, and a turn of many calls.
 */
import * as acp from '@agentclientprotocol/sdk';
import { EDIT_NEW, EDIT_OLD, REWRITE_NEW, REWRITE_OLD } from '../../edits.ts';
import { STEP_MS } from '../options.ts';
import { pause, type Play } from '../turn.ts';

/** Calls in a `steps` turn, each an entry of the transcript. */
const STEPS = 150;

// A long transcript in one turn: a call an entry, each named by its
// number, done, so a test reads which are mounted.
const steps: Play = async (turn) => {
  for (let step = 1; step <= STEPS; step++) {
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: turn.callId('read'),
      title: `Read step-${step}.ts`,
      kind: 'read',
      status: 'completed',
    });
  }

  await turn.say(`${STEPS} steps read.`);

  return 'end_turn';
};

export const TOOLS = {
  steps,

  // The same calls after a second's pause, for a drag to start before
  // them with no key pressed, which would clear it.
  async stepslater(turn) {
    await pause(turn.signal, STEP_MS * 200);

    return steps(turn);
  },

  async tools(turn) {
    const read = turn.callId('read');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: read,
      title: 'Read README.md',
      kind: 'read',
      status: 'pending',
      locations: [{ path: 'README.md' }],
      rawInput: { path: 'README.md' },
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: read,
      status: 'in_progress',
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: read,
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: '# chord' },
        },
      ],
      rawOutput: { lines: 1 },
    });
    await turn.say('Read it.');

    return 'end_turn';
  },

  // Calls as a screen shows them: long output, a long command that stays in
  // progress long enough to look at, and one that fails.
  async calls(turn) {
    const source = turn.callId('read');
    const test = turn.callId('bash');
    const missing = turn.callId('read');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: source,
      title: 'Read src/main.tsx',
      kind: 'read',
      status: 'in_progress',
      locations: [{ path: 'src/main.tsx' }],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: source,
      status: 'completed',
      content: [
        {
          type: 'content',
          content: {
            type: 'text',
            text: [
              "import { Command } from '@cliffy/command';",
              "import { render } from 'ink';",
              "import { App } from './ui/App.tsx';",
              '',
              'await new Command()',
              "  .name('chord')",
              '  .parse(Deno.args);',
            ].join('\n'),
          },
        },
      ],
    });
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: test,
      title:
        '`deno test --allow-read --allow-write --allow-env --allow-run ' +
        '--allow-sys lint/ tests/ --filter "tool calls draw their status"`',
      kind: 'execute',
      status: 'in_progress',
    });
    await pause(turn.signal, STEP_MS * 300);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: test,
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: 'ok | 1 passed | 0 failed (12ms)' },
        },
      ],
    });
    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: missing,
      title: 'Read src/missing.ts',
      kind: 'read',
      status: 'in_progress',
      locations: [{ path: 'src/missing.ts' }],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: missing,
      status: 'failed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: 'File does not exist.' },
        },
      ],
    });
    await turn.say('Two calls worked, one failed.');

    return 'end_turn';
  },

  // What a client has to survive: an update before its call, the call sent
  // twice, and a stale status after the call finished.
  async unordered(turn) {
    const id = turn.callId('grep');
    const call: acp.ToolCall = {
      toolCallId: id,
      title: 'Search for TODO',
      kind: 'search',
      status: 'pending',
    };

    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: id,
      status: 'in_progress',
    });
    await turn.send({ sessionUpdate: 'tool_call', ...call });
    await turn.send({ sessionUpdate: 'tool_call', ...call });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: id,
      status: 'completed',
      content: [
        {
          type: 'content',
          content: { type: 'text', text: 'src/main.tsx:1: TODO' },
        },
      ],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: id,
      status: 'in_progress',
    });
    await turn.say('Searched.');

    return 'end_turn';
  },

  async edit(turn) {
    const edit = turn.callId('edit');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: edit,
      title: 'Edit src/greeting.ts',
      kind: 'edit',
      status: 'in_progress',
      locations: [{ path: 'src/greeting.ts', line: 1 }],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: edit,
      status: 'completed',
      content: [
        {
          type: 'diff',
          path: 'src/greeting.ts',
          oldText: EDIT_OLD,
          newText: EDIT_NEW,
        },
      ],
    });
    await turn.say('Edited.');

    return 'end_turn';
  },

  async rewrite(turn) {
    const rewrite = turn.callId('rewrite');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: rewrite,
      title: 'Edit src/table.ts',
      kind: 'edit',
      status: 'in_progress',
      locations: [{ path: 'src/table.ts', line: 1 }],
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: rewrite,
      status: 'completed',
      content: [
        {
          type: 'diff',
          path: 'src/table.ts',
          oldText: REWRITE_OLD,
          newText: REWRITE_NEW,
        },
      ],
    });
    await turn.say('Rewrote the table.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;
