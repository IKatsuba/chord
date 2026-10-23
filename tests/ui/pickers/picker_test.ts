import { expect, test } from 'bun:test';
import {
  choiceKey,
  CURRENT_MARK,
  DIRECTORY_WIDTH,
  initialChoice,
  lastUsed,
  type ModelChoice,
  modelChoices,
  modelToAsk,
  openView,
  optionChoices,
  type PickerKey,
  pickerKey,
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
    { key: 's1', label: '2 minutes ago  fix the build', value: '0' },
    { key: 's2', label: '3 days ago     add a test', value: '1' },
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
