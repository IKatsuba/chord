/** Messages between agents on screen: `←` for what came in, `→` for what went. */
import { expect, test } from 'bun:test';
import chalk from 'chalk';
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
  queuedMessage,
} from '../../../src/ui/transcript/message.ts';
import { TranscriptEntry } from '../../../src/ui/transcript/Transcript.tsx';

async function frame(entry: Entry): Promise<string> {
  const drawn = await draw(
    <TranscriptEntry
      entry={entry}
      turn={{ status: 'idle' }}
      agent='fake'
      expanded={false}
      width={80}
    />,
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

test('a message that came in is ←, its sender and what it said', async () => {
  expect(
    await frame(
      came({ name: 'Fix the tokenizer', runtime: 'codex', note: 'report' }),
    ),
  ).toContain('← Fix the tokenizer · codex · report\n  ⎿  Fixed.');
  expect(
    await frame(
      came({ name: 'Fix the tokenizer', runtime: 'codex', note: 'failed' }),
    ),
  ).toContain('← Fix the tokenizer · codex · failed');
  expect(
    await frame(came({ name: 'parser', runtime: 'codex', reachable: true })),
  ).toContain('← @parser · codex');
  expect(await frame(came({ name: 'main', reachable: true }))).toContain(
    '← @main',
  );
  expect(await frame(came({ name: 'chord' }))).toContain('← chord');
});

test('@ goes on a sender send_message reaches, told by who sent it, not its name', async () => {
  // A task titled as an agent is named is still a task.
  expect(await frame(came({ name: 'parser', runtime: 'codex' }))).toContain(
    '← parser · codex',
  );
  expect(
    queuedMessage({ name: 'docs', runtime: 'claude', reachable: true }, 'Hi'),
  ).toContain('@docs · claude: Hi');
  expect(queuedMessage({ name: 'Fix it', runtime: 'codex' }, 'Hi')).toContain(
    'Fix it · codex: Hi',
  );
});

test('a message sent is → and its recipient, not a call, queued or refused', async () => {
  const delivered = await frame(sent({ queued: true }));

  expect(delivered).toContain('→ @parser · queued\n  ⎿  Run the parser tests.');
  expect(
    !delivered.includes('⏺'),
    'a sent message is drawn as a call',
  ).toBeTruthy();
  expect(
    !delivered.includes('Message('),
    'a sent message is drawn as a call',
  ).toBeTruthy();
  expect(await frame(sent({}, 'in_progress'))).toContain('→ @parser\n');
  expect(
    await frame(sent({ error: 'parser is closed; it takes no more messages' })),
  ).toContain('→ @parser\n  ⎿  parser is closed; it takes no more messages');
  // A child's, inside its task block, goes to main.
  expect(
    await frame(sent({ input: { text: 'Found it' }, queued: true })),
  ).toContain('→ @main · queued');
});

test("a child's message inside its task block is → @main, not Message(main)", async () => {
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

  expect(shown).toContain('⎿  → @main · queued');
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

    expect(stripAnsi(body)).toContain('← @main\n  ⎿  Do not hand back.');
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

      expect(stripAnsi(delivered)).toContain('→ @main');
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

test("a monitor's event is ← its description · monitor, its lines as printed, not markdown", async () => {
  expect(await frame(event())).toContain(
    '← dev server errors · monitor\n  ⎿  a *b* _c_\n         at x (y.ts:1:2)',
  );
  expect(
    queuedMessage({ name: 'dev server errors', monitor: { id: 'm1' } }, 'WARN'),
  ).toContain('dev server errors · monitor: WARN');
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
    expect(stripAnsi(shown)).toContain('← red errors · monitor');
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
    '← dev server errors · monitor · exit code 1\n  ⎿  line 1\n',
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
  expect(arrow({ kind: 'timed_out', timeoutMs: 600_000 })).toStrictEqual(
    'warning',
  );
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
