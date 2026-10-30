import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { logoRows, SHOTS } from '../../../scripts/dev/screenshots.ts';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import { TAGLINE } from '../../../src/ui/app/start_layout.ts';
import { parseTeam } from '../../../src/teams.ts';

describe('CHD-407 R1 tester: screenshot team', () => {
  test('the dedicated team parses with the selected runtime and model pairs', async () => {
    const text = await readFile(
      new URL('../../../scripts/dev/screenshots_team.md', import.meta.url),
      'utf8',
    );
    const parsed = parseTeam('bugfix', text, ['claude', 'codex']);

    assert('team' in parsed);
    expect(parsed.team.lead.agent).toBe('claude');
    expect(parsed.team.lead.model).toBe('claude-opus-5-5');
    expect(
      parsed.team.members.map(({ name, agent, model }) => ({
        name,
        agent,
        model,
      })),
    ).toEqual([
      { name: 'tester', agent: 'claude', model: 'claude-opus-5-5' },
      { name: 'coder', agent: 'codex', model: 'gpt-6.1-sol' },
      { name: 'reviewer', agent: 'claude', model: 'claude-opus-5-5' },
    ]);
  });
});

describe('CHD-560 U2 tester: screenshot team modes', () => {
  for (const file of ['screenshots_team.md', 'screenshots_proposal.md']) {
    test(`${file} gives the coder auto while retaining the other roles' modes`, async () => {
      const text = await readFile(
        new URL(`../../../scripts/dev/${file}`, import.meta.url),
        'utf8',
      );
      const parsed = parseTeam('bugfix', text, ['claude', 'codex']);

      assert('team' in parsed);
      expect(parsed.team.lead.mode).toBe('default');
      expect(
        parsed.team.members.map(({ name, mode }) => ({ name, mode })),
      ).toStrictEqual([
        { name: 'tester', mode: 'acceptEdits' },
        { name: 'coder', mode: 'auto' },
        { name: 'reviewer', mode: 'plan' },
      ]);
    });
  }
});

describe('CHD-564 the title page shots', () => {
  const shot = (name: string) => {
    const found = SHOTS.find((each) => each.name === name);

    assert(found !== undefined);

    return found;
  };

  test('start passes no name, waits for the picker, picks nothing, and leaves out own CLIs', () => {
    const { args, first, env, steps } = shot('start');

    expect(args).toEqual([]);
    expect(first).toBe('Select agent');
    expect(env).toContain('PATH=/usr/bin:/bin');
    expect(steps).toEqual([]);
  });

  test('resume leaves with /exit, ages the records, and starts chord --resume', () => {
    const { steps } = shot('resume');
    const typed = steps.flatMap((step) => ('type' in step ? [step.type] : []));

    expect(typed).not.toContain('/resume');
    expect(typed.at(-1)).toBe('/exit');
    expect(steps.slice(-4)).toEqual([
      { exited: true },
      { aged: [2, 26, 75] },
      { respawn: ['--resume'] },
      { until: 'Resume a session' },
    ]);
  });

  test('every other shot is named, on the prompt', () => {
    for (const { name, args, first } of SHOTS) {
      if (name !== 'start') {
        expect(args).toBeUndefined();
        expect(first).toBeUndefined();
      }
    }
  });
});

describe('CHD-564 the logo crop', () => {
  const pad = ' '.repeat(32);
  const green = '\x1b[38;2;71;231;165m';
  const art = Array.from(
    { length: 8 },
    (_, at) =>
      `${pad}${at % 2 === 0 ? '' : ' '}${green}${'▀'.repeat(at + 1)}\x1b[39m    ${green}${'█'.repeat(45)}\x1b[39m`,
  );
  const frame = [
    '',
    '',
    ...art,
    '',
    `${' '.repeat(42)}${TAGLINE}`,
    `${' '.repeat(48)}v0.65.0 · ~/src/app`,
    '',
    '    Select agent',
  ].join('\n');

  test("keeps the 8 rows above the tagline's gap, from the art's left edge", () => {
    const rows = logoRows(frame);

    expect(rows).toHaveLength(8);
    expect(stripAnsi(rows[0] ?? '').startsWith('▀')).toBe(true);
    expect(stripAnsi(rows[1] ?? '').startsWith(' ▀')).toBe(true);
    expect(rows.join('')).not.toContain('v0.65.0');
    expect(rows.join('')).not.toContain(TAGLINE);
  });

  test('keeps 57 columns and the colours', () => {
    for (const row of logoRows(frame)) {
      expect(stringWidth(stripAnsi(row))).toBeLessThanOrEqual(57);
      expect(row).toContain('38;2;71;231;165');
    }
  });

  test('a colour opened before the left edge is carried in', () => {
    const open = [
      ...art.map((row) => row.replace(pad, `${green}${pad}`)),
      '',
      TAGLINE,
    ].join('\n');

    for (const row of logoRows(open)) {
      expect(row).toContain('38;2;71;231;165');
    }
  });

  test('a frame with no art above its tagline is refused', () => {
    expect(() => logoRows('Select agent')).toThrow('no title page art');
    expect(() => logoRows(`\n\n${TAGLINE}`)).toThrow('no title page art');
  });
});

describe('CHD-564 tester: resume screenshot session fixtures', () => {
  test('the three documented prompts are submitted as separate sessions before exit', () => {
    const resume = SHOTS.find((shot) => shot.name === 'resume');

    assert(resume !== undefined);

    const typed = resume.steps.flatMap((step, at) =>
      'type' in step ? [{ text: step.type, next: resume.steps[at + 1] }] : [],
    );

    expect(typed.map(({ text }) => text)).toEqual([
      'Explain src/ui/state.ts',
      '/clear',
      'Add a --json flag to the agents command',
      '/clear',
      "Tidy the README's install section",
      '/clear',
      '/exit',
    ]);

    for (const { next } of typed) {
      expect(next).toEqual({ keys: ['Enter'] });
    }
  });
});

describe('CHD-564 tester: logo cell boundaries and background paint', () => {
  test('the right edge excludes the next cell while foreground and background survive the left crop', () => {
    const foreground = '\x1b[38;2;71;231;165m';
    const background = '\x1b[48;2;21;199;162m';
    const art = Array.from(
      { length: 8 },
      () =>
        `${foreground}${background}${' '.repeat(32)}${'▀'.repeat(57)}OUTSIDE\x1b[0m`,
    );
    const frame = [...art, '', TAGLINE, 'v0.65.0', 'Select agent'].join('\n');
    const cropped = logoRows(frame);

    expect(cropped).toHaveLength(8);

    for (const row of cropped) {
      expect(stripAnsi(row)).toBe('▀'.repeat(57));
      expect(row).toContain('38;2;71;231;165');
      expect(row).toContain('48;2;21;199;162');
      expect(row).not.toContain('OUTSIDE');
    }
  });

  test('blank space above the page and a painted tagline leave the crop unchanged', () => {
    const art = Array.from(
      { length: 8 },
      (_, at) => `${' '.repeat(31)}${'█'.repeat(at + 1)}`,
    );
    const plain = [...art, '', TAGLINE].join('\n');
    const moved = [
      '',
      '',
      '',
      ...art,
      '',
      `\x1b[38;2;228;228;228m${TAGLINE}\x1b[39m`,
      'v0.65.0 · ~/src/app',
    ].join('\n');

    expect(logoRows(moved)).toEqual(logoRows(plain));
  });
});
