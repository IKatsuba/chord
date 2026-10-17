/**
 * Tool calls: a read, calls as a screen shows them, calls out of order,
 * edits with their diffs, a turn of many calls, and headlines longer than a
 * row, an MCP call's among them.
 */
import * as acp from '@agentclientprotocol/sdk';
import { EDIT_NEW, EDIT_OLD, REWRITE_NEW, REWRITE_OLD } from '../../edits.ts';
import {
  NOTE_ARGUMENTS,
  NOTES_COMMAND,
  WEATHER_COMMAND,
} from '../../headlines.ts';
import { STEP_MS } from '../options.ts';
import { codexCall } from './chord_tools.ts';
import { pause, type Play, type Turn } from '../turn.ts';

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

/** A heredoc command, a heading and a list in it, as Claude writes notes. */
const HEREDOC = [
  "cat >> notes.md <<'EOF'",
  '## Decisions',
  '',
  'The headline shows the whole command:',
  '',
  '- every line of a heredoc',
  '- wrapped to the width',
  '- with no ctrl+o',
  '',
  '### Left',
  '',
  '1. a cap, if ever',
  'EOF',
].join('\n');

/** A command of one line, over 200 characters. */
const ONE_LINE =
  'cd apps/editor && grep -rn "headline" src/ui/transcript/tools/ ' +
  '--include="*.ts" --include="*.tsx" | grep -v "_test" | sort | uniq -c | ' +
  'sort -rn | head -20; git log --oneline -n 5 -- src/ui/transcript/tools/';

/** Lines of the `headlines` scenario's longest command. */
const LONG_COMMAND = 300;

/** A heredoc of `LONG_COMMAND` lines: its opener, numbered lines, `EOF`. */
const LONG = [
  "cat > lines.txt <<'EOF'",
  ...Array.from(
    { length: LONG_COMMAND - 2 },
    (_, line) => `line ${line + 1} of the long command`,
  ),
  'EOF',
].join('\n');

/** A command Bash ran, as Claude's adapter titles it, that wrote `output`. */
async function ran(
  turn: Turn,
  command: string,
  output: string,
): Promise<acp.StopReason> {
  const toolCallId = turn.callId('bash');

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title: `\`${command}\``,
    kind: 'execute',
    status: 'in_progress',
    rawInput: { command },
  });
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [{ type: 'content', content: { type: 'text', text: output } }],
  });
  await turn.say('Done.');

  return 'end_turn';
}

/** An MCP call's result on one line of JSON, a few rows long at 120 columns. */
export const LONG_JSON = JSON.stringify({
  status: 'completed',
  result:
    '# Long MCP result\n\nEvery note in the vault, exported with its tags, ' +
    'its links and the date it was last changed, so the agent can read ' +
    'them without opening each file.\n\nEnd of the long result.',
  logs: [],
});

/** A command's output with a line longer than any row. */
export const LONG_STDOUT = [
  'Building chord for darwin-arm64, linux-x64, linux-arm64, windows-x64 ' +
    'and darwin-x64 with bun build --compile, the native library embedded ' +
    'for each target, and the binaries laid out under dist/.',
  'Done.',
].join('\n');

/** A file's one line before and after an edit that makes it long. */
export const LONG_DIFF = {
  path: 'src/greeting.ts',
  oldText: "export const greeting = 'Hello';\n",
  newText:
    "export const greeting = 'Hello, and welcome to chord, the terminal ' +\n" +
    "  'client for coding agents that speak the Agent Client Protocol, ' + 'run from source';\n",
};

/** A terminal's line longer than any row, as Codex's adapter streams it. */
export const LONG_TERMINAL =
  'error: tests/parse/tokenize_test.ts:42 expected the closing quote of a ' +
  'string at the end of a line to be kept, but the token ended one ' +
  'character early and the quote was read as the start of the next one\n';

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

  // Results longer than a row, each to be read whole and wrapped: an MCP
  // call's JSON on one line, a command's long stdout, an edit that makes a
  // line long, and a terminal's long line, as Codex's adapter sends one.
  async longresults(turn) {
    const done = (
      toolCallId: string,
      call: Omit<acp.ToolCall, 'toolCallId' | 'status'>,
      content: acp.ToolCallContent[],
    ) =>
      turn.send({
        sessionUpdate: 'tool_call',
        toolCallId,
        status: 'completed',
        ...call,
        content,
      });
    const text = (value: string): acp.ToolCallContent => ({
      type: 'content',
      content: { type: 'text', text: value },
    });

    await done(
      turn.callId('export'),
      { title: 'mcp__notes__export_notes', kind: 'other', rawInput: {} },
      [text(LONG_JSON)],
    );
    await done(
      turn.callId('build'),
      { title: '`bun dev compile --all`', kind: 'execute' },
      [text(LONG_STDOUT)],
    );
    await done(
      turn.callId('edit'),
      { title: 'Edit src/greeting.ts', kind: 'edit' },
      [{ type: 'diff', ...LONG_DIFF }],
    );

    const shell = turn.callId('shell');
    const terminalId = `terminal-${shell}`;

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId: shell,
      title: 'Run deno task test',
      kind: 'execute',
      status: 'in_progress',
      content: [{ type: 'terminal', terminalId }],
      _meta: { terminal_info: { terminal_id: terminalId } },
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: shell,
      status: 'failed',
      _meta: {
        terminal_output_delta: { terminal_id: terminalId, data: LONG_TERMINAL },
        terminal_exit: { terminal_id: terminalId, exit_code: 1, signal: null },
      },
    });
    await turn.say('Four long results.');

    return 'end_turn';
  },

  // As `overlap`, but `a` ends failed: a call that fails has ended too, and
  // a message held for it goes in before `b` ends.
  async overlapfail(turn) {
    const open = (toolCallId: string, title: string) =>
      turn.send({
        sessionUpdate: 'tool_call',
        toolCallId,
        title,
        kind: 'execute',
        status: 'in_progress',
      });

    await open('overlapfail-a', '`false`');
    await pause(turn.signal, STEP_MS * 20);
    await open('overlapfail-b', '`sleep 2`');
    await pause(turn.signal, STEP_MS * 20);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'overlapfail-a',
      status: 'failed',
    });
    await pause(turn.signal, STEP_MS * 20);
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId: 'overlapfail-b',
      status: 'completed',
    });
    await turn.say('One failed, one slept.');

    return 'end_turn';
  },

  // Two calls that overlap: `a` opens, then `b` a while later, then `a`
  // ends and, a while after, `b`, so a message told while only `a` was
  // open is seen to wait for `a` alone.
  async overlap(turn) {
    const open = (toolCallId: string, title: string) =>
      turn.send({
        sessionUpdate: 'tool_call',
        toolCallId,
        title,
        kind: 'execute',
        status: 'in_progress',
      });
    const end = (toolCallId: string) =>
      turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId,
        status: 'completed',
      });

    await open('overlap-a', '`sleep 1`');
    await pause(turn.signal, STEP_MS * 20);
    await open('overlap-b', '`sleep 2`');
    await pause(turn.signal, STEP_MS * 20);
    await end('overlap-a');
    await pause(turn.signal, STEP_MS * 20);
    await end('overlap-b');
    await turn.say('Both slept.');

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

  // Headlines longer than a row: a heredoc, a long one-line command, an MCP
  // call as Claude's adapter titles one, by its name with the arguments in
  // `rawInput`, and a command of 300 lines; each answered with a line.
  async headlines(turn) {
    const calls: readonly [acp.ToolCall, string][] = [
      [
        {
          toolCallId: turn.callId('bash'),
          title: `\`${HEREDOC}\``,
          kind: 'execute',
          rawInput: { command: HEREDOC },
        },
        '(no output)',
      ],
      [
        {
          toolCallId: turn.callId('bash'),
          title: `\`${ONE_LINE}\``,
          kind: 'execute',
          rawInput: { command: ONE_LINE },
        },
        '     12 src/ui/transcript/tools/tools.ts',
      ],
      [
        {
          toolCallId: turn.callId('send'),
          title: 'mcp__chord__send_message',
          kind: 'other',
          rawInput: {
            to: 'reviewer',
            text:
              'CHD-393 U1 is done: the headlines scenario plays a heredoc, ' +
              'a long one-line command, this call and a command of 300 ' +
              'lines; nothing of chord changes, so it goes to you directly.',
          },
        },
        'Delivered to reviewer.',
      ],
      [
        {
          toolCallId: turn.callId('bash'),
          title: `\`${LONG}\``,
          kind: 'execute',
          rawInput: { command: LONG },
        },
        '(no output)',
      ],
    ];

    for (const [call, output] of calls) {
      await turn.send({
        sessionUpdate: 'tool_call',
        ...call,
        status: 'in_progress',
      });
      await turn.send({
        sessionUpdate: 'tool_call_update',
        toolCallId: call.toolCallId,
        status: 'completed',
        content: [{ type: 'content', content: { type: 'text', text: output } }],
      });
    }

    await turn.say('Four calls with long headlines.');

    return 'end_turn';
  },

  // The calls of the Claude Code capture in docs/design/CHD-393.md.
  heredoc: (turn) => ran(turn, NOTES_COMMAND, '      10 notes.md'),
  longcommand: (turn) => ran(turn, WEATHER_COMMAND, '309'),

  // The capture's MCP call as codex-acp sends one: a command by its dotted
  // name, the server, tool and arguments wrapped in rawInput (CHD-419).
  async codexmcpnote(turn) {
    const toolCallId = turn.callId('save_note');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      status: 'in_progress',
      ...codexCall('notes', 'save_note', NOTE_ARGUMENTS),
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
            text: `saved "${NOTE_ARGUMENTS.title}" (${NOTE_ARGUMENTS.body.length} chars)`,
          },
        },
      ],
    });
    await turn.say('Done.');

    return 'end_turn';
  },

  // The capture's MCP call, as claude-agent-acp sends one: titled by its
  // name, its arguments in rawInput alone, first empty then whole.
  async mcpnote(turn) {
    const toolCallId = turn.callId('save_note');

    await turn.send({
      sessionUpdate: 'tool_call',
      toolCallId,
      title: 'mcp__notes__save_note',
      kind: 'other',
      status: 'pending',
      rawInput: {},
    });
    await turn.send({
      sessionUpdate: 'tool_call_update',
      toolCallId,
      status: 'in_progress',
      rawInput: NOTE_ARGUMENTS,
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
            text: `saved "${NOTE_ARGUMENTS.title}" (${NOTE_ARGUMENTS.body.length} chars)`,
          },
        },
      ],
    });
    await turn.say('Done.');

    return 'end_turn';
  },
} satisfies Record<string, Play>;
