import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import type { SessionUpdate } from '@agentclientprotocol/sdk';
import { OUTPUT_LIMIT } from '../../../src/session/context.ts';
import { recordActions } from '../../../src/session/record.ts';
import { pastActions } from '../../../src/session/replay.ts';
import type { PastAction } from '../../../src/session/session.ts';
import { COLUMN_LIMIT } from '../../../src/session/terminal_text.ts';
import type {
  Terminal,
  Transcript,
  TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { fold, states } from './fold.ts';
import { NOTES_COMMAND } from '../../fixtures/headlines.ts';

/** A tool call update for call `c1`, carrying `_meta` and `fields`. */
function terminalUpdate(
  _meta: Record<string, unknown>,
  fields: Partial<
    Extract<SessionUpdate, { sessionUpdate: 'tool_call_update' }>
  > = {},
): TranscriptAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'c1',
      ...fields,
      _meta,
    },
  };
}

/** The terminals of the one tool call in `transcript`. */
function terminalsOf(transcript: Transcript): readonly Terminal[] | undefined {
  const entry = transcript.entries.find((each) => each.kind === 'tool');

  assert(entry?.kind === 'tool');

  return entry.call.terminals;
}

test("a terminal's output grows by deltas and ends with the exit that carries the last of it", () => {
  const actions: TranscriptAction[] = [
    { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
    {
      type: 'update',
      turnId: 't1',
      update: {
        sessionUpdate: 'tool_call',
        toolCallId: 'c1',
        title: 'Run make',
        kind: 'execute',
        status: 'in_progress',
        content: [{ type: 'terminal', terminalId: 'x' }],
        _meta: { terminal_info: { terminal_id: 'x', cwd: '/work' } },
      },
    },
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: 'a\n' },
    }),
    // An escape cut in two by the pieces it came in.
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: '\x1b[3' },
    }),
    terminalUpdate(
      {
        terminal_output_delta: { terminal_id: 'x', data: '1mb\x1b[0m\n' },
        terminal_exit: { terminal_id: 'x', exit_code: 2, signal: null },
      },
      { status: 'failed' },
    ),
  ];
  const seen = states(actions);

  expect(terminalsOf(seen[1]!)).toStrictEqual([
    { id: 'x', output: '', cwd: '/work', exited: false },
  ]);
  expect(terminalsOf(seen[2]!)).toStrictEqual([
    { id: 'x', output: 'a\n', cwd: '/work', exited: false },
  ]);

  const [terminal] = terminalsOf(fold(actions)) ?? [];

  expect(terminalsOf(seen[3]!)).toStrictEqual([
    {
      id: 'x',
      output: 'a\n',
      cwd: '/work',
      exited: false,
      escape: {
        kind: 'csi',
        params: '3',
      },
    },
  ]);
  expect(terminal).toStrictEqual({
    id: 'x',
    output: 'a\nb\n',
    cwd: '/work',
    exited: true,
    exitCode: 2,
  });
});

test("a terminal's whole output replaces what it had, and a signal ends it", () => {
  const big = `${'x'.repeat(OUTPUT_LIMIT)}\n`;
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'bash', at: 0 },
    terminalUpdate({ terminal_info: { terminal_id: 'x' } }),
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: big },
    }),
    terminalUpdate({ terminal_output: { terminal_id: 'x', data: 'all\n' } }),
    terminalUpdate({
      terminal_exit: { terminal_id: 'x', exit_code: null, signal: 'SIGINT' },
    }),
  ]);

  expect(terminalsOf(transcript)).toStrictEqual([
    { id: 'x', output: 'all\n', exited: true, signal: 'SIGINT' },
  ]);
});

test('a terminal keeps the last of its output past the limit, from a line start', () => {
  const head = `${'h'.repeat(10)}\n`;
  const tail = `${'t'.repeat(OUTPUT_LIMIT - 5)}\n`;
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: head },
    }),
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: tail },
    }),
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: 'z' },
    }),
  ]);

  expect(terminalsOf(transcript)).toStrictEqual([
    { id: 'x', output: `${tail}z`, exited: false, truncated: true },
  ]);
});

test('a terminal cut past the limit starts at a line, and an escape before it no longer counts', () => {
  const lines = Array.from(
    { length: 4 },
    (_, index) => `${String(index).repeat(OUTPUT_LIMIT / 3)}\n`,
  );
  const cut = cutOutput(lines)!;

  expect(cut.output).toStrictEqual(lines.slice(-2).join(''));
  expect(cut.truncated).toStrictEqual(true);

  // CHD-178: a line whose link's escape began before the bound is kept
  // whole, since the escape is gone before the bound is counted.
  const link = cutOutput([
    `head\n\x1b]8;;https://${'u'.repeat(5000)}\x07`,
    `${'x'.repeat(OUTPUT_LIMIT - 10)}\x1b]8;;\x07`,
  ])!;

  expect(link.output).toStrictEqual(`head\n${'x'.repeat(OUTPUT_LIMIT - 10)}`);
  expect(link.truncated).toStrictEqual(undefined);
});

test('a terminal sent a cursor move of any length stays within the bound', () => {
  const far = `\x1b[${'9'.repeat(15)}C`;
  const moved = cutOutput([far, 'X', `\n${far}Y`.repeat(100), far])!;

  expect(moved.output.length <= OUTPUT_LIMIT).toBeTruthy();
  expect(moved.truncated).toStrictEqual(true);
  expect(moved.output.endsWith(`${' '.repeat(COLUMN_LIMIT)}Y`)).toBeTruthy();
});

/** The output of the one terminal `pieces` write, each a delta of its own. */
function cutOutput(pieces: readonly string[]): Terminal | undefined {
  return terminalsOf(
    fold([
      { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
      ...pieces.map((data) =>
        terminalUpdate({ terminal_output_delta: { terminal_id: 'x', data } }),
      ),
    ]),
  )?.[0];
}

/**
 * Escapes no delta ends, whatever their length: an OSC's body, an
 * introducer's intermediates, the bytes a terminal ignores inside one, and a
 * CSI's parameters, each twice the bound and fed in pieces.
 */
const UNENDED = [
  ['an OSC', '\x1b]8;;https://', 'u', '\x07visible'],
  ['an introducer', '\x1b', ' ', '0visible'],
  ['ignored bytes', '\x1b', '\x00', ']u\x07visible'],
  ['a CSI', '\x1b[', '1;', 'mvisible'],
  ['a C1 string', 'gone\n\x9d8;;', 'u', '\x9cvisible'],
] as const;

for (const [name, opener, filler, end] of UNENDED) {
  test(`a terminal holds ${name} no delta ends within a constant, and shows what follows its end`, () => {
    const body = filler.repeat(OUTPUT_LIMIT * 2);
    const pieces = [opener, body, body.slice(0, OUTPUT_LIMIT), end];

    for (let count = 1; count < pieces.length; count++) {
      const open = cutOutput(pieces.slice(0, count))!;

      expect(open.output.length <= OUTPUT_LIMIT).toBeTruthy();
      expect(open.escape !== undefined, 'still open').toBeTruthy();
      expect(
        JSON.stringify(open.escape).length <= 64,
        'held within bounds',
      ).toBeTruthy();
    }

    const ended = cutOutput(pieces)!;

    expect(ended.output.endsWith('visible'), ended.output).toBeTruthy();
    expect(ended.escape).toStrictEqual(undefined);
  });
}

for (const [name, pieces] of [
  ['an OSC', [`\x1b]8;;https://${'u'.repeat(OUTPUT_LIMIT)}`, '\x07visible']],
  [
    'an oversized introducer',
    [
      `\x1b${' '.repeat(OUTPUT_LIMIT * 2)}`,
      ' '.repeat(OUTPUT_LIMIT),
      '0visible',
    ],
  ],
  [
    'an introducer full of ignored bytes',
    [
      `\x1b${'\x00'.repeat(OUTPUT_LIMIT * 2)}]u`,
      'u'.repeat(OUTPUT_LIMIT),
      '\x07visible',
    ],
  ],
  // CHD-190: an OSC an `ESC` breaks off, then a sequence of its own.
  ['an OSC broken off by an escape', ['\x1b]8;;https://a\x1b', 'bvisible']],
  // CHD-195: an `ESC` with an intermediate, ended by its final byte.
  ['an escape with an intermediate', ['\x1b', ' 0visible']],
] as const) {
  test(`a terminal inside ${name} that a later piece ends folds the same when the session is resumed`, () => {
    resumesTheSame(pieces);
  });
}

function resumesTheSame(pieces: readonly string[]) {
  const updates: SessionUpdate[] = pieces.map((data) => ({
    sessionUpdate: 'tool_call_update',
    toolCallId: 'c1',
    _meta: { terminal_output_delta: { terminal_id: 'x', data } },
  }));
  const live = fold([
    { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
    ...updates.map((update): TranscriptAction => ({
      type: 'update',
      turnId: 't1',
      update,
    })),
  ]);
  // As the agent replays it on load, and as chord's own record reads back.
  const transcriptOf = (past: readonly PastAction[]) =>
    fold(past.flatMap((action) => (action.type === 'usage' ? [] : [action])));
  const replayed = transcriptOf(
    pastActions(
      updates.map((update) => ({ update })),
      0,
    ),
  );
  const recorded = transcriptOf(
    recordActions([
      { type: 'prompt', turnId: 't1', at: 0, prompt: 'shell', images: 0 },
      ...updates.map((update) => ({
        type: 'update' as const,
        turnId: 't1',
        update,
      })),
    ]),
  );

  expect(terminalsOf(live)![0]!.output).toStrictEqual('visible');
  expect(terminalsOf(replayed)).toStrictEqual(terminalsOf(live));
  expect(terminalsOf(recorded)).toStrictEqual(terminalsOf(live));
}

test("a terminal's signal is kept as plain as its output", () => {
  const [terminal] =
    terminalsOf(
      fold([
        { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
        terminalUpdate({
          terminal_exit: {
            terminal_id: 'x',
            exit_code: null,
            signal: 'SIGTERM\x1b[31mRED\x1b[0m\x1b[2J',
          },
        }),
      ]),
    ) ?? [];

  expect(terminal?.signal).toStrictEqual('SIGTERMRED');
});

test('each terminal of a call keeps its own output, and a malformed one leaves the rest of the update', () => {
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'shell', at: 0 },
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'x', data: '1' },
    }),
    terminalUpdate({
      terminal_output_delta: { terminal_id: 'y', data: '2' },
    }),
    terminalUpdate(
      {
        terminal_output_delta: { terminal_id: 'x', data: 3 },
        terminal_exit: { terminal_id: 'y', exit_code: 0 },
      },
      { status: 'completed' },
    ),
  ]);
  const entry = transcript.entries.find((each) => each.kind === 'tool');

  assert(entry?.kind === 'tool');
  expect(entry.call.status).toStrictEqual('completed');
  expect(entry.call.terminals).toStrictEqual([
    { id: 'x', output: '1', exited: false },
    { id: 'y', output: '2', exited: true, exitCode: 0 },
  ]);
});

test('a tool call that names no terminal has none', () => {
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'tools', at: 0 },
    terminalUpdate({ claudeCode: { toolName: 'Read' } }),
  ]);
  const entry = transcript.entries.find((each) => each.kind === 'tool');

  assert(entry?.kind === 'tool');
  expect('terminals' in entry.call).toStrictEqual(false);
});

test("a call's title keeps every line and its length, as the headline draws it whole", () => {
  const title = `\`${NOTES_COMMAND}\n${'x'.repeat(5000)}\``;
  const update = (
    fields: Partial<Extract<SessionUpdate, { sessionUpdate: 'tool_call' }>>,
  ): TranscriptAction => ({
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'tool_call',
      toolCallId: 'c1',
      title: 'Bash',
      ...fields,
    },
  });
  const transcript = fold([
    { type: 'prompt', turnId: 't1', text: 'heredoc', at: 0 },
    update({ kind: 'execute', status: 'pending' }),
    // Claude's adapter sends the command in a later update.
    {
      type: 'update',
      turnId: 't1',
      update: { sessionUpdate: 'tool_call_update', toolCallId: 'c1', title },
    },
  ]);
  const entry = transcript.entries.find((each) => each.kind === 'tool');

  assert(entry?.kind === 'tool');
  expect(entry.call.title).toStrictEqual(title);
});

test("a call Claude's adapter cut off before it ran is marked cut, live and from the record; a cancelled one is not", () => {
  const updates: SessionUpdate[] = [
    {
      sessionUpdate: 'tool_call',
      toolCallId: 'a',
      title: 'mcp__chord__send_message',
      status: 'pending',
      rawInput: { to: 'main', text: 'Hi' },
    },
    {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'a',
      status: 'failed',
      _meta: { claudeCode: { nonExecutionKind: 'interrupted' } },
    },
    {
      sessionUpdate: 'tool_call',
      toolCallId: 'b',
      title: '`ls`',
      status: 'pending',
    },
    {
      sessionUpdate: 'tool_call_update',
      toolCallId: 'b',
      status: 'failed',
      _meta: { claudeCode: { nonExecutionKind: 'cancelled' } },
    },
  ];
  const cuts = (state: ReturnType<typeof fold>) =>
    state.entries.flatMap((entry) =>
      entry.kind === 'tool' ? [[entry.call.id, entry.call.cut]] : [],
    );
  const live = fold([
    { type: 'prompt', turnId: 't1', text: 'cutcalls', at: 0 },
    ...updates.map((update): TranscriptAction => ({
      type: 'update',
      turnId: 't1',
      update,
    })),
  ]);
  const recorded = fold(
    recordActions([
      { type: 'prompt', turnId: 't1', at: 0, prompt: 'cutcalls', images: 0 },
      ...updates.map((update) => ({
        type: 'update' as const,
        turnId: 't1',
        update,
      })),
    ]).flatMap((action) => (action.type === 'usage' ? [] : [action])),
  );

  expect(cuts(live)).toStrictEqual([
    ['a', true],
    ['b', undefined],
  ]);
  expect(cuts(recorded)).toStrictEqual(cuts(live));
});
