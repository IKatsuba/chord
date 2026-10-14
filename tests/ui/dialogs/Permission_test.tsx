import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import { PermissionPrompt } from '../../../src/ui/dialogs/Permission.tsx';
import assert from 'node:assert/strict';
import { readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { parseTeam } from '../../../src/teams.ts';
import {
  asked,
  DOWN,
  ESC,
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
