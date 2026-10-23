import { expect, test } from 'bun:test';
import type { ElicitationSchema } from '@agentclientprotocol/sdk';
import {
  answeredRows,
  answeredText,
  contentOf,
  fieldsOf,
  focusedField,
  formHint,
  type FormKey,
  formKey,
  formRows,
  type FormState,
  linkHost,
  openForm,
  problemsOf,
  toFix,
} from '../../../src/ui/dialogs/form.ts';
import { FORM_SCHEMA } from '../../fixtures/forms.ts';

const NONE: FormKey = { ctrl: false, escape: false };

/** One key's press, by the name the shortcuts panel gives it. */
const KEYS: Record<string, FormKey> = {
  esc: { ...NONE, escape: true },
  enter: { ...NONE, return: true },
  tab: { ...NONE, tab: true },
  'shift + tab': { ...NONE, tab: true, shift: true },
  '↑': { ...NONE, upArrow: true },
  '↓': { ...NONE, downArrow: true },
  '←': { ...NONE, leftArrow: true },
  '→': { ...NONE, rightArrow: true },
  home: { ...NONE, home: true },
  end: { ...NONE, end: true },
  backspace: { ...NONE, backspace: true },
  delete: { ...NONE, delete: true },
};

/** Presses each of `keys` in turn: a named key, or text typed as it is. */
function press(form: FormState, ...keys: string[]): FormState {
  return keys.reduce(
    (at, name) =>
      formKey(at, KEYS[name] === undefined ? name : '', KEYS[name] ?? NONE)
        .form,
    form,
  );
}

function open(): FormState {
  return openForm(FORM_SCHEMA);
}

/** The form with the focus on the field named `key`. */
function at(form: FormState, key: string): FormState {
  const index = form.fields.findIndex((field) => field.key === key);

  return { ...form, focus: { on: 'field', index }, cursor: 0 };
}

test('each property is a field of its kind, titled, in order', () => {
  const fields = fieldsOf(FORM_SCHEMA);

  expect(
    fields.map(({ key, label, kind, required }) => [
      key,
      label,
      kind,
      required,
    ]),
  ).toStrictEqual([
    ['name', 'Project name', 'text', true],
    ['email', 'Contact email', 'text', false],
    ['replicas', 'Replicas', 'integer', true],
    ['ratio', 'Traffic share', 'number', false],
    ['public', 'Public', 'boolean', false],
    ['region', 'Region', 'choice', true],
    ['tags', 'Tags', 'multi', false],
  ]);
  expect(fields[5]?.options[1]).toStrictEqual({
    value: 'us',
    title: 'United States',
  });
  expect(fields[6]?.options.map((option) => option.title)).toStrictEqual([
    'web',
    'api',
    'worker',
  ]);
});

test('a property without a title is labelled by its name', () => {
  const [field] = fieldsOf({
    type: 'object',
    properties: { port: { type: 'integer' } },
  });

  expect(field?.label).toStrictEqual('port');
});

test('a type a form cannot ask for is kept, unset, and blocks Accept if required', () => {
  const schema = {
    type: 'object',
    properties: { blob: { type: 'object' } },
    required: ['blob'],
  } as unknown as ElicitationSchema;
  const form = openForm(schema);

  expect(form.fields[0]?.kind).toStrictEqual('other');
  expect(
    formRows(form, 10)[0]?.kind === 'field' && formRows(form, 10)[0],
  ).toStrictEqual({
    kind: 'field',
    field: form.fields[0]!,
    focused: true,
    status: 'required',
    value: { text: "can't be filled in here", dim: true },
  });
  expect(formKey(form, '', KEYS.tab!).response).toStrictEqual(undefined);
  expect(formKey(press(form, 'tab'), '', KEYS.enter!).response).toStrictEqual(
    undefined,
  );
});

test('the form opens with defaults set and the focus on the first field', () => {
  const form = open();

  expect(form.values).toStrictEqual({ replicas: '2', public: false });
  expect(focusedField(form)?.key).toStrictEqual('name');
});

test('a form with no fields opens on Accept', () => {
  const form = openForm({ type: 'object', properties: {} });

  expect(form.focus).toStrictEqual({ on: 'accept' });
  expect(formKey(form, '', KEYS.enter!).response).toStrictEqual({
    action: 'accept',
    content: {},
  });
});

test('typing edits the focused text field at the cursor', () => {
  let form = press(open(), 'w', 'b', '-', 'a', 'p', 'p');

  expect(form.values.name).toStrictEqual('wb-app');

  form = press(form, 'home', '→', 'e');

  expect(form.values.name).toStrictEqual('web-app');
  expect(form.cursor).toStrictEqual(2);

  form = press(form, 'end', 'backspace');

  expect(form.values.name).toStrictEqual('web-ap');

  form = press(form, 'home', 'delete');

  expect(form.values.name).toStrictEqual('eb-ap');
});

test('emptying a text field unsets it', () => {
  const form = press(open(), 'a', 'backspace');

  expect('name' in form.values).toStrictEqual(false);
});

test('ctrl+u, ctrl+k and ctrl+w cut as in a shell', () => {
  const typed = press(open(), 'my web app');
  const ctrl = { ...NONE, ctrl: true };

  expect(formKey(typed, 'w', ctrl).form.values.name).toStrictEqual('my web ');
  expect(
    formKey(press(typed, 'home'), 'k', ctrl).form.values.name,
  ).toStrictEqual(undefined);
  expect(
    formKey(press(typed, '←', '←', '←'), 'u', ctrl).form.values.name,
  ).toStrictEqual('app');
});

test('a pasted line break is a space in one line of text', () => {
  expect(press(open(), 'a\nb').values.name).toStrictEqual('a b');
});

test('a number field refuses keys that cannot be part of a number', () => {
  const replicas = at(open(), 'replicas');

  expect(
    press(replicas, 'end', '1', 'x', '.', '5').values.replicas,
  ).toStrictEqual('215');
  expect(
    press(at(open(), 'ratio'), '0', '.', '2', 'e').values.ratio,
  ).toStrictEqual('0.2');
  // A paste with a letter in it is refused whole.
  expect(press(at(open(), 'ratio'), '0.2x').values.ratio).toStrictEqual(
    undefined,
  );
});

test('Space toggles a boolean, and Backspace unsets it', () => {
  const form = at(open(), 'public');

  expect(press(form, ' ').values.public).toStrictEqual(true);
  expect(press(form, ' ', ' ').values.public).toStrictEqual(false);
  expect('public' in press(form, 'backspace').values).toStrictEqual(false);
});

test('→ opens a choice list on the current value, and a digit picks', () => {
  const form = at(open(), 'region');
  const opened = press(form, '→');

  expect(opened.list).toStrictEqual({ highlighted: 0 });
  expect(press(opened, '2').values.region).toStrictEqual('us');
  expect(press(opened, '2').list).toStrictEqual(undefined);
  expect(press(opened, '↓', '↓', '↓', 'enter').values.region).toStrictEqual(
    'ap',
  );
  expect(press(press(opened, '2'), ' ').list).toStrictEqual({ highlighted: 1 });
});

test('Esc or ← closes an open list and leaves the form open', () => {
  const opened = press(at(open(), 'region'), ' ');

  for (const key of ['esc', '←']) {
    const step = formKey(opened, '', KEYS[key]!);

    expect(step.response).toStrictEqual(undefined);
    expect(step.form.list).toStrictEqual(undefined);
    expect('region' in step.form.values).toStrictEqual(false);
  }
});

test('a multi-select ticks with Space, in the list order, and Enter closes it', () => {
  const opened = press(at(open(), 'tags'), ' ');
  const ticked = press(opened, '↓', '↓', ' ', '↑', '↑', ' ');

  expect(ticked.values.tags).toStrictEqual(['web', 'worker']);
  expect(press(ticked, 'enter').list).toStrictEqual(undefined);
  expect('tags' in press(ticked, ' ').values).toStrictEqual(true);
  expect('tags' in press(ticked, ' ', '↓', '↓', ' ').values).toStrictEqual(
    false,
  );
});

test('Enter moves to the next field, and from the last to Accept', () => {
  const form = open();

  expect(focusedField(press(form, 'enter'))?.key).toStrictEqual('email');
  expect(press(at(form, 'tags'), 'enter').focus).toStrictEqual({
    on: 'accept',
  });
  expect(press(form, 'shift + tab', '↑').focus).toStrictEqual(form.focus);
  expect(press(at(form, 'tags'), '↓', '→').focus).toStrictEqual({
    on: 'decline',
  });
  expect(focusedField(press(at(form, 'tags'), '↓', '↑'))?.key).toStrictEqual(
    'tags',
  );
});

test('an error shows once the focus leaves the field, not while typing', () => {
  const typing = press(open(), 'a', 'b');

  expect(typing.shown.size).toStrictEqual(0);

  const left = press(typing, '↓');

  expect([...left.shown]).toStrictEqual(['name']);
  expect(formRows(left, 20)[1]).toStrictEqual({
    kind: 'note',
    text: 'At least 3 characters',
    error: true,
  });

  // Back on it, it is checked on every keystroke: fixed, the error goes.
  const fixed = press(left, '↑', 'end', 'c');

  expect(problemsOf(fixed).has('name')).toStrictEqual(false);
  expect(
    formRows(fixed, 20).every((row) => row.kind !== 'note' || !row.error),
  ).toBeTruthy();
});

test('moving through a form never flags a required field left empty', () => {
  const form = press(open(), '↓', '↓', '↓', '↓', '↓', '↓');

  expect(form.shown.size).toStrictEqual(0);
  expect(
    formRows(form, 20)
      .filter((row) => row.kind === 'field')
      .map((row) => (row.kind === 'field' ? row.status : '')),
  ).toStrictEqual([
    'required',
    'none',
    'valid',
    'none',
    'valid',
    'required',
    'none',
  ]);
});

test('Accept on an invalid form is refused, every problem shown, the focus on the first', () => {
  let form = press(open(), 'a', 'b', '↓', 'ops@', '↓', 'backspace', '1', '2');

  form = { ...form, focus: { on: 'accept' } };

  const step = formKey(form, '', KEYS.enter!);

  expect(step.response).toStrictEqual(undefined);
  expect(focusedField(step.form)?.key).toStrictEqual('name');
  expect(toFix(step.form)).toStrictEqual(4);
  expect(
    formRows(step.form, 20).flatMap((row) =>
      row.kind === 'note' ? [row.text] : [],
    ),
  ).toStrictEqual([
    'At least 3 characters',
    'Not an email address, such as name@example.com',
    'A whole number from 1 to 9',
    'Required',
  ]);
  // The count follows the fixes.
  expect(toFix(press(step.form, 'c'))).toStrictEqual(3);
});

test('Accept on a valid form answers with the values in their schema types', () => {
  let form = press(open(), 'web-app', '↓', 'ops@example.io', '↓');

  form = press(form, 'backspace', '3', '↓', '0.25', '↓', ' ', '↓', '→', '2');
  form = press(form, '↓', ' ', ' ', '↓', '↓', ' ', 'enter', '↓');

  expect(formKey(form, '', KEYS.enter!).response).toStrictEqual({
    action: 'accept',
    content: {
      name: 'web-app',
      email: 'ops@example.io',
      replicas: 3,
      ratio: 0.25,
      public: true,
      region: 'us',
      tags: ['web', 'worker'],
    },
  });
});

test('unset fields are not sent', () => {
  expect(contentOf(open())).toStrictEqual({ replicas: 2, public: false });
});

test('Decline answers decline, and Esc answers cancel', () => {
  const form = press(at(open(), 'tags'), '↓', '→');

  expect(formKey(form, '', KEYS.enter!).response).toStrictEqual({
    action: 'decline',
  });
  expect(formKey(open(), '', KEYS.esc!).response).toStrictEqual({
    action: 'cancel',
  });
});

test('each rule reads in plain words', () => {
  const schema = {
    type: 'object',
    properties: {
      short: { type: 'string', maxLength: 2 },
      code: { type: 'string', pattern: '^[a-z-]+$' },
      site: { type: 'string', format: 'uri' },
      day: { type: 'string', format: 'date' },
      when: { type: 'string', format: 'date-time' },
      low: { type: 'integer', minimum: 1 },
      high: { type: 'number', maximum: 1 },
      whole: { type: 'integer' },
      few: {
        type: 'array',
        minItems: 2,
        items: { type: 'string', enum: ['a', 'b', 'c'] },
      },
      many: {
        type: 'array',
        maxItems: 1,
        items: {
          anyOf: [
            { const: 'a', title: 'A' },
            { const: 'b', title: 'B' },
          ],
        },
      },
    },
  } as unknown as ElicitationSchema;
  const form: FormState = {
    ...openForm(schema),
    values: {
      short: 'abc',
      code: 'A',
      site: 'nope',
      day: '2026-13-01',
      when: 'soon',
      low: '0',
      high: '2',
      whole: '1.5',
      few: ['a'],
      many: ['a', 'b'],
    },
  };

  expect(Object.fromEntries(problemsOf(form))).toStrictEqual({
    short: 'At most 2 characters',
    code: 'Must match ^[a-z-]+$',
    site: 'Not a URL, such as https://example.com',
    day: 'Not a date, such as 2026-10-06',
    when: 'Not a date and time, such as 2026-10-06T14:30:00Z',
    low: 'A whole number of 1 or more',
    high: 'A number of 1 or less',
    whole: 'A whole number',
    few: 'Pick at least 2',
    many: 'Pick at most 1',
  });
});

test('fields that do not fit scroll, the focused one whole and in view', () => {
  const opened = press(at(open(), 'region'), '→');
  const rows = formRows(opened, 8);

  expect(rows.length).toStrictEqual(8);
  expect(rows[0]).toStrictEqual({ kind: 'more', direction: 'up', count: 3 });
  expect(rows.some((row) => row.kind === 'field' && row.focused)).toBeTruthy();
  expect(rows.filter((row) => row.kind === 'option').length).toStrictEqual(3);

  const top = formRows(open(), 4);

  expect(top.at(-1)).toStrictEqual({
    kind: 'more',
    direction: 'down',
    count: 5,
  });
  expect(top.length).toStrictEqual(4);
});

test('the hint names the keys for the focus, shorter in a narrow box', () => {
  const form = open();

  expect(formHint(form, 114)).toStrictEqual(
    'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel',
  );
  expect(formHint(form, 76)).toStrictEqual(
    'Type to fill in · ↑↓ to move · Esc to cancel',
  );
  expect(formHint(press(at(form, 'region'), '→'), 76)).toStrictEqual(
    '↑↓ · 1–3 or Enter to pick · ← to close · Esc to cancel',
  );
  expect(formHint(at(form, 'public'), 114)).toStrictEqual(
    'Space to toggle · ↑↓ to move · Esc to cancel',
  );
  expect(formHint({ ...form, focus: { on: 'decline' } }, 114)).toStrictEqual(
    '←→ to switch · Enter to decline · Esc to cancel',
  );
});

test('an answered form reads back as the form showed it', () => {
  const content = {
    name: 'web-app',
    replicas: 3,
    public: true,
    region: 'us',
    tags: ['web', 'worker'],
  };

  expect(answeredRows(FORM_SCHEMA, content)).toStrictEqual([
    { label: 'Project name', value: 'web-app' },
    { label: 'Replicas', value: '3' },
    { label: 'Public', value: 'Yes' },
    { label: 'Region', value: 'United States' },
    { label: 'Tags', value: 'web, worker' },
  ]);
  expect(answeredText(content)).toStrictEqual('Answered · 5 fields');
  expect(answeredText({ name: 'x' })).toStrictEqual('Answered · 1 field');
  expect(answeredText(undefined)).toStrictEqual('Answered');
});

test('a link names its host, and only a web link has one', () => {
  expect(
    linkHost('https://example.com/oauth/authorize?client=abc'),
  ).toStrictEqual('example.com');
  expect(linkHost('file:///etc/passwd')).toStrictEqual(undefined);
  expect(linkHost('not a url')).toStrictEqual(undefined);
});

test("↓ on the buttons leaves for the agents list, the form as it was; a choice's open list keeps its ↓ (Q192)", () => {
  const buttons = press(open(), ...open().fields.map(() => '↓'));

  expect(buttons.focus.on).toStrictEqual('accept');
  expect(formKey(buttons, '', KEYS['↓']!)).toStrictEqual({
    form: buttons,
    leave: true,
  });
  // Above the buttons ↓ moves on, as before.
  expect(formKey(open(), '', KEYS['↓']!).leave).toBeUndefined();
});
