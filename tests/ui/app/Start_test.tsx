import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import {
  earlierSessions,
  type EarlierSession,
} from '../../../src/session/sessions.ts';
import { Start } from '../../../src/ui/app/Start.tsx';
import { startLayout, TAGLINE } from '../../../src/ui/app/start_layout.ts';
import type { ListedAgent } from '../../../src/agents.ts';
import { SHORTCUTS } from '../../../src/ui/shortcuts/keys.ts';
import {
  DEFAULT_KEYMAP,
  readKeybindings,
} from '../../../src/ui/shortcuts/bindings.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import { ESC, until } from './render.tsx';

describe('CHD-565 tester: explicit list navigation and clipping', () => {
  const agents: ListedAgent[] = Array.from({ length: 15 }, (_, at) => ({
    name: `offered-${at + 1}`,
    title: undefined,
    from: 'settings',
    start: 'fixture',
  }));

  async function page(offered: readonly string[], columns = 80, rows = 24) {
    const picks: (string | undefined)[] = [];
    const app = await draw(
      <Start
        version='0.65.0'
        kind='agents'
        agents={agents}
        offered={offered}
        preferred='outside-the-list'
        directory='/tmp/chord-qa'
        colours={paletteOf('dark', false)}
        keymap={DEFAULT_KEYMAP}
        onPick={(chosen) => picks.push(chosen)}
      />,
      { columns, rows },
    );

    return { ...app, picks };
  }

  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`one known row still waits for a choice at ${columns}x${rows}`, async () => {
      const app = await page(
        ['unknown-first', 'offered-7', 'offered-7', 'unknown-first'],
        columns,
        rows,
      );

      try {
        expect(app.picks).toEqual([]);
        expect(app.frame()).toContain('❯ 1. offered-7');
        expect(app.frame()).not.toContain('2.');
        expect(app.frame()).toContain(
          'Unknown in offeredAgents: unknown-first',
        );
        await app.write('2');
        expect(app.picks).toEqual([]);
        await app.write('\r');
        await app.write('1');
        expect(app.picks).toEqual(['offered-7']);
      } finally {
        await app.unmount();
      }
    });
  }

  test('reordered tail stays selected across resizing with its note suppressed', async () => {
    const offered = [...agents].reverse().map(({ name }) => name);
    const app = await page([...offered, 'unknown-tail'], 120, 40);

    try {
      expect(app.frame()).not.toContain('Unknown in offeredAgents');

      for (let at = 1; at < offered.length; at++) {
        await app.write('j');
      }

      expect(app.frame()).toMatch(/❯\s+15\.\s+offered-1/);
      await app.resize({ columns: 80, rows: 24 });
      expect(app.frame()).toMatch(/❯\s+15\.\s+offered-1/);
      expect(app.frame()).not.toContain('Unknown in offeredAgents');
      await app.resize({ columns: 120, rows: 40 });
      await app.write('k');
      await app.write('\r');
      expect(app.picks).toEqual(['offered-2']);
    } finally {
      await app.unmount();
    }
  });

  test('an unknown note gives way to rows and returns without changing selection', async () => {
    const app = await page(['offered-9', 'offered-2', 'typo']);

    try {
      await app.write('j');
      expect(app.frame()).toContain('❯ 2. offered-2');
      expect(app.frame()).toContain('Unknown in offeredAgents: typo');
      await app.resize({ columns: 30, rows: 8 });
      expect(app.frame()).not.toContain('Unknown in offeredAgents');
      await app.resize({ columns: 80, rows: 24 });
      expect(app.frame()).toContain('❯ 2. offered-2');
      expect(app.frame()).toContain('Unknown in offeredAgents: typo');
      await app.write(ESC);
      await until('cancel offered list', () => app.picks.length === 1);
      await app.write('\r');
      expect(app.picks).toEqual([undefined]);
    } finally {
      await app.unmount();
    }
  });
});

const NOW = Date.now();
const ago = (minutes: number) => new Date(NOW - minutes * 60_000).toISOString();

const SESSIONS: EarlierSession[] = [
  {
    resume: { sessionId: 's1', cwd: '/h/src/app' },
    lastUsedAt: ago(11),
    prompt: 'fix the failing date test',
  },
  {
    resume: { sessionId: 's9', cwd: '/h/src/api' },
    lastUsedAt: ago(30),
    prompt: 'over in the api',
  },
];

/** `chord --resume` with no id, on `/h/src/app`, and what it was told. */
async function started() {
  const picks: (EarlierSession | undefined)[] = [];
  const app = await draw(
    <Start
      version='0.65.0'
      agent='claude'
      directory='~/src/app'
      home='/h'
      cwd='/h/src/app'
      sessions={SESSIONS}
      colours={paletteOf('dark', false)}
      keymap={DEFAULT_KEYMAP}
      onPick={(chosen) => picks.push(chosen)}
    />,
  );
  const frame = () => app.frame();
  const press = async (key: string) => {
    await app.write(key);
    await new Promise((resolve) => setTimeout(resolve, 50));
  };

  return { app, frame, press, picks };
}

test('chord --resume with no id draws the picker, with no prompt box, before anything is open', async () => {
  const { app, frame } = await started();

  try {
    await until('the picker', () => frame().includes('Resume a session'));
    expect(frame()).toContain('chord');
    expect(frame()).toContain('claude · ~/src/app');
    expect(frame()).toContain("Pick one of claude's earlier sessions to open.");
    // Sessions only: a window held several, and chord opens one (CHD-493).
    expect(frame()).toContain('❯ 1. 11 minutes ago  fix the failing date');
    expect(frame()).not.toContain('▣');
    // Another directory's session waits for ctrl+a.
    expect(!frame().includes('over in the api'), frame()).toBeTruthy();
    expect(frame()).toContain(
      'Enter to resume · Ctrl+a for all directories · Esc to quit',
    );
    expect(!frame().includes('›'), 'a prompt box').toBeTruthy();
  } finally {
    await app.unmount();
  }
});

test('Enter on a session picks it, ctrl+a lists every directory, and Esc quits picking nothing', async () => {
  const picking = await started();

  try {
    await until('the picker', () => picking.frame().includes('❯ 1.'));
    await picking.press('\x01');
    await until('every directory', () =>
      picking.frame().includes('over in the api'),
    );
    await picking.press('\r');
    expect(picking.picks).toStrictEqual([SESSIONS[0]!]);
  } finally {
    await picking.app.unmount();
  }

  const leaving = await started();

  try {
    await until('the picker', () => leaving.frame().includes('❯ 1.'));
    await leaving.press(ESC);
    expect(leaving.picks).toStrictEqual([undefined]);
    // Picked once: a key after it picks nothing more.
    await leaving.press('\r');
    expect(leaving.picks).toStrictEqual([undefined]);
  } finally {
    await leaving.app.unmount();
  }
});

describe('CHD-445 U2 tester: titled start picker navigation and resets', () => {
  const title = Array.from({ length: 180 }, (_, at) => `token${at}`).join(' ');
  const sessions = earlierSessions(
    [
      { id: 'short', title: 'Short named session', cwd: '/work/app' },
      { id: 'tall', title, cwd: '/work/app' },
      { id: 'foreign', title: 'Other directory title', cwd: '/work/elsewhere' },
    ].map((item, index) => ({
      path: `/records/${item.id}.jsonl`,
      sessionId: item.id,
      agent: 'fake',
      cwd: item.cwd,
      lastUsedAt: NOW - (index + 1) * 60_000,
      prompt: `original prompt for ${item.id}`,
      title: item.title,
    })),
    { agent: 'fake' },
  );

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const reset of [false, true]) {
      test(`${reset ? 'height and scope reset a scrolled title' : 'Enter picks the title while its first line is off screen'} at ${columns}×${rows}`, async () => {
        const picks: (EarlierSession | undefined)[] = [];
        const app = await draw(
          <Start
            version='0.65.0'
            agent='fake'
            directory='/work/app'
            home={undefined}
            cwd='/work/app'
            sessions={sessions}
            colours={paletteOf('dark', false)}
            keymap={DEFAULT_KEYMAP}
            onPick={(chosen) => picks.push(chosen)}
          />,
          { columns, rows },
        );
        const frame = () => stripAnsi(app.frame());
        const readToEnd = async () => {
          for (let press = 0; !frame().includes('token179'); press++) {
            expect(press).toBeLessThan(80);
            await app.write('j');
          }
        };

        try {
          await until('the titled start picker', () =>
            frame().includes('Short named session'),
          );
          expect(frame()).not.toContain('original prompt');
          expect(frame()).not.toContain('Other directory title');
          await app.write('j');
          await readToEnd();
          expect(frame()).not.toContain('token0 ');
          expect(
            frame()
              .split('\n')
              .filter((line) => line.trimStart().startsWith('│')).length,
          ).toBeLessThanOrEqual(
            startLayout({
              columns,
              rows,
              lines: 1000,
              framed: true,
              hintRows: 1,
            }).listRows + 6,
          );

          if (reset) {
            await app.resize({ rows: rows - 10 });
            await until(
              'the highlighted title from its first line after resize',
              () => frame().includes('token0 '),
            );
            await readToEnd();
            await app.resize({ columns: columns === 80 ? 120 : 80 });
            await until(
              'the highlighted title from its first line after a width change',
              () => frame().includes('token0 '),
            );
            await readToEnd();
            await app.write('\x01');
            await until(
              'the new scope from its top',
              () =>
                /❯\s*1\./.test(frame()) &&
                frame().includes('Short named session'),
            );
            expect(frame()).not.toContain('token179');
            await app.write('\r');
            expect(picks[0]?.resume.sessionId).toBe('short');
          } else {
            await app.write('k');
            await app.write('\r');
            expect(picks[0]?.resume.sessionId).toBe('tall');
            expect(picks[0]?.resume.title).toBe(title);
          }

          expect(picks).toHaveLength(1);
        } finally {
          await app.unmount();
        }
      });
    }
  }
});

describe('CHD-532 startup agent picker', () => {
  const agents: ListedAgent[] = [
    {
      name: 'one',
      title: 'First agent',
      from: 'settings',
      start: 'fixture-one',
    },
    {
      name: 'two',
      title: 'two',
      from: 'cli',
      start: 'fixture-two',
      found: true,
    },
    {
      name: 'three',
      title: undefined,
      from: 'settings',
      start: 'fixture-three',
    },
  ];

  async function choosing(
    list = agents,
    preferred = 'two',
    columns = 80,
    rows = 24,
    keymap = DEFAULT_KEYMAP,
    offered?: readonly string[],
  ) {
    const picks: (string | undefined)[] = [];
    const app = await draw(
      <Start
        version='0.65.0'
        kind='agents'
        agents={list}
        offered={offered}
        preferred={preferred}
        directory='/tmp/chord-qa'
        colours={paletteOf('dark', false)}
        keymap={keymap}
        onPick={(choice) => picks.push(choice)}
      />,
      { columns, rows },
    );

    return { ...app, picks };
  }

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`short catalog at ${columns}x${rows} highlights the default without an active-session mark`, async () => {
      const app = await choosing(agents, 'two', columns, rows);

      try {
        expect(app.frame()).toContain('Select agent');
        expect(app.frame()).toContain('1. one · First agent');
        expect(app.frame()).toContain('❯ 2. two');
        expect(app.frame()).toContain('3. three');
        expect(app.frame()).toContain('Esc to cancel');
        expect(app.frame()).not.toContain('✔');
        expect(app.frame()).not.toContain('two · /tmp');
        expect(app.frame()).not.toContain('›');
        await app.write('\x01');
        expect(app.frame()).not.toContain('Resume a session');
        await app.write('\r');
        expect(app.picks).toEqual(['two']);
        await app.write('1');
        expect(app.picks).toEqual(['two']);
      } finally {
        await app.unmount();
      }
    });
  }

  test('missing default opens on first; j/k and absolute digits use existing choices', async () => {
    const app = await choosing(agents, 'unknown');

    try {
      expect(app.frame()).toContain('❯ 1. one');
      await app.write('j');
      expect(app.frame()).toContain('❯ 2. two');
      await app.write('k');
      expect(app.frame()).toContain('❯ 1. one');
      await app.write('3');
      expect(app.picks).toEqual(['three']);

      for (const name of ['j', 'k', '1', '3', 'enter']) {
        expect(SHORTCUTS.some((entry) => entry.choices?.includes(name))).toBe(
          true,
        );
      }
    } finally {
      await app.unmount();
    }
  });

  test('long catalog scrolls without reordering and resizes while keeping the highlight', async () => {
    const list = Array.from({ length: 20 }, (_, i) => ({
      name: `fixture-${i + 1}`,
      title: 'Long title '.repeat(30),
      from: 'settings' as const,
      start: 'fixture',
    }));
    const app = await choosing(list, 'fixture-18');

    try {
      expect(app.frame()).toContain('18. fixture-18');
      expect(app.frame()).toContain('more');
      expect(app.frame().split('\n').length).toBeLessThanOrEqual(24);
      await app.resize({ columns: 120, rows: 40 });
      expect(app.frame()).toContain('18. fixture-18');
      await app.write('2');
      expect(app.picks).toEqual(['fixture-2']);
    } finally {
      await app.unmount();
    }
  });

  test('empty catalog cannot select and only offers cancellation', async () => {
    const app = await choosing([]);

    try {
      expect(app.frame()).toContain('No agents available');
      expect(app.frame()).not.toContain('Enter or');
      await app.write('1\r');
      expect(app.picks).toEqual([]);
      await app.write(ESC);
      await until('cancelled empty picker', () => app.picks.length === 1);
      expect(app.picks).toEqual([undefined]);
    } finally {
      await app.unmount();
    }
  });

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    const offering = (offered: readonly string[], preferred = 'one') =>
      choosing(
        [
          ...agents,
          {
            name: 'missing',
            title: 'Missing agent',
            from: 'cli',
            start: 'fixture-missing',
            found: false,
          },
        ],
        preferred,
        columns,
        rows,
        DEFAULT_KEYMAP,
        offered,
      );

    test(`CHD-565 at ${columns}x${rows}, the list sets the rows and their order, and the numbers follow`, async () => {
      const app = await offering(['three', 'one']);

      try {
        expect(app.frame()).toContain('1. three');
        expect(app.frame()).toContain('❯ 2. one · First agent');
        expect(app.frame()).not.toContain('two');
        expect(app.frame()).not.toContain('3.');
        expect(app.frame()).not.toContain('Unknown in offeredAgents');
        await app.write('1');
        await until('a pick from the list', () => app.picks.length === 1);
        expect(app.picks).toStrictEqual(['three']);
      } finally {
        await app.unmount();
      }
    });

    test(`CHD-565 at ${columns}x${rows}, a listed own CLI PATH lacks stays, says so and can be picked`, async () => {
      const app = await offering(['one', 'missing']);

      try {
        expect(app.frame()).toContain(
          '2. missing · Missing agent · not on PATH',
        );
        await app.write('2');
        await until('a pick of the missing row', () => app.picks.length === 1);
        expect(app.picks).toStrictEqual(['missing']);
      } finally {
        await app.unmount();
      }
    });

    test(`CHD-565 at ${columns}x${rows}, a preferred agent outside the list opens on the first row`, async () => {
      const app = await offering(['three', 'one'], 'two');

      try {
        expect(app.frame()).toContain('❯ 1. three');
      } finally {
        await app.unmount();
      }
    });

    test(`CHD-565 at ${columns}x${rows}, unknown names are said once under the hint`, async () => {
      const app = await offering(['one', 'cdex', 'codx']);

      try {
        const frame = app.frame();

        expect(frame).toContain('Unknown in offeredAgents: cdex, codx');
        expect(frame.indexOf('Esc to cancel')).toBeLessThan(
          frame.indexOf('Unknown in offeredAgents'),
        );
        expect(frame).not.toContain('cdex ');
      } finally {
        await app.unmount();
      }
    });

    test(`CHD-565 at ${columns}x${rows}, only unknown names offer nothing, say why and only cancel`, async () => {
      const app = await offering(['cdex']);

      try {
        const frame = app.frame();

        expect(frame).toContain('No agents available');
        expect(frame).toContain(
          'offeredAgents in settings.json names no agent chord knows.',
        );
        expect(frame).not.toContain('Unknown in offeredAgents');
        expect(frame).not.toContain('cdex');
        expect(frame).not.toContain('Enter or 1–9');
        await app.write('1');
        await app.write('\r');
        expect(app.picks).toStrictEqual([]);
        await app.write(ESC);
        await until('cancelling', () => app.picks.length === 1);
        expect(app.picks).toStrictEqual([undefined]);
      } finally {
        await app.unmount();
      }
    });

    test(`CHD-544 at ${columns}x${rows}, an own CLI PATH lacks is not offered, the highlight opening on the first row when it was the default`, async () => {
      const list: ListedAgent[] = [
        agents[0]!,
        {
          name: 'missing',
          title: 'Missing agent',
          from: 'cli',
          start: 'fixture-missing',
          found: false,
        },
        agents[2]!,
      ];
      const app = await choosing(list, 'missing', columns, rows);

      try {
        expect(app.frame()).not.toContain('missing');
        expect(app.frame()).not.toContain('not found');
        expect(app.frame()).toContain('❯ 1. one · First agent');
        expect(app.frame()).toContain('2. three');
        expect(app.frame()).not.toContain('3.');
        await app.write('2');
        expect(app.picks).toEqual(['three']);
      } finally {
        await app.unmount();
      }
    });
  }

  test('cancel follows its existing binding and Ctrl+C cancels independently', async () => {
    const { keymap } = readKeybindings(
      JSON.stringify({
        bindings: [
          {
            context: 'Select',
            bindings: { escape: null, 'ctrl+q': 'select:cancel' },
          },
        ],
      }),
    );
    const app = await choosing(agents, 'one', 80, 24, keymap);

    try {
      // A longer key takes the hint past the column, so it wraps at a space.
      expect(stripAnsi(app.frame()).replace(/\s+/g, ' ')).toContain(
        'Ctrl+q to cancel',
      );
      expect(
        SHORTCUTS.some((entry) => entry.actions?.includes('select:cancel')),
      ).toBe(true);
      await app.write('\x11');
      expect(app.picks).toEqual([undefined]);
    } finally {
      await app.unmount();
    }

    const control = await choosing();

    try {
      await control.write('\x03');
      expect(control.picks).toEqual([undefined]);
    } finally {
      await control.unmount();
    }
  });
});

describe('CHD-544 tester: filtered picker keys and empty catalogs', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`an all-hidden catalog cannot be picked and cancels once at ${columns}x${rows}`, async () => {
      const picks: (string | undefined)[] = [];
      const app = await draw(
        <Start
          version='0.65.0'
          kind='agents'
          agents={[
            {
              name: 'missing',
              title: 'Missing',
              start: 'missing',
              from: 'cli',
              found: false,
            },
          ]}
          preferred='missing'
          directory='/tmp/chord-qa'
          colours={paletteOf('dark', false)}
          keymap={DEFAULT_KEYMAP}
          onPick={(choice) => picks.push(choice)}
        />,
        { columns, rows },
      );

      try {
        expect(app.frame()).toContain('No agents available');
        expect(app.frame()).not.toContain('not found');
        await app.write('1');
        await app.write('\r');
        await app.write('j');
        expect(picks).toStrictEqual([]);
        await app.write(ESC);
        await until('empty catalog cancellation', () => picks.length === 1);
        await app.write('\r');
        expect(picks).toStrictEqual([undefined]);
      } finally {
        await app.unmount();
      }
    });

    test(`digit selection follows the filtered numbering past hidden rows at ${columns}x${rows}`, async () => {
      const picks: (string | undefined)[] = [];
      const agents: ListedAgent[] = Array.from({ length: 12 }, (_, i) => [
        {
          name: `hidden-${i}`,
          title: undefined,
          start: 'missing',
          from: 'cli' as const,
          found: false,
        },
        {
          name: `kept-${i}`,
          title: undefined,
          start: 'fixture',
          from: 'settings' as const,
        },
      ]).flat();
      const app = await draw(
        <Start
          version='0.65.0'
          kind='agents'
          agents={agents}
          preferred='hidden-11'
          directory='/tmp/chord-qa'
          colours={paletteOf('dark', false)}
          keymap={DEFAULT_KEYMAP}
          onPick={(choice) => picks.push(choice)}
        />,
        { columns, rows },
      );

      try {
        expect(app.frame()).toMatch(/❯\s+1\.\s+kept-0/);
        expect(app.frame()).not.toContain('hidden-');
        await app.write('9');
        expect(picks).toStrictEqual(['kept-8']);
      } finally {
        await app.unmount();
      }
    });
  }
});

describe('CHD-564 the title page', () => {
  const list = (count: number): ListedAgent[] =>
    Array.from({ length: count }, (_, at) => ({
      name: `agent-${at + 1}`,
      title: undefined,
      from: 'settings' as const,
      start: 'fixture',
    }));
  const was = chalk.level;

  beforeAll(() => {
    chalk.level = 3;
  });

  afterAll(() => {
    chalk.level = was;
  });

  async function page(
    columns: number,
    rows: number,
    {
      count = 28,
      colours = paletteOf('dark', true),
      directory = '~/src/app',
      preferred = 'agent-5',
    } = {},
  ) {
    const app = await draw(
      <Start
        version='0.65.0'
        kind='agents'
        agents={list(count)}
        preferred={preferred}
        directory={directory}
        colours={colours}
        keymap={DEFAULT_KEYMAP}
        onPick={() => {}}
      />,
      { columns, rows },
    );
    const lines = () => stripAnsi(app.frame()).split('\n');

    return { ...app, lines, text: () => lines().join('\n') };
  }

  const rowOf = (lines: string[], text: string) =>
    lines.findIndex((line) => line.includes(text));

  test('full at 120x40: the block wordmark, tagline and version, the list capped at 14', async () => {
    const app = await page(120, 40);

    try {
      const lines = app.lines();
      const art = rowOf(lines, '██████╗ ██╗');

      expect(art).toBe(5);
      // The mark's left edge, 57 columns of art centred on 120, the odd
      // column where Yoga puts it; the word after its 9 and a gap of 3.
      expect(lines[art]?.indexOf('▀')).toBe(32);
      expect(lines[art]?.indexOf('█')).toBe(45);
      expect(rowOf(lines, TAGLINE)).toBe(13);
      expect(lines[13]?.indexOf(TAGLINE)).toBe(42);
      expect(rowOf(lines, 'v0.65.0 · ~/src/app')).toBe(14);
      expect(rowOf(lines, 'Select agent')).toBe(16);
      // The column is 62 wide centred on 120, its padding inside it.
      expect(lines[16]?.indexOf('Select agent')).toBe(30);
      expect(app.text()).toContain('14. agent-14');
      expect(app.text()).toContain('… +14 more');
      expect(app.text()).not.toContain('15. agent-15');
    } finally {
      await app.unmount();
    }
  });

  test('a short list moves the page, not the art out of its step', async () => {
    const app = await page(120, 40, { count: 5 });

    try {
      const lines = app.lines();

      expect(rowOf(lines, '██████╗ ██╗')).toBe(10);
      expect(lines.join('\n')).not.toContain('more');
    } finally {
      await app.unmount();
    }
  });

  test('compact at 80x24: the tiny wordmark and the version, no tagline', async () => {
    const app = await page(80, 24);

    try {
      const lines = app.lines();

      expect(rowOf(lines, '█▀▀ █ █ █▀█ █▀█ █▀▄')).toBe(1);
      expect(rowOf(lines, 'v0.65.0 · ~/src/app')).toBe(4);
      expect(rowOf(lines, 'Select agent')).toBe(6);
      expect(app.text()).not.toContain(TAGLINE);
      expect(app.text()).toContain('12. agent-12');
      expect(app.text()).toContain('… +16 more');
    } finally {
      await app.unmount();
    }
  });

  test('line under 40 columns: the bold word and the version, no art', async () => {
    const app = await page(39, 24);

    try {
      expect(rowOf(app.lines(), 'chord v0.65.0 · ~/src/app')).toBe(0);
      expect(app.text()).not.toContain('▀');
      expect(rowOf(app.lines(), 'Select agent')).toBe(2);
      expect(app.text()).toContain('15. agent-15');
    } finally {
      await app.unmount();
    }
  });

  test('none at 30x8: the picker from the first row, one row of list', async () => {
    const app = await page(30, 8);

    try {
      expect(rowOf(app.lines(), 'Select agent')).toBe(0);
      expect(app.text()).not.toContain('v0.65.0');
      expect(app.text()).toContain('❯ ↑ 5.');
      expect(app.text()).toContain('… +27 more');
    } finally {
      await app.unmount();
    }
  });

  test('the version line cuts its directory from the left', async () => {
    const app = await page(39, 24, {
      directory: '~/work/acme/services/billing/acme-api',
    });

    try {
      expect(app.lines()[0]).toContain('chord v0.65.0 · …/billing/acme-api');
    } finally {
      await app.unmount();
    }
  });

  test('no agents: the page with one row, and only the way out', async () => {
    const app = await page(80, 24, { count: 0 });

    try {
      const lines = app.lines();

      expect(rowOf(lines, 'v0.65.0')).toBe(10);
      expect(rowOf(lines, 'No agents available')).toBe(14);
      expect(rowOf(lines, 'Esc to cancel')).toBe(16);
      expect(app.text()).not.toContain('Enter or');
    } finally {
      await app.unmount();
    }
  });

  for (const [columns, rows, word] of [
    [120, 40, 'chord'],
    [80, 24, 'chord'],
  ] as const) {
    test(`PLAIN at ${columns}x${rows}: a bold word in the wordmark's place, in the same rows`, async () => {
      const plain = await page(columns, rows, {
        colours: paletteOf('dark', false),
      });
      const coloured = await page(columns, rows);

      try {
        const lines = plain.lines();
        const at = rowOf(lines, word);

        expect(at).toBeGreaterThan(0);
        expect(plain.text()).not.toContain('█▀▀');
        expect(plain.text()).not.toContain('██████╗');
        expect(rowOf(lines, 'Select agent')).toBe(
          rowOf(coloured.lines(), 'Select agent'),
        );
      } finally {
        await plain.unmount();
        await coloured.unmount();
      }
    });
  }

  test('a highlight is kept across a step and back', async () => {
    const app = await page(120, 40);

    try {
      await app.write('j');
      expect(app.text()).toMatch(/❯\s+6\.\s+agent-6/);
      await app.resize({ columns: 80, rows: 24 });
      expect(app.text()).toContain('█▀▀ █ █');
      expect(app.text()).toMatch(/❯\s+6\.\s+agent-6/);
      await app.resize({ columns: 39, rows: 24 });
      expect(app.text()).toMatch(/❯\s+6\.\s+agent-6/);
      await app.resize({ columns: 120, rows: 40 });
      expect(app.text()).toContain('██████╗ ██╗');
      expect(app.text()).toMatch(/❯\s+6\.\s+agent-6/);
    } finally {
      await app.unmount();
    }
  });
});

describe('CHD-564 the title page around --resume', () => {
  const was = chalk.level;
  const long =
    'a long title that goes on well past what the frame of 84 columns can hold on one line of its own, and then some';
  const sessions: EarlierSession[] = Array.from({ length: 14 }, (_, at) => ({
    resume: { sessionId: `s${at}`, cwd: '/h/src/app' },
    lastUsedAt: ago(at + 1),
    prompt: at === 0 ? long : `prompt ${at}`,
  }));

  beforeAll(() => {
    chalk.level = 3;
  });

  afterAll(() => {
    chalk.level = was;
  });

  async function page(
    columns: number,
    rows: number,
    list: readonly EarlierSession[] = sessions,
  ) {
    const app = await draw(
      <Start
        version='0.65.0'
        agent='claude'
        directory='~/src/app'
        home='/h'
        cwd='/h/src/app'
        sessions={list}
        colours={paletteOf('dark', true)}
        keymap={DEFAULT_KEYMAP}
        onPick={() => {}}
      />,
      { columns, rows },
    );
    const lines = () => stripAnsi(app.frame()).split('\n');

    return { ...app, lines, text: () => lines().join('\n') };
  }

  const rowOf = (lines: string[], text: string) =>
    lines.findIndex((line) => line.includes(text));

  test('full at 120x40: art, words naming the agent, a frame of 84 wrapping a long title', async () => {
    const app = await page(120, 40);

    try {
      const lines = app.lines();
      const frame = rowOf(lines, 'Resume a session') - 1;

      expect(app.text()).toContain('██████╗ ██╗');
      expect(app.text()).toContain(TAGLINE);
      expect(app.text()).toContain('v0.65.0 · claude · ~/src/app');
      // 84 columns centred on 120.
      expect(lines[frame]?.indexOf('╭')).toBe(18);
      expect(lines[frame]?.indexOf('╮')).toBe(101);
      expect(app.text()).not.toContain('...');
      expect(app.text().replace(/[│\s]+/g, ' ')).toContain(long);
      expect(app.text()).toContain('Esc to quit');
    } finally {
      await app.unmount();
    }
  });

  test('compact at 80x24: the list scrolls under the tiny wordmark', async () => {
    const app = await page(80, 24, [
      ...sessions.slice(1),
      { ...sessions[1]!, resume: { sessionId: 'x', cwd: '/h/src/app' } },
    ]);

    try {
      expect(app.text()).toContain('█▀▀ █ █');
      expect(app.text()).toContain('v0.65.0 · claude · ~/src/app');
      expect(app.text()).toContain('… +6 more');
      expect(app.lines()[0]).toContain('▀▄');
      expect(app.text()).toContain('Esc to quit');
    } finally {
      await app.unmount();
    }
  });

  test('line under 40 columns says the agent after the version', async () => {
    const app = await page(39, 24);

    try {
      expect(app.lines()[0]).toContain('chord v0.65.0 · claude · ~/src/app');
    } finally {
      await app.unmount();
    }
  });

  test('ctrl+a counts the other scope, and its page moves', async () => {
    const here: EarlierSession = sessions[1]!;
    const there: EarlierSession[] = Array.from({ length: 10 }, (_, at) => ({
      resume: { sessionId: `t${at}`, cwd: '/h/src/api' },
      lastUsedAt: ago(100 + at),
      prompt: `over there ${at}`,
    }));
    const app = await page(120, 40, [here, ...there]);

    try {
      const before = rowOf(app.lines(), 'Resume a session');

      await app.write('\x01');
      await until('every directory', () => app.text().includes('over there 0'));

      expect(rowOf(app.lines(), 'Resume a session')).toBeLessThan(before);
    } finally {
      await app.unmount();
    }
  });
});

describe('CHD-564 tester: title page navigation and terminal depth', () => {
  const agents: ListedAgent[] = Array.from({ length: 28 }, (_, at) => ({
    name: `fixture-${at + 1}`,
    title: undefined,
    start: 'fixture',
    from: 'settings',
  }));

  async function page(columns: number, rows: number, empty = false) {
    const picks: (string | undefined)[] = [];
    const app = await draw(
      <Start
        version='0.65.0'
        kind='agents'
        agents={empty ? [] : agents}
        preferred='fixture-5'
        directory='~/src/app'
        colours={paletteOf('dark', true)}
        keymap={DEFAULT_KEYMAP}
        onPick={(chosen) => picks.push(chosen)}
      />,
      { columns, rows },
    );

    return { ...app, picks, text: () => stripAnsi(app.frame()) };
  }

  test('scrolling to the catalog end keeps the art, words and hint on their rows', async () => {
    const level = chalk.level;

    chalk.level = 3;

    const app = await page(120, 40);

    try {
      const before = app.text().split('\n');
      const fixed = ['██████╗ ██╗', TAGLINE, 'v0.65.0', '↑↓ or j/k'].map(
        (part) => before.findIndex((line) => line.includes(part)),
      );

      for (let at = 5; at < 28; at++) {
        await app.write('j');
      }

      const after = app.text().split('\n');

      expect(app.text()).toMatch(/❯\s+28\.\s+fixture-28/);
      expect(app.text()).toContain('… +14 more');
      expect(fixed.every((row) => row >= 0)).toBe(true);

      for (const row of fixed) {
        expect(after[row]).toBe(before[row]);
      }

      await app.write('\r');
      await app.write('1');
      expect(app.picks).toEqual(['fixture-28']);
    } finally {
      await app.unmount();

      chalk.level = level;
    }
  });

  test('the highlighted tail survives full, compact, line and none steps and back', async () => {
    const app = await page(120, 40);

    try {
      for (let at = 5; at < 28; at++) {
        await app.write('j');
      }

      for (const [columns, rows] of [
        [80, 24],
        [39, 24],
        [30, 8],
        [120, 40],
      ] as const) {
        await app.resize({ columns, rows });
        expect(app.text()).toMatch(/❯\s+↑?\s*28\.\s+fixture-28/);
      }

      await app.write('k');
      await app.write('\r');
      expect(app.picks).toEqual(['fixture-27']);
    } finally {
      await app.unmount();
    }
  });

  for (const rows of [2, 5, 8]) {
    test(`pick keys and Ctrl+C work when a ${rows}-row window clips the page`, async () => {
      const picking = await page(30, rows);

      try {
        await picking.write('9');
        expect(picking.picks).toEqual(['fixture-9']);
      } finally {
        await picking.unmount();
      }

      const leaving = await page(30, rows, true);

      try {
        await leaving.write('1');
        await leaving.write('\r');
        expect(leaving.picks).toEqual([]);
        await leaving.write('\x03');
        await leaving.write('\r');
        expect(leaving.picks).toEqual([undefined]);
      } finally {
        await leaving.unmount();
      }
    });
  }

  for (const level of [0, 1, 2] as const) {
    for (const [columns, rows] of [
      [120, 40],
      [80, 24],
    ] as const) {
      test(`terminal colour level ${level} draws and picks at ${columns}x${rows}`, async () => {
        const previous = chalk.level;

        chalk.level = level;

        const app = await page(columns, rows);

        try {
          expect(app.text()).toContain('Select agent');
          expect(app.text()).toContain('v0.65.0 · ~/src/app');

          if (level === 0) {
            expect(app.text()).toContain('chord');
            expect(app.text()).not.toContain('██████╗');
            expect(app.text()).not.toContain('█▀▀ █ █');
          } else {
            expect(app.text()).toContain(
              columns === 120 ? '██████╗ ██╗' : '█▀▀ █ █ █▀█',
            );
          }

          await app.write('\r');
          expect(app.picks).toEqual(['fixture-5']);
        } finally {
          await app.unmount();

          chalk.level = previous;
        }
      });
    }
  }
});

describe('CHD-564 tester: resume page scope, clipping and stable frame', () => {
  const longTitle = Array.from({ length: 180 }, (_, at) => `word${at}`).join(
    ' ',
  );
  const sessions: EarlierSession[] = [
    {
      resume: { sessionId: 'long', cwd: '/h/src/app' },
      lastUsedAt: ago(2),
      prompt: longTitle,
    },
    {
      resume: { sessionId: 'foreign', cwd: '/h/src/api' },
      lastUsedAt: ago(5),
      prompt: 'foreign title with 界 and emoji 🌱 kept whole',
    },
  ];

  async function page(
    columns: number,
    rows: number,
    list = sessions,
    keymap = DEFAULT_KEYMAP,
  ) {
    const picks: (EarlierSession | undefined)[] = [];
    const app = await draw(
      <Start
        version='0.65.0'
        agent='fixture'
        directory='~/src/app'
        home='/h'
        cwd='/h/src/app'
        sessions={list}
        colours={paletteOf('dark', false)}
        keymap={keymap}
        onPick={(chosen) => picks.push(chosen)}
      />,
      { columns, rows },
    );

    return { ...app, picks, text: () => stripAnsi(app.frame()) };
  }

  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    test(`an empty local scope gains its foreign choices and returns empty at ${columns}x${rows}`, async () => {
      const app = await page(columns, rows, sessions.slice(1));

      try {
        expect(app.text()).not.toContain('foreign title');
        expect(app.text()).not.toContain('Enter to resume');
        await app.write('1');
        await app.write('\r');
        expect(app.picks).toEqual([]);
        await app.write('\x01');
        expect(app.text().replace(/[│\s]+/g, ' ')).toContain(
          'foreign title with 界 and emoji 🌱 kept whole',
        );
        expect(app.text()).toContain('Enter to resume');
        expect(app.text()).toContain('Ctrl+a for this directory');
        await app.write('\x01');
        expect(app.text()).not.toContain('foreign title');
        expect(app.text()).not.toContain('Enter to resume');
        await app.write(ESC);
        expect(app.picks).toEqual([undefined]);
      } finally {
        await app.unmount();
      }
    });

    test(`rebound scope and cancel keys retain their hints and ownership at ${columns}x${rows}`, async () => {
      const { keymap } = readKeybindings(
        JSON.stringify({
          bindings: [
            {
              context: 'Select',
              bindings: {
                escape: null,
                'ctrl+a': null,
                'ctrl+s': 'select:toggleScope',
                'ctrl+q': 'select:cancel',
              },
            },
          ],
        }),
      );
      const app = await page(
        columns,
        rows,
        [{ ...sessions[0]!, prompt: 'local title' }, sessions[1]!],
        keymap,
      );

      try {
        expect(app.text().replace(/[│\s]+/g, ' ')).toContain(
          'Ctrl+s for all directories · Ctrl+q to quit',
        );
        await app.write(ESC);
        await app.write('\x01');
        expect(app.picks).toEqual([]);
        expect(app.text()).not.toContain('foreign title');
        await app.write('\x13');
        expect(app.text()).toContain('foreign title');
        await app.write('\x11');
        await app.write('\r');
        expect(app.picks).toEqual([undefined]);
      } finally {
        await app.unmount();
      }
    });

    test(`a PLAIN resume page keeps the selected long session through every step at ${columns}x${rows}`, async () => {
      const app = await page(columns, rows);

      try {
        expect(app.text()).toContain('chord');
        expect(app.text()).toContain('v0.65.0 · fixture · ~/src/app');
        expect(app.text()).not.toContain('...');

        for (const [width, height] of [
          [39, 24],
          [30, 8],
          [120, 40],
        ] as const) {
          await app.resize({ columns: width, rows: height });
        }

        await app.write('\r');
        await app.write('1');
        expect(app.picks).toEqual([sessions[0]]);
      } finally {
        await app.unmount();
      }
    });
  }

  test('a height change inside full preserves a scrolled title when frame and list rows stay fixed', async () => {
    const app = await page(120, 40);

    try {
      for (let at = 0; !app.text().includes('word179'); at++) {
        expect(at).toBeLessThan(80);
        await app.write('j');
      }

      expect(app.text()).not.toContain('word0 ');
      await app.resize({ rows: 44 });
      expect(app.text()).not.toContain('word0 ');
      expect(app.text()).toContain('word179');
      await app.write('\r');
      expect(app.picks[0]?.resume.sessionId).toBe('long');
      expect(app.picks).toHaveLength(1);
    } finally {
      await app.unmount();
    }
  });
});
