import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import { ConfigPicker } from '../../../src/ui/pickers/Pickers.tsx';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseServers } from '../../../src/mcp.ts';
import type { ThemeSetting } from '../../../src/ui/theme/theme.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { recordSession } from '../../fixtures/records.ts';
import { writeWindow } from '../../../src/session/windows.ts';
import {
  readRecords,
  type ResumableTab,
} from '../../../src/session/sessions.ts';
import {
  DOWN,
  ESC,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';

/** Waits for the model picker, and for its list to take the keys. */
async function picking(window: Window): Promise<void> {
  await window.shows('Select model');
  await new Promise((resolve) => setTimeout(resolve, 150));
}

test("/model lists the agent's models, and Enter switches", () =>
  withWindow(async (window) => {
    const status = () => window.frame().split('\n').at(-1) ?? '';

    await window.shows('Fake Large with a 1M context window');
    await window.type('/model');
    await window.press('\r');
    await picking(window);
    expect(window.frame()).toContain(
      '❯ 1. Fake Large with a 1M context window ✔',
    );
    expect(window.frame()).toContain('2. Fake Small');
    expect(
      !promptRow(window)?.includes('/model'),
      'the draft stayed',
    ).toBeTruthy();
    await window.press(DOWN);
    await window.shows('❯ 2. Fake Small');
    await window.press('\r');
    await until(
      'the picker to close',
      () => !window.frame().includes('Select model'),
    );
    await until('the new model', () => status().includes('Fake Small'));
    expect(!status().includes('Fake Large'), status()).toBeTruthy();
    expect(
      !window.frame().includes('Could not switch'),
      window.frame(),
    ).toBeTruthy();
    expect((await window.session()?.models())?.current).toStrictEqual(
      'fake-small',
    );
    // Opened again, the mark has moved.
    await window.type('/model');
    await window.press('\r');
    await picking(window);
    await window.shows('❯ 2. Fake Small ✔');
    await window.press('1');
    await until('the first model', () => status().includes('Fake Large'));
  }));

test('Esc closes the model picker and the draft takes keys again', () =>
  withWindow(async (window) => {
    await window.shows('Fake Large with a 1M context window');
    await window.type('/model');
    await window.press('\r');
    await picking(window);
    // A letter is not the draft's while the picker is open.
    await window.type('x');
    expect(
      !promptRow(window)?.includes('x'),
      'the draft took a key',
    ).toBeTruthy();
    await window.press(ESC);
    await until(
      'the picker to close',
      () => !window.frame().includes('Select model'),
    );
    await window.type('y');
    await until('the draft', () => promptRow(window)?.includes('› y') ?? false);
    expect((await window.session()?.models())?.current).toStrictEqual(
      'fake-large',
    );
  }));

/**
 * Sessions an earlier chord left in the window's directory, one prompt sent in
 * each, one after another so each is used later than the last; their ids,
 * oldest first.
 */
async function earlierSessions(
  window: Window,
  ...prompts: string[]
): Promise<string[]> {
  return await sessionsIn(window, window.dir, ...prompts);
}

/** The same, in `cwd`, which need not be the window's directory. */
async function sessionsIn(
  window: Window,
  cwd: string,
  ...prompts: string[]
): Promise<string[]> {
  const ids: string[] = [];

  await mkdir(cwd, { recursive: true });

  for (const prompt of prompts) {
    ids.push(
      await recordSession({
        stateDir: join(window.dir, 'state'),
        cwd,
        command: fakeAgentCommand(),
        prompts: [prompt],
      }),
    );
  }

  return ids;
}

/** Waits for the session picker, and for its list to take the keys. */
async function resuming(window: Window): Promise<void> {
  await window.shows('Resume a session');
  await new Promise((resolve) => setTimeout(resolve, 150));
}

test("/resume lists this directory's sessions, and Enter replays one here", () =>
  withWindow(
    async (window) => {
      const [, second] = await earlierSessions(
        window,
        '/echo the first',
        '/echo the second',
        '/echo the third',
      );
      const first = window.session();

      await ready(window);
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));
      await window.type('/resume');
      await window.press('\r');
      await resuming(window);

      const rows = window
        .frame()
        .split('\n')
        .filter((line) => line.includes('/echo the '));

      // Newest first, and not the session on screen.
      expect(rows.length, window.frame()).toStrictEqual(3);
      expect(rows[0]!).toContain('❯ 1. just now');
      expect(rows[0]!).toContain('/echo the third');
      expect(rows[1]!).toContain('/echo the second');
      expect(rows[2]!).toContain('/echo the first');
      await window.press(DOWN);
      await window.shows('❯ 2.');
      await window.press('\r');
      await until('the chosen session', () => window.session() !== first);
      expect(window.session()?.id).toStrictEqual(second);
      // The agent offers `session/resume`, which replays nothing: the past on
      // screen is chord's record.
      await window.shows('› /echo the second');
      await window.shows('⏺ the second');
      expect(
        !window.frame().includes('Resume a session'),
        'the picker stayed',
      ).toBeTruthy();
      expect(
        !window.frame().includes('in chunks'),
        'the old transcript stayed',
      ).toBeTruthy();
      await until('the old agent to stop', () => first?.agentPids.size === 0);
      // It goes on in the session it resumed.
      await send(window, '/echo and on');
      await window.shows('⏺ and on');
      expect(window.session()?.id).toStrictEqual(second);
    },
    { agentCommand: fakeAgentCommand(undefined, '--resume-only') },
  ));

test('Esc closes the session picker and the session stays', () =>
  withWindow(async (window) => {
    await earlierSessions(window, '/echo before');

    const first = window.session();

    await ready(window);
    await window.type('/resume');
    await window.press('\r');
    await resuming(window);
    await window.type('x');
    expect(
      !promptRow(window)?.includes('x'),
      'the draft took a key',
    ).toBeTruthy();
    await window.press(ESC);
    await until(
      'the picker to close',
      () => !window.frame().includes('Resume a session'),
    );
    expect(window.session()).toStrictEqual(first);
    await window.type('y');
    await until('the draft', () => promptRow(window)?.includes('› y') ?? false);
  }));

test('/resume with no earlier session says so', () =>
  withWindow(async (window) => {
    await ready(window);
    await send(window, '/resume');
    await window.shows(
      'No earlier fake session or window to resume, here or in any',
    );
    expect(
      !window.frame().includes('Resume a session'),
      'the picker opened',
    ).toBeTruthy();
  }));

for (const typed of [undefined, 'my-agent --acp']) {
  test(`ctrl+a lists every directory's sessions with their directories, and one from elsewhere is refused with its command, ${typed === undefined ? 'its settings command left to the settings' : 'the typed --agent-command said again'} (Q56)`, () =>
    withWindow(
      async (window) => {
        const [there] = await sessionsIn(
          window,
          join(window.dir, 'other'),
          '/echo over there',
        );

        await earlierSessions(window, '/echo right here');

        const first = window.session();

        await ready(window);
        await window.type('/resume');
        await window.press('\r');
        await resuming(window);
        expect(window.frame()).toContain('/echo right here');
        expect(
          !window.frame().includes('over there'),
          'another directory showed',
        ).toBeTruthy();
        await window.shows('Ctrl+a for all directories');
        await window.press('\x01');
        await window.shows('/echo over there');
        await window.shows('Ctrl+a for this directory');

        const rows = window
          .frame()
          .split('\n')
          .filter((line) => line.includes('/echo '));

        // Newest first, each from ~, which the window was given as the test's
        // directory.
        expect(rows.length, window.frame()).toStrictEqual(2);
        expect(rows[0]!).toContain('~  ');
        expect(rows[0]!).toContain('/echo right here');
        expect(rows[1]!).toContain('~/other');
        expect(rows[1]!).toContain('/echo over there');
        await window.press('2');
        await window.shows(
          'That session is in ~/other. Quit and open it there with:',
        );
        await window.shows(`--resume ${there}`);
        expect(window.frame()).toContain(
          typed === undefined
            ? `chord fake --resume ${there}`
            : `chord fake --agent-command '${typed}' --resume ${there}`,
        );
        expect(
          !window.frame().includes('Resume a session'),
          'the picker stayed',
        ).toBeTruthy();
        expect(window.session()).toStrictEqual(first);
        await window.press('\x01');
        await window.type('y');
        await until(
          'the draft',
          () => promptRow(window)?.includes('› y') ?? false,
        );
      },
      {
        home: (dir) => dir,
        columns: 160,
        ...(typed === undefined ? {} : { typedCommand: typed }),
      },
    ));
}

test('/resume opens on an empty list here when only another directory has sessions', () =>
  withWindow(async (window) => {
    await sessionsIn(window, join(window.dir, 'other'), '/echo over there');
    await ready(window);
    await window.type('/resume');
    await window.press('\r');
    await resuming(window);
    await window.shows('No earlier sessions or windows in this directory.');
    expect(
      !window.frame().includes('Enter to resume'),
      'Enter offered',
    ).toBeTruthy();
    await window.press('\x01');
    await window.shows('/echo over there');
    await window.shows('Enter to resume');
  }));

test('/resume waits for the turn to end', () =>
  withWindow(async (window) => {
    await earlierSessions(window, '/echo before');
    await ready(window);
    await send(window, 'long');
    await window.type('/resume');
    await window.press('\r');
    await window.shows('A turn is running.');
    expect(
      !window.frame().includes('Resume a session'),
      'the picker opened',
    ).toBeTruthy();
  }));

test('a /resume whose read ends after a turn started opens nothing', () => {
  const { promise: released, resolve: release } = Promise.withResolvers<void>();
  let held = false;

  return withWindow(
    async (window) => {
      await earlierSessions(window, '/echo before');

      const first = window.session();

      try {
        await ready(window);
        await window.type('/resume');
        await window.press('\r');
        await until('the read to start', () => held);
        await send(window, 'long');
        await window.shows('Working');
        release();
        await window.shows('A turn is running.');
        expect(
          !window.frame().includes('Resume a session'),
          'the picker opened',
        ).toBeTruthy();
        expect(window.session()).toStrictEqual(first);
      } finally {
        release();
      }
    },
    {
      // Holds this window's read of the records until the turn has started.
      readRecords: async (stateDir) => {
        held = true;

        await released;

        return await readRecords(stateDir);
      },
    },
  );
});

/** `/config` sent, and its picker open on `title` and taking keys. */
async function configuring(window: Window, title = 'Settings') {
  await window.shows('Fake Large with a 1M context window');
  await window.type('/config');
  await window.press('\r');
  await window.shows(title);
  // As with the model picker, the list takes keys an effect after it draws.
  await new Promise((resolve) => setTimeout(resolve, 150));
}

test("/config lists the agent's settings, and Enter on a value sets it", () =>
  withWindow(async (window) => {
    await configuring(window);
    await window.shows('❯ 1. Effort  Medium');
    // The mode and the model have pickers of their own.
    expect(!window.frame().includes('2. '), window.frame()).toBeTruthy();
    expect(
      !promptRow(window)?.includes('/config'),
      'the draft stayed',
    ).toBeTruthy();
    await window.press('\r');
    await window.shows('Set Effort');
    // The highlight starts on the value in use.
    await window.shows('❯ 2. Medium ✔');
    expect(window.frame()).toContain('1. Low');
    expect(window.frame()).toContain('3. High');
    await window.press(DOWN);
    await window.shows('❯ 3. High');
    await window.press('\r');
    // Under the command as typed, as /context reports.
    await window.shows('› /config\n   ⎿  Effort set to High');
    expect(
      !window.frame().includes('Set Effort'),
      'the picker stayed open',
    ).toBeTruthy();
    expect(
      (await window.session()?.options())?.map(({ current }) => current),
    ).toStrictEqual(['high']);
    // Opened again, the list says what it is set to now.
    await window.type('/config');
    await window.press('\r');
    await window.shows('❯ 1. Effort  High');
  }));

test('Esc backs out of /config one level at a time', () =>
  withWindow(async (window) => {
    await configuring(window);
    await window.press('\r');
    await window.shows('Set Effort');
    await window.press(ESC);
    await window.shows('❯ 1. Effort  Medium');
    expect(!window.frame().includes('Set Effort'), window.frame()).toBeTruthy();
    await window.press(ESC);
    await until(
      'the picker to close',
      () => !window.frame().includes('Settings'),
    );
    await window.type('y');
    await until('the draft', () => promptRow(window)?.includes('› y') ?? false);
    // Nothing was set, so nothing is noted.
    expect(!window.frame().includes('set to'), window.frame()).toBeTruthy();
  }));

test('/config says so when the agent has no other settings', () =>
  withWindow(
    async (window) => {
      await configuring(window);
      await window.shows('fake has no settings other than its model and mode.');
      expect(window.frame()).toContain('Esc to close');
      await window.press(ESC);
      await until(
        'the picker to close',
        () => !window.frame().includes('Settings'),
      );
    },
    { agentCommand: fakeAgentCommand(undefined, '--no-config') },
  ));

test('a setting the agent refuses is an error line, and nothing moves', () =>
  withWindow(
    async (window) => {
      await configuring(window);
      await window.press('\r');
      await window.shows('Set Effort');
      await window.press('3');
      await window.shows('› /config\n ⏺ Could not set Effort to High');
      expect(window.frame()).toContain('The fake agent holds its effort.');
      expect(
        !window.frame().includes('set to High'),
        window.frame(),
      ).toBeTruthy();
      expect(
        (await window.session()?.options())?.map(({ current }) => current),
      ).toStrictEqual(['medium']);
    },
    { agentCommand: fakeAgentCommand(undefined, '--refuse-config') },
  ));

/** Waits for `/theme`'s picker, and for its list to take the keys. */
async function theming(window: Window): Promise<void> {
  await window.type('/theme');
  await window.press('\r');
  await window.shows('↑↓ to preview');
  await new Promise((resolve) => setTimeout(resolve, 150));
}

test('/theme keeps the theme Enter picks, saves it and says so', () => {
  const saved: ThemeSetting[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await theming(window);
      await window.shows('❯ 1. Auto (dark: the terminal did not say) ✔');
      await window.shows('2 +   return `hello, ${name}`;');
      await window.shows('Esc to go back to Auto');
      await window.press(DOWN);
      await window.shows('❯ 2. Dark');
      expect(saved, 'a preview saves nothing').toStrictEqual([]);
      await window.press('\r');
      await window.shows('Theme set to Dark');
      expect(saved).toStrictEqual(['dark']);
      expect(
        !window.frame().includes('↑↓ to preview'),
        'the picker stayed',
      ).toBeTruthy();

      // The one in use again changes nothing.
      await theming(window);
      await window.shows('❯ 2. Dark ✔');
      await window.press('\r');
      await until('the picker to close', () => !window.frame().includes('↑↓'));
      expect(saved).toStrictEqual(['dark']);
    },
    {
      saveTheme: (theme) => {
        saved.push(theme);

        return Promise.resolve();
      },
    },
  );
});

test('Esc on /theme goes back to the theme in use and saves nothing', () => {
  const saved: ThemeSetting[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await theming(window);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows('❯ 3. Light');
      await window.press(ESC);
      await until('the picker to close', () => !window.frame().includes('↑↓'));
      expect(saved).toStrictEqual([]);
      expect(
        !window.frame().includes('Theme set'),
        'a note was added',
      ).toBeTruthy();
      await theming(window);
      await window.shows('❯ 1. Auto (dark: the terminal did not say) ✔');
    },
    {
      saveTheme: (theme) => {
        saved.push(theme);

        return Promise.resolve();
      },
    },
  );
});

test('a theme that cannot be saved still lasts the session, and says so', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await theming(window);
      await window.press(DOWN);
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('Could not save the theme to');
      await window.shows(
        '~/.config/chord/settings.json: it is not valid JSON;',
      );
      // The sentence wraps at the window's edge.
      await window.shows('chord quits');
      await theming(window);
      await window.shows('❯ 3. Light ✔');
    },
    {
      saveTheme: () => Promise.reject(new Error('it is not valid JSON')),
    },
  ));

const SERVERS = [
  ...parseServers('.mcp.json', {
    filesystem: { command: 'npx', args: ['-y', 'files'], env: { A: 'b' } },
  }).servers,
  ...parseServers('~/.config/chord/settings.json', {
    docs: {
      type: 'http',
      url: 'https://mcp.example.com/mcp',
      headers: { Authorization: 'Bearer secret' },
    },
  }).servers,
];

test('/mcp lists the servers the agent was given, and Esc closes it', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('/mcp');
      await window.press('\r');
      await window.shows('MCP servers');

      const frame = window.frame();

      expect(frame).toMatch(/filesystem\s+stdio\s+npx -y files\s+\.mcp\.json/);
      expect(frame).toMatch(
        /docs\s+http\s+https:\/\/mcp\.example\.com\/mcp\s+~\/\.config\/chord\/settings\.json/,
      );
      expect(frame).toContain('ACP does not say whether fake connected');
      expect(!frame.includes('secret'), 'a header was shown').toBeTruthy();
      await window.press(ESC);
      await until(
        'the list to close',
        () => !window.frame().includes('MCP servers'),
      );

      // What the list showed is what the agent holds.
      await send(window, 'mcp');
      await window.shows('"url": "https://mcp.example.com/mcp"');
      expect(window.frame()).toContain('"command": "npx"');
    },
    { mcpServers: SERVERS, rows: 60 },
  ));

test('/mcp with no servers says none were passed', () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('/mcp');
    await window.press('\r');
    await window.shows('No MCP servers were passed to fake');
    await window.press(ESC);
    await until(
      'the list to close',
      () => !window.frame().includes('MCP servers'),
    );
    await ready(window);
  }));

test('/mcp says what the files defined that chord did not pass', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('/mcp');
      await window.press('\r');
      await window.shows('2 servers in .mcp.json were ignored');
      expect(window.frame()).toContain('chord said why when it started.');
    },
    {
      mcpServers: SERVERS,
      mcpIgnored: [{ from: '.mcp.json', servers: 2 }],
      rows: 60,
    },
  ));

test('/mcp with every server ignored says so, not that none are defined', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('/mcp');
      await window.press('\r');
      await window.shows('.mcp.json was ignored');

      const frame = window.frame();

      expect(frame).toContain('No MCP servers were passed to fake.');
      expect(
        !frame.includes('none are defined'),
        'the files define some',
      ).toBeTruthy();
    },
    { mcpIgnored: [{ from: '.mcp.json', servers: 'all' }] },
  ));

/** A saved window of `ids`, each a fake session in the window's directory. */
async function savedWindow(
  window: Window,
  id: string,
  ids: readonly string[],
  front: number,
): Promise<void> {
  await writeWindow(join(window.dir, 'state'), {
    id,
    at: Date.now(),
    tabs: ids.map((sessionId) => ({
      sessionId,
      agent: 'fake',
      cwd: window.dir,
    })),
    front,
  });
}

/** The strip's tabs, as the window's top row names them. */
function strip(window: Window): string {
  return window.frame().split('\n')[0] ?? '';
}

test('Enter on a saved window from a fresh chord opens its tabs in order, its front in front, and no empty tab', () => {
  let quit: readonly ResumableTab[] = [];

  return withWindow(
    async (window) => {
      const ids = await earlierSessions(
        window,
        '/echo one',
        '/echo two',
        '/echo three',
      );
      const first = window.session();

      await savedWindow(window, 'w-0a1b2c3d', ids, 1);
      await ready(window);
      await window.type('/resume');
      await window.press('\r');
      await resuming(window);
      await window.shows('❯ 1. just now');
      await window.shows('▣ 3 sessions · fake, fake, fake · /echo two');
      await window.press('\r');
      // Only the front tab's past is drawn: the recorded front's.
      await window.shows('› /echo two');
      expect(
        !window.frame().includes('› /echo one'),
        window.frame(),
      ).toBeTruthy();
      expect(strip(window)).toContain('1 fake');
      expect(strip(window)).toContain('3 fake');
      expect(!strip(window).includes('4 fake'), strip(window)).toBeTruthy();
      // The empty tab gave its place, and its agent went.
      await until('the empty tab to close', () => first?.agentPids.size === 0);
      await until('three agents beside it', () => window.pids.length === 4);
      await quitAll(window);
      expect(quit.map(({ sessionId }) => sessionId)).toStrictEqual(ids);
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--resume-only'),
      columns: 120,
      onQuit: (tabs) => {
        quit = tabs;
      },
    },
  );
});

test('Enter on a saved window beside a session in use adds its tabs at the end, and opens none that is open', () => {
  let quit: readonly ResumableTab[] = [];

  return withWindow(
    async (window) => {
      const ids = await earlierSessions(window, '/echo one', '/echo two');

      await savedWindow(window, 'w-0a1b2c3d', ids, 0);
      await ready(window);
      await send(window, '/echo here');
      await window.shows('⏺ here');

      const here = window.session()?.id;

      await window.type('/resume');
      await window.press('\r');
      await resuming(window);
      await window.press('1');
      await window.shows('› /echo one');
      await window.shows('3 fake');
      expect(
        !window.frame().includes('› /echo here'),
        window.frame(),
      ).toBeTruthy();
      await until('two agents beside it', () => window.pids.length === 3);
      // Again: every tab of it is open, so Enter goes to its front tab.
      await leader(window, '1');
      await window.shows('› /echo here');
      await window.type('/resume');
      await window.press('\r');
      await resuming(window);
      await window.shows('▣ 2 sessions, all open · fake, fake · /echo one');
      await window.press('1');
      await window.shows('› /echo one');
      expect(
        !window.frame().includes('› /echo here'),
        window.frame(),
      ).toBeTruthy();
      await new Promise((resolve) => setTimeout(resolve, 500));
      expect(window.pids.length).toStrictEqual(3);
      await quitAll(window);
      expect(quit.map(({ sessionId }) => sessionId)).toStrictEqual([
        here!,
        ...ids,
      ]);
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--resume-only'),
      columns: 120,
      onQuit: (tabs) => {
        quit = tabs;
      },
    },
  );
});

test('a saved window past the cap of nine opens none of its tabs, and the status line says how many to close', () =>
  withWindow(
    async (window) => {
      const records = join(window.dir, 'state', 'records');
      const ids = Array.from({ length: 9 }, () => crypto.randomUUID());

      await mkdir(records, { recursive: true });

      // Records written as chord writes them; none is opened.
      for (const [index, sessionId] of ids.entries()) {
        await writeFile(
          join(records, `${sessionId}.jsonl`),
          [
            {
              type: 'session',
              version: 1,
              sessionId,
              agent: 'fake',
              cwd: window.dir,
              at: 1,
            },
            {
              type: 'prompt',
              turnId: 't',
              at: 2,
              prompt: `part ${index}`,
              images: 0,
            },
          ]
            .map((line) => JSON.stringify(line))
            .join('\n') + '\n',
        );
      }

      await savedWindow(window, 'w-0a1b2c3d', ids, 0);
      await ready(window);
      await send(window, 'text');
      await window.shows('This reply came in chunks.');

      const here = window.session();

      await window.type('/resume');
      await window.press('\r');
      await resuming(window);
      await window.shows('▣ 9 sessions · fake ×9 · part 0');
      await window.press('1');
      await window.shows(
        'That window needs 9 tabs and 8 are free · close 1 with ctrl+x k, then /resume again',
      );
      await new Promise((resolve) => setTimeout(resolve, 500));
      expect(window.pids.length).toStrictEqual(1);
      expect(window.session()).toStrictEqual(here);
    },
    { columns: 120 },
  ));

test("a setting's name keeps the agent's colours in its heading and explanation", async () => {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <ConfigPicker
        options={[]}
        option={{
          id: 'x',
          name: '\x1b[31mRED\x1b[0m',
          values: [],
          current: 'x',
        }}
        from={undefined}
        agent='fake'
        rows={5}
        active={false}
        onOpen={() => {}}
        onPick={() => {}}
      />,
      { columns: 80, rows: 24 },
    );
    const shown = drawn.frame();

    await drawn.unmount();
    expect(shown).toContain('\x1b[31m');
    expect(stripAnsi(shown)).toContain('Set RED');
    expect(stripAnsi(shown)).toContain("Choose fake's RED for this session.");
    expect(stripAnsi(shown)).not.toMatch(/\[\d*m/);
  } finally {
    chalk.level = level;
  }
});
