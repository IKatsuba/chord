import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import {
  type RequestScroller,
  PermissionPrompt,
} from '../../../src/ui/dialogs/Permission.tsx';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { parseTeam } from '../../../src/teams.ts';
import {
  asked,
  DOWN,
  END,
  ESC,
  left,
  leader,
  promptRow,
  send,
  until,
  UP,
  withWindow,
} from '../app/render.tsx';

test("a permission request shows the agent's options, numbered", () =>
  withWindow(async (window) => {
    await send(window, 'permission');
    await asked(window);

    const frame = window.frame();

    expect(frame).toContain('Write notes.txt');
    expect(frame).toContain('❯ 1. Allow');
    expect(frame).toContain('  2. Always allow');
    expect(frame).toContain('  3. Deny');
    expect(frame).toContain('Waiting for permission…');
    expect(
      !frame.includes('file_path'),
      'a request with content showed its input',
    ).toBeTruthy();
    await window.press('1');
    await window.shows('Allowed Write notes.txt · Allow');
    await window.shows('Permission: allow.');
  }));

test("an MCP call's arguments show under its name before it is allowed", () =>
  withWindow(async (window) => {
    // Not `send`: the box is tall enough to push the prompt's row off the
    // screen as soon as it comes, so that row may never be seen.
    await window.type('mcpask');
    await window.press('\r');
    await asked(window);

    const frame = window.frame();

    expect(frame).toContain('mcp__chord__monitor');
    expect(frame).toContain(
      '  command: tail -f dev.log | grep --line-buffered -E "ERROR|WARN"',
    );
    expect(frame).toContain('  description: dev server errors');
    expect(frame).toContain('  timeout_ms: 600000');
    await window.press('1');
    await window.shows('Permission: allow.');
  }));

test('a number key picks its option', () =>
  withWindow(async (window) => {
    await send(window, 'permission');
    await asked(window);
    await window.press('2');
    await window.shows('Allowed Write notes.txt · Always allow');
    await window.shows('Permission: always.');
    expect(
      !window.frame().includes('Do you want'),
      'the prompt stayed up',
    ).toBeTruthy();
  }));

test('arrows move the highlight and Enter picks it', () =>
  withWindow(async (window) => {
    await send(window, 'permission');
    await asked(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('❯ 3. Deny');
    await window.press(UP);
    await window.shows('❯ 2. Always allow');
    await window.press(DOWN);
    await window.press('\r');
    await window.shows('Rejected Write notes.txt');
    await window.shows('Permission: deny.');
  }));

test('Esc rejects the request, the turn goes on, the prompt works', () =>
  withWindow(async (window) => {
    await send(window, 'permission');
    await asked(window);
    await window.press(ESC);
    await window.shows('Rejected Write notes.txt');
    await window.shows('Permission: deny.');
    expect(
      !window.frame().includes('Interrupted'),
      'Esc interrupted the turn',
    ).toBeTruthy();
    await until('the turn to end', () => !window.frame().includes('Working'));
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
  }));

test('keys typed while a permission is asked stay out of the draft', () =>
  withWindow(async (window) => {
    await send(window, 'permission');
    await asked(window);
    await window.type('xyz');
    await window.press('3');
    await window.shows('Permission: deny.');
    expect(
      !window.frame().includes('xyz'),
      'the draft took the keys',
    ).toBeTruthy();
  }));

/** Runs `body` in a window whose agent has chord's server. */
async function withServer(body: Parameters<typeof withWindow>[0]) {
  const server = serveChord();

  try {
    await withWindow(body, {
      server,
      runtimes: ['fake', 'claude', 'codex'],
      rows: 60,
      columns: 120,
    });
  } finally {
    await server.close();
  }
}

test("propose_team's team is drawn as a table, and saved where the person picks, by chord", () =>
  withServer(async (window) => {
    await send(window, 'propose');
    await window.shows('Save team bugfix?');
    await new Promise((resolve) => setTimeout(resolve, 150));

    const frame = window.frame();

    expect(frame).toContain('Team(bugfix) · proposal');
    expect(frame).toContain(
      'coder     codex · gpt-5.3-codex  auto         Writes the fix',
    );
    expect(frame).toContain('❯ 1. Yes, for this project');
    expect(frame).toContain('.chord/teams/bugfix.md');
    // The window has no config directory, so no choice for every project.
    expect(frame).toContain('2. No, tell fake what to change');
    expect(frame).toContain('Esc to tell fake what to change');
    expect(frame).toContain('Waiting for you…');
    expect(!frame.includes('Do you want to proceed?')).toBeTruthy();

    await window.press('1');
    await window.shows(
      'Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it a job',
    );
    await window.shows('bugfix is saved for this project.');

    const read = parseTeam(
      'bugfix',
      await readFile(join(window.dir, '.chord', 'teams', 'bugfix.md'), 'utf8'),
      ['claude', 'codex'],
    );

    assert('team' in read);
    expect(read.team.members.map((member) => member.mode)).toStrictEqual([
      'acceptEdits',
      'auto',
      'plan',
    ]);
    // The answer is on the call, with no line of its own.
    expect(!window.frame().includes('Allowed')).toBeTruthy();

    // The person's words change it: a change to the team saved.
    await send(window, 'put the reviewer on codex too');
    await window.shows('Replace team bugfix?');
    await window.shows('Team(bugfix) · change');
    await window.shows('~  reviewer  codex · gpt-5.3-codex');
    await window.shows('without asking, and the lead reports to main.');
  }));

test('Esc on the save box saves nothing, and the person says what to change', () =>
  withServer(async (window) => {
    await send(window, 'propose');
    await window.shows('Save team bugfix?');
    await new Promise((resolve) => setTimeout(resolve, 150));
    await window.press(ESC);
    await window.shows('Not saved · the person will say what to change');
    await until('the turn to end', () => !window.frame().includes('Waiting'));

    const teams = join(window.dir, '.chord', 'teams');

    expect(
      await stat(teams).then(
        () => false,
        () => true,
      ),
      'a team was saved',
    ).toBeTruthy();

    await send(window, 'let the tester run the suite without asking');
    await window.shows('Save team bugfix?');
    await window.shows('bypassPermissions');
  }));

test("a proposal's efforts are a column, saved to the file, and a change says each one it had", () =>
  withServer(async (window) => {
    await send(window, 'proposeefforts');
    await window.shows('Save team bugfix?');
    await window.shows(
      'tester    claude · sonnet        medium  acceptEdits  Writes the',
    );
    await window.shows(
      'coder     codex · gpt-5.3-codex  —       auto         Writes the fix',
    );
    await window.press('1');
    await window.shows('bugfix is saved for this project.');

    const read = parseTeam(
      'bugfix',
      await readFile(join(window.dir, '.chord', 'teams', 'bugfix.md'), 'utf8'),
      ['claude', 'codex'],
    );

    assert('team' in read);
    expect(read.team.lead.effort).toStrictEqual('high');
    expect(read.team.members.map((member) => member.effort)).toStrictEqual([
      'medium',
      undefined,
      undefined,
    ]);

    await send(window, 'more effort on the work');
    await window.shows('Replace team bugfix?');
    await window.shows(
      '~  tester    claude · sonnet        high was medium  bypassPermissions was acceptEdits',
    );
    await window.shows('~  coder     codex · gpt-5.3-codex  xhigh was —');
  }));

test("the subagent that asks keeps the agent's colours in its title", async () => {
  const level = chalk.level;

  chalk.level = 3;

  try {
    const drawn = await draw(
      <PermissionPrompt
        wait={{ id: 'p', title: 'Write', options: [] }}
        asker={[
          {
            id: 's',
            title: '\x1b[31mRED\x1b[0m',
            state: 'running',
            entries: [],
            plan: [],
          },
        ]}
        width={76}
        active={false}
        onChoose={() => {}}
      />,
      { columns: 80, rows: 24 },
    );
    const shown = drawn.frame();

    await drawn.unmount();
    expect(shown).toContain('\x1b[31m');
    expect(stripAnsi(shown)).toContain('RED');
    expect(stripAnsi(shown)).not.toMatch(/\[\d*m/);
  } finally {
    chalk.level = level;
  }
});

const PAGE_DOWN = '\x1b[6~';
const HOME = '\x1b[H';
const SHIFT_DOWN = '\x1b[1;2B';
/** An SGR wheel report, `up` or down, at the 0-based cell `x`, `y`. */
const wheel = (x: number, y: number, up: boolean) =>
  `\x1b[<${up ? 64 : 65};${x + 1};${y + 1}M`;

/** The permission box's rows in `frame`, its borders included. */
function boxRows(frame: string): string[] {
  const lines = stripAnsi(frame).split('\n');
  // The box's own title row, not the transcript's call above it.
  const title = lines.findIndex((line) =>
    line.startsWith('│ mcp__files__write'),
  );
  const end = lines.findIndex(
    (line, index) => index > title && /^╰/.test(line),
  );

  return lines.slice(title - 1, end + 1).map((line) => line.trimEnd());
}

/** The box as designer's mock of `state` draws it (docs/design/CHD-246.md). */
async function mock(state: string): Promise<string[]> {
  const path = join(
    import.meta.dir,
    `../../../docs/design/evidence/CHD-246/mock/${state}.txt`,
  );

  return boxRows(await readFile(path, 'utf8'));
}

/** Waits for the box to draw `rows`, and says what it drew instead. */
async function draws(
  window: Awaited<Parameters<Parameters<typeof withWindow>[0]>[0]>,
  rows: string[],
): Promise<void> {
  await until('the box as the mock draws it', () =>
    Bun.deepEquals(boxRows(window.frame()), rows),
  ).catch(() => {
    expect(boxRows(window.frame())).toStrictEqual(rows);
  });
}

for (const [columns, rows] of [
  [80, 24],
  [120, 40],
] as const) {
  test(`a request taller than its room scrolls under its pinned title, the answers whole, at ${columns}×${rows}`, () =>
    withWindow(
      async (window) => {
        await send(window, 'bigask');
        await asked(window);
        await draws(window, await mock(`top-${columns}x${rows}`));
        // The prompt box and the status line are still on screen.
        expect(window.frame()).toContain('? for shortcuts');

        await window.press(END);
        await draws(window, await mock(`end-${columns}x${rows}`));
      },
      { columns, rows },
    ));
}

test('the scroll keys move a request that overflows: a page, a row, its top and its end', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);
      await window.shows('── ↓ 37 lines below · pagedown to scroll');

      // A page is the request's room, six rows, less one.
      await window.press(PAGE_DOWN);
      await window.shows('── ↑ 5 lines above · pageup to scroll');
      await window.shows('── ↓ 33 lines below');
      await window.press(SHIFT_DOWN);
      await window.shows('── ↑ 6 lines above');
      await window.press(HOME);
      await window.shows('── ↓ 37 lines below');
      expect(window.frame()).not.toContain('lines above');
      await window.press(END);
      await window.shows('── ↑ 37 lines above');
      expect(window.frame()).toContain('mode: overwrite');
      // The answers still take their keys.
      await window.press(DOWN);
      await window.shows('❯ 2. Yes');
    },
    { columns: 80, rows: 24 },
  ));

test('the wheel over the request scrolls it, and over the transcript the transcript', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);
      await window.shows('── ↓ 22 lines below');

      const lines = stripAnsi(window.frame()).split('\n');
      const over = lines.findIndex((line) => line.includes('Change 3:'));

      await window.press(wheel(10, over, false));
      await window.shows('── ↑ 1 line above');
      // The transcript was not moved by it.
      expect(window.frame()).not.toContain('end to jump to the bottom');

      await window.press(wheel(10, 1, true));
      await window.shows('end to jump to the bottom');
      expect(window.frame()).toContain('── ↑ 1 line above');
    },
    { columns: 120, rows: 40 },
  ));

test('a request that fits has no rule, and the scroll keys keep the transcript', () =>
  withWindow(
    async (window) => {
      await send(window, 'mcpask');
      await asked(window);
      expect(window.frame()).not.toContain('to scroll');
      expect(window.frame()).toContain('timeout_ms: 600000');
    },
    { columns: 80, rows: 24 },
  ));

test('a window of 19 rows leaves the request one row, its count beside the title, and every answer', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);

      const box = boxRows(window.frame());

      // No rule fits, so the count goes at the pinned row's end.
      expect(box[1]).toStrictEqual(
        '│ mcp__files__write_file                                      ↓ 41 lines below │',
      );
      expect(box[2]).toContain('path: docs/release.md');
      expect(box.slice(1, -1).join('\n')).not.toContain('──');
      expect(box.join('\n')).toContain('3. No, and tell Claude');
      expect(box.join('\n')).toContain('Esc to reject');

      // A room of one row: a page is a row, and end still goes to the end.
      await window.press(PAGE_DOWN);
      await window.shows('content: # Release 0.56.0');
      await window.shows('↑ 1 above · ↓ 40 below');
      await window.press(END);
      await window.shows('mode: overwrite');
      await window.shows('↑ 41 lines above');
    },
    { columns: 80, rows: 19 },
  ));

test('pgdn page after page shows every row of the request, none passed over', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);

      const seen = new Set<string>();

      for (let page = 0; page < 20; page++) {
        for (const row of boxRows(window.frame())) {
          seen.add(row);
        }

        if (window.frame().includes('mode: overwrite')) {
          break;
        }

        const before = boxRows(window.frame()).join('\n');

        await window.press(PAGE_DOWN);
        await until(
          'the page to move',
          () => boxRows(window.frame()).join('\n') !== before,
        );
      }

      for (let change = 1; change <= 30; change++) {
        expect(
          [...seen].some((row) => row.includes(`Change ${change}:`)),
          `Change ${change} never shown`,
        ).toBeTruthy();
      }
    },
    { columns: 80, rows: 24 },
  ));

test('a resize lays the request out again, its top row kept and its answers whole', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);
      await window.press(END);
      await window.shows('mode: overwrite');
      await window.resize({ columns: 80, rows: 24 });
      // The top row stays where the new room lets it; the answers are whole.
      await window.shows('── ↑ 22 lines above');
      await window.shows('── ↓ 16 lines below');

      const box = boxRows(window.frame()).join('\n');

      expect(box).toContain('3. No, and tell Claude');
      expect(box).toContain('│ Esc to reject');
      expect(window.frame()).toContain('? for shortcuts');
    },
    { columns: 120, rows: 40 },
  ));

test('a click on the request leaves the keys with the answers', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigask');
      await asked(window);

      const lines = stripAnsi(window.frame()).split('\n');
      const over = lines.findIndex((line) => line.includes('content:'));

      await window.press(left(10, over, 'down'));
      await window.press(left(10, over, 'up'));
      await window.press(DOWN);
      await window.shows('❯ 2. Yes');
      await window.press(PAGE_DOWN);
      await window.shows('── ↑ 5 lines above');
    },
    { columns: 80, rows: 24 },
  ));

describe('CHD-246 tester: long-title paging regression', () => {
  test('a one-row room keeps every word of a long title reachable beside its count', async () => {
    const title = Array.from(
      { length: 60 },
      (_, index) => `word${index + 1}`,
    ).join(' ');
    const scroller: { current: RequestScroller | undefined } = {
      current: undefined,
    };
    const drawn = await draw(
      <box height={12}>
        <PermissionPrompt
          wait={{
            id: 'long-title',
            title,
            rawInput: { mode: 'overwrite' },
            options: [
              { optionId: 'allow', name: 'Yes', kind: 'allow_once' },
              { optionId: 'always', name: 'Always', kind: 'allow_always' },
              { optionId: 'deny', name: 'No', kind: 'reject_once' },
            ],
          }}
          width={76}
          active
          onChoose={() => {}}
          scroller={scroller}
        />
      </box>,
      { columns: 80, rows: 19 },
    );

    try {
      await until('a one-row title count', () =>
        drawn.frame().includes('lines below'),
      );

      const seen = new Set<string>();

      for (let page = 0; page < 30; page++) {
        const frame = stripAnsi(drawn.frame());

        for (const word of frame.matchAll(/word\d+/g)) {
          seen.add(word[0]);
        }

        expect(frame).toContain('Esc to reject');
        expect(frame).toContain('3. No');

        if (frame.includes('mode: overwrite')) {
          break;
        }

        const before = frame;

        scroller.current?.('page_down');
        await drawn.write('');
        await until(
          'the one-row request moves',
          () => stripAnsi(drawn.frame()) !== before,
        );
      }

      expect(seen).toEqual(new Set(title.split(' ')));
      expect(stripAnsi(drawn.frame())).toContain('mode: overwrite');
    } finally {
      await drawn.unmount();
    }
  });
});

describe('CHD-246 tester: request lifecycle and small rooms', () => {
  for (const [key, outcome] of [
    ['1', 'allow'],
    ['2', 'always'],
    ['3', 'deny'],
    [ESC, 'deny'],
  ] as const) {
    test(`answers ${outcome} at the unread top with ${JSON.stringify(key)}`, () =>
      withWindow(
        async (window) => {
          await send(window, 'bigask');
          await asked(window);
          expect(window.frame()).toContain('↓ 37 lines below');
          expect(window.frame()).not.toContain('mode: overwrite');
          await window.press(key);
          await window.shows(`Permission: ${outcome}.`);
          expect(window.frame()).not.toContain('Do you want to proceed?');
        },
        { columns: 80, rows: 24 },
      ));
  }

  test('two sessions answer their own overflowing requests independently', () =>
    withWindow(
      async (window) => {
        await send(window, 'bigask');
        await asked(window);
        await window.press(END);
        await window.shows('mode: overwrite');
        await leader(window, 'c');
        await window.shows('Fake Large with a 1M context window');
        await send(window, 'bigask');
        await asked(window);
        expect(window.frame()).toContain('path: docs/release.md');
        expect(window.frame()).not.toContain('mode: overwrite');
        await window.press(PAGE_DOWN);
        await window.shows('lines above');
        await leader(window, '1');
        await asked(window);
        await window.press('1');
        await window.shows('Permission: allow.');
        await leader(window, '2');
        await asked(window);
        expect(window.frame()).not.toContain('Permission: allow.');
        await window.press(ESC);
        await window.shows('Permission: deny.');
      },
      { columns: 80, rows: 24 },
    ));

  test('resizing signals every hidden side and keeps every row reachable', () =>
    withWindow(
      async (window) => {
        await send(window, 'bigask');
        await asked(window);
        await window.resize({ rows: 19 });
        await window.shows('↓ 41 lines below');
        await window.press(END);
        await window.shows('mode: overwrite');
        await window.resize({ columns: 120, rows: 40 });
        await until('resize leaves a signalled request', () => {
          const box = boxRows(window.frame()).join('\n');

          return (
            (box.includes('path: docs/release.md') ||
              box.includes('lines above')) &&
            (box.includes('mode: overwrite') || box.includes('lines below'))
          );
        });

        expect(window.frame()).toContain('3. No, and tell Claude');
        expect(window.frame()).toContain('Esc to reject');
        await window.press(END);
        await window.shows('mode: overwrite');
        expect(boxRows(window.frame()).join('\n')).not.toContain('lines below');
        await window.press(HOME);
        await window.shows('path: docs/release.md');
        expect(boxRows(window.frame()).join('\n')).not.toContain('lines above');
        await window.resize({ rows: 120 });
        await until('the whole request fits', () => {
          const box = boxRows(window.frame()).join('\n');

          return (
            box.includes('path: docs/release.md') &&
            box.includes('mode: overwrite') &&
            !box.includes('lines above')
          );
        });

        await window.press('1');
        await window.shows('Permission: allow.');
      },
      { columns: 80, rows: 24 },
    ));
});

describe('CHD-246 tester: queued large permission requests', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`the second concurrent request opens at the top after the first ends at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'bigasktwice');
          await asked(window);
          expect(window.frame()).toContain('path: docs/release.md');
          await window.press(END);
          await window.shows('mode: overwrite');
          await window.press('1');
          await window.shows('path: docs/changes.md');
          await asked(window);

          const next = boxRows(window.frame()).join('\n');

          expect(next).toContain('content: # Release 0.56.0');
          expect(next).toContain('lines below');
          expect(next).not.toContain('lines above');
          expect(next).not.toContain('mode: append');
          await window.press(ESC);
          await window.shows('Permission: deny.');
          await window.shows('Permission: allow.');
          expect(window.frame()).not.toContain('Do you want to proceed?');
        },
        { columns, rows },
      ));
  }
});

describe('a request between turns (CHD-158)', () => {
  test("a subagent's waits without the keys until ctrl+x a, a typed digit going to the draft, then its form the same", () =>
    withWindow(async (window) => {
      await send(window, 'claudebetween');
      await window.shows(
        'Agent(tester (general-purpose)) asks · between turns',
      );
      await window.shows('ctrl+x a to answer');

      let frame = window.frame();

      expect(frame).toMatch(
        /● permission( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(frame).not.toContain('❯ 1. Allow');
      expect(frame).not.toContain('Esc to reject');

      // A digit typed for the prompt is the draft's, not an answer.
      await window.type('2');
      expect(promptRow(window)).toContain('› 2');
      expect(window.frame()).toContain('1. Allow');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.shows('Esc to reject');
      expect(promptRow(window)).toContain('› 2');
      await window.press('1');

      // The form after it waits the same way, above the prompt.
      await window.shows(
        'Agent(tester (general-purpose)) asks for input · between turns',
      );

      frame = window.frame();

      expect(frame).toContain('ctrl+x a to answer');
      expect(frame).toMatch(
        /● input( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(promptRow(window)).toContain('› 2');
      await leader(window, 'a');
      await window.press(ESC);
      await window.shows('⏺ fake asked: Which suite should run next?');
      expect(promptRow(window)).toContain('› 2');
    }));

  test("the session's own agent is named, and answered once the keys are in", () =>
    withWindow(async (window) => {
      await send(window, 'mainbetween');
      await window.shows('main asks · between turns');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('2');
      await window.shows('Permission: deny.');
      expect(window.frame()).not.toContain('between turns');
    }));

  test('a held form names who asks and shows no ❯ until ctrl+x a', () =>
    withWindow(async (window) => {
      await send(window, 'claudebetween');
      await window.shows('ctrl+x a to answer');
      await leader(window, 'a');
      await window.press('1');
      await window.shows(
        'Agent(tester (general-purpose)) asks for input · between turns',
      );

      const held = window.frame();

      expect(held).toContain('ctrl+x a to answer');
      expect(held).not.toContain('❯');
      await leader(window, 'a');
      await window.shows('❯   Suite');
      await window.press(ESC);
      await window.shows('⏺ fake asked: Which suite should run next?');
    }));

  test('with session:attention unbound, the box takes the keys at once, as in a turn', () =>
    withWindow(
      async (window) => {
        await send(window, 'mainbetween');
        await window.shows('main asks · between turns');
        await window.shows('❯ 1. Allow');

        const frame = window.frame();

        expect(frame).toContain('Esc to reject');
        expect(frame).not.toContain('to answer');
        await window.press('2');
        await window.shows('Permission: deny.');
      },
      {
        keybindings: JSON.stringify({
          bindings: [{ context: 'Global', bindings: { 'ctrl+x a': null } }],
        }),
      },
    ));

  test('the asker row wraps rather than cut at a narrow width', () =>
    withWindow(
      async (window) => {
        await send(window, 'claudebetween');
        await window.shows('ctrl+x a to answer');

        const frame = window.frame();

        expect(frame).toContain('Agent(tester (general-purpose)) asks');
        expect(frame).toContain('between turns');
        // Never cut from the left, as the row in a turn was.
        expect(frame).not.toMatch(/│ …/);
      },
      { columns: 44 },
    ));
});

describe('a prompt sent while a request waits between turns (CHD-158)', () => {
  test('waits in the queue after your answer, and goes once answered', () =>
    withWindow(async (window) => {
      await send(window, 'mainbetween');
      await window.shows('main asks · between turns');
      await window.type('text');
      await window.press('\r');
      await window.shows('› after your answer: text');
      // The request still waits, on the person.
      expect(window.frame()).toContain('main asks · between turns');
      await leader(window, 'a');
      await window.press('1');
      await window.shows('Permission: allow.');
      // The held prompt goes once the agent has gone quiet, and is answered.
      await window.shows('Hello, world.');

      const frame = window.frame();

      expect(frame).not.toContain('after your answer');
      // The answer's follow-up is a block of its own, above the prompt.
      expect(frame).toMatch(
        /⏺ Permission: allow\.\n\n › text\n\n ⏺ Hello, world\./,
      );
    }));
});

describe('CHD-158 tester: attendance in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const focus of ['search', 'sessions'] as const) {
      test(`attention answers from ${focus} and preserves the draft at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await send(window, 'mainbetween');
            await window.shows('ctrl+x a to answer');
            await window.type('keep-this-draft');

            if (focus === 'search') {
              await window.press('\x12');
              await window.shows('search prompts:');
            } else {
              await leader(window, 'w');
              await window.shows('Enter to go');
            }

            await window.press('\x18');
            await window.press('a');
            await window.shows('❯ 1. Allow');
            expect(window.frame()).not.toContain('search prompts:');
            expect(window.frame()).not.toContain('Enter to go');
            expect(promptRow(window)).toContain('keep-this-draft');
            await window.press(ESC);
            await window.shows('Permission: deny.');
            expect(promptRow(window)).toContain('keep-this-draft');
          },
          { columns, rows },
        ));
    }
  }

  test('a second queued permission needs its own attendance before a digit can answer it', () =>
    withWindow(async (window) => {
      const session = window.session();

      assert(session);

      const request = (id: string) =>
        session.permissions.handler(
          {
            sessionId: session.id,
            toolCall: { toolCallId: id, title: `Write ${id}.md` },
            options: [
              { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
            ],
          },
          new AbortController().signal,
        );
      const first = request('first');
      const second = request('second');

      await window.shows('Write first.md');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      expect(await first).toStrictEqual({
        outcome: { outcome: 'selected', optionId: 'allow' },
      });
      await window.shows('Write second.md');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');
      await window.type('2');
      expect(promptRow(window)).toContain('› 2');
      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('2');
      expect(await second).toStrictEqual({
        outcome: { outcome: 'selected', optionId: 'deny' },
      });
      await until(
        'the second permission to close',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      expect(promptRow(window)).toContain('› 2');
    }));
});

describe('CHD-158 tester: agent and task requesters', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`attention takes the keys from agents focus at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'agents');
            await window.shows('All 214 parser tests pass now.');
            await until(
              'the parent to finish its replies',
              () => !window.frame().includes('Working…'),
            );
            await send(window, 'mainbetween');
            await window.shows('main asks · between turns');
            await window.press(DOWN);
            await window.shows('❯ main');
            await window.press('\x18');
            await window.press('a');
            await window.shows('❯ 1. Allow');
            expect(window.frame()).not.toContain('❯ main');
            await window.press(ESC);
            await window.shows('Permission: deny.');
            await window.type('after-focus');
            expect(promptRow(window)).toContain('after-focus');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });

    test(`a spawn_task permission is held with its requester named after the parent ends at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            const parent = window.session()!;
            const prompt = parent.prompt.bind(parent);
            let ended = false;

            parent.prompt = (...args) => {
              const turn = prompt(...args);

              void turn.result.then(() => {
                ended = true;
              });

              return turn;
            };

            await send(window, 'taskbetween');
            await window.shows(
              'Agent(Fix the tokenizer) · fake asks · between turns',
            );
            await window.shows('ctrl+x a to answer');
            expect(ended).toBe(true);
            expect(window.frame()).not.toContain('❯ 1. Allow');
            await window.type('3');
            expect(promptRow(window)).toContain('› 3');
            await leader(window, 'a');
            await window.shows('❯ 1. Allow');
            await window.press('1');
            await window.shows(
              'Received the message from Fix the tokenizer · fake · report.',
            );
            expect(promptRow(window)).toContain('› 3');
            expect(window.frame()).not.toContain('ctrl+x a to answer');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-158 tester: queued requests in the window', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const mode of ['form', 'url'] as const) {
      test(`${mode}: a queued prompt stays held until the attended request is cancelled at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            const session = window.session()!;
            const answer = session.elicitations.handler(
              mode === 'form'
                ? {
                    sessionId: session.id,
                    mode: 'form',
                    message: 'Choose a target',
                    requestedSchema: { type: 'object', properties: {} },
                  }
                : {
                    sessionId: session.id,
                    mode: 'url',
                    message: 'Approve a target',
                    url: 'https://example.com/approve',
                    elicitationId: 'queued-link',
                  },
              new AbortController().signal,
            );

            await window.shows('ctrl+x a to answer');
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('between turns');
            await leader(window, 'a');
            await window.press(ESC);
            expect(await answer).toStrictEqual({ action: 'cancel' });
            await window.shows('Hello, world.');
            expect(window.frame()).not.toContain('after your answer');
            expect(window.frame()).not.toContain('ctrl+x a to answer');
          },
          { columns, rows },
        ));
    }

    test(`an incoming agent message and the person’s prompt retain their order after answering at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Parameters<typeof admit>[0] | undefined;
      let child: Parameters<typeof admit>[0] | undefined;

      server.admit = (caller) => {
        if (caller.agent === undefined) {
          main = caller;
        } else {
          child = caller;
        }

        return admit(caller);
      };

      try {
        await withWindow(
          async (window) => {
            assert(main);
            await main.window.open(main.key, {
              agent: 'fake',
              name: 'sender',
              prompt: 'text',
            });
            assert(child);
            await send(window, 'mainbetween');
            await window.shows('main asks · between turns');
            expect(
              child.window.message(child, 'Check the queued report.', () => {}),
            ).toMatchObject({ delivered: 'queued' });
            await window.shows('← from @sender · fake · after your answer:');
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('main asks · between turns');
            await leader(window, 'a');
            await window.press('1');
            await window.shows('Received the message from sender · fake.');
            await window.shows('Hello, world.');

            const frame = window.frame();

            expect(frame).not.toContain('after your answer');
            expect(frame.indexOf('Permission: allow.')).toBeLessThan(
              frame.indexOf('Received the message from sender'),
            );
            expect(
              frame.indexOf('Received the message from sender'),
            ).toBeLessThan(frame.indexOf('› text'));
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });

    test(`a task’s between-turn permission holds the queued prompt at ${columns} columns`, async () => {
      const server = serveChord();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'taskbetween');
            await window.shows(
              'Agent(Fix the tokenizer) · fake asks · between turns',
            );
            await window.type('text');
            await window.press('\r');
            await window.shows('› after your answer: text');
            expect(window.frame()).toContain('ctrl+x a to answer');
            await leader(window, 'a');
            await window.press('1');
            await window.shows('Hello, world.');
            expect(window.frame()).not.toContain('› after your answer: text');
          },
          { server, runtimes: ['fake'], columns, rows },
        );
      } finally {
        await server.close();
      }
    });
  }
});

describe('CHD-158 tester: interrupting a mixed held queue', () => {
  test('Esc restores the typed prompt but keeps the agent message marked after your answer', async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    let child: Parameters<typeof admit>[0] | undefined;

    server.admit = (caller) => {
      if (caller.agent === undefined) {
        main = caller;
      } else {
        child = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          assert(main);
          await main.window.open(main.key, {
            agent: 'fake',
            name: 'sender',
            prompt: 'text',
          });
          assert(child);
          await send(window, 'mainbetween');
          await window.shows('main asks · between turns');
          await window.type('My queued prompt.');
          await window.press('\r');
          await window.shows('› after your answer: My queued prompt.');
          child.window.message(child, 'Agent message stays.', () => {});

          await window.shows('← from @sender · fake · after your answer:');
          await window.press(ESC);
          expect(promptRow(window)).toContain('My queued prompt.');
          expect(window.frame()).toContain('main asks · between turns');
          expect(window.frame()).toContain(
            '← from @sender · fake · after your answer:',
          );
        },
        { server, runtimes: ['fake'], columns: 120, rows: 40 },
      );
    } finally {
      await server.close();
    }
  });
});

describe("a permission left open at its turn's end (CHD-158 C4, the owner's Q44)", () => {
  test('stays answerable between turns, the queue behind it, through what follows', () =>
    withWindow(async (window) => {
      await send(window, 'leftask');
      // In its turn it has the keys.
      await window.shows('❯ 1. Allow');
      await window.shows('I asked; the turn ends with it open.');
      // Its turn over, it waits between turns, without the keys.
      await window.shows('main asks · between turns');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');
      // The call that asked still says it waits, as the box does.
      expect(window.frame()).toMatch(
        /Write\(notes\/left\.md\)\n\s+⎿ {2}Waiting…/,
      );

      await window.type('text');
      await window.press('\r');
      await window.shows('› after your answer: text');
      expect(window.frame()).toContain('main asks · between turns');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      await window.shows('Permission: allow.');
      await window.shows('Hello, world.');
      expect(window.frame()).not.toContain('between turns');
    }));
});

test("a member's permission row names its team, in a turn and between turns (CHD-389 U3, the owner's Q45)", async () => {
  for (const between of [false, true]) {
    const drawn = await draw(
      <PermissionPrompt
        wait={{
          id: 'p',
          title: 'Write tests/parse/tokenize_test.ts',
          options: [],
        }}
        child={{ name: 'tester', colour: undefined, team: 'bugfix' }}
        between={between}
        width={76}
        active={false}
        onChoose={() => {}}
      />,
      { columns: 80, rows: 24 },
    );
    const shown = stripAnsi(drawn.frame());

    await drawn.unmount();
    expect(shown).toContain(
      between ? 'tester · bugfix asks · between turns' : 'tester · bugfix asks',
    );
  }
});

describe('CHD-158 C4 tester: promoted permission keys and withdrawal', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a typed digit remains a draft across two promoted waits and withdrawing the second at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'leftask');
          await window.shows('main asks · between turns');

          const session = window.session();

          assert(session);

          const stop = new AbortController();
          const answer = session.permissions.handler(
            {
              sessionId: session.id,
              toolCall: {
                toolCallId: 'queued-write',
                title: 'Write queued.md',
              },
              options: [
                { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              ],
            },
            stop.signal,
          );

          try {
            await window.type('2');
            expect(promptRow(window)).toContain('› 2');
            expect(window.frame()).not.toContain('❯ 1. Allow');
            await leader(window, 'a');
            await window.shows('❯ 1. Allow');
            await window.press(ESC);
            await window.shows('Write queued.md');
            await window.shows('ctrl+x a to answer');
            expect(window.frame()).not.toContain('❯ 1. Allow');
            stop.abort();
            expect(await answer).toMatchObject({
              outcome: { outcome: 'cancelled' },
            });
            await until(
              'the withdrawn permission box to leave',
              () => !window.frame().includes('Write queued.md'),
            );
            await window.shows('› 2');
            await window.shows('Permission: deny.');
          } finally {
            stop.abort();
            await answer;
          }
        },
        { columns, rows },
      ));
  }
});

describe('CHD-389 U3 tester: permission row identity and wrapping', () => {
  const name =
    'release validation member checking tokenizer boundaries and source locations';
  const team =
    'the second independent release validation run across all terminal sizes';

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const between of [false, true]) {
      test(`a long member and team stay whole with choices visible at ${columns} columns, between=${between}`, async () => {
        const drawn = await draw(
          <PermissionPrompt
            wait={{
              id: 'p',
              title: 'Write report.md',
              options: [
                { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
              ],
            }}
            child={{ name, team, colour: '#c49cff' }}
            between={between}
            held={between}
            width={columns - 4}
            active={false}
            onChoose={() => {}}
          />,
          { columns, rows },
        );

        try {
          const frame = stripAnsi(drawn.frame());
          const plain = frame.replace(/[│╭╮╰╯─]/g, ' ').replace(/\s+/g, ' ');

          expect(plain).toContain(
            `${name} · ${team} asks${between ? ' · between turns' : ''}`,
          );
          expect(frame).toContain('1. Allow');
          expect(frame).toContain(
            between ? 'ctrl+x a to answer' : 'Esc to reject',
          );
          expect(
            frame.split('\n').every((row) => row.length <= columns),
          ).toBeTrue();
        } finally {
          await drawn.unmount();
        }
      });
    }
  }

  test('member name is bold in its colour, team and between suffix dim, asks plain', async () => {
    const level = chalk.level;

    chalk.level = 3;

    try {
      const drawn = await draw(
        <PermissionPrompt
          wait={{ id: 'p', title: 'Write report.md', options: [] }}
          child={{ name: 'tester', team: 'bugfix', colour: '#c49cff' }}
          between
          width={116}
          active={false}
          onChoose={() => {}}
        />,
        { columns: 120, rows: 40 },
      );

      try {
        const frame = drawn.frame();

        expect(frame).toContain('\x1b[1m\x1b[38;2;196;156;255mtester\x1b[0m');
        expect(frame).toContain('\x1b[2m · bugfix\x1b[0m asks');
        expect(frame).toContain('\x1b[2m · between turns\x1b[0m');
      } finally {
        await drawn.unmount();
      }
    } finally {
      chalk.level = level;
    }
  });

  for (const kind of ['main', 'child', 'task', 'unknown'] as const) {
    test(`${kind} retains its permission naming rule`, async () => {
      const drawn = await draw(
        <PermissionPrompt
          wait={{
            id: 'p',
            title: 'Write report.md',
            options: [],
            ...(kind === 'unknown' ? { subagentId: 'unknown' } : {}),
          }}
          {...(kind === 'child' || kind === 'task' || kind === 'unknown'
            ? { child: { name: 'docs', colour: undefined } }
            : {})}
          {...(kind === 'task'
            ? {
                asker: [
                  {
                    id: 'task',
                    title: 'Fix the tokenizer',
                    state: 'running',
                    entries: [],
                    plan: [],
                    task: { name: 'Fix the tokenizer', runtime: 'fake' },
                  },
                ],
              }
            : {})}
          between={kind === 'unknown'}
          width={76}
          active={false}
          onChoose={() => {}}
        />,
        { columns: 80, rows: 24 },
      );

      try {
        const frame = stripAnsi(drawn.frame());

        if (kind === 'main') {
          expect(frame).not.toContain(' asks');
        } else {
          expect(frame).toContain(
            kind === 'child'
              ? 'docs asks'
              : kind === 'task'
                ? 'Agent(Fix the tokenizer) · fake asks'
                : 'a subagent of docs asks · between turns',
          );
        }
      } finally {
        await drawn.unmount();
      }
    });
  }
});

test('a tall permission held between turns names no scroll key until it has the keys (CHD-158 §8)', () =>
  withWindow(
    async (window) => {
      await send(window, 'bigaskleft');
      await window.shows('main asks · between turns');
      await window.shows('lines below ─');
      // No key scrolls it while the keys are the prompt's.
      expect(window.frame()).not.toContain('to scroll');
      expect(window.frame()).toContain('ctrl+x a to answer');

      await leader(window, 'a');
      await window.shows('pagedown to scroll');
      await window.shows('❯ 1. Yes');
    },
    { columns: 80, rows: 24 },
  ));
