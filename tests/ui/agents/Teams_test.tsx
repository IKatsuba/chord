/**
 * A team run in the window: its lead opening its members, their messages
 * and runs, closing and efforts.
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
  leader,
  ready,
  send,
  until,
  type Window,
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

test("a run after /clear is numbered past the cleared session's, so an old name still means its run (Q184)", () =>
  withTeams(async (window) => {
    await started(window);
    await send(window, '/clear');
    await until(
      'the run closed with its session',
      () => !window.frame().includes('    bugfix '),
    );
    await ready(window);
    await send(window, 'team2');
    await window.shows('Team(bugfix 2) · fake · fake-large');
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

describe('CHD-493 U11 tester: resumed sessions keep team run numbers', () => {
  const mainIdle = (window: Window) =>
    until(
      'main is idle',
      () =>
        window.frame().split('\n').at(-1)?.includes('? for shortcuts') ===
          true || /main\s+fake.*◦ idle/.test(window.frame()),
    );

  for (const columns of [80, 120]) {
    test(`a direct pick reserves both retired run names at ${columns} columns`, async () => {
      const server = serveChord();
      const admit = server.admit.bind(server);
      let main: Caller | undefined;

      server.admit = (caller) => {
        if (caller.role === 'person') {
          main = caller;
        }

        return admit(caller);
      };

      // The harness's last opened session can be a late team child.
      // Read main's actual session from the same view its tools use.
      const mainId = () => main?.window.sessions()[0]?.id;

      await withTeams(
        async (window) => {
          await window.resize({ columns, rows: 40 });
          await mainIdle(window);

          const target = mainId();

          expect(target).toBeDefined();

          await started(window);

          await send(window, '/clear');
          await until(
            'the next main',
            () => mainId() !== undefined && mainId() !== target,
          );
          await mainIdle(window);
          await send(window, 'team2');
          await window.shows('Team(bugfix 2) · fake · fake-large');
          await window.shows('← from @bugfix 2 · fake');
          await mainIdle(window);
          await send(window, '/resume');
          await window.shows('Resume a session');

          for (
            let row = 0;
            !/❯\s+\d+\. .* {2}team\s*│/.test(window.frame());
            row++
          ) {
            expect(row).toBeLessThan(12);
            await window.press(DOWN);
          }

          await window.press('\r');
          await until('the first main resumed', () => mainId() === target);
          await mainIdle(window);
          await send(window, 'team2');
          await window.shows('Team(bugfix 3) · fake · fake-large');
        },
        { bugfix: BUGFIX },
        server,
      );
    });
  }
});
