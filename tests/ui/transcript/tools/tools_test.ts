import { describe, expect, test } from 'bun:test';
import type { ToolCall } from '../../../../src/session/transcript/types.ts';
import { TextAttributes } from '@opentui/core';
import stringWidth from 'string-width';
import { runs, type Run } from '../../../../src/ui/theme/text.ts';
import {
  firstLine,
  type Headline,
  headline,
  headlineRows,
  mcpArguments,
  sentBody,
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
    row.map((run) => run.text).join(''),
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

/** Each row's runs as their text and how they are drawn. */
function styled(rows: Run[][]): [string, string][][] {
  return rows.map((row) =>
    row.map((run) => [
      run.text,
      [
        run.attributes & TextAttributes.BOLD ? 'bold' : '',
        run.attributes & TextAttributes.DIM ? 'dim' : '',
        run.fg === undefined ? '' : 'fg',
      ]
        .filter(Boolean)
        .join(' '),
    ]),
  );
}

test('the note follows the `)`; the name keeps its bold and colour, the `to` and the note their dim, on every row', () => {
  expect(
    styled(
      headlineRows(
        {
          name: 'tester',
          arg: 'run the suite',
          note: ' · waited 2s',
          sent: true,
        },
        18,
        '#6cb6ff',
      ),
    ),
  ).toStrictEqual([
    [
      ['to ', 'dim'],
      ['@tester', 'bold fg'],
      ['(run the', ''],
    ],
    [
      ['suite)', ''],
      [' · waited 2s', 'dim'],
    ],
  ]);
});

test("an agent's colour in an argument is kept on each row it wraps to", () => {
  expect(
    styled(
      headlineRows(
        { name: 'Bash', arg: '\x1b[31mred words here\x1b[0m plain' },
        13,
      ),
    ),
  ).toStrictEqual([
    [
      ['Bash', 'bold'],
      ['(', ''],
      ['red', 'fg'],
    ],
    [['words here', 'fg']],
    [['plain)', '']],
  ]);
});

test('an argument wrap-ansi writes otherwise is drawn whole, its `)` kept', () => {
  // A decomposed é, which wrap-ansi composes, four times (CHD-393 review).
  const accents = rowsText({ name: 'Bash', arg: 'e\u0301'.repeat(4) }, 76);

  expect(accents.join('').normalize('NFC')).toStrictEqual(
    `Bash(${'é'.repeat(4)})`,
  );

  // A tab, which wrap-ansi lays out as spaces, then the rest of the line.
  const tabbed = rowsText({ name: 'Bash', arg: 'printf "a\tb" | cat' }, 76);

  expect(tabbed).toHaveLength(1);
  expect(tabbed[0]).toStartWith('Bash(printf "a');
  expect(tabbed[0]).toEndWith('b" | cat)');
});

test("an MCP call's headline is Claude Code's: the server, the tool, (MCP), its arguments", () => {
  const call = (rawInput?: unknown): ToolCall => ({
    id: 'a',
    title: 'mcp__notes__save_note',
    kind: 'other',
    ...(rawInput === undefined ? {} : { rawInput }),
  });

  expect(headline(call({ title: 'A "quoted" note', limit: 3 }))).toStrictEqual({
    name: 'notes - save_note',
    tag: ' (MCP)',
    arg: 'title: "A \\"quoted\\" note", limit: 3',
  });
  // No arguments yet, as the adapter sends the call first: the name alone.
  expect(headline(call({}))).toStrictEqual({
    name: 'notes - save_note',
    tag: ' (MCP)',
  });

  // The title alone makes an MCP call: no arguments at all, or null, is
  // the name alone as {} is.
  for (const input of [undefined, null]) {
    expect(headline(call(input))).toStrictEqual({
      name: 'notes - save_note',
      tag: ' (MCP)',
    });
  }

  // The server runs to the next `__`; the tool is the rest.
  expect(
    headline({ ...call({}), title: 'mcp__my_files__write__file' }).name,
  ).toStrictEqual('my_files - write__file');
});

test('MCP arguments: strings quoted, the rest bare or compact JSON, a newline as \\n', () => {
  expect(
    mcpArguments({
      timeout_ms: 600000,
      follow: true,
      since: null,
      paths: ['src/a.ts', 'src/b.ts'],
      options: { depth: 2, ignore: ['node_modules'] },
      content: '# Notes\n\n- one\t',
    }),
  ).toStrictEqual(
    'timeout_ms: 600000, follow: true, since: null, ' +
      'paths: ["src/a.ts","src/b.ts"], ' +
      'options: {"depth":2,"ignore":["node_modules"]}, ' +
      'content: "# Notes\\n\\n- one\\t"',
  );
  expect(mcpArguments({})).toStrictEqual(undefined);
  expect(mcpArguments('just text')).toStrictEqual('"just text"');
  expect(mcpArguments(['a', 1])).toStrictEqual('["a",1]');
  // A key is JSON with its quotes dropped; C1 controls are escaped.
  expect(mcpArguments({ 'say "hi"': 'a\u0085b' })).toStrictEqual(
    'say \\"hi\\": "a\\u0085b"',
  );
});

test("a call to chord's own server is chord's own from its first update, by the name the session gave it", () => {
  const call = (server: string): ToolCall => ({
    id: 'a',
    title: `mcp__${server}__send_message`,
    kind: 'other',
    rawInput: { to: 'reviewer', text: 'hi' },
  });

  expect(headline(call('chord'), 'chord')).toStrictEqual({
    name: 'reviewer',
    sent: true,
  });
  // Beside a server of the person's called chord, chord's is chord-2.
  expect(headline(call('chord-2'), 'chord-2')).toStrictEqual({
    name: 'reviewer',
    sent: true,
  });
  // chord's own from its first update, before any arguments come.
  expect(
    headline({ id: 'a', title: 'mcp__chord__monitor', kind: 'other' }, 'chord'),
  ).toStrictEqual({ name: 'Monitor' });
  expect(headline(call('chord'), 'chord-2')).toStrictEqual({
    name: 'chord - send_message',
    tag: ' (MCP)',
    arg: 'to: "reviewer", text: "hi"',
  });
});

test("an MCP headline wraps as one long line, (MCP) dim, the design's rows at 80 columns", () => {
  const rows = (rawInput: unknown) =>
    headline({
      id: 'a',
      title: 'mcp__files__write_file',
      kind: 'other',
      rawInput,
    });

  expect(
    rowsText(
      rows({
        paths: ['src/a.ts', 'src/b.ts'],
        options: { depth: 2, ignore: ['node_modules'] },
      }),
      76,
    ),
  ).toStrictEqual([
    'files - write_file (MCP)(paths: ["src/a.ts","src/b.ts"], options:',
    '{"depth":2,"ignore":["node_modules"]})',
  ]);
  expect(
    rowsText(
      rows({ path: 'notes.md', content: '# Notes\n\n- one\n- two\n' }),
      76,
    ),
  ).toStrictEqual([
    'files - write_file (MCP)(path: "notes.md", content: "# Notes\\n\\n- one\\n-',
    'two\\n")',
  ]);
  expect(styled(headlineRows(rows({}), 76))).toStrictEqual([
    [
      ['files - write_file', 'bold'],
      [' (MCP)', 'dim'],
    ],
  ]);
});

test("Codex's MCP call is drawn as Claude's, named by its wrapper's server and tool, never its title", () => {
  const wrapped = (server: string, tool: string, input: unknown): ToolCall => ({
    id: 'a',
    title: `mcp.${server}.${tool}`,
    kind: 'execute',
    rawInput: { server, tool, arguments: input },
    mcp: { server, tool, input },
  });

  expect(
    headline(wrapped('notes', 'list_notes', { tag: 'ui', limit: 2 })),
  ).toStrictEqual({
    name: 'notes - list_notes',
    tag: ' (MCP)',
    arg: 'tag: "ui", limit: 2',
  });
  // A dotted server name needs no splitting of the title.
  expect(headline(wrapped('notes.v2', 'list', {})).name).toStrictEqual(
    'notes.v2 - list',
  );

  // No arguments, {} or null: the name alone.
  for (const input of [undefined, {}, null]) {
    expect(headline(wrapped('notes', 'list_notes', input))).toStrictEqual({
      name: 'notes - list_notes',
      tag: ' (MCP)',
    });
  }

  // chord's own server's: chord's own row, as before.
  expect(
    headline(
      wrapped('chord', 'send_message', { to: 'ship', text: 'hi' }),
      'chord',
    ),
  ).toStrictEqual({ name: 'ship', sent: true });
  // With nothing filed from a wrapper, or no server in it, the title as today.
  expect(
    headline({ id: 'a', title: 'mcp.notes.list_notes', kind: 'execute' }),
  ).toStrictEqual({ name: 'Bash', arg: 'mcp.notes.list_notes' });
  expect(
    headline({
      id: 'a',
      title: 'mcp.notes.list_notes',
      kind: 'execute',
      mcp: { tool: 'list_notes', input: {} },
    }),
  ).toStrictEqual({ name: 'Bash', arg: 'mcp.notes.list_notes' });
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

test("long output is drawn whole, and only a Read's keeps three lines and counts the rest", () => {
  const call: ToolCall = {
    id: 'a',
    status: 'completed',
    content: [text('1\n2\n3\n4\n5\n')],
  };

  expect(summary(call, false)).toStrictEqual({
    lines: ['1', '2', '3', '4', '5'],
    hidden: 0,
    terminals: [],
    diffs: [],
  });
  expect(summary({ ...call, kind: 'read' }, false)).toStrictEqual({
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
    summary({ ...call, kind: 'read', content: [text('1\n2\n3')] }, false)
      .hidden,
  ).toStrictEqual(0);
});

test("a result line longer than its room wraps at its words, a Read's too, never cut", () => {
  const line = 'one two three four five six seven eight nine ten';

  for (const kind of ['other', 'read'] as const) {
    const { lines, hidden } = summary(
      { id: 'a', status: 'completed', kind, content: [text(line)] },
      false,
      undefined,
      false,
      20,
    );

    expect(lines).toStrictEqual([
      'one two three four',
      'five six seven eight',
      'nine ten',
    ]);
    expect(hidden).toStrictEqual(0);
  }
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

test('what Team and Open handed over wraps to the row, whole', () => {
  const job =
    'Issue 214: a string at the end of a line loses its closing ' +
    'quote. readString stops at the newline before it consumes the quote. ' +
    'Add a test that fails for that reason, fix it, and have it reviewed.';
  const call = (tool: 'run_team' | 'open_agent') => ({
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
    for (const expanded of [false, true]) {
      const whole = summary(call(tool), expanded, undefined, false, 40);

      expect(whole.lines.every((line) => line.length <= 40)).toStrictEqual(
        true,
      );
      expect(whole.lines.join(' ')).toStrictEqual(job);
      expect(whole.hidden).toStrictEqual(0);
    }
  }
});

test("a sent message's body is its text in every state, a refusal or Failed after it, and none for an empty text or another call", () => {
  const call = (status: string, text: string, error?: string): ToolCall => ({
    id: 'a',
    status,
    chord: {
      tool: 'send_message',
      input: { to: 'parser', text },
      ...(error === undefined ? {} : { error }),
    },
  });

  for (const status of ['pending', 'in_progress', 'completed'] as const) {
    expect(sentBody(call(status, 'one\n\ntwo'))).toStrictEqual({
      text: 'one\n\ntwo',
    });
  }

  expect(sentBody(call('completed', 'Hi', 'parser is closed'))).toStrictEqual({
    text: 'Hi',
    ending: 'parser is closed',
  });
  expect(sentBody(call('failed', 'Hi'))).toStrictEqual({
    text: 'Hi',
    ending: 'Failed',
  });
  expect(sentBody(call('failed', '  '))).toBeUndefined();
  expect(
    sentBody({
      id: 'b',
      status: 'completed',
      chord: { tool: 'close_agent', input: { to: 'parser' } },
    }),
  ).toBeUndefined();
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

describe('CHD-393 tester: styled headline boundaries', () => {
  test('keeps an open colour across a real newline and resets it before plain text', () => {
    const rows = headlineRows(
      { name: 'Bash', arg: '\x1b[31mone\ntwo three four\x1b[0m plain' },
      13,
    );
    const pieces = rows.flat();

    expect(
      pieces
        .filter((run) => run.fg)
        .map((run) => run.text)
        .join(' '),
    ).toBe('one two three four');
    expect(
      pieces.find((run) => run.text.includes('plain'))?.fg,
    ).toBeUndefined();
    expect(rows.map((row) => row.map((run) => run.text).join(''))).toEqual([
      'Bash(one',
      'two three',
      'four plain)',
    ]);
  });

  for (const width of [3, 13, 76]) {
    test(`keeps Unicode, tab suffix and closing punctuation within ${width} cells`, () => {
      const rows = headlineRows(
        { name: 'Bash', arg: 'e\u0301漢👩‍💻\tEND' },
        width,
      ).map((row) => row.map((run) => run.text).join(''));

      expect(rows.join('').replace(/\s/g, '').normalize('NFC')).toBe(
        'Bash(é漢👩‍💻END)',
      );
      expect(rows.every((row) => stringWidth(row) <= width)).toBe(true);
    });
  }
});

describe('CHD-415 tester: MCP identity and control boundaries', () => {
  test('own-server collision routing is stable before arguments and served identity wins', () => {
    for (const rawInput of [undefined, null, {}]) {
      expect(
        headline(
          { id: 'a', title: 'mcp__chord-2__monitor', rawInput },
          'chord-2',
        ),
      ).toEqual({ name: 'Monitor' });
      expect(
        headline(
          { id: 'a', title: 'mcp__chord__monitor', rawInput },
          'chord-2',
        ),
      ).toEqual({ name: 'chord - monitor', tag: ' (MCP)' });
    }

    expect(
      headline(
        {
          id: 'a',
          title: 'mcp__other__monitor',
          rawInput: { to: 'wrong' },
          chord: {
            tool: 'send_message',
            input: { to: 'alias', text: 'hello' },
            answer: { to: 'reviewer' },
          },
        },
        'chord-2',
      ),
    ).toEqual({ name: 'reviewer', sent: true });
    expect(
      headline(
        { id: 'a', title: 'mcp__chord-2__custom', rawInput: {} },
        'chord-2',
      ),
    ).toEqual({ name: 'chord-2 - custom', tag: ' (MCP)' });
  });

  test('primitive inputs and escaped control keys remain visible JSON text', () => {
    expect(mcpArguments(false)).toBe('false');
    expect(mcpArguments(0)).toBe('0');
    expect(mcpArguments('')).toBe('""');
    expect(mcpArguments({ 'line\n\u007f': 'left\u009bright\u009f' })).toBe(
      'line\\n\\u007f: "left\\u009bright\\u009f"',
    );
  });
});

describe('CHD-419 tester: wrapper authority and legacy title fallback', () => {
  test('dotted wrapper names override a contradictory title and raw input', () => {
    const call: ToolCall = {
      id: 'dotted',
      title: 'mcp__wrong__wrong',
      kind: 'execute',
      rawInput: {
        server: 'wrong',
        tool: 'wrong',
        arguments: { ignored: true },
      },
      mcp: { server: 'my.notes', tool: 'notes.v2', input: { title: 'kept' } },
    };

    expect(headline(call)).toEqual({
      name: 'my.notes - notes.v2',
      tag: ' (MCP)',
      arg: 'title: "kept"',
    });
    expect(
      headline({
        ...call,
        chord: { tool: 'list_agents', input: {}, answer: {} },
      }),
    ).toEqual({ name: 'List agents' });
  });

  test('a server-less filed record follows its old title and raw arguments', () => {
    const call: ToolCall = {
      id: 'old',
      title: 'mcp__notes__save_note',
      rawInput: { title: 'legacy' },
      mcp: { tool: 'ignored', input: { title: 'wrong' } },
    };

    expect(headline(call)).toEqual({
      name: 'notes - save_note',
      tag: ' (MCP)',
      arg: 'title: "legacy"',
    });
    expect(
      headline(
        {
          ...call,
          mcp: { server: 'chord-2', tool: 'list_agents', input: undefined },
        },
        'chord-2',
      ),
    ).toEqual({ name: 'List agents' });
  });
});

test("a chord call cut off before it reached chord keeps what it asked for, and says it did nothing after it, read on chord's server alone", () => {
  const cut = (tool: string, rawInput: unknown): ToolCall => ({
    id: 'a',
    title: `mcp__chord__${tool}`,
    status: 'failed',
    rawInput,
    cut: true,
    content: [text(`Error calling tool (mcp__chord__${tool}): `)],
  });

  expect(
    sentBody(cut('send_message', { to: 'main', text: 'Hi' }), 'chord'),
  ).toStrictEqual({
    text: 'Hi',
    ending:
      'Not delivered: cut off before it reached chord. chord tells the agent at its next turn.',
  });
  expect(
    summary(
      cut('open_agent', { name: 'parser', prompt: 'agentchild' }),
      false,
      undefined,
      false,
      undefined,
      'chord',
    ).lines,
  ).toStrictEqual([
    'agentchild',
    'Cut off before it reached chord, so it did nothing. chord tells the agent at its next turn.',
  ]);
  // Not chord's server: the agent's own error, as any failed call says it.
  expect(
    summary(cut('open_agent', {}), false, undefined, false, undefined, 'other')
      .lines,
  ).toStrictEqual(['Error: Error calling tool (mcp__chord__open_agent):']);
  expect(
    sentBody(cut('send_message', { text: 'Hi' }), 'other'),
  ).toBeUndefined();
});

describe('CHD-422 tester: wrapped result styling', () => {
  test('a coloured result stays coloured across all wrapped rows and resets for the following line', () => {
    const coloured = 'one two three four five six seven eight nine ten';
    const shown = summary(
      {
        id: 'styled',
        kind: 'other',
        status: 'completed',
        content: [text(`\x1b[31m${coloured}\x1b[0m\nplain-end`)],
      },
      false,
      undefined,
      false,
      12,
    );
    const painted = shown.lines.slice(0, -1).flatMap((line) => runs(line));

    expect(shown.hidden).toBe(0);
    expect(shown.lines.length > 3).toBe(true);
    expect(
      painted
        .map((run) => run.text)
        .join(' ')
        .replace(/\s+/g, ' '),
    ).toBe(coloured);
    expect(painted.every((run) => run.fg !== undefined)).toBe(true);
    expect(runs(shown.lines.at(-1)!)).toStrictEqual([
      { text: 'plain-end', attributes: 0 },
    ]);
  });
});
