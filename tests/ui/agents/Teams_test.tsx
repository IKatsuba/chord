/**
 * Teams in the window, on the fake agent and chord's own server: a team
 * handed a job through `run_team`, its lead opening the file's members, the
 * members messaging each other and the person, a second run, and closing.
 */
import { expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
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
  leader,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from '../app/render.tsx';

const BUGFIX = await readFile(
  fileURLToPath(
    new URL('../../fixtures/teams/fake/bugfix.md', import.meta.url),
  ),
  'utf8',
);

/** How many times `text` is on screen. */
function count(window: Window, text: string): number {
  return window.frame().split(text).length - 1;
}

/** Runs `body` in a window with chord's server and `teams` saved. */
async function withTeams(
  body: (window: Window) => Promise<void>,
  teams: Readonly<Record<string, string>> = { bugfix: BUGFIX },
  server: ChordServer = serveChord(),
) {
  try {
    await withWindow(body, {
      server,
      runtimes: ['fake'],
      rows: 80,
      columns: 120,
      teams,
    });
  } finally {
    await server.close();
  }
}

/** `team`, until the lead has reported and tester asks the person. */
async function started(window: Window): Promise<void> {
  await ready(window);
  await send(window, 'team');
  await window.shows('Team(bugfix) · fake · fake-large');
  await window.shows('← @bugfix · fake');
  await window.shows('● tester needs your permission');
  await window.shows('└─ coder ');
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
    await window.shows('← @main');
    await window.shows('Open(tester) · fake · fake-small · acceptEdits');
    await window.shows('Open(coder) · fake · fake-large · plan');
    await window.shows('→ @main');
    await window.shows('← @tester · fake');
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
    await window.shows('tester asks');

    const frame = window.frame();

    expect(frame).toContain('→ @coder');
    expect(frame).toContain('Bash(deno task test tests/parse)');
    expect(frame).toContain('⏵⏵ accept edits on');

    await window.press('3');
    await window.shows('Not run; I will ask bugfix how to go on.');
    await window.shows(CODER_TO_TESTER);
    await window.shows("tester · fake · Fake Small · bugfix's member");
    await window.shows('opened by @bugfix');
    await window.shows("⏺ bugfix's instructions for tester · ");
    await window.shows('← @bugfix');
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
    await window.shows('← @tester · fake');
    await window.shows(TESTER_TO_CODER.slice(0, 60));
    await window.shows('→ @tester');
  }));

test("a second run of a running team is 'bugfix 2', and its lead reaches the first run's", () =>
  withTeams(async (window) => {
    await started(window);
    await send(window, 'team2');
    await window.shows('Team(bugfix 2) · fake · fake-large');
    await window.shows('← @bugfix 2 · fake');
    await window.shows('    bugfix 2   team · fake');
    expect(count(window, '← @bugfix · fake')).toStrictEqual(1);

    // bugfix heard from bugfix 2 directly.
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('╭─ bugfix ─');
    await window.shows('← @bugfix 2 · fake');
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
    await window.shows('← chord');
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
