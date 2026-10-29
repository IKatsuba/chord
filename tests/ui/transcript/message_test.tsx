/** Messages between agents on screen: `←` for what came in, `→` for what went. */
import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import { left } from '../app/render.tsx';
import { draw } from '../harness.tsx';
import stripAnsi from 'strip-ansi';
import type {
  ChordCall,
  Entry,
  MessageFrom,
  MonitorEnd,
} from '../../../src/session/transcript/types.ts';
import { AgentColours, Colours } from '../../../src/ui/app/context.ts';
import { paletteOf, type ThemeName } from '../../../src/ui/theme/theme.ts';
import {
  inArrow,
  monitorMessage,
  forkedLine,
  queuedMessage,
  selfStartedLine,
  wrapLine,
} from '../../../src/ui/transcript/message.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';
import {
  PROSE_EN,
  PROSE_RU,
} from '../../fixtures/fake_agent/scenarios/agents.ts';

async function frame(
  entry: Entry,
  expanded = false,
  width = 80,
): Promise<string> {
  const drawn = await draw(
    <TranscriptEntry
      entry={entry}
      turn={{ status: 'idle' }}
      agent='fake'
      expanded={expanded}
      width={width}
    />,
    // Tall enough for a long message whole.
    { columns: width, rows: 60 },
  );
  const shown = stripAnsi(drawn.frame());

  await drawn.unmount();

  return shown;
}

const came = (from: MessageFrom, text = 'Fixed.'): Entry => ({
  kind: 'message',
  turnId: 't',
  from,
  text,
});

const sent = (chord: Partial<ChordCall>, status = 'completed'): Entry => ({
  kind: 'tool',
  turnId: 't',
  call: {
    id: 'c',
    status,
    chord: {
      tool: 'send_message',
      input: { to: 'parser', text: 'Run the parser tests.' },
      ...chord,
    },
  },
});

test('a message that came in is ← from, its sender and what it said', async () => {
  expect(
    await frame(
      came({ name: 'Fix the tokenizer', runtime: 'codex', note: 'report' }),
    ),
  ).toContain('← from Fix the tokenizer · codex · report\n  ⎿  Fixed.');
  expect(
    await frame(
      came({ name: 'Fix the tokenizer', runtime: 'codex', note: 'failed' }),
    ),
  ).toContain('← from Fix the tokenizer · codex · failed');
  expect(
    await frame(came({ name: 'parser', runtime: 'codex', reachable: true })),
  ).toContain('← from @parser · codex');
  expect(await frame(came({ name: 'main', reachable: true }))).toContain(
    '← from @main',
  );
  expect(await frame(came({ name: 'chord' }))).toContain('← from chord');
});

test('@ goes on a sender send_message reaches, told by who sent it, not its name', async () => {
  // A task titled as an agent is named is still a task.
  expect(await frame(came({ name: 'parser', runtime: 'codex' }))).toContain(
    '← from parser · codex',
  );
  expect(
    queuedMessage({ name: 'docs', runtime: 'claude', reachable: true }, 'Hi'),
  ).toStrictEqual({ header: 'from @docs · claude: ', text: 'Hi' });
  expect(
    queuedMessage({ name: 'Fix it', runtime: 'codex' }, 'Hi'),
  ).toStrictEqual({ header: 'from Fix it · codex: ', text: 'Hi' });
});

test('a message sent is → to and its recipient, not a call, queued or refused', async () => {
  const delivered = await frame(sent({ queued: true }));

  expect(delivered).toContain(
    '→ to @parser · queued\n  ⎿  Run the parser tests.',
  );
  expect(
    !delivered.includes('⏺'),
    'a sent message is drawn as a call',
  ).toBeTruthy();
  expect(
    !delivered.includes('Message('),
    'a sent message is drawn as a call',
  ).toBeTruthy();
  expect(await frame(sent({}, 'in_progress'))).toContain('→ to @parser\n');
  expect(
    await frame(sent({ error: 'parser is closed; it takes no more messages' })),
  ).toContain(
    '→ to @parser\n  ⎿  Run the parser tests.\n     parser is closed; it takes no more messages',
  );
  // A child's, inside its task block, goes to main.
  expect(
    await frame(sent({ input: { text: 'Found it' }, queued: true })),
  ).toContain('→ to @main · queued');
});

/** A review of eleven rows at 80 columns, its list items wrapping. */
const REVIEW = [
  'CHD-1 unit 4: points 1 and 2 are good. Four things before I look again:',
  '',
  '1. The fold counts the blank line after the list; drop it, as ' +
    '`foldMessage` already does for a received message.',
  '2. The hint names ctrl+o even when the person has rebound it.',
  '3. The refusal goes after the body, **never** folded.',
  '',
  "Tell me when the check passes and I'll look again.",
].join('\n');

/** The rows from the entry's `⎿` on, the gutter cut off. */
function body(shown: string): string[] {
  const rows = shown.split('\n');

  return rows
    .slice(rows.findIndex((row) => row.includes('⎿')))
    .map((row) => row.slice(5).trimEnd())
    .filter((row, index, rows) => rows.slice(index).some((r) => r !== ''));
}

test('a message sent is drawn as one received is: markdown, wrapped to the row, whole, with no fold', async () => {
  const input = { to: 'parser', text: REVIEW };
  const sentRows = body(await frame(sent({ input })));
  const cameRows = body(
    await frame(came({ name: 'parser', reachable: true }, REVIEW)),
  );

  expect(sentRows).toStrictEqual(cameRows);
  expect(sentRows).toStrictEqual([
    'CHD-1 unit 4: points 1 and 2 are good. Four things before I look again:',
    '',
    '1. The fold counts the blank line after the list; drop it, as foldMessage',
    '   already does for a received message.',
    '2. The hint names ctrl+o even when the person has rebound it.',
    '3. The refusal goes after the body, never folded.',
    '',
    "Tell me when the check passes and I'll look again.",
  ]);
  // ctrl+o has nothing more to show.
  expect(body(await frame(sent({ input }), true))).toStrictEqual(sentRows);
});

/** The words of `text`, markdown's and the gutter's marks aside. */
function words(text: string): string[] {
  return text.split(/\s+/).filter((word) => /[\p{L}\p{N}]/u.test(word));
}

for (const width of [80, 120]) {
  test(`long paragraphs, Cyrillic and ASCII, sent and received, are wrapped whole at ${width} columns: every word, no cut, no fold`, async () => {
    for (const text of [PROSE_RU, PROSE_EN]) {
      for (const entry of [
        sent({ input: { to: 'parser', text } }),
        came({ name: 'parser', runtime: 'codex', reachable: true }, text),
      ]) {
        const shown = await frame(entry, false, width);
        const rows = body(shown);

        // OpenTUI wraps at spaces and after `/ - . , : (` too, so a row may
        // end inside a word: the rows read as the words with no space lost
        // or added between them.
        expect(rows.join('').replace(/\s+/g, '')).toStrictEqual(
          words(text).join(''),
        );
        expect(!shown.includes('...')).toBeTruthy();
        expect(!shown.includes('to expand')).toBeTruthy();
        expect(rows.length > 2).toBeTruthy();
        expect(
          shown.split('\n').every((row) => row.length <= width),
        ).toBeTruthy();
      }
    }
  });
}

test('a message sent that opens with an indented code block keeps it, as the same message received does', async () => {
  const code = '    const answer = 42;\n\nThat is the fix.';
  const sentShown = await frame(sent({ input: { to: 'parser', text: code } }));
  const cameShown = await frame(
    came({ name: 'parser', reachable: true }, code),
  );

  expect(body(sentShown)).toStrictEqual(body(cameShown));
  expect(sentShown).toContain('│ const answer = 42; │');
});

test('a message sent draws its text at once, with no Waiting… while it goes, and an empty one only its failure', async () => {
  for (const status of ['pending', 'in_progress']) {
    const shown = await frame(sent({}, status));

    expect(shown).toContain('→ to @parser\n  ⎿  Run the parser tests.');
    expect(!shown.includes('Waiting…')).toBeTruthy();
    expect(!shown.includes('Running…')).toBeTruthy();
  }

  const empty = { to: 'parser', text: '  ' };

  expect(body(await frame(sent({ input: empty }, 'failed')))).toStrictEqual([
    'Failed',
  ]);
  expect(
    body(await frame(sent({ input: empty, error: 'parser is closed' }))),
  ).toStrictEqual(['parser is closed']);
});

test("a refused message keeps its whole text, and chord's refusal comes after it", async () => {
  const refusal = 'No agent parser is open in this session';
  const rows = body(
    await frame(
      sent({ input: { to: 'parser', text: REVIEW }, error: refusal }),
    ),
  );

  expect(rows.slice(0, 1)).toStrictEqual([
    'CHD-1 unit 4: points 1 and 2 are good. Four things before I look again:',
  ]);
  expect(rows.slice(-2)).toStrictEqual([
    "Tell me when the check passes and I'll look again.",
    refusal,
  ]);
  expect(body(await frame(sent({}, 'failed')))).toStrictEqual([
    'Run the parser tests.',
    'Failed',
  ]);
});

test("a child's message inside its task block is → to @main, not Message(main)", async () => {
  const shown = await frame({
    kind: 'subagent',
    turnId: 't',
    subagent: {
      id: 'task-1',
      title: 'Fix the tokenizer',
      state: 'running',
      plan: [],
      task: { name: 'Fix the tokenizer', runtime: 'codex' },
      entries: [sent({ input: { text: 'Found it' }, queued: true })],
    },
  });

  expect(shown).toContain('⎿  → to @main · queued');
  expect(!shown.includes('Message('), 'the old call is drawn').toBeTruthy();
});

/** A frame with its escapes, in `theme`, with `parser` in a colour of its own. */
async function painted(
  entry: Entry,
  theme: ThemeName,
  expanded: boolean,
): Promise<string> {
  // Ink's chalk sees no terminal under test, so it would drop every colour.
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <Colours.Provider value={paletteOf(theme, true)}>
        <AgentColours.Provider value={{ parser: '#00ff00' }}>
          <TranscriptEntry
            entry={entry}
            turn={{ status: 'idle' }}
            agent='fake'
            expanded={expanded}
            width={80}
          />
        </AgentColours.Provider>
      </Colours.Provider>,
    );
    const shown = drawn.frame();

    await drawn.unmount();

    return shown;
  } finally {
    chalk.level = level;
  }
}

for (const theme of ['dark', 'light'] as const) {
  test(`a message's body is dim under ⎿, a failed report's in the error colour (${theme})`, async () => {
    const body = await painted(
      came({ name: 'main', reachable: true }, 'Do not hand back.'),
      theme,
      false,
    );

    expect(stripAnsi(body)).toContain('← from @main\n  ⎿  Do not hand back.');
    expect(body).toContain('\x1b[2mDo not hand back.');

    const failed = await painted(
      came(
        { name: 'Fix the tokenizer', runtime: 'codex', note: 'failed' },
        'Stopped: the agent exited before it reported.',
      ),
      theme,
      false,
    );

    expect(failed).toContain(
      `${RED[theme].slice(0, -1)}Stopped: the agent exited`,
    );
    expect(
      !failed.includes('\x1b[2mStopped'),
      'a failed report is dim',
    ).toBeTruthy();
  });
}

test("a message's own escapes are text chord does not colour", async () => {
  const body = await painted(
    came(
      { name: 'main', reachable: true },
      'Run \x1b[31mthis\x1b[0m and \x1b]8;;https://example.com\x07that\x1b]8;;\x07.',
    ),
    'dark',
    false,
  );

  expect(stripAnsi(body)).toContain('⎿  Run this and that.');
  expect(!body.includes('\x1b[31m'), 'its red drawn').toBeTruthy();
  expect(!body.includes('example.com'), 'its link drawn').toBeTruthy();
});

/** A task block whose child sent `to` a message, its call in `status`. */
const childSent = (
  to: string,
  status: string,
  chord: Partial<ChordCall> = {},
): Entry => ({
  kind: 'subagent',
  turnId: 't',
  subagent: {
    id: 'task-1',
    title: 'Fix the tokenizer',
    state: 'running',
    plan: [],
    task: { name: 'Fix the tokenizer', runtime: 'codex' },
    entries: [sent({ input: { to, text: 'Found it' }, ...chord }, status)],
  },
});

test("from and to are dim, the name after them the agent's", async () => {
  expect(
    await painted(came({ name: 'parser', reachable: true }), 'dark', false),
  ).toContain('\x1b[2mfrom ');
  expect(await painted(sent({}), 'dark', false)).toContain('\x1b[2mto ');
  expect(
    await painted(childSent('main', 'completed'), 'dark', false),
  ).toContain('\x1b[2mto ');
});

const DIM = '\x1b[2m→';
const RED = { dark: '\x1b[38;2;255;107;128m→', light: '\x1b[38;2;196;22;42m→' };

for (const theme of ['dark', 'light'] as const) {
  for (const expanded of [false, true]) {
    const view = `${theme}, ${expanded ? 'opened' : 'folded'}`;

    test(`a child's → in its task block is dim while delivering, red when refused, plain once delivered (${view})`, async () => {
      for (const status of ['pending', 'in_progress']) {
        const shown = await painted(childSent('main', status), theme, expanded);

        expect(shown, `${status}: no dim arrow`).toContain(DIM);
        expect(
          !shown.includes(RED[theme]),
          `${status}: a red arrow`,
        ).toBeTruthy();
      }

      // chord's refusal wins over the adapter's completed.
      const refused = await painted(
        childSent('main', 'completed', { error: 'main is closed' }),
        theme,
        expanded,
      );

      expect(refused).toContain(RED[theme]);
      expect(!refused.includes(DIM), 'a refused arrow is dim').toBeTruthy();

      const delivered = await painted(
        childSent('main', 'completed'),
        theme,
        expanded,
      );

      expect(stripAnsi(delivered)).toContain('→ to @main');
      expect(!delivered.includes(DIM), 'a delivered arrow is dim').toBeTruthy();
      expect(
        !delivered.includes(RED[theme]),
        'a delivered arrow is red',
      ).toBeTruthy();

      // To an agent with a colour, arrow and name take it, its @ with it.
      const coloured = await painted(
        childSent('parser', 'completed'),
        theme,
        expanded,
      );

      expect(coloured).toContain('\x1b[38;2;0;255;0m→');
      expect(coloured).toContain('\x1b[38;2;0;255;0m@parser');
    });
  }
}

const event = (end?: MonitorEnd, text = 'a *b* _c_\n    at x (y.ts:1:2)') =>
  came(
    {
      name: 'dev server errors',
      monitor: { id: 'm1', ...(end === undefined ? {} : { end }) },
    },
    text,
  );

test("a monitor's event is ← from its description · monitor, its lines as printed, not markdown", async () => {
  expect(await frame(event())).toContain(
    '← from dev server errors · monitor\n  ⎿  a *b* _c_\n         at x (y.ts:1:2)',
  );
  expect(
    queuedMessage({ name: 'dev server errors', monitor: { id: 'm1' } }, 'WARN'),
  ).toStrictEqual({
    header: 'from dev server errors · monitor: ',
    text: 'WARN',
  });
});

test("a monitor's escapes in its description colour its header, the rest go", async () => {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <TranscriptEntry
        entry={came(
          {
            name: '\x1b[31mred\x1b[0m\x1b[2K errors',
            monitor: { id: 'm1' },
          },
          'WARN',
        )}
        turn={{ status: 'idle' }}
        agent='fake'
        expanded={false}
        width={80}
      />,
    );
    const shown = drawn.frame();

    await drawn.unmount();
    expect(shown).toContain('\x1b[31m');
    expect(stripAnsi(shown)).toContain('← from red errors · monitor');
    expect(stripAnsi(shown)).not.toMatch(/\[\d*[mK]/);
  } finally {
    chalk.level = level;
  }
});

test("a monitor's end says it in the header, its lines first and chord's sentence last, never folded", async () => {
  const lines = Array.from({ length: 9 }, (_, index) => `line ${index + 1}`);
  const shown = await frame(
    event(
      { kind: 'exit', code: 1 },
      [...lines, 'Exited with code 1 after 6m 3s.'].join('\n'),
    ),
  );

  expect(shown).toContain(
    '← from dev server errors · monitor · exit code 1\n  ⎿  line 1\n',
  );
  expect(shown).toContain(
    '     line 6\n     … +3 lines (ctrl+o to expand)\n     Exited with code 1 after 6m 3s.',
  );
  expect(
    monitorMessage('The person stopped it after 4s.', {
      ended: true,
      expanded: false,
      width: 76,
    }),
  ).toStrictEqual({
    lines: [],
    hidden: 0,
    sentence: 'The person stopped it after 4s.',
  });
});

test("a monitor's end colours its arrow by how it ended", () => {
  const arrow = (end: MonitorEnd) =>
    inArrow({ name: 'ci', monitor: { id: 'm1', end } });

  expect(inArrow({ name: 'ci', monitor: { id: 'm1' } })).toStrictEqual('plain');
  expect(arrow({ kind: 'exit', code: 0 })).toStrictEqual('plain');
  expect(arrow({ kind: 'exit', code: 1 })).toStrictEqual('failed');
  expect(arrow({ kind: 'signal', signal: 'SIGKILL' })).toStrictEqual('failed');
  expect(arrow({ kind: 'flooded', by: 'lines' })).toStrictEqual('failed');
  expect(arrow({ kind: 'timed_out', timeoutMs: 600_000 })).toStrictEqual('dim');
  expect(arrow({ kind: 'stopped' })).toStrictEqual('dim');
});

test('a long line of an event wraps after its own indent, with no space left at the break', () => {
  expect(
    monitorMessage('ERROR one two three\n    at four five six', {
      ended: false,
      expanded: false,
      width: 14,
    }).lines,
  ).toStrictEqual(['ERROR one two', 'three', '    at four', 'five six']);
});

describe('CHD-385 tester: outgoing recipients at 80 columns', () => {
  const name = 'sssssssssssssss';

  for (const expanded of [false, true]) {
    test(`the long recipient and queued marker fit, expanded=${expanded}`, async () => {
      const entry = childSent(name, 'completed', { queued: true });
      const drawn = await draw(
        <TranscriptEntry
          entry={entry}
          turn={{ status: 'idle' }}
          agent='fake'
          expanded={expanded}
          width={80}
        />,
        { columns: 80, rows: 24 },
      );

      try {
        const shown = stripAnsi(drawn.frame());

        expect(shown).toContain('→ to @sssssssssssssss · queued');
        expect(shown).not.toContain('Message(');
        expect(shown).not.toContain('@@');
        expect(shown.split('\n').every((row) => row.length <= 80)).toBe(true);
      } finally {
        await drawn.unmount();
      }
    });
  }

  test('the served recipient wins over the requested alias in every call state', async () => {
    for (const status of ['pending', 'in_progress', 'completed', 'failed']) {
      const shown = await frame(
        sent(
          {
            input: { to: 'requested-alias', text: 'The answer is ready.' },
            answer: { to: name },
            ...(status === 'failed' ? { error: 'The recipient closed.' } : {}),
          },
          status,
        ),
      );

      expect(shown).toContain('→ to @sssssssssssssss');
      expect(shown).not.toContain('@requested-alias');
      expect(shown).not.toContain('queued');
    }
  });

  test('a refused call keeps to dim and the recipient coloured in both themes', async () => {
    for (const theme of ['dark', 'light'] as const) {
      const shown = await painted(
        sent({ error: 'parser is closed; it takes no more messages' }),
        theme,
        false,
      );

      expect(shown).toContain(RED[theme]);
      expect(shown).toContain('\x1b[2mto ');
      expect(shown).toContain('\x1b[38;2;0;255;0m@parser');
      expect(stripAnsi(shown)).toContain('→ to @parser');
      expect(stripAnsi(shown)).toContain('parser is closed');
    }
  });
});

test('a line indented past the width keeps as much indent as leaves room for its text, no row wider', () => {
  const rows = wrapLine(`${' '.repeat(80)}two words`, 76);

  // Its text has the cell the indent left on every row, as wrapLine gives
  // each row the first one's room.
  expect(rows).toStrictEqual([`${' '.repeat(75)}t`, ...'wowords']);
  expect(rows.every((row) => row.length <= 76)).toBeTruthy();
  expect(wrapLine('  indented', 76)).toStrictEqual(['  indented']);
});

describe('CHD-387 tester: sent body boundaries', () => {
  test('sent escapes and fenced code render exactly as the received text does', async () => {
    const text = [
      '\x1b[31m**Read this**\x1b[0m and `keep` its formatting.',
      '',
      '```ts',
      'const answer = 42;',
      '```',
      '',
      'The last paragraph is still here.',
    ].join('\n');

    for (const expanded of [false, true]) {
      const outgoing = await frame(
        sent({ input: { to: 'parser', text } }),
        expanded,
      );
      const incoming = await frame(
        came({ name: 'parser', reachable: true }, text),
        expanded,
      );

      expect(body(outgoing)).toStrictEqual(body(incoming));
      expect(outgoing).not.toContain('[31m');
      expect(outgoing).toContain('const answer = 42;');
    }
  });

  test('a failed long body keeps its final sentence before Failed in both views', async () => {
    const entry = sent({ input: { to: 'parser', text: REVIEW } }, 'failed');
    const compact = body(await frame(entry));
    const expanded = body(await frame(entry, true));

    expect(compact.slice(-2)).toStrictEqual([
      "Tell me when the check passes and I'll look again.",
      'Failed',
    ]);
    expect(expanded).toStrictEqual(compact);
    expect(compact.join('\n')).not.toContain('to expand');
    expect(compact.join('\n')).not.toContain('… +');
  });
});

test("a message's code box is OpenTUI's, and a copy over the message keeps its code bare and the blank rows around it, as a reply's does (CHD-396)", async () => {
  const drawn = await draw(
    <TranscriptEntry
      entry={came(
        { name: 'main', reachable: true },
        'First.\n\n```sh\nls -la\n```\n\nSecond.',
      )}
      turn={{ status: 'idle' }}
      agent='fake'
      expanded={false}
      width={80}
    />,
    { columns: 80, rows: 12 },
  );

  try {
    const rows = stripAnsi(drawn.frame()).split('\n');
    const from = rows.findIndex((row) => row.includes('First.'));
    const to = rows.findIndex((row) => row.includes('Second.'));
    const end = rows[to]!.indexOf('Second.') + 'Second.'.length;

    expect(rows.join('\n')).toContain(
      '┌─ sh ─[copy]─[run]─┐\n     │ ls -la            │',
    );
    await drawn.write(left(rows[from]!.indexOf('First.'), from, 'down'));

    for (let y = from + 1; y <= to; y++) {
      await drawn.write(left(end, y, 'drag'));
    }

    await drawn.write(left(end, to, 'up'));
    // The box's border does not copy; each blank row holds one space, which
    // the copy keeps (Q186).
    expect(drawn.selected()).toStrictEqual('First.\n \nls -la\n \nSecond.');
  } finally {
    await drawn.unmount();
  }
});

describe('CHD-396 U4 tester: message gaps preserve their source blocks', () => {
  for (const columns of [80, 120]) {
    test(`sent and received messages keep exactly one-space gap rows at ${columns} columns`, async () => {
      for (const [text, expected] of [
        ['First.\n\nSecond.', 'First.\n \nSecond.'],
        [
          'First.\n\n```txt\ncode\n```\n\nSecond.',
          'First.\n \ncode\n \nSecond.',
        ],
      ] as const) {
        for (const entry of [
          came({ name: 'parser', reachable: true }, text),
          sent({ input: { to: 'parser', text } }),
        ]) {
          const drawn = await draw(
            <TranscriptEntry
              entry={entry}
              turn={{ status: 'idle' }}
              agent='fake'
              expanded={false}
              width={columns}
            />,
            { columns, rows: 24 },
          );

          try {
            const rows = stripAnsi(drawn.frame()).split('\n');
            const first = rows.findIndex((row) => row.includes('First.'));
            const last = rows.findIndex((row) => row.includes('Second.'));
            const end = rows[last]!.indexOf('Second.') + 6;

            await drawn.write(
              left(rows[first]!.indexOf('First.'), first, 'down'),
            );

            for (let row = first + 1; row <= last; row++) {
              await drawn.write(left(end, row, 'drag'));
            }

            await drawn.write(left(end, last, 'up'));
            expect(drawn.selected()).toBe(expected);
          } finally {
            await drawn.unmount();
          }
        }
      }
    });

    test(`message selections can begin on their blank body row at ${columns} columns`, async () => {
      for (const entry of [
        came({ name: 'main', reachable: true }, 'First.\n\nSecond.'),
        sent({ input: { to: 'parser', text: 'First.\n\nSecond.' } }),
      ]) {
        const drawn = await draw(
          <TranscriptEntry
            entry={entry}
            turn={{ status: 'idle' }}
            agent='fake'
            expanded={false}
            width={columns}
          />,
          { columns, rows: 24 },
        );

        try {
          const rows = stripAnsi(drawn.frame()).split('\n');
          const last = rows.findIndex((row) => row.includes('Second.'));
          const start = rows[last]!.indexOf('Second.');

          await drawn.write(left(start, last - 1, 'down'));
          await drawn.write(left(start + 6, last, 'drag'));
          await drawn.write(left(start + 6, last, 'up'));
          expect(drawn.selected()).toBe(' \nSecond.');
        } finally {
          await drawn.unmount();
        }
      }
    });
  }
});

test('a fork says where it parted, by its source and the local time, dim and alone (CHD-101)', async () => {
  const at = new Date(2026, 9, 28, 22, 10).getTime();

  expect(forkedLine('main', at, 80)).toStrictEqual(
    '── forked from main · 22:10 ──',
  );
  expect(forkedLine('a long fork name', at, 20)).toHaveLength(20);
  expect(
    await frame({ kind: 'forked', turnId: 'forked', from: 'fork', at }),
  ).toContain('── forked from fork · 22:10 ──');
});

test("the line closing a turn the agent started on its own with the person's steered prompt says it is theirs (CHD-378)", () => {
  expect(selfStartedLine(undefined, 120)).toStrictEqual(
    'Interrupted · the agent started this on its own; your message goes as the next turn',
  );
});
