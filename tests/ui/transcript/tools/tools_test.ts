import { expect, test } from 'bun:test';
import type { ToolCall } from '../../../../src/session/transcript/types.ts';
import {
  firstLine,
  type Headline,
  headline,
  headlineRows,
  summary,
  toneOf,
} from '../../../../src/ui/transcript/tools/tools.ts';
import { NOTES_COMMAND, WEATHER_COMMAND } from '../../../fixtures/headlines.ts';

function text(value: string): NonNullable<ToolCall['content']>[number] {
  return { type: 'content', content: { type: 'text', text: value } };
}

test('a title starting with a verb reads as Verb(arg)', () => {
  expect(headline({ id: 'a', title: 'Read src/main.tsx' })).toStrictEqual({
    name: 'Read',
    arg: 'src/main.tsx',
  });
  expect(
    headline({ id: 'a', title: 'Edit `src/a.ts`', kind: 'edit' }),
  ).toStrictEqual({
    name: 'Edit',
    arg: 'src/a.ts',
  });
});

test('a bare command or description is named by its kind', () => {
  expect(
    headline({ id: 'a', title: '`ls -la`', kind: 'execute' }),
  ).toStrictEqual({
    name: 'Bash',
    arg: 'ls -la',
  });
  expect(
    headline({ id: 'a', title: 'grep TODO', kind: 'search' }),
  ).toStrictEqual({
    name: 'Search',
    arg: 'grep TODO',
  });
  expect(headline({ id: 'a', title: 'Task' })).toStrictEqual({ name: 'Task' });
  expect(headline({ id: 'a' })).toStrictEqual({ name: 'Tool' });
  expect(headline({ id: 'a', kind: 'fetch' })).toStrictEqual({ name: 'Fetch' });
});

test('a title of several lines is the argument whole, every line kept', () => {
  const title = "cat >> notes.md <<'EOF'  \n## 1. One\n\n  - indented\nEOF";

  expect(headline({ id: 'a', title, kind: 'execute' })).toStrictEqual({
    name: 'Bash',
    arg: title,
  });
});

test("a row that stays one row takes the argument's first line", () => {
  expect(
    firstLine({ name: 'Bash', arg: "cat <<'EOF'  \n## 1. One\nEOF" }),
  ).toStrictEqual({ name: 'Bash', arg: "cat <<'EOF'" });
  expect(firstLine({ name: 'Bash' })).toStrictEqual({ name: 'Bash' });
});

/** The rows' text, each row's pieces joined. */
function rowsText(line: Headline, width: number): string[] {
  return headlineRows(line, width).map((row) =>
    row.map((piece) => piece.run.text).join(''),
  );
}

test("a long command wraps between words as the design's mocks do at 80 and 120 columns", () => {
  const line = { name: 'Bash', arg: WEATHER_COMMAND };

  // An entry's width is the window's less four cells.
  expect(rowsText(line, 76)).toStrictEqual([
    'Bash(echo "This morning the weather started out cool and misty with a thin',
    'layer of fog rolling over the hills, but by noon the sun had burned through',
    'the clouds, the temperature climbed steadily, a light breeze came in from',
    'the west, and forecasters warned that scattered thunderstorms could arrive',
    'late in the evening" | tr a-z A-Z | wc -c)',
  ]);
  expect(rowsText(line, 116)).toStrictEqual([
    'Bash(echo "This morning the weather started out cool and misty with a thin layer of fog rolling over the hills, but',
    'by noon the sun had burned through the clouds, the temperature climbed steadily, a light breeze came in from the',
    'west, and forecasters warned that scattered thunderstorms could arrive late in the evening" | tr a-z A-Z | wc -c)',
  ]);
});

test('each line of a heredoc starts a row, an empty one too, the `)` after the last', () => {
  const [first, ...rest] = NOTES_COMMAND.split('\n');

  expect(rowsText({ name: 'Bash', arg: NOTES_COMMAND }, 76)).toStrictEqual([
    `Bash(${first}`,
    ...rest.slice(0, -1),
    'EOF)',
  ]);
});

test('a line keeps its indent; a word wider than the room breaks at the edge', () => {
  expect(rowsText({ name: 'Bash', arg: 'f\n    two words' }, 10)).toStrictEqual(
    ['Bash(f', '    two', 'words)'],
  );
  expect(
    rowsText({ name: 'Fetch', arg: 'https://example.com/a' }, 10),
  ).toStrictEqual(['Fetch(http', 's://exampl', 'e.com/a)']);
});

test('the note follows the `)`; the name, the `to` and the note keep their parts on every row', () => {
  const rows = headlineRows(
    { name: 'tester', arg: 'run the suite', note: ' · waited 2s', sent: true },
    18,
  );

  expect(
    rows.map((row) => row.map(({ part, run }) => [part, run.text])),
  ).toStrictEqual([
    [
      ['to', 'to '],
      ['name', '@tester'],
      ['arg', '(run the'],
    ],
    [
      ['arg', 'suite)'],
      ['note', ' · waited 2s'],
    ],
  ]);
});

test("an agent's colour in an argument is kept on each row it wraps to", () => {
  const rows = headlineRows(
    { name: 'Bash', arg: '\x1b[31mred words here\x1b[0m plain' },
    13,
  );

  expect(
    rows.map((row) =>
      row.map(({ run }) => [run.text, run.fg === undefined ? '' : 'fg']),
    ),
  ).toStrictEqual([
    [
      ['Bash', ''],
      ['(', ''],
      ['red', 'fg'],
    ],
    [['words here', 'fg']],
    [['plain)', '']],
  ]);
});

test('the status picks the tone; no status is pending', () => {
  expect(toneOf({ id: 'a' })).toStrictEqual('pending');
  expect(toneOf({ id: 'a', status: 'pending' })).toStrictEqual('pending');
  expect(toneOf({ id: 'a', status: 'in_progress' })).toStrictEqual('running');
  expect(toneOf({ id: 'a', status: 'completed' })).toStrictEqual('done');
  expect(toneOf({ id: 'a', status: 'failed' })).toStrictEqual('failed');
});

test('a call with no output says where it is', () => {
  expect(summary({ id: 'a' }, false)).toStrictEqual({
    lines: ['Waiting…'],
    hidden: 0,
    terminals: [],
    diffs: [],
  });
  expect(
    summary({ id: 'a', status: 'in_progress' }, false).lines,
  ).toStrictEqual(['Running…']);
  expect(summary({ id: 'a', status: 'completed' }, false).lines).toStrictEqual(
    [],
  );
  expect(summary({ id: 'a', status: 'failed' }, false).lines).toStrictEqual([
    'Failed',
  ]);
});

test('a call left unfinished by what ran it, which has ended, waits on nothing', () => {
  expect(summary({ id: 'a' }, true, undefined, true).lines).toStrictEqual([]);
  expect(
    summary({ id: 'a', status: 'in_progress' }, true, undefined, true).lines,
  ).toStrictEqual([]);
  expect(
    summary({ id: 'a', status: 'failed' }, true, undefined, true).lines,
  ).toStrictEqual(['Failed']);
});

test('long output keeps three lines and counts the rest', () => {
  const call: ToolCall = {
    id: 'a',
    status: 'completed',
    content: [text('1\n2\n3\n4\n5\n')],
  };

  expect(summary(call, false)).toStrictEqual({
    lines: ['1', '2', '3'],
    hidden: 2,
    terminals: [],
    diffs: [],
  });
  expect(summary(call, true)).toStrictEqual({
    lines: ['1', '2', '3', '4', '5'],
    hidden: 0,
    terminals: [],
    diffs: [],
  });
  expect(
    summary({ ...call, content: [text('1\n2\n3')] }, false).hidden,
  ).toStrictEqual(0);
});

test('a failed call says Error before its output', () => {
  expect(
    summary(
      { id: 'a', status: 'failed', content: [text('no such file')] },
      false,
    ).lines,
  ).toStrictEqual(['Error: no such file']);
});

test('a diff draws under the lines, not among them', () => {
  const { lines, hidden, diffs } = summary(
    {
      id: 'a',
      status: 'completed',
      content: [
        text('done'),
        {
          type: 'diff',
          path: 'src/a.ts',
          oldText: 'a\nb\n',
          newText: 'a\nc\nd\n',
        },
      ],
    },
    false,
  );

  expect({ lines, hidden }).toStrictEqual({ lines: ['done'], hidden: 0 });
  expect(
    diffs.map((view) => [view.path, view.added, view.removed]),
  ).toStrictEqual([['src/a.ts', 2, 1]]);
});

test('a diff alone needs no status line, unless the call failed', () => {
  const diff = {
    type: 'diff',
    path: 'a.ts',
    oldText: 'a',
    newText: 'b',
  } as const;

  for (const status of ['pending', 'in_progress', 'completed'] as const) {
    expect(
      summary({ id: 'a', status, content: [diff] }, false).lines,
    ).toStrictEqual([]);
  }

  expect(
    summary({ id: 'a', status: 'failed', content: [diff] }, false).lines,
  ).toStrictEqual(['Failed']);
});

test('a terminal draws its output in place of the call working', () => {
  const call: ToolCall = {
    id: 'a',
    status: 'in_progress',
    content: [{ type: 'terminal', terminalId: 't' }],
    terminals: [{ id: 't', output: '', exited: false }],
  };

  // Claude's adapter sends nothing of it until the command is done.
  expect(summary(call, false).lines).toStrictEqual(['Running…']);
  expect(summary(call, false).terminals).toStrictEqual([]);

  const growing = summary(
    {
      ...call,
      terminals: [{ id: 't', output: '1\n2\n3\n4\n', exited: false }],
    },
    false,
  );

  expect(growing.lines).toStrictEqual([]);
  expect(growing.terminals).toStrictEqual([
    { lines: ['2', '3', '4'], hidden: 1 },
  ]);
});

test('a failing exit is the failure, in words, without Failed', () => {
  const failed = (exitCode: number): ToolCall => ({
    id: 'a',
    status: 'failed',
    content: [{ type: 'terminal', terminalId: 't' }],
    terminals: [{ id: 't', output: 'boom\n', exited: true, exitCode }],
  });

  expect(summary(failed(1), false).lines).toStrictEqual([]);
  expect(summary(failed(1), false).terminals[0]?.note).toStrictEqual({
    text: 'Exit code 1',
    failed: true,
  });
  // A call that failed though its command did not still says so.
  expect(summary(failed(0), false).lines).toStrictEqual(['Failed']);
});

test('what Team and Open handed over wraps to the row and folds after three lines; a message stays cut', () => {
  const job =
    'Issue 214: a string at the end of a line loses its closing ' +
    'quote. readString stops at the newline before it consumes the quote. ' +
    'Add a test that fails for that reason, fix it, and have it reviewed.';
  const call = (tool: 'run_team' | 'open_agent' | 'send_message') => ({
    id: 'a',
    status: 'completed' as const,
    chord: {
      tool,
      input: {
        team: 'bugfix',
        job,
        member: 'tester',
        prompt: job,
        text: job,
      },
      answer: {},
    },
  });

  for (const tool of ['run_team', 'open_agent'] as const) {
    const folded = summary(call(tool), false, undefined, false, 40);

    expect(folded.lines.length).toStrictEqual(3);
    expect(folded.lines.every((line) => line.length <= 40)).toStrictEqual(true);
    expect(folded.hidden > 0).toStrictEqual(true);

    const whole = summary(call(tool), true, undefined, false, 40);

    expect(whole.lines.join(' ')).toStrictEqual(job);
    expect(whole.hidden).toStrictEqual(0);
  }

  expect(
    summary(call('send_message'), false, undefined, false, 40).lines,
  ).toStrictEqual([job]);
});

test('a call whose questions the box answered draws none of its own lines until ctrl+o', () => {
  const call: ToolCall = {
    id: 'ask-1',
    title: 'Asking for your input',
    status: 'completed',
    asked: true,
    content: [
      {
        type: 'content',
        content: { type: 'text', text: 'User has answered your questions.' },
      },
    ],
  };

  expect(summary(call, false).lines).toStrictEqual([]);
  expect(summary(call, true).lines).toStrictEqual([
    'User has answered your questions.',
  ]);
});

test("a call whose questions the box answered reads Asking(…), whatever its title's first word", () => {
  expect(
    headline({ id: 'a', title: 'Asking for your input', asked: true }),
  ).toStrictEqual({ name: 'Asking', arg: 'for your input' });
  expect(
    headline({
      id: 'a',
      title: 'Which language should helper scripts use?',
      asked: true,
    }),
  ).toStrictEqual({
    name: 'Asking',
    arg: 'Which language should helper scripts use?',
  });
});
