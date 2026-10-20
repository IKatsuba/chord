import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import type { BackgroundItem } from '../../../src/ui/background/background.ts';
import {
  laidAt,
  moveView,
  type ViewAt,
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

test("narrower, nothing gives way: a task's kind wraps in its column after a ` · `, then a state in its own, and the row grows a line (CHD-473)", () => {
  const at = (width: number) =>
    text(viewRows(ITEMS, { width, focus: undefined, now: NOW }));

  expect(at(85)).toStrictEqual([
    '❯ CI run 4812        monitor            ✗ exit code 1 after 3m 12s · 3 events  main',
    '  dev server errors  monitor            running 4m 2s · 1 event                main',
    '  parser tests       monitor            running 2m 3s · 4 events               parser',
    '  Fix the tokenizer  task · fake ·      ● permission 13s                       main',
    '                     Fake Small',
    '  Fix the printer    task · fake ·      working 32s                            coder',
    '                     Fake Large',
  ]);
  // Narrower, the state wraps in its column too, after a ` · ` and at its
  // spaces; the columns hold.
  expect(at(76)).toStrictEqual([
    '❯ CI run 4812        monitor        ✗ exit code 1 after 3m 12s ·      main',
    '                                    3 events',
    '  dev server errors  monitor        running 4m 2s · 1 event           main',
    '  parser tests       monitor        running 2m 3s · 4 events          parser',
    '  Fix the tokenizer  task · fake ·  ● permission 13s                  main',
    '                     Fake Small',
    '  Fix the printer    task · fake ·  working 32s                       coder',
    '                     Fake Large',
  ]);
  expect(at(60).slice(0, 3)).toStrictEqual([
    '❯ CI run 4812        monitor        ✗ exit code 1     main',
    '                                    after 3m 12s ·',
    '                                    3 events',
  ]);
  // Not even the state's widest word beside the kind's widest part: the
  // state and owner go under the name.
  expect(at(46).slice(0, 3)).toStrictEqual([
    '❯ CI run 4812        monitor',
    '    ✗ exit code 1 after 3m 12s · 3 events',
    '    main',
  ]);
});

test('narrower still, each item takes two lines or more: its name and kind, then its state and owner two cells further in, nothing given way (CHD-473)', () => {
  const at = (width: number) =>
    text(viewRows(ITEMS.slice(2, 4), { width, focus: undefined, now: NOW }));

  expect(at(46)).toStrictEqual([
    '❯ parser tests       monitor',
    '    running 2m 3s · 4 events  parser',
    '  Fix the tokenizer  task · fake · Fake Small',
    '    ● permission 13s  main',
  ]);
  // The kind does not fit beside the name: it goes to lines of its own,
  // whole.
  expect(at(40)).toStrictEqual([
    '❯ parser tests',
    '    monitor',
    '    running 2m 3s · 4 events  parser',
    '  Fix the tokenizer',
    '    task · fake · Fake Small',
    '    ● permission 13s  main',
  ]);

  // A kind wider than a line wraps after a ` · `, and a state and owner
  // too wide together go one under the other.
  const narrow = at(24);

  expect(narrow).toStrictEqual([
    '❯ parser tests',
    '    monitor',
    '    running 2m 3s · 4',
    '    events',
    '    parser',
    '  Fix the tokenizer',
    '    task · fake ·',
    '    Fake Small',
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
  const moveViewFocus = (
    items: readonly BackgroundItem[],
    focus: { key: number; id: string } | undefined,
    by: 1 | -1,
  ) =>
    moveView(items, focus === undefined ? undefined : { focus }, by, {
      width: 116,
      height: 40,
      now: NOW,
    })?.focus;

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

  test('every focus stays visible among variable-height rows and gutter marks consume no extra lines', () => {
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
        const visible = edgeMarked(shown);

        expect(
          shown.rows
            .filter(({ focused }) => focused)
            .map(({ item }) => item.id),
        ).toStrictEqual([item.id]);
        expect(visible).toHaveLength(shown.height);
        expect(visible.length).toBeLessThanOrEqual(20);
        expect(visible.some(({ row }) => row.item.id === item.id)).toBe(true);
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

describe('a row taller than the frame scrolls by line inside it (CHD-430)', () => {
  const tall = task('t1', 'word '.repeat(120).trim(), { group: 'running' });
  const short = task('t2', 'Watch the build', { group: 'running' });
  const items = [short, tall, task('t3', 'Lint', { group: 'running' })];
  const frame = { width: 76, height: 6, now: NOW };
  const laid = laidAt(frame.width, frame.height);
  /** The lines in sight at `at`, each as text, its gutter first. */
  const shown = (at: ViewAt) =>
    edgeMarked(
      viewWindow(
        viewRows(items, { width: frame.width, focus: at.focus, now: NOW }),
        frame.height,
        at,
        laid,
      ),
    ).map(({ cells }) => cells.map((cell) => cell.text).join(''));
  // The tall row's lines, which start on the second line of all.
  const lines = viewRows(items, {
    width: frame.width,
    focus: undefined,
    now: NOW,
  })[1]!.lines.length;
  const t1 = { key: 1, id: 't1' };

  test('reached with ↓, it shows from its first line, the ❯ on it; each ↓ scrolls a line, then the next row comes whole into sight below its last lines', () => {
    let at = moveView(items, { focus: { key: 1, id: 't2' } }, 1, frame)!;

    expect(at).toStrictEqual({ focus: t1, top: 1, laid });
    expect(shown(at)[0]).toStartWith('❯ word');
    expect(shown(at).at(-1)).toStartWith('↓ ');

    for (let step = 1; step <= lines - 6; step++) {
      at = moveView(items, at, 1, frame)!;

      expect(at.top).toBe(1 + step);
      expect(shown(at)).toHaveLength(6);
    }

    // Its first line out of sight, the gutter's ↑ stands for it.
    expect(shown(at)[0]).toStartWith('↑ ');
    expect(shown(at).some((line) => line.includes('❯'))).toBeFalsy();

    // Off it: the next row comes whole into sight, its last lines above.
    const off = moveView(items, at, 1, frame)!;

    expect(off).toStrictEqual({
      focus: { key: 1, id: 't3' },
      top: lines + 2 - 6,
      laid,
    });
    expect(shown(off)).toHaveLength(6);
    expect(shown(off)[0]).toStartWith('↑ ');
    expect(shown(off).at(-1)).toStartWith('❯ Lint');
  });

  test('reached with ↑, it shows from its last line, and each ↑ scrolls a line up, then the row above', () => {
    let at = moveView(items, { focus: { key: 1, id: 't3' } }, -1, frame)!;

    expect(at).toStrictEqual({ focus: t1, top: lines + 1 - 6, laid });
    expect(shown(at)[0]).toStartWith('↑ ');
    expect(shown(at).at(-1)).toStartWith('↓ ');

    while (at.top! > 1) {
      at = moveView(items, at, -1, frame)!;

      expect(at.focus).toStrictEqual(t1);
    }

    expect(shown(at)[0]).toStartWith('❯ word');

    const off = moveView(items, at, -1, frame)!;

    expect(off).toStrictEqual({ focus: { key: 1, id: 't2' }, top: 0, laid });
    expect(shown(off)[0]).toStartWith('❯ Watch the build');
    expect(shown(off)).toHaveLength(6);
  });

  test('at another size, or with no line kept, a tall row shows from its first line again', () => {
    const scrolled = { focus: t1, top: 5, laid };

    expect(shown(scrolled)[0]).toStartWith('↑ ');
    expect(shown({ ...scrolled, laid: laidAt(70, 6) })[0]).toStartWith(
      '❯ word',
    );
    expect(shown({ focus: t1 })[0]).toStartWith('❯ word');
  });

  test('rows that all fit are moved over whole, nothing scrolled', () => {
    expect(
      moveView(items, { focus: { key: 1, id: 't2' } }, 1, {
        ...frame,
        height: 40,
      }),
    ).toStrictEqual({ focus: t1, top: 0, laid: laidAt(76, 40) });
  });
});

test("an ended task's row says its money after its state, which never gives way (CHD-373, CHD-473)", () => {
  const spent = {
    cost: { amount: 0.0125, currency: 'USD' },
    tokens: { totalTokens: 2000 },
  };
  const ended = task(
    't1',
    'Fix the tokenizer',
    { group: 'failed', endedAt: NOW },
    { spent, startedAt: NOW - 15_000 },
  );

  expect(stateText(ended, NOW).text).toBe('✗ failed after 15s · $0.0125');
  expect(
    stateText({ ...ended, spent: { ...spent, estimated: true } }, NOW).text,
  ).toBe('✗ failed after 15s · ~$0.0125');
  // While it works, none.
  expect(
    stateText({ ...ended, status: { group: 'running' } }, NOW).text,
  ).not.toContain('$');

  // At any width its model, its money and its runtime all stay (CHD-473).
  const drawn = (width: number) =>
    text(viewRows([ended], { width, focus: undefined, now: NOW })).join(' ');

  for (let width = 120; width > 30; width--) {
    for (const part of ['task', 'fake', 'Fake Small', '$0.0125']) {
      expect(drawn(width), `${width}`).toContain(part);
    }
  }
});

describe('CHD-373 S2 tester: zero and absent money in background states', () => {
  for (const group of ['done', 'failed', 'stopped'] as const) {
    test(`${group} retains reported zero money while absent cost stays absent`, () => {
      const item = task(
        'zero',
        'Zero cost',
        { group, endedAt: NOW },
        {
          spent: {
            cost: { amount: 0, currency: 'USD' },
            tokens: { totalTokens: 0 },
          },
        },
      );

      expect(stateText(item, NOW).text).toContain('$0.0000');
      expect(
        stateText(task('missing', 'No cost', { group, endedAt: NOW }), NOW)
          .text,
      ).not.toContain('$');
      expect(
        stateText({ ...item, spent: { ...item.spent!, estimated: true } }, NOW)
          .text,
      ).toContain('~$0.0000');
    });
  }
});

test("a task's runtime or model with CR, LF or tabs reads as spaces in every layout, no line holding a line break and no word lost (CHD-473)", () => {
  const odd = task(
    't9',
    'Fix the tokenizer',
    { group: 'running' },
    { runtime: 'fake\tlocal', model: 'Fake\r\nSmall\nmodel' },
  );

  for (const width of [116, 60, 40, 24]) {
    const drawn = text(
      viewRows([ITEMS[0]!, odd], { width, focus: undefined, now: NOW }),
    );

    expect(
      drawn.some((line) => /[\r\n\t]/.test(line)),
      `${width}`,
    ).toBe(false);
    expect(drawn.join(' ').replace(/\s+/g, ' '), `${width}`).toContain(
      'fake local',
    );

    for (const word of ['Fake', 'Small', 'model']) {
      expect(drawn.join(' '), `${width}`).toContain(word);
    }
  }

  expect(
    text(viewRows([odd], { width: 116, focus: undefined, now: NOW }))[0],
  ).toBe(
    '❯ Fix the tokenizer  task · fake local · Fake Small model  working 32s  main',
  );
});
