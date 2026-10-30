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
  ) {
    const picks: (string | undefined)[] = [];
    const app = await draw(
      <Start
        version='0.65.0'
        kind='agents'
        agents={list}
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
