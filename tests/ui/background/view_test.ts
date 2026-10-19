import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
import {
  moveViewFocus,
  stateText,
  stopRefused,
  type ViewRow,
  viewRows,
  viewWindow,
  edgeMarked,
} from '../../../src/ui/background/view.ts';

const NOW = 1_000_000;

function monitor(
  id: string,
  name: string,
  status: BackgroundItem['status'],
  more: Partial<BackgroundItem> = {},
): BackgroundItem {
  return {
    kind: 'monitor',
    id,
    key: 1,
    name,
    startedAt: NOW - 242_000,
    status,
    events: 1,
    ...more,
  };
}

function task(
  id: string,
  name: string,
  status: BackgroundItem['status'],
  more: Partial<BackgroundItem> = {},
): BackgroundItem {
  return {
    kind: 'task',
    id,
    key: 1,
    name,
    startedAt: NOW - 32_000,
    status,
    runtime: 'fake',
    model: 'Fake Small',
    ...more,
  };
}

const PARSER = { name: 'parser', colour: 0 };
const CODER = { name: 'coder', colour: 1 };

/** The design's five items, `Fix the tokenizer` asking. */
const ITEMS: BackgroundItem[] = [
  monitor(
    'm1',
    'CI run 4812',
    { group: 'failed', endedAt: NOW - 30_000, end: { kind: 'exit', code: 1 } },
    { startedAt: NOW - 30_000 - 192_000, events: 3 },
  ),
  monitor('m2', 'dev server errors', { group: 'running' }),
  monitor(
    'm1',
    'parser tests',
    { group: 'running' },
    { key: 2, owner: PARSER, startedAt: NOW - 123_000, events: 4 },
  ),
  task('t1', 'Fix the tokenizer', {
    group: 'asking',
    on: 'permission',
    since: NOW - 13_000,
  }),
  task(
    't2',
    'Fix the printer',
    { group: 'running' },
    { key: 3, owner: CODER, model: 'Fake Large' },
  ),
];

const text = (rows: readonly ViewRow[]) =>
  rows.flatMap((row) =>
    row.lines.map((line) =>
      line
        .map((cell) => cell.text)
        .join('')
        .trimEnd(),
    ),
  );

test('each state says its time, an end its words, as the design table has them', () => {
  const say = (item: BackgroundItem) => stateText(item, NOW).text;

  expect(ITEMS.map(say)).toStrictEqual([
    '✗ exit code 1 after 3m 12s · 3 events',
    'running 4m 2s · 1 event',
    'running 2m 3s · 4 events',
    '● permission 13s',
    'working 32s',
  ]);

  const ended = (
    end: NonNullable<
      Extract<BackgroundItem['status'], { endedAt: number }>['end']
    >,
    group: 'done' | 'failed' | 'stopped',
  ) =>
    say(
      monitor(
        'm',
        'x',
        { group, endedAt: NOW, end },
        { startedAt: NOW - 180_000 },
      ),
    );

  expect(ended({ kind: 'exit', code: 0 }, 'done')).toStrictEqual(
    '✓ exit code 0 after 3m · 1 event',
  );
  expect(ended({ kind: 'signal', signal: 'SIGKILL' }, 'failed')).toStrictEqual(
    '✗ killed by SIGKILL after 3m · 1 event',
  );
  expect(
    ended({ kind: 'timed_out', timeoutMs: 600_000 }, 'failed'),
  ).toStrictEqual('✗ timed out after 3m · 1 event');
  expect(ended({ kind: 'flooded', by: 'lines' }, 'failed')).toStrictEqual(
    '✗ flooded after 3m · 1 event',
  );
  expect(ended({ kind: 'stopped' }, 'stopped')).toStrictEqual(
    '■ stopped after 3m · 1 event',
  );
  expect(
    say(task('t', 'x', { group: 'asking', on: 'input', since: NOW - 13_000 })),
  ).toStrictEqual('● input 13s');
  expect(
    ['done', 'failed', 'stopped'].map((group) =>
      say(
        task('t', 'x', {
          group: group as 'done',
          endedAt: NOW - 2_000,
        }),
      ),
    ),
  ).toStrictEqual([
    '✓ reported after 30s',
    '✗ failed after 30s',
    '■ stopped after 30s',
  ]);
});

test('a row is name, kind, state and owner in columns two cells apart, the ❯ on the focused one', () => {
  expect(
    text(
      viewRows(ITEMS, { width: 116, focus: { key: 1, id: 't1' }, now: NOW }),
    ),
  ).toStrictEqual([
    '  CI run 4812        monitor                   ✗ exit code 1 after 3m 12s · 3 events  main',
    '  dev server errors  monitor                   running 4m 2s · 1 event                main',
    '  parser tests       monitor                   running 2m 3s · 4 events               parser',
    '❯ Fix the tokenizer  task · fake · Fake Small  ● permission 13s                       main',
    '  Fix the printer    task · fake · Fake Large  working 32s                            coder',
  ]);
});

test("narrower, an end's events go first, then a task's model, then its runtime; the state and owner stay", () => {
  const at = (width: number) =>
    text(viewRows(ITEMS, { width, focus: undefined, now: NOW }));

  expect(at(85)).toStrictEqual([
    '❯ CI run 4812        monitor                   ✗ exit code 1 after 3m 12s  main',
    '  dev server errors  monitor                   running 4m 2s · 1 event     main',
    '  parser tests       monitor                   running 2m 3s · 4 events    parser',
    '  Fix the tokenizer  task · fake · Fake Small  ● permission 13s            main',
    '  Fix the printer    task · fake · Fake Large  working 32s                 coder',
  ]);
  expect(at(76)).toStrictEqual([
    '❯ CI run 4812        monitor      ✗ exit code 1 after 3m 12s  main',
    '  dev server errors  monitor      running 4m 2s · 1 event     main',
    '  parser tests       monitor      running 2m 3s · 4 events    parser',
    '  Fix the tokenizer  task · fake  ● permission 13s            main',
    '  Fix the printer    task · fake  working 32s                 coder',
  ]);
  expect(at(66)[3]).toStrictEqual(
    '  Fix the tokenizer  task     ● permission 13s            main',
  );
});

test('narrower still, each item takes two lines: its name and kind, then its state and owner two cells further in', () => {
  const at = (width: number) =>
    text(viewRows(ITEMS.slice(2, 4), { width, focus: undefined, now: NOW }));

  expect(at(46)).toStrictEqual([
    '❯ parser tests       monitor',
    '    running 2m 3s · 4 events  parser',
    '  Fix the tokenizer  task · fake · Fake Small',
    '    ● permission 13s  main',
  ]);
  // The kind's parts give way before it leaves the name's line.
  expect(at(40)).toStrictEqual([
    '❯ parser tests       monitor',
    '    running 2m 3s · 4 events  parser',
    '  Fix the tokenizer  task · fake',
    '    ● permission 13s  main',
  ]);

  // Not even a bare kind beside the name: it goes to a line of its own,
  // and a state and owner too wide together go one under the other.
  const narrow = at(24);

  expect(narrow).toStrictEqual([
    '❯ parser tests',
    '    monitor',
    '    running 2m 3s · 4',
    '    events',
    '    parser',
    '  Fix the tokenizer',
    '    task',
    '    ● permission 13s',
    '    main',
  ]);
  expect(narrow.every((line) => line.length <= 24)).toStrictEqual(true);
});

test('a name past 24 cells wraps two cells short of its column, the rest two cells in, the other columns on its first line', () => {
  const long = monitor('m9', 'Run the parser suite in watch mode', {
    group: 'running',
  });

  expect(
    text(
      viewRows([long, ITEMS[1]!], { width: 116, focus: undefined, now: NOW }),
    ),
  ).toStrictEqual([
    '❯ Run the parser suite      monitor  running 4m 2s · 1 event  main',
    '    in watch mode',
    '  dev server errors         monitor  running 4m 2s · 1 event  main',
  ]);
});

test('↑ ↓ move the ❯ by rows, stopping at the first and last, and it follows its item', () => {
  expect(moveViewFocus(ITEMS, undefined, 1)).toStrictEqual({
    key: 1,
    id: 'm2',
  });
  expect(moveViewFocus(ITEMS, undefined, -1)).toStrictEqual({
    key: 1,
    id: 'm1',
  });
  expect(moveViewFocus(ITEMS, { key: 3, id: 't2' }, 1)).toStrictEqual({
    key: 3,
    id: 't2',
  });
  // m1 of agent 2 is not m1 of agent 1.
  expect(moveViewFocus(ITEMS, { key: 2, id: 'm1' }, 1)).toStrictEqual({
    key: 1,
    id: 't1',
  });
  // An item gone leaves the ❯ on the first.
  expect(moveViewFocus(ITEMS, { key: 9, id: 'x' }, 1)).toStrictEqual({
    key: 1,
    id: 'm2',
  });
  expect(moveViewFocus([], undefined, 1)).toStrictEqual(undefined);
});

test('more rows than fit scroll to keep the ❯ in sight, the gutter marking the rest above and below (CHD-462)', () => {
  const many = Array.from({ length: 30 }, (_, index) =>
    monitor(`m${index + 1}`, `build ${index + 1}`, { group: 'running' }),
  );
  const window = (focus: number, height: number) => {
    const shown = viewWindow(
      viewRows(many, {
        width: 76,
        focus: { key: 1, id: `m${focus}` },
        now: NOW,
      }),
      height,
    );

    return {
      names: shown.rows.map((row) => row.item.name),
      above: shown.above,
      below: shown.below,
    };
  };

  // At the top, every line a row: the marks take none.
  expect(window(1, 20)).toStrictEqual({
    names: many.slice(0, 20).map((item) => item.name),
    above: 0,
    below: 10,
  });

  // Scrolled just far enough for the ❯.
  const scrolled = window(25, 20);

  expect(scrolled.names.at(-1)).toStrictEqual('build 25');
  expect(scrolled.names.length).toStrictEqual(20);
  expect(scrolled.above + scrolled.names.length + scrolled.below).toStrictEqual(
    30,
  );
  // At the end, nothing below.
  expect(window(30, 20)).toStrictEqual({
    names: many.slice(10).map((item) => item.name),
    above: 10,
    below: 0,
  });
  // All fit: neither.
  expect(window(1, 40).above + window(1, 40).below).toStrictEqual(0);
});

test('a long unbroken name breaks where wrap-ansi breaks it, every character kept and nothing added', () => {
  const name = 'x'.repeat(60);
  const rows = viewRows([monitor('m1', name, { group: 'running' })], {
    width: 116,
    focus: undefined,
    now: NOW,
  });
  const names = rows[0]!.lines.map((line) =>
    line.find((cell) => cell.role === 'name')!.text.trimEnd(),
  );

  expect(names).toStrictEqual(['x'.repeat(22), 'x'.repeat(22), 'x'.repeat(16)]);
  expect(names.join('')).toStrictEqual(name);
});

describe('CHD-424 tester: view layout edges', () => {
  test('long unbroken Unicode names keep every grapheme at wide and narrow widths', () => {
    for (const name of [
      '界'.repeat(30),
      'e\u0301'.repeat(60),
      '👩‍💻'.repeat(30),
    ]) {
      for (const width of [24, 40, 76, 116]) {
        const rows = viewRows([monitor('m1', name, { group: 'running' })], {
          width,
          focus: undefined,
          now: NOW,
        });
        const kept = rows[0]!.lines
          .flatMap((line) =>
            line
              .filter(({ role }) => role === 'name')
              .map(({ text }) => text.trimEnd()),
          )
          .join('');

        expect(kept.normalize('NFC')).toBe(name.normalize('NFC'));
        expect(text(rows).every((line) => stringWidth(line) <= width)).toBe(
          true,
        );
      }
    }
  });

  test('ended durations freeze while working and asking durations advance from their own clocks', () => {
    const ended = ITEMS[0]!;
    const asking = ITEMS[3]!;
    const working = ITEMS[4]!;

    expect(stateText(ended, NOW + 90_000)).toStrictEqual(stateText(ended, NOW));
    expect(stateText(asking, NOW + 2_000).text).toBe('● permission 15s');
    expect(stateText(working, NOW + 2_000).text).toBe('working 34s');
  });

  test('every focus stays visible among variable-height rows and the indicators count items', () => {
    const many = Array.from({ length: 30 }, (_, index) =>
      monitor(
        `m${index + 1}`,
        index % 2 === 0
          ? `build-${index + 1}-` + 'x'.repeat(48)
          : `build ${index + 1}`,
        { group: 'running' },
      ),
    );

    for (const width of [24, 40, 76]) {
      for (const item of many) {
        const shown = viewWindow(
          viewRows(many, {
            width,
            focus: item,
            now: NOW,
          }),
          20,
        );
        const occupied =
          shown.rows.reduce((n, row) => n + row.lines.length, 0) +
          Number(shown.above > 0) +
          Number(shown.below > 0);

        expect(
          shown.rows
            .filter(({ focused }) => focused)
            .map(({ item }) => item.id),
        ).toStrictEqual([item.id]);
        expect(occupied).toBeLessThanOrEqual(20);
        expect(shown.above + shown.rows.length + shown.below).toBe(many.length);
      }
    }
  });

  test('a state change keeps focus on the same owner when monitor ids collide across agents', () => {
    const focus = { key: 2, id: 'm1' };
    const changed = ITEMS.map((item) =>
      item.key === focus.key && item.id === focus.id
        ? { ...item, status: { group: 'stopped' as const, endedAt: NOW } }
        : item,
    );
    const laid = viewRows(changed, { width: 76, focus, now: NOW });

    expect(laid.map(({ item }) => item.name)).toStrictEqual(
      ITEMS.map(({ name }) => name),
    );
    expect(
      laid
        .filter(({ focused }) => focused)
        .map(({ item }) => [item.key, item.id]),
    ).toStrictEqual([[2, 'm1']]);
    expect(text(laid).find((line) => line.startsWith('❯'))).toContain(
      'parser tests',
    );
  });
});

test("an agent item's state reads as CHD-2's table words it", () => {
  const say = (status: BackgroundItem['status']) =>
    stateText(
      {
        kind: 'agent',
        id: 'a',
        key: 1,
        name: 'Explore the parser',
        startedAt: NOW - 41_000,
        status,
      },
      NOW,
    ).text;
  const ended = (
    group: 'done' | 'failed' | 'stopped',
    word?: 'ended' | 'disconnected',
  ) => ({
    group,
    endedAt: NOW - 41_000 + 124_000 - 83_000,
    ...(word === undefined ? {} : { word }),
  });

  expect(say({ group: 'running' })).toBe('running 41s');
  expect(say({ group: 'running', stopping: true })).toBe('■ stopping 41s');
  expect(say({ group: 'asking', on: 'permission', since: NOW - 13_000 })).toBe(
    '● permission 13s',
  );
  expect(say({ group: 'asking', on: 'input', since: NOW - 13_000 })).toBe(
    '● input 13s',
  );
  expect(say({ group: 'asking', on: 'waiting', since: NOW - 13_000 })).toBe(
    '● waiting 13s',
  );
  expect(say(ended('done'))).toBe('✓ done in 41s');
  expect(say(ended('failed'))).toBe('✗ failed after 41s');
  expect(say(ended('failed', 'disconnected'))).toBe('✗ disconnected after 41s');
  expect(say(ended('stopped'))).toBe('■ stopped after 41s');
  expect(say(ended('stopped', 'ended'))).toBe('■ ended after 41s');
  // Its time stands at the unknown.
  expect(say({ group: 'untracked', endedAt: NOW - 20_000 })).toBe(
    '? untracked 21s',
  );
});

describe('CHD-2 tester: agent row clocks and wrapping', () => {
  test('untracked time freezes while stopping time advances from the original start', () => {
    const base: BackgroundItem = {
      kind: 'agent',
      id: 'a',
      key: 1,
      name: 'A',
      startedAt: NOW - 10_000,
      status: { group: 'untracked', endedAt: NOW - 5000 },
    };

    expect(stateText(base, NOW + 60_000).text).toBe('? untracked 5s');
    expect(
      stateText(
        { ...base, status: { group: 'running', stopping: true } },
        NOW + 60_000,
      ).text,
    ).toBe('■ stopping 1m 10s');
  });

  test('long agent names preserve state and owner in narrow and wide rows', () => {
    const name = 'Read the transport tests and describe cancellation';
    const entry: BackgroundItem = {
      kind: 'agent',
      id: 'a',
      key: 2,
      owner: PARSER,
      name,
      startedAt: NOW - 20_000,
      status: { group: 'untracked', endedAt: NOW - 10_000 },
    };

    for (const width of [76, 116]) {
      const rows = viewRows([entry], { width, focus: entry, now: NOW });
      const lines = text(rows);
      const kept = rows[0]!.lines
        .flatMap((line) =>
          line
            .filter(({ role }) => role === 'name')
            .map(({ text }) => text.trim()),
        )
        .join(' ');

      expect(kept).toBe(name);
      expect(lines[0]).toContain('? untracked 10s');
      expect(lines[0]).toContain('parser');
      expect(lines.every((line) => stringWidth(line) <= width)).toBe(true);
    }
  });
});

test("a stop that could not be sent says its error's first line", () => {
  expect(stopRefused(new Error('Session not found\nat line 2'))).toBe(
    'could not stop: Session not found',
  );
  expect(stopRefused('closed')).toBe('could not stop: closed');
});

test("the gutter says what is out of sight, as the pickers' edges do: ↑ on the first line, ↓ on the last, the ❯ keeping its place (CHD-462)", () => {
  const many = Array.from({ length: 10 }, (_, index) =>
    monitor(`m${index + 1}`, `build ${index + 1}`, { group: 'running' }),
  );
  const marked = (focus: number) =>
    edgeMarked(
      viewWindow(
        viewRows(many, {
          width: 76,
          focus: { key: 1, id: `m${focus}` },
          now: NOW,
        }),
        4,
      ),
    ).map(({ cells }) => cells.map((cell) => cell.text).join(''));

  // The top: nothing above, more below.
  expect(marked(1).map((line) => line.slice(0, 2))).toStrictEqual([
    '❯ ',
    '  ',
    '  ',
    '↓ ',
  ]);
  // Scrolled to the middle: the ❯ on the last line in sight keeps it.
  expect(marked(6).map((line) => line.slice(0, 2))).toStrictEqual([
    '↑ ',
    '  ',
    '  ',
    '❯ ',
  ]);
  // Every line keeps its width.
  expect(marked(6)[0]!.slice(2)).toBe(marked(1)[1]!.slice(2).replace('2', '3'));
});
