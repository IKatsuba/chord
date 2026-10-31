import { describe, expect, test } from 'bun:test';
import type { ChordCall } from '../../../../src/session/transcript/types.ts';
import {
  foldedSettingsNote,
  settingsHeadline,
  settingsRows,
} from '../../../../src/ui/transcript/tools/settings_row.ts';

const read = (path?: unknown, answer?: unknown): ChordCall => ({
  tool: 'settings',
  input: { action: 'read', ...(path === undefined ? {} : { path }) },
  ...(answer === undefined ? {} : { answer }),
});

describe('settingsHeadline', () => {
  test('names the path, its note once served', () => {
    expect(
      settingsHeadline(read(['agents', 'my.agent', 'model'])),
    ).toStrictEqual({
      name: 'Settings',
      arg: 'agents."my.agent".model',
    });
    expect(settingsHeadline(read(['theme'], {}))).toStrictEqual({
      name: 'Settings',
      arg: 'theme',
      note: ' · read',
    });
    expect(settingsHeadline(read(undefined, {}))).toStrictEqual({
      name: 'Settings',
      note: ' · read',
    });
  });

  test('a refusal has no note', () => {
    expect(
      settingsHeadline({ ...read(['nope']), error: 'No setting nope' }),
    ).toStrictEqual({ name: 'Settings', arg: 'nope' });
  });

  test("an agent's control characters and odd paths never reach the row raw", () => {
    expect(settingsHeadline(read(['a\u009bb'])).arg).toBe('"a\\u009bb"');
    expect(settingsHeadline(read('theme'))).toStrictEqual({ name: 'Settings' });
    expect(settingsHeadline(read([1]))).toStrictEqual({ name: 'Settings' });
  });
});

describe('foldedSettingsNote', () => {
  const line = { name: 'Settings', note: ' · read' };

  test('says the key on a folded read of every key alone', () => {
    const every = read(undefined, {});

    expect(foldedSettingsNote(line, every, false, 'ctrl+o').note).toBe(
      ' · read (ctrl+o to expand)',
    );
    expect(foldedSettingsNote(line, every, true, 'ctrl+o')).toBe(line);
    expect(foldedSettingsNote(line, every, false, undefined)).toBe(line);
    expect(foldedSettingsNote(line, read(['theme'], {}), false, 'ctrl+o')).toBe(
      line,
    );
    expect(foldedSettingsNote(line, read(), false, 'ctrl+o')).toBe(line);
    expect(foldedSettingsNote(line, undefined, false, 'ctrl+o')).toBe(line);
  });
});

describe('settingsRows', () => {
  test('none before an answer, for a refusal, or for another tool', () => {
    expect(settingsRows(read(), false, 80)).toBeUndefined();
    expect(
      settingsRows({ ...read(['nope']), error: 'No setting nope' }, false, 80),
    ).toBeUndefined();
    expect(
      settingsRows({ tool: 'list_agents', input: {}, answer: {} }, false, 80),
    ).toBeUndefined();
  });

  test('one key draws its three values, absent ones in words, null as null', () => {
    const rows = settingsRows(
      read(['teamSelection', 'prefer', 'model'], {
        user: null,
        effective: 'm',
      }),
      false,
      80,
    );

    expect(rows!.map(({ label, text }) => label + text)).toStrictEqual([
      'Effective  "m"',
      'User       null',
      'Project    not set',
    ]);
  });

  test('a linked project file reads not read, not not set', () => {
    const rows = settingsRows(
      {
        ...read(['agent'], { project: null, effective: 'a' }),
        settingsFiles: { user: 'u', project: 'p', projectUnread: true },
      },
      false,
      80,
    );

    expect(rows!.at(-1)).toMatchObject({
      label: 'Project    ',
      text: 'not read',
    });
  });

  test('a refused project file says it may win, a verified one that it does', () => {
    const said = (answer: unknown) =>
      settingsRows(
        {
          tool: 'settings',
          input: { action: 'set', path: ['agent'], value: 'a' },
          answer,
        },
        false,
        80,
      )!.at(-1);

    expect(
      said({ after: 'a', shadowedBy: '.chord', shadowedUnread: true }),
    ).toMatchObject({
      text: '.chord was not read and may set this too, and win here',
      tone: 'warning',
    });
    expect(said({ after: 'a', shadowedBy: 'p.json' })).toMatchObject({
      text: 'p.json sets this too, and wins here',
      tone: 'warning',
    });
  });

  test('a long value wraps at the cell under its column, never cut', () => {
    const value = 'x'.repeat(50) + ' ' + 'y'.repeat(50);
    const rows = settingsRows(
      read(['agents', 'a', 'model'], { effective: value }),
      false,
      31,
    )!;
    const effective = rows.slice(0, -2);

    expect(effective.length).toBeGreaterThan(2);
    expect(effective[0]!.label).toBe('Effective  ');
    expect(
      effective.slice(1).every(({ label }) => label === ' '.repeat(11)),
    ).toBe(true);
    expect(effective.every(({ text }) => text.length <= 20)).toBe(true);
    expect(effective.map(({ text }) => text).join('')).toBe(`"${value}"`);
  });

  test('every key folds to a line per file, then its problems', () => {
    const call: ChordCall = {
      ...read(undefined, { problems: [{}, {}] }),
      settingsFiles: { user: 'no home directory', project: 'p · not there' },
    };

    expect(settingsRows(call, false, 80)).toStrictEqual([
      { label: 'User     ', text: 'no home directory', tone: 'text' },
      { label: 'Project  ', text: 'p · not there', tone: 'text' },
      { label: '', text: '2 problems', tone: 'warning' },
    ]);
    expect(
      settingsRows({ ...call, answer: { problems: [{}] } }, false, 80)!.at(-1)!
        .text,
    ).toBe('1 problem');
    expect(
      settingsRows({ ...call, answer: { problems: [] } }, false, 80),
    ).toHaveLength(2);
  });

  test('opened, it is the answer as two-space JSON, escaped', () => {
    const rows = settingsRows(
      read(undefined, { user: { theme: 'a\u009bb' }, project: null }),
      true,
      80,
    )!;

    expect(rows.map(({ label, text }) => label + text)).toStrictEqual([
      '{',
      '  "user": {',
      '    "theme": "a\\u009bb"',
      '  },',
      '  "project": null',
      '}',
    ]);
  });
});

describe('a set or remove on the row', () => {
  const changed = (input: unknown, answer: unknown): ChordCall => ({
    tool: 'settings',
    input,
    answer,
  });
  const set = { action: 'set', path: ['agents', 'codex', 'model'], value: 'n' };
  const remove = { action: 'remove', path: ['offeredAgents'] };
  const said = (call: ChordCall, width = 80) =>
    settingsRows(call, false, width)!.map(({ label, text }) => label + text);

  test('its note says what it does', () => {
    const note = (call: ChordCall) => settingsHeadline(call).note;

    expect(note(changed(set, { before: 'o', after: 'n' }))).toBe(' · change');
    expect(note(changed(set, { after: 'n' }))).toBe(' · set');
    expect(note(changed(remove, { before: ['a'] }))).toBe(' · remove');
    expect(note(changed(set, { unchanged: true, before: 'n' }))).toBe(
      ' · unchanged',
    );
    expect(note({ tool: 'settings', input: set })).toBeUndefined();
    expect(note({ tool: 'settings', input: set, error: 'x' })).toBeUndefined();
  });

  test('it draws now and after, an absent one in words', () => {
    expect(said(changed(set, { before: 'o', after: 'n' }))).toStrictEqual([
      'Now    "o"',
      'After  "n"',
    ]);
    expect(said(changed(set, { after: 'n' }))).toStrictEqual([
      'Now    not set',
      'After  "n"',
    ]);
    expect(said(changed(remove, { before: ['a', 'b'] }))).toStrictEqual([
      'Now    ["a","b"]',
      'After  not set',
    ]);
  });

  test('a project holding it warns, right under the change', () => {
    const rows = settingsRows(
      changed(set, {
        before: 'o',
        after: 'n',
        shadowedBy: '.chord/settings.json',
      }),
      false,
      80,
    )!;

    expect(rows.at(-1)).toStrictEqual({
      label: '',
      text: '.chord/settings.json sets this too, and wins here',
      tone: 'warning',
    });
  });

  test('the answer adds a line below the change', () => {
    const base = { before: 'o', after: 'n', file: '~/s.json' };
    const last = (answer: unknown) =>
      settingsRows(changed(set, answer), false, 80)!.at(-1);

    expect(last({ ...base, saved: true, takesEffect: 'now' })).toMatchObject({
      text: 'Saved to ~/s.json · takes effect now',
      tone: 'success',
    });
    expect(
      last({ ...base, saved: true, takesEffect: 'next start' }),
    ).toMatchObject({
      text: 'Saved to ~/s.json · takes effect at the next start',
      tone: 'success',
    });
    expect(last({ ...base, saved: false })).toMatchObject({
      text: 'Not saved · the person will say what to change',
      tone: 'dim',
    });
  });

  test('nothing to do says so, shadowed or not', () => {
    expect(
      said(changed(set, { unchanged: true, before: 'dark' })),
    ).toStrictEqual(['Already "dark"; nothing to change']);
    expect(said(changed(remove, { unchanged: true }))).toStrictEqual([
      'Not set; nothing to change',
    ]);
    expect(
      said(
        changed(set, { unchanged: true, before: 'd', shadowedBy: 'p.json' }),
      ).at(-1),
    ).toBe('p.json sets this too, and wins here');
  });

  test('a long value is whole, wrapped under its column', () => {
    const value = 'f'.repeat(100);
    const rows = settingsRows(changed(set, { after: value }), false, 27)!;
    const after = rows.slice(1);

    expect(after[0]!.label).toBe('After  ');
    expect(after.slice(1).every(({ label }) => label === '       ')).toBe(true);
    expect(after.map(({ text }) => text).join('')).toBe(`"${value}"`);
  });

  test('a value with a control reads escaped', () => {
    expect(said(changed(set, { after: 'a\u202eb' }))[1]).toBe(
      'After  "a\\u202eb"',
    );
  });
});
