/**
 * A team run in the window: its lead opening its members, their messages
 * and runs, closing, efforts, and who a box that asks beside them names.
 */
import { describe, expect, test } from 'bun:test';
import { type ChordServer, serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import {
  CODER_TO_TESTER,
  LEAD_REPORT,
  TESTER_PROMPT,
  TESTER_REPORT,
  TESTER_TO_CODER,
} from '../../fixtures/fake_agent/scenarios/teams.ts';
import {
  DOWN,
  END,
  leader,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';
import { BUGFIX, withTeams, started } from './teams_window.tsx';

/** How many times `text` is on screen. */
function count(window: Window, text: string): number {
  return window.frame().split(text).length - 1;
}

test("run_team opens the team's lead, which opens the file's members, and its report reaches main", () =>
  withTeams(async (window) => {
    await started(window);

    const frame = window.frame();

    expect(frame).toContain('List teams');
    expect(frame).toContain('1 team · bugfix');
    expect(frame).toContain('Issue 214: a string at the end of a line');
    expect(frame).toContain(LEAD_REPORT.slice(0, 60));
    expect(frame).toContain('    bugfix     team · fake · Fake Large');
    expect(frame).toContain('    ├─ tester  fake · Fake Small');
    // The members' messages are theirs and the lead's: main sees none.
    expect(!frame.includes(TESTER_REPORT.slice(0, 40))).toBeTruthy();
    expect(!frame.includes('Open(tester)')).toBeTruthy();
  }));

test("the lead's transcript has its instructions as one line, its Open rows with the file's modes, and its members' reports", () =>
  withTeams(async (window) => {
    await started(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('bugfix · team · fake · Fake Large');
    await window.shows('opened by @main');
    await window.shows("⏺ bugfix's instructions for the lead · ");
    await window.shows('← from @main');
    await window.shows('Open(tester) · fake · fake-small · acceptEdits');
    await window.shows('Open(coder) · fake · fake-large · plan');
    await window.shows('→ to @main');
    await window.shows('← from @tester · fake');
    await window.shows('╭─ bugfix ─');

    const frame = window.frame();

    expect(frame).toContain(TESTER_REPORT.slice(0, 40));
    // tester's word to coder is not routed through the lead.
    expect(!frame.includes(TESTER_TO_CODER.slice(0, 40))).toBeTruthy();
    expect(
      !frame.includes('Received the message from'.concat(' main')),
    ).toBeTruthy();
  }));

test("a member picked has its run in its box's title, its instructions folded, the lead's prompt, and its permission box", () =>
  withTeams(async (window) => {
    await started(window);
    await leader(window, 'a');
    await window.shows('╭─ tester · bugfix ─');
    await window.shows('tester · bugfix asks');

    const frame = window.frame();

    expect(frame).toContain('→ to @coder');
    expect(frame).toContain('Bash(deno task test tests/parse)');
    expect(frame).toContain('⏵⏵ accept edits on');

    await window.press('3');
    await window.shows('Not run; I will ask bugfix how to go on.');
    await window.shows(CODER_TO_TESTER);
    await window.shows("tester · fake · Fake Small · bugfix's member");
    await window.shows('opened by @bugfix');
    await window.shows("⏺ bugfix's instructions for tester · ");
    await window.shows('← from @bugfix');
    expect(window.frame()).toContain(TESTER_PROMPT.slice(0, 60));
  }));

test('members message each other by name, directly', () =>
  withTeams(async (window) => {
    await started(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('╭─ coder · bugfix ─');
    await window.shows('← from @tester · fake');
    await window.shows(TESTER_TO_CODER.slice(0, 60));
    await window.shows('→ to @tester');
  }));

test("a second run of a running team is 'bugfix 2', and its lead reaches the first run's", () =>
  withTeams(async (window) => {
    await started(window);
    await send(window, 'team2');
    await window.shows('Team(bugfix 2) · fake · fake-large');
    await window.shows('← from @bugfix 2 · fake');
    await window.shows('    bugfix 2   team · fake');
    expect(count(window, '← from @bugfix · fake')).toStrictEqual(1);

    // bugfix heard from bugfix 2 directly.
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('╭─ bugfix ─');
    await window.shows('← from @bugfix 2 · fake');
    await window.shows('Which files do you hold?');
  }));

test('x on the lead closes its members with it, and chord tells main which', () =>
  withTeams(async (window) => {
    await started(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('╭─ bugfix ─');
    // tester waits on the person, so the first x arms.
    await window.press('x');
    await window.shows(
      'bugfix and its 2 members are working · x again to stop them and close',
    );
    await window.press('x');
    await window.shows('← from chord');
    await window.shows('The person closed team bugfix: its lead (fake');
    await window.shows('and its members tester and coder.');
    await window.shows('run_team starts it again.');
    expect(!window.frame().includes('├─ tester ')).toBeTruthy();
    expect(!window.frame().includes('└─ coder ')).toBeTruthy();
  }));

test('run_team refuses a team that is not saved, as a failed Team row', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, 'team');
    await window.shows('Team(bugfix)');
    await window.shows('No team named bugfix · list_teams lists them');
    await window.shows('chord did not start the team.');
  }, {}));

test('two open_agent calls for one member at once open it once', async () => {
  const served = serveChord();
  const callers: Caller[] = [];
  const server: ChordServer = {
    ...served,
    url: served.url,
    admit: (caller) => {
      callers.push(caller);

      return served.admit(caller);
    },
  };

  await withTeams(
    async (window) => {
      await started(window);

      const lead = callers.find((caller) => caller.team === 'lead')!;
      const view = lead.window;

      expect(!('error' in view.close(lead, 'coder'))).toBeTruthy();
      await until('coder closed', () => count(window, '└─ coder ') === 0);

      const answers = await Promise.all(
        [1, 2].map(() =>
          view.openMember(lead, { member: 'coder', prompt: 'Fix it' }),
        ),
      );

      expect(answers.filter((answer) => 'error' in answer)).toStrictEqual([
        { error: 'coder is open; send_message reaches it' },
      ]);
      await window.shows('└─ coder ');
      expect(count(window, '└─ coder ')).toStrictEqual(1);
    },
    { bugfix: BUGFIX },
    server,
  );
});

test("a team's lead and members start on the file's efforts, and one the runtime refuses leaves its own with the refusal said", () =>
  withTeams(
    async (window) => {
      await started(window);
      await window.shows('Team(bugfix) · fake · fake-large · high');
      await window.shows(
        'bugfix     team · fake · Fake Large with a 1M context window · high',
      );
      // tester's runtime has no max for its model: it runs on its own.
      await window.shows('├─ tester  fake · Fake Small · medium');
      await window.press(DOWN);
      await window.press(DOWN);
      await window.shows(
        'Open(tester) · fake · fake-small · medium · acceptEdits',
      );
      await window.shows('Open(coder) · fake · fake-large · plan');
      await window.press(DOWN);
      await window.shows(
        'Could not start on max effort, set by team bugfix: the agent offers ' +
          'low, medium, high',
      );
    },
    {
      bugfix: BUGFIX.replace(
        '  model: fake-large\n  mode: default\n',
        '  model: fake-large\n  effort: high\n  mode: default\n',
      ).replace(
        '    model: fake-small\n',
        '    model: fake-small\n    effort: max\n',
      ),
    },
  ));

test("a member's question box names it with its team (CHD-389)", () =>
  withTeams(async (window) => {
    await started(window);
    await leader(window, 'a');
    await window.shows('╭─ tester · bugfix ─');
    await window.press('3');
    await window.shows('Not run; I will ask bugfix how to go on.');
    await send(window, 'askclaude');
    await window.shows('tester · bugfix asks you 2 questions');
    expect(window.frame()).not.toContain('fake asks you 2 questions');
  }));

describe('a task of main asking beside a member (CHD-431)', () => {
  /** `teamtask`, until main's task and tester both ask. */
  async function bothAsk(window: Window): Promise<void> {
    await ready(window);
    await send(window, 'teamtask');
    await window.shows('The team and the task are both at work.');
    await window.shows('Agent(Fix the tokenizer) · fake asks');
    await window.shows('├─ tester');
    await until('tester asks', () =>
      /├─ tester .*● permission/.test(window.frame()),
    );
  }

  /** tester picked from the list, its prompt given the keys. */
  async function toTester(window: Window): Promise<void> {
    for (let presses = 0; presses < 8; presses++) {
      if (/❯ ├─ tester/.test(window.frame())) {
        break;
      }

      await window.press(DOWN);
    }

    await window.press('\r');
    await window.shows('╭─ tester · bugfix ─');
  }

  test("main's held box comes first, then ctrl+x a goes on to the member", () =>
    withTeams(async (window) => {
      await bothAsk(window);
      // main's own request between turns is the line's, naming nobody behind.
      // Wide or short, as the line has room.
      expect(window.frame()).toMatch(
        /● permission( asked between turns)? · ctrl\+x a to answer/,
      );
      expect(window.frame()).not.toContain('tester needs your permission');
      await leader(window, 'a');
      await window.shows('Esc to reject');
      await window.press('1');
      await window.shows('● tester needs your permission · ctrl+x a to go');
      await leader(window, 'a');
      await window.shows('╭─ tester · bugfix ─');
      await window.shows('tester · bugfix asks');
    }));

  test("from the member, the hint names main's task as its box does, and ctrl+x a reaches it", () =>
    withTeams(async (window) => {
      await bothAsk(window);
      await toTester(window);
      // Wide, or short where tester's mode leaves no room for the task's name.
      await until('the task named', () =>
        /● (Agent\(Fix the tokenizer\) · fake|main's task) needs your permission · ctrl\+x a/.test(
          window.frame(),
        ),
      );

      // From a session picked by hand, ctrl+x a goes first to what the hint
      // names, main's task, however coder's reply came (the owner's Q46).
      const shown = () =>
        /╭─ (\w+) · bugfix ─/.exec(window.frame())?.[1] ?? 'main';
      const task = 'Agent(Fix the tokenizer) · fake asks';

      await leader(window, 'a');
      await until('ctrl+x a moves on', () => shown() !== 'tester');
      await window.shows(task);
      expect(shown()).toStrictEqual('main');
    }));

  test("at 80x24 tester's box keeps its hint inside its border, the agents list folding to fit and the summary line whole (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await toTester(window);

          const lines = window.frame().split('\n');
          const hint = lines.findIndex((line) =>
            /^│ Esc to reject +│$/.test(line.trimEnd()),
          );

          expect(hint, window.frame()).toBeGreaterThan(0);
          expect(lines[hint + 1]?.trimEnd()).toMatch(/^╰─+╯$/);
          expect(window.frame()).toMatch(/… \+\d+ more/);
          expect(window.frame()).toContain('background  ● 1 task asking');
        },
        {
          server,
          runtimes: ['fake'],
          rows: 24,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });

  test("at 80x24 a tall request's ↓ rule sits under its last shown row, the hint inside the border (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await leader(window, 'a');
          await window.shows('Esc to reject');
          await window.press('1');
          await send(window, 'bigask');
          await window.shows('mcp__files__write_file');
          await window.shows('lines below · pagedown to scroll');

          const lines = window.frame().split('\n');
          const rule = lines.findIndex((line) =>
            /^│ ── ↓ \d+ lines below · pagedown to scroll ─+ │$/.test(
              line.trimEnd(),
            ),
          );
          const hint = lines.findIndex((line) =>
            /^│ Esc to reject +│$/.test(line.trimEnd()),
          );

          // Drawn over the request's last row, the rule left its own row
          // blank: two blank rows before the question instead of one.
          expect(rule, window.frame()).toBeGreaterThan(0);
          expect(lines[rule - 1]?.trimEnd(), window.frame()).toMatch(
            /^│ (mcp__files__write_file| {2}.*) +│$/,
          );
          expect(lines[rule + 1]?.trimEnd(), window.frame()).toMatch(/^│ +│$/);
          expect(lines[rule + 2]?.trimEnd(), window.frame()).toMatch(
            /^│ Do you want to proceed\? +│$/,
          );
          expect(hint, window.frame()).toBeGreaterThan(rule);
          expect(lines[hint + 1]?.trimEnd()).toMatch(/^╰─+╯$/);
        },
        {
          server,
          runtimes: ['fake'],
          rows: 24,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });

  test("at 120x40 under the folded list, a tall request's room holds still and its end view shows its last row (CHD-464)", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await bothAsk(window);
          await leader(window, 'a');
          await window.shows('Esc to reject');
          await window.press('1');
          await send(window, 'bigask');
          await window.shows('lines below · pagedown to scroll');
          await window.press(END);
          await window.shows('lines above · pageup to scroll');

          // The request, from its title to the question under it.
          const request = () => {
            const lines = window.frame().split('\n');
            const from = lines.findIndex((line) =>
              line.includes('mcp__files__write_file'),
            );
            const to = lines.findIndex((line) =>
              line.includes('Do you want to proceed?'),
            );

            return lines.slice(from, to + 1).map((line) => line.trimEnd());
          };

          // The list folding and the box giving way traded rows on every
          // frame, so the room, and with it the view, never held.
          const seen = new Set<string>();

          for (let frame = 0; frame < 10; frame++) {
            seen.add(request().join('\n'));
            await new Promise((resolve) => setTimeout(resolve, 50));
          }

          const shown = request();

          expect(seen.size, [...seen].join('\n\n')).toStrictEqual(1);
          expect(shown.join('\n')).not.toContain('lines below');
          expect(shown.at(-3), shown.join('\n')).toMatch(
            /^│ {3}mode: overwrite +│$/,
          );
          expect(shown.at(-2)).toMatch(/^│ +│$/);
        },
        {
          server,
          runtimes: ['fake'],
          rows: 40,
          columns: 120,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });
});

describe('a task of main asking beside a member, at 80 columns (CHD-431)', () => {
  test("the hint names whose task it is where the task's name does not fit", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'teamtask');
          await window.shows('The team and the task are both at work.');
          await window.shows('├─ tester');
          await until('tester asks', () =>
            /├─ tester .*● permission/.test(window.frame()),
          );

          for (let presses = 0; presses < 8; presses++) {
            if (/❯ ├─ tester/.test(window.frame())) {
              break;
            }

            await window.press(DOWN);
          }

          await window.press('\r');
          await window.shows('╭─ tester · bugfix ─');
          await window.shows("● main's task needs your permission · ctrl+x a");
        },
        {
          server,
          runtimes: ['fake'],
          rows: 40,
          columns: 80,
          teams: { bugfix: BUGFIX },
        },
      );
    } finally {
      await server.close();
    }
  });
});
