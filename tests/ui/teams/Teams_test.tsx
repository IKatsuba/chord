/**
 * `/team` in the window, on the fake agent and chord's own server: the
 * picker and its Enter, a team's name completed, a run the person starts
 * and stops, `/team show` saved and running, and `/team new` and a change
 * in plain words going to main.
 */
import { expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { type ChordServer, serveChord } from '../../../src/server/server.ts';
import { LEAD_REPORT } from '../../fixtures/fake_agent/scenarios/teams.ts';
import {
  CTRL_O,
  DOWN,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

const BUGFIX = await readFile(
  fileURLToPath(
    new URL('../../fixtures/teams/fake/bugfix.md', import.meta.url),
  ),
  'utf8',
);

/** A team file whose second member names no runtime. */
const TRIAGE = `---
description: Finds why a test is flaky
lead:
  agent: fake
members:
  - name: finder
    role: Finds it
    agent: fake
    instructions: Find it.
  - name: fixer
    role: Fixes it
    instructions: Fix it.
---

Find it, then fix it.
`;

const JOB = 'issue 214: strings at the end of a line lose their closing quote';

/** Runs `body` in a window with chord's server and `teams` saved. */
async function withTeams(
  body: (window: Window) => Promise<void>,
  options: {
    teams?: Readonly<Record<string, string>>;
    runtimes?: readonly string[];
  } = {},
) {
  const server: ChordServer = serveChord();

  try {
    await withWindow(body, {
      server,
      runtimes: options.runtimes ?? ['fake'],
      rows: 60,
      columns: 120,
      teams: options.teams ?? { bugfix: BUGFIX, triage: TRIAGE },
    });
  } finally {
    await server.close();
  }
}

/** `/team run bugfix <JOB>`, until the lead has reported and tester asks. */
async function ran(window: Window): Promise<void> {
  await ready(window);
  await send(window, `/team run bugfix ${JOB}`);
  await window.shows('Team(bugfix) · fake · fake-large');
  await window.shows('← from @bugfix · fake');
  await window.shows('● tester needs your permission');
  await window.shows('└─ coder ');
}

test("/team lists the saved teams, a broken file with its problem, and Enter puts a run's start in the box", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team');
    await window.shows('Teams');
    await window.shows('Saved for this project in .chord/teams.');

    const frame = window.frame();

    expect(frame).toContain(
      '1. bugfix  3 agents · fake  this project           Fixes a bug end to end',
    );
    expect(frame).toContain(
      '2. triage  ✗ not read: members.1.agent is missing  ' +
        '.chord/teams/triage.md',
    );
    expect(frame).toContain(
      'Enter to hand it a job · /team show <name> · Esc to close',
    );

    await window.press('\r');
    await window.shows('› /team run bugfix ');
    expect(!window.frame().includes('Teams\n')).toBeTruthy();
    // The `› /team` row went with the picker, as /resume's does.
    expect(!/› \/team\s*$/m.test(window.frame())).toBeTruthy();
  }));

test('Enter on a broken file leaves the picker open with the box empty, and Esc closes it', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team');
    await window.shows('Teams');
    await window.press(DOWN);
    await window.shows('❯ 2. triage');
    // Enter takes no job here, so the hint does not offer it.
    await window.shows(
      'Fix the file, or ask main to fix triage · Esc to close',
    );
    expect(!window.frame().includes('Enter to hand it a job')).toBeTruthy();
    await window.press('\r');
    // A row Enter takes would have closed the picker by now.
    await window.press(UP);
    await window.shows('❯ 1. bugfix');
    await window.shows('Enter to hand it a job');
    expect(window.frame().includes('Teams')).toBeTruthy();
    expect(!window.frame().includes('› /team edit')).toBeTruthy();
    // The row stands while the picker is open.
    expect(/› \/team\s*$/m.test(window.frame())).toBeTruthy();
    await window.press('\x1b');
    await until('the picker to close', () => !window.frame().includes('Teams'));
    expect(!/› \/team\s*$/m.test(window.frame())).toBeTruthy();
  }));

test("a saved team's name is offered after /team show, and a run's after /team stop", () =>
  withTeams(async (window) => {
    await ran(window);
    await window.type('/team show ');
    await window.shows('  bugfix');
    // A broken file has nothing to show but its problem, which the picker
    // says.
    expect(!window.frame().includes('  triage')).toBeTruthy();
  }));

test("/team run hands the team the person's words, drawn as run_team's call, without a turn of main's", () =>
  withTeams(async (window) => {
    await ran(window);

    const frame = window.frame();

    expect(frame).toContain(`⎿  ${JOB}`);
    expect(frame).toContain(LEAD_REPORT.slice(0, 60));
    expect(frame).toContain('    bugfix     team · fake · Fake Large');
    // Main took no part: its first turn is the lead's report.
    expect(frame.split('Received the message from').length - 1).toStrictEqual(
      1,
    );
  }));

test('/team run refuses a broken file with its problem, and a team it does not have; /team, words it cannot read', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run triage the flaky test in tests/net');
    await window.shows(
      '⎿  .chord/teams/triage.md is not a team chord can run:',
    );
    await window.shows('members.1.agent is missing');
    expect(!window.frame().includes('/team edit')).toBeTruthy();
    await send(window, '/team run bugfx fix it');
    await window.shows('No team named bugfx · /team lists them');
    await send(window, '/team show');
    await window.shows('Which team? /team lists them');
  }));

test('/team show draws the saved team: its file, description, agents and body folded', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team show bugfix');
    await window.shows('⎿  bugfix · .chord/teams/bugfix.md');

    const frame = window.frame();

    expect(frame).toContain('Fixes a bug end to end — a failing test');
    expect(frame).toContain(
      'tester  fake · fake-small  acceptEdits  Writes the failing test',
    );
    expect(frame).toContain('How bugfix works');
    expect(frame).toContain('(ctrl+o to expand)');
  }));

test("/team show opened draws each agent's long instructions whole, wrapped to the window (CHD-332)", () => {
  const words = [
    'Ты ведущий команды `dev`: читай задачу через `quarry task read`,',
    'решай, кто что делает, и держи правило: сначала библиотека,',
    'потом свой код. Отчитывайся в задаче, а не в чате,',
    'и закрывай только то, что проверено.',
  ];
  const long = `---
description: Builds the dev branch
lead:
  agent: fake
  instructions: "${words.join(' ')}"
members:
  - name: coder
    role: Writes it
    agent: fake
    instructions: Write it.
---

Build it.
`;

  return withTeams(
    async (window) => {
      await ready(window);
      await send(window, '/team show dev');
      await window.shows('⎿  dev · .chord/teams/dev.md');
      await window.press(CTRL_O);
      await window.shows("lead's instructions");
      await window.shows('и закрывай только то, что проверено.');

      const rows = window
        .frame()
        .split('\n')
        .map((row) => row.trim());
      const under = rows.indexOf("lead's instructions");
      const paragraph = rows.slice(under + 1, rows.indexOf('', under));

      // Wrapped between words on more than one row, and not a word lost.
      expect(paragraph.length).toBeGreaterThan(1);
      expect(paragraph.join(' ')).toStrictEqual(words.join(' '));
      expect(rows).toContain("coder's instructions");
    },
    { teams: { dev: long } },
  );
});

test('/team show of a running team gives each agent its state and latest headline', () =>
  withTeams(async (window) => {
    await ran(window);
    await send(window, '/team show bugfix');
    await window.shows('bugfix · .chord/teams/bugfix.md · working ');
    await window.shows('on "issue 214: strings at the end');
    await window.shows('tester  fake · fake-small  acceptEdits  ● permission');
    await window.shows('Bash(deno task test tests/parse)');
    await window.shows('lead    fake · fake-large  default');
  }));

test("/team show gives a message that came after an agent's last call as its latest headline", () =>
  withTeams(async (window) => {
    await ran(window);

    // coder sends tester a word, then tester's word to it arrives.
    const coder = () =>
      window
        .frame()
        .split('\n')
        .findLast((line) => line.includes('coder   fake · fake-large  plan')) ??
      '';

    await until("tester's word in coder's headline", async () => {
      await send(window, '/team show bugfix');
      await new Promise((resolve) => setTimeout(resolve, 200));

      return coder().includes('← from @tester · fake');
    });

    expect(!coder().includes('→ @tester')).toBeTruthy();
  }));

test("/team stop closes the run and its members at once, and main hears it after the command's line", () =>
  withTeams(async (window) => {
    await ran(window);
    await send(window, '/team stop bugfix');
    await window.shows(
      '⎿  Stopped bugfix: its lead, tester, and coder are closed · ' +
        '/resume lists them',
    );
    await window.shows('The person closed team bugfix: its lead (fake');

    const frame = window.frame();

    expect(
      frame.indexOf('Stopped bugfix') < frame.indexOf('The person closed'),
    ).toBeTruthy();
    expect(!frame.includes('├─ tester ')).toBeTruthy();

    await send(window, '/team stop bugfix');
    await window.shows(
      'No run named bugfix is open · the list under the prompt names them',
    );
  }));

test('/team new goes to main, which proposes through propose_team, and a change asked in plain words proposes against the saved team', () =>
  withTeams(
    async (window) => {
      await ready(window);
      await send(window, '/team new a team that fixes bugs, a test first');
      await window.shows('Team(bugfix) · proposal');
      await window.shows('Save team bugfix?');
      await window.press('1');
      await window.shows('Saved to .chord/teams/bugfix.md');
      await send(window, '/team edit bugfix');
      await window.shows(
        '/team has no edit; it takes list, new, show, run or stop',
      );
      await send(window, 'put the reviewer on codex');
      await window.shows('Team(bugfix) · change');
      await window.shows('Replace team bugfix?');
    },
    { teams: {}, runtimes: ['fake', 'claude', 'codex'] },
  ));

test('/team with a child picked talks to main, and says so on the status line once', () =>
  withTeams(async (window) => {
    await ran(window);
    await window.press(DOWN);
    await window.press(DOWN);
    await window.shows('╭─ bugfix ─');
    // The keys back to the box, the lead still picked.
    await window.press('\x1b');
    await window.type('/team show bugfix');
    await window.press('\r');
    // The status line, above the list of agents.
    await window.shows('  /team talks to main ');
    // The report is main's, not the lead's.
    expect(!window.frame().includes('› /team show bugfix')).toBeTruthy();
  }));
