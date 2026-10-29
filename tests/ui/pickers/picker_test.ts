import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  agentChoices,
  choiceKey,
  choiceLines,
  CURRENT_MARK,
  DIRECTORY_WIDTH,
  initialChoice,
  lastUsed,
  fromFirstLine,
  lineKey,
  linedRows,
  openLineView,
  type ModelChoice,
  modelChoices,
  modelToAsk,
  openView,
  optionChoices,
  type PickerKey,
  pickerKey,
  pickerLayout,
  pickerLines,
  pickerRows,
  type PickerView,
  sessionChoices,
  valueChoices,
  valueToAsk,
} from '../../../src/ui/pickers/picker.ts';

const MODELS = {
  available: [
    { id: 'fake-large', name: 'Fake Large' },
    { id: 'fake-small', name: 'Fake Small' },
  ],
  current: 'fake-small',
};

/** Twelve models, as Claude Code offers, the eleventh in use. */
const TWELVE = modelChoices({
  available: Array.from({ length: 12 }, (_, index) => ({
    id: `m${index + 1}`,
    name: `Model ${index + 1}`,
  })),
  current: 'm11',
});

const NO_KEY: PickerKey = {
  upArrow: false,
  downArrow: false,
  return: false,
  shift: false,
};

/** What the list shows: edge, number and label of each row, and the rest. */
function drawn(choices: readonly ModelChoice[], view: PickerView, rows = 6) {
  const shown = pickerRows(choices, view, rows);

  return [
    ...shown.rows.map(
      ({ edge, number, choice, highlighted }) =>
        `${highlighted ? '❯' : ' '}${edge ?? ''}${number} ${choice.label}`,
    ),
    ...(shown.hidden > 0 ? [`+${shown.hidden}`] : []),
  ];
}

/** The view after pressing each of `presses` in turn. */
function press(
  view: PickerView,
  ...presses: (string | Partial<PickerKey>)[]
): PickerView {
  return presses.reduce<PickerView>((at, pressed) => {
    const step =
      typeof pressed === 'string'
        ? pickerKey(at, TWELVE.length, 6, pressed, NO_KEY)
        : pickerKey(at, TWELVE.length, 6, '', { ...NO_KEY, ...pressed });

    return step?.type === 'move' ? step.view : at;
  }, view);
}

test("the picker lists the agent's models and marks the one in use", () => {
  const choices = modelChoices(MODELS);

  expect(choices.map(({ label }) => label)).toStrictEqual([
    'Fake Large',
    `Fake Small ${CURRENT_MARK}`,
  ]);
  expect(choices.map(({ value }) => value)).toStrictEqual([
    'fake-large',
    'fake-small',
  ]);
  expect(initialChoice(choices)).toStrictEqual(1);
});

test('a list that fits is numbered, with no edge column and nothing hidden', () => {
  const choices = modelChoices(MODELS);

  expect(drawn(choices, openView(choices, 6))).toStrictEqual([
    ' 1. Fake Large',
    `❯2. Fake Small ${CURRENT_MARK}`,
  ]);
});

test('the highlight starts on the first when none is in use', () => {
  const choices = modelChoices({ available: MODELS.available });

  expect(choices.some(({ current }) => current)).toStrictEqual(false);
  expect(initialChoice(choices)).toStrictEqual(0);
  expect(modelChoices(undefined)).toStrictEqual([]);
});

test('picking the model in use asks the agent for nothing', () => {
  expect(modelToAsk(MODELS, 'fake-small')).toStrictEqual(undefined);
  expect(modelToAsk(MODELS, 'fake-large')).toStrictEqual('fake-large');
  expect(modelToAsk(undefined, 'fake-large')).toStrictEqual('fake-large');
});

test('a long list opens with the model in use in sight, marking what is hidden', () => {
  expect(drawn(TWELVE, openView(TWELVE, 6))).toStrictEqual([
    ' ↑6.  Model 6',
    '  7.  Model 7',
    '  8.  Model 8',
    '  9.  Model 9',
    '  10. Model 10',
    `❯↓11. Model 11 ${CURRENT_MARK}`,
    '+6',
  ]);
});

test('the window slides with the highlight and stops at either end', () => {
  const top = press(openView(TWELVE, 6), ...Array(20).fill('k'));

  expect(top).toStrictEqual({ highlighted: 0, top: 0 });
  expect(drawn(TWELVE, top)).toStrictEqual([
    '❯ 1.  Model 1',
    '  2.  Model 2',
    '  3.  Model 3',
    '  4.  Model 4',
    '  5.  Model 5',
    ' ↓6.  Model 6',
    '+6',
  ]);
  // The window holds still while the highlight walks inside it.
  expect(press(top, 'j', 'j', 'j', 'j', 'j')).toStrictEqual({
    highlighted: 5,
    top: 0,
  });
  expect(drawn(TWELVE, press(top, ...Array(6).fill('j')))).toStrictEqual([
    ' ↑2.  Model 2',
    '  3.  Model 3',
    '  4.  Model 4',
    '  5.  Model 5',
    '  6.  Model 6',
    `❯↓7.  Model 7`,
    '+6',
  ]);
  expect(press(top, ...Array(20).fill({ downArrow: true }))).toStrictEqual({
    highlighted: 11,
    top: 6,
  });
});

test('a digit picks by the place in the whole list, Enter the highlighted', () => {
  const view = openView(TWELVE, 6);

  expect(pickerKey(view, 12, 6, '2', NO_KEY)).toStrictEqual({
    type: 'pick',
    index: 1,
  });
  expect(pickerKey(view, 12, 6, '', { ...NO_KEY, return: true })).toStrictEqual(
    {
      type: 'pick',
      index: 10,
    },
  );
  expect(
    pickerKey(openView(TWELVE.slice(0, 2), 6), 2, 6, '3', NO_KEY),
  ).toStrictEqual(undefined);
});

test('shift+arrows are the window’s, not the list’s', () => {
  const view = openView(TWELVE, 6);

  expect(press(view, { upArrow: true, shift: true })).toStrictEqual(view);
  expect(press(view, { upArrow: true }).highlighted).toStrictEqual(9);
});

const NOW = Date.parse('2026-10-05T12:00:00.000Z');

test('a session reads as how long ago it was last used', () => {
  const ago = (seconds: number) =>
    lastUsed(new Date(NOW - seconds * 1000).toISOString(), NOW);

  expect(ago(30)).toStrictEqual('just now');
  expect(ago(5 * 60)).toStrictEqual('5 minutes ago');
  expect(ago(3 * 60 * 60)).toStrictEqual('3 hours ago');
  expect(ago(26 * 60 * 60)).toStrictEqual('yesterday');
  expect(ago(3 * 24 * 60 * 60)).toStrictEqual('3 days ago');
  expect(ago(15 * 24 * 60 * 60)).toStrictEqual('2 weeks ago');
  expect(ago(400 * 24 * 60 * 60)).toStrictEqual('last year');
  // A clock behind the record's is not the future.
  expect(ago(-60)).toStrictEqual('just now');
  expect(lastUsed('soon', NOW)).toStrictEqual('soon');
});

test("/resume's rows line the prompts up after when each was used", () => {
  const session = (id: string, at: string, prompt: string) => ({
    resume: { sessionId: id, cwd: '/work' },
    lastUsedAt: at,
    prompt,
  });
  const choices = sessionChoices(
    [
      session('s1', '2026-10-05T11:58:00.000Z', 'fix the build'),
      session('s2', '2026-10-02T12:00:00.000Z', 'add a test'),
    ],
    NOW,
  );

  expect(choices).toStrictEqual([
    { key: 's1', label: '2 minutes ago  fix the build', hang: 15, value: '0' },
    { key: 's2', label: '3 days ago     add a test', hang: 15, value: '1' },
  ]);
  // None is in use, so the highlight starts on the newest.
  expect(initialChoice(choices)).toStrictEqual(0);
});

test("every directory's /resume rows name each directory from ~, cut from the start at a /", () => {
  const session = (id: string, cwd: string, prompt: string) => ({
    resume: { sessionId: id, cwd },
    lastUsedAt: '2026-10-05T11:58:00.000Z',
    prompt,
  });
  const long = 'a'.repeat(40);
  const choices = sessionChoices(
    [
      session('s1', '/h/src/app', 'fix the build'),
      session('s2', '/srv/api', 'add a test'),
      session(
        's3',
        '/h/work/deeply/nested/projects/with-a-long-name/service',
        'deep',
      ),
      session('s4', `/h/src/${long}`, 'long'),
    ],
    NOW,
    { home: '/h' },
  );
  // A last segment longer than the column has no / to cut at.
  const cut = `…${long.slice(-(DIRECTORY_WIDTH - 1))}`;

  expect(choices.map(({ label }) => label)).toStrictEqual([
    `2 minutes ago  ${'~/src/app'.padEnd(DIRECTORY_WIDTH)}  fix the build`,
    `2 minutes ago  ${'/srv/api'.padEnd(DIRECTORY_WIDTH)}  add a test`,
    `2 minutes ago  ${'…/with-a-long-name/service'.padEnd(
      DIRECTORY_WIDTH,
    )}  deep`,
    `2 minutes ago  ${cut}  long`,
  ]);
});

const EFFORT = {
  id: 'effort',
  name: 'Effort',
  values: [
    { value: 'low', name: 'Low' },
    { value: 'medium', name: 'Medium' },
    { value: 'high', name: 'High' },
  ],
  current: 'medium',
};

test("/config's options line their values up after their names", () => {
  expect(
    optionChoices([
      EFFORT,
      {
        id: 'verbosity',
        name: 'Verbosity',
        values: [{ value: 'terse', name: 'Terse' }],
        current: 'terse',
      },
    ]),
  ).toStrictEqual([
    { key: 'effort', label: 'Effort     Medium', value: 'effort' },
    { key: 'verbosity', label: 'Verbosity  Terse', value: 'verbosity' },
  ]);
  expect(optionChoices([])).toStrictEqual([]);
});

test("/config's options open on the one Esc came back from", () => {
  const verbosity = {
    id: 'verbosity',
    name: 'Verbosity',
    values: [{ value: 'terse', name: 'Terse' }],
    current: 'terse',
  };

  expect(
    optionChoices([EFFORT, verbosity], 'verbosity').map(
      ({ current }) => current,
    ),
  ).toStrictEqual([undefined, true]);
});

test("an option's values mark the one it is set to, and start on it", () => {
  const choices = valueChoices(EFFORT);

  expect(choices.map(({ label }) => label)).toStrictEqual([
    'Low',
    `Medium ${CURRENT_MARK}`,
    'High',
  ]);
  expect(initialChoice(choices)).toStrictEqual(1);
});

test('the value an option is set to already asks the agent for nothing', () => {
  expect(valueToAsk(EFFORT, 'medium')).toStrictEqual(undefined);
  expect(valueToAsk(EFFORT, 'high')).toStrictEqual('high');
});

test("/resume's rows say which session is open now, as a child of this one", () => {
  const session = (id: string, at: string, prompt: string) => ({
    resume: { sessionId: id, cwd: '/work' },
    lastUsedAt: at,
    prompt,
  });
  const choices = sessionChoices(
    [
      session('s1', '2026-10-05T11:58:00.000Z', 'fix the build'),
      session('s2', '2026-10-02T12:00:00.000Z', 'add a test'),
    ],
    NOW,
    undefined,
    new Set(['s2']),
  );

  expect(choices.map(({ label }) => label)).toStrictEqual([
    '2 minutes ago            fix the build',
    '3 days ago     open now  add a test',
  ]);
});

test("a numbered list's keys move round, pick, and leave shift+arrows alone", () => {
  const key = { ctrl: false, escape: false };

  expect(choiceKey('', { ...key, upArrow: true }, 0, 3)).toStrictEqual({
    move: 2,
  });
  expect(choiceKey('j', key, 2, 3)).toStrictEqual({ move: 0 });
  expect(choiceKey('', { ...key, return: true }, 1, 3)).toStrictEqual({
    pick: 1,
  });
  expect(
    choiceKey('', { ...key, return: true, shift: true }, 1, 3),
  ).toStrictEqual({ pick: 1 });
  expect(choiceKey('3', key, 0, 3)).toStrictEqual({ pick: 2 });
  expect(choiceKey('4', key, 0, 3)).toBeUndefined();
  expect(
    choiceKey('', { ...key, upArrow: true, shift: true }, 1, 3),
  ).toBeUndefined();
});

test('a box that ends at its last choice leaves on ↓ or j there, and still wraps on ↑ (Q194)', () => {
  const key = { ctrl: false, escape: false };

  expect(choiceKey('', { ...key, downArrow: true }, 2, 3, true)).toStrictEqual({
    leave: true,
  });
  expect(choiceKey('j', key, 2, 3, true)).toStrictEqual({ leave: true });
  expect(choiceKey('j', key, 1, 3, true)).toStrictEqual({ move: 2 });
  expect(choiceKey('', { ...key, upArrow: true }, 0, 3, true)).toStrictEqual({
    move: 2,
  });
  // A box alone, Decline its one choice, leaves at once.
  expect(choiceKey('j', key, 0, 1, true)).toStrictEqual({ leave: true });
});

test('a /resume label wider than its row wraps at its spaces under its own start, a word broken only where it alone is wider; a choice that does not hang stays one line (CHD-445)', () => {
  const [row] = sessionChoices(
    [
      {
        resume: { sessionId: 's1', cwd: '/work' },
        lastUsedAt: '2026-10-05T11:58:00.000Z',
        prompt: 'Fix the tokenizer handling of a quoted string at the end',
      },
    ],
    NOW,
  );

  expect(choiceLines(row!, 40)).toStrictEqual([
    '2 minutes ago  Fix the tokenizer',
    '               handling of a quoted',
    '               string at the end',
  ]);
  expect(choiceLines(row!, 200)).toStrictEqual([row!.label]);
  expect(
    choiceLines(
      { key: 'x', label: 'abc  ' + 'z'.repeat(12), hang: 5, value: 'x' },
      10,
    ),
  ).toStrictEqual(['abc  zzzzz', '     zzzzz', '     zz']);
  expect(
    choiceLines(
      { key: 'm', label: 'a model name past the edge', value: 'm' },
      5,
    ),
  ).toStrictEqual(['a model name past the edge']);
});

test("a row taller than the picker is read a line a press while highlighted, the view moving the least it must, and no '+N more' then (CHD-445)", () => {
  // As the design's 80×24 mock: row 2 wraps to 8 lines in a budget of 6.
  const lines = [
    ['Fix the tokenizer'],
    ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
    ['docs · Fix the parser'],
  ];
  const heights = lines.map((each) => each.length);
  const choices = lines.map((_, index) => ({
    key: String(index),
    label: String(index),
    value: String(index),
  }));
  const down = { upArrow: false, downArrow: true, return: false, shift: false };
  const up = { ...down, upArrow: true, downArrow: false };
  const drawn = (view: PickerView) => {
    const shown = linedRows(choices, lines, view, 6);

    return [
      ...shown.rows.flatMap((row) =>
        row.lines.map(
          (line) =>
            `${line.edge ?? ''}${row.highlighted && line.first ? '❯' : ' '}${line.first ? row.number : '  '} ${line.text}`,
        ),
      ),
      ...(shown.hidden > 0 ? [`+${shown.hidden}`] : []),
    ];
  };

  // Every view, its `… +N more` line counted, stays within the budget.
  const step = (view: PickerView, key: PickerKey) => {
    const moved = lineKey(view, heights, 6, '', key);

    assert(moved?.type === 'move');
    expect(drawn(moved.view).length).toBeLessThanOrEqual(6);

    return moved.view;
  };

  let view = openLineView(choices, heights, 6);

  expect(drawn(view)).toStrictEqual([
    ' ❯1. Fix the tokenizer',
    '  2. a',
    '     b',
    '     c',
    '↓    d',
    '+1',
  ]);

  // Onto the tall row: its first line is in sight, so nothing moves.
  view = step(view, down);

  expect(view).toStrictEqual({ highlighted: 1, top: 0 });
  // Read by line now, the whole budget its own: no `+N more`.
  expect(drawn(view).at(-1)).toStrictEqual('↓    e');

  // A line a press, to its last, the highlight staying on the row.
  view = step(view, down);
  view = step(view, down);
  view = step(view, down);

  expect(view).toStrictEqual({ highlighted: 1, top: 3 });
  expect(drawn(view)).toStrictEqual([
    '↑    c',
    '     d',
    '     e',
    '     f',
    '     g',
    '↓    h',
  ]);

  // Then on to row 3, brought whole into sight with the least move.
  view = step(view, down);

  expect(view).toStrictEqual({ highlighted: 2, top: 4 });
  expect(drawn(view)).toStrictEqual([
    '↑    d',
    '     e',
    '     f',
    '     g',
    '     h',
    ' ❯3. docs · Fix the parser',
  ]);
  expect(lineKey(view, heights, 6, '', down)).toStrictEqual(undefined);

  // Back the same way: onto row 2 at its last line, then a line a press.
  view = step(view, up);

  expect(view).toStrictEqual({ highlighted: 1, top: 4 });

  view = step(view, up);

  expect(view).toStrictEqual({ highlighted: 1, top: 3 });
  // Enter picks the row wherever in it the view is; a resize shows it from
  // its first line again.
  expect(
    lineKey(view, heights, 6, '', { ...down, downArrow: false, return: true }),
  ).toStrictEqual({ type: 'pick', index: 1 });
  expect(fromFirstLine(view, heights, 6)).toStrictEqual({
    highlighted: 1,
    top: 1,
  });
  // Rows that fit are whole and unmarked.
  expect(
    linedRows(choices, [['x'], ['y']], { highlighted: 0, top: 0 }, 6).rows.map(
      (row) => row.lines,
    ),
  ).toStrictEqual([[{ text: 'x', first: true }], [{ text: 'y', first: true }]]);
});

test("a picker's labels go on lines of their own under their columns, every row alike, where the room beside the columns is under half the box (CHD-445)", () => {
  const rows = sessionChoices(
    [
      {
        resume: { sessionId: 's1', cwd: '/h/src/app' },
        lastUsedAt: '2026-10-05T11:58:00.000Z',
        prompt: 'Fix the tokenizer handling of tests/parse/tokenize_test.ts',
      },
      {
        resume: { sessionId: 's2', cwd: '/h/src/lib' },
        lastUsedAt: '2026-10-02T12:00:00.000Z',
        prompt: 'docs · permission',
      },
    ],
    NOW,
    { home: '/h' },
  );

  // Beside: 60 cells less the columns leave more than half of 50.
  expect(pickerLines(rows, 60, 50)![1]).toStrictEqual([
    '3 days ago     ~/src/lib  docs · permission',
  ]);
  // Under: 30 cells less the columns leave under half of 50.
  expect(pickerLines(rows, 30, 50)).toStrictEqual([
    [
      '2 minutes ago  ~/src/app',
      'Fix the tokenizer handling of',
      'tests/parse/tokenize_test.ts',
    ],
    ['3 days ago     ~/src/lib', 'docs · permission'],
  ]);
  expect(
    pickerLines([{ key: 'm', label: 'a model', value: 'm' }], 10, 50),
  ).toStrictEqual(undefined);
});

test("a picker's layout leaves its labels the frame, the highlight's gutter, the number, and the scroll's gutter once their lines take more than the rows (CHD-445)", () => {
  const [row] = sessionChoices(
    [
      {
        resume: { sessionId: 's1', cwd: '/work' },
        lastUsedAt: '2026-10-05T11:58:00.000Z',
        prompt: 'Fix the tokenizer handling of a quoted string at the end',
      },
    ],
    NOW,
  );

  // 80 columns: 80 - 4 - 2 - 3 = 71 cells, which the 71 of the row fit.
  expect(pickerLayout([row!], 5, 80)).toStrictEqual([[row!.label]]);
  // No room for its line: the scroll's gutter takes two cells more, 69,
  // and the label wraps.
  expect(pickerLayout([row!], 0, 80)).toStrictEqual([choiceLines(row!, 69)]);
  expect(pickerLayout([row!], 0, 80)![0]!.length).toBeGreaterThan(1);
  expect(
    pickerLayout([{ key: 'm', label: 'a model', value: 'm' }], 5, 80),
  ).toStrictEqual(undefined);
});

test('a row as tall as the picker is drawn whole while highlighted, the +N more line giving way, and the next press moves on; on the last row, with none after, the room is the whole budget again (CHD-445)', () => {
  const lines = [['a', 'b', 'c', 'd', 'e', 'f'], ['next']];
  const heights = lines.map((each) => each.length);
  const choices = lines.map((_, index) => ({
    key: String(index),
    label: String(index),
    value: String(index),
  }));
  const texts = (view: PickerView) => {
    const shown = linedRows(choices, lines, view, 6);

    return [
      ...shown.rows.flatMap((row) =>
        row.lines.map((line) => `${line.edge ?? ''}${line.text}`),
      ),
      ...(shown.hidden > 0 ? [`+${shown.hidden}`] : []),
    ];
  };

  const view = openLineView(choices, heights, 6);

  // Highlighted, its six lines whole; the edge says a row follows.
  expect(view).toStrictEqual({ highlighted: 0, top: 0 });
  expect(texts(view)).toStrictEqual([' a', ' b', ' c', ' d', ' e', '↓f']);

  const moved = lineKey(view, heights, 6, 'j', {
    upArrow: false,
    downArrow: false,
    return: false,
    shift: false,
  });

  // Not taller than that, so ↓ goes straight on, to the last row: nothing
  // after it, no notice, and the whole budget is lines of rows again.
  expect(moved).toStrictEqual({
    type: 'move',
    view: { highlighted: 1, top: 1 },
  });
  assert(moved?.type === 'move');
  expect(texts(moved.view)).toStrictEqual([
    '↑b',
    ' c',
    ' d',
    ' e',
    ' f',
    ' next',
  ]);
});

test('CHD-532 agent adaptation retains catalog order and only marks the preferred initial position', () => {
  const choices = agentChoices(
    [
      {
        name: 'second',
        title: 'Second title',
        start: 'fixture',
        from: 'settings',
      },
      {
        name: 'first',
        title: 'first',
        start: 'fixture',
        from: 'cli',
        found: true,
      },
    ],
    'first',
  );

  expect(choices.map(({ value }) => value)).toEqual(['second', 'first']);
  expect(choices[0]?.label).toBe('second\x1b[2m · Second title\x1b[22m');
  expect(choices[1]?.label).toBe('first');
  expect(openView(choices, 6).highlighted).toBe(1);
  expect(openView(agentChoices([], 'absent'), 6).highlighted).toBe(0);
});

test('CHD-544 agent choices leave out an own CLI PATH lacks, and keep what chord agents counts', () => {
  const choices = agentChoices(
    [
      { name: 'claude', title: 'Claude', start: 'npx c', from: 'npx' },
      {
        name: 'cursor',
        title: 'Cursor',
        start: 'agent acp',
        from: 'cli',
        found: false,
      },
      { name: 'fast', title: 'Fast', start: 'uvx f', from: 'uvx' },
      {
        name: 'goose',
        title: 'goose',
        start: 'goose acp',
        from: 'cli',
        found: true,
      },
      { name: 'mine', title: undefined, start: 'mine', from: 'settings' },
    ],
    'cursor',
  );

  expect(choices.map(({ value }) => value)).toEqual([
    'claude',
    'fast',
    'goose',
    'mine',
  ]);
  expect(choices.some(({ label }) => label.includes('not found'))).toBe(false);
  // The preferred agent left out: the highlight opens on the first row.
  expect(choices.some(({ current }) => current)).toBe(false);
  expect(openView(choices, 6).highlighted).toBe(0);
});
