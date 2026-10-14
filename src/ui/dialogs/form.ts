/**
 * An elicitation form, kept out of the component: the fields a requested
 * schema asks for, what each key does to them, which values are wrong and in
 * what words, the rows the box draws and the answer it sends. The component
 * only draws `formRows` and hands keys to `formKey`.
 *
 * Whether a value is wrong is zod's call, through `z.fromJSONSchema` on the
 * schema the agent sent; the words are chord's, from the schema's own bounds.
 */
import type {
  ElicitationContentValue,
  ElicitationSchema,
} from '@agentclientprotocol/sdk';
import { z } from '@zod/zod';
import type { ElicitationReply } from '../../session/elicitations.ts';
import type { KeyPress } from '../shortcuts/state.ts';

/** How a field takes its value. */
export type FieldKind =
  | 'text'
  | 'number'
  | 'integer'
  | 'boolean'
  /** One of a list: a string with `enum` or `oneOf`. */
  | 'choice'
  /** Any of a list: an array of `enum` or `anyOf` strings. */
  | 'multi'
  /** A type a form cannot ask for; it stays unset. */
  | 'other';

/** One entry in a choice or multi-select list. */
export interface FieldOption {
  /** What is sent: the `enum` string or the `oneOf`/`anyOf` `const`. */
  readonly value: string;
  readonly title: string;
}

/** One property of the requested schema, as the form asks for it. */
export interface Field {
  readonly key: string;
  /** The property's `title`, or its name when it has none. */
  readonly label: string;
  readonly description?: string;
  readonly required: boolean;
  readonly kind: FieldKind;
  readonly options: readonly FieldOption[];
  /** The property's schema as sent, for the bounds the error lines name. */
  readonly schema: Readonly<Record<string, unknown>>;
}

/**
 * A field's value while the form is open. Text and number fields hold what is
 * typed; a number is parsed only when it is checked or sent.
 */
export type FieldValue = string | boolean | readonly string[];

/** Where the focus is: a field by index, or one of the buttons. */
export type Focus =
  | { readonly on: 'field'; readonly index: number }
  | { readonly on: 'accept' }
  | { readonly on: 'decline' };

export interface FormState {
  readonly fields: readonly Field[];
  /** Unset fields have no entry. */
  readonly values: Readonly<Record<string, FieldValue>>;
  readonly focus: Focus;
  /** The cursor in the focused text or number field, in code points. */
  readonly cursor: number;
  /** The focused choice or multi-select field's list, when it is open. */
  readonly list?: { readonly highlighted: number };
  /**
   * Fields whose problems show. A field joins when the focus leaves it with
   * a problem, or when Accept is refused; from then on it is checked on
   * every keystroke, so its error goes as soon as the value is fixed.
   */
  readonly shown: ReadonlySet<string>;
  /** Accept was refused once; the button row counts the problems since. */
  readonly refused: boolean;
}

function optionsOf(schema: Record<string, unknown>): FieldOption[] {
  const titled = (list: unknown): FieldOption[] =>
    Array.isArray(list)
      ? list.flatMap((entry) =>
          typeof entry?.const === 'string'
            ? [
                {
                  value: entry.const,
                  title:
                    typeof entry.title === 'string' ? entry.title : entry.const,
                },
              ]
            : [],
        )
      : [];
  const plain = (list: unknown): FieldOption[] =>
    Array.isArray(list)
      ? list
          .filter((value) => typeof value === 'string')
          .map((value) => ({
            value,
            title: value,
          }))
      : [];

  if (schema.type === 'array') {
    const items = (schema.items ?? {}) as Record<string, unknown>;

    return items.anyOf !== undefined ? titled(items.anyOf) : plain(items.enum);
  }

  return schema.oneOf !== undefined ? titled(schema.oneOf) : plain(schema.enum);
}

function kindOf(
  schema: Record<string, unknown>,
  options: readonly FieldOption[],
): FieldKind {
  switch (schema.type) {
    case 'string':
      return options.length > 0 ? 'choice' : 'text';
    case 'number':
    case 'integer':
    case 'boolean':
      return schema.type;
    case 'array':
      return options.length > 0 ? 'multi' : 'other';
    default:
      return 'other';
  }
}

/** The requested schema's properties, in the order it lists them. */
export function fieldsOf(schema: ElicitationSchema): Field[] {
  const required = new Set(schema.required ?? []);

  return Object.entries(schema.properties ?? {}).map(([key, property]) => {
    const raw = property as Record<string, unknown>;
    const options = optionsOf(raw);
    const description =
      typeof raw.description === 'string' && raw.description !== ''
        ? raw.description
        : undefined;

    return {
      key,
      label:
        typeof raw.title === 'string' && raw.title !== '' ? raw.title : key,
      ...(description === undefined ? {} : { description }),
      required: required.has(key),
      kind: kindOf(raw, options),
      options,
      schema: raw,
    };
  });
}

/** The schema's default for a field, as the form holds it. */
function defaultOf(field: Field): FieldValue | undefined {
  const value = field.schema.default;

  switch (field.kind) {
    case 'text':
      return typeof value === 'string' && value !== '' ? value : undefined;
    case 'number':
    case 'integer':
      return typeof value === 'number' ? String(value) : undefined;
    case 'boolean':
      return typeof value === 'boolean' ? value : undefined;
    case 'choice':
      return field.options.some((option) => option.value === value)
        ? (value as string)
        : undefined;
    case 'multi': {
      const picked = Array.isArray(value)
        ? field.options.filter((option) => value.includes(option.value))
        : [];

      return picked.length > 0
        ? picked.map((option) => option.value)
        : undefined;
    }
    case 'other':
      return undefined;
  }
}

function focusAt(fields: readonly Field[], index: number): Focus {
  return index < fields.length ? { on: 'field', index } : { on: 'accept' };
}

/**
 * The form as it opens: defaults filled in, the focus on the first field, or
 * on Accept when there are none to fill.
 */
export function openForm(schema: ElicitationSchema): FormState {
  const fields = fieldsOf(schema);
  const values: Record<string, FieldValue> = {};

  for (const field of fields) {
    const value = defaultOf(field);

    if (value !== undefined) {
      values[field.key] = value;
    }
  }

  const focus = focusAt(fields, 0);

  return {
    fields,
    values,
    focus,
    cursor: cursorAtEnd(fields, values, focus),
    shown: new Set(),
    refused: false,
  };
}

function cursorAtEnd(
  fields: readonly Field[],
  values: Readonly<Record<string, FieldValue>>,
  focus: Focus,
): number {
  if (focus.on !== 'field') {
    return 0;
  }

  const value = values[fields[focus.index]?.key ?? ''];

  return typeof value === 'string' ? [...value].length : 0;
}

/** The field the focus is on, if it is on one. */
export function focusedField(form: FormState): Field | undefined {
  return form.focus.on === 'field' ? form.fields[form.focus.index] : undefined;
}

function typed(kind: FieldKind): boolean {
  return kind === 'text' || kind === 'number' || kind === 'integer';
}

const NUMBER = /^[-+]?(\d+\.?\d*|\.\d+)$/;
const INTEGER = /^[-+]?\d+$/;

/**
 * Whether `text` can be typed into a number field: digits and signs, and a
 * point where the number need not be whole. Letters never can.
 */
export function typeable(kind: FieldKind, text: string): boolean {
  if (kind === 'number') {
    return /^[\d.+-]+$/.test(text);
  }

  if (kind === 'integer') {
    return /^[\d+-]+$/.test(text);
  }

  return true;
}

/** A value as the agent gets it, in its schema type; none for unset. */
function sent(
  field: Field,
  value: FieldValue | undefined,
): ElicitationContentValue | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (field.kind === 'number' || field.kind === 'integer') {
    return Number(value);
  }

  return value as ElicitationContentValue;
}

/** What Accept sends: every set field, in its schema type. */
export function contentOf(
  form: FormState,
): Record<string, ElicitationContentValue> {
  const content: Record<string, ElicitationContentValue> = {};

  for (const field of form.fields) {
    const value = sent(field, form.values[field.key]);

    if (value !== undefined) {
      content[field.key] = value;
    }
  }

  return content;
}

type Issue = z.core.$ZodIssue;

const validators = new WeakMap<readonly Field[], z.ZodType | undefined>();

/**
 * The zod schema the requested one makes, built once per form. One zod cannot
 * read leaves every value unchecked rather than refusing the form.
 */
function validatorOf(fields: readonly Field[]): z.ZodType | undefined {
  if (validators.has(fields)) {
    return validators.get(fields);
  }

  const properties: Record<string, z.core.JSONSchema.JSONSchema> = {};
  const required: string[] = [];

  for (const field of fields) {
    properties[field.key] = field.schema as z.core.JSONSchema.JSONSchema;

    if (field.required) {
      required.push(field.key);
    }
  }

  let validator: z.ZodType | undefined;

  try {
    validator = z.fromJSONSchema({ type: 'object', properties, required });
  } catch {
    validator = undefined;
  }

  validators.set(fields, validator);

  return validator;
}

function bound(schema: Readonly<Record<string, unknown>>, key: string) {
  const value = schema[key];

  return typeof value === 'number' ? value : undefined;
}

/** `A whole number from 1 to 9`, from the field's bounds. */
function numberWords(field: Field): string {
  const what = field.kind === 'integer' ? 'A whole number' : 'A number';
  const min = bound(field.schema, 'minimum');
  const max = bound(field.schema, 'maximum');

  if (min !== undefined && max !== undefined) {
    return `${what} from ${min} to ${max}`;
  }

  if (min !== undefined) {
    return `${what} of ${min} or more`;
  }

  if (max !== undefined) {
    return `${what} of ${max} or less`;
  }

  return what;
}

function characters(count: number): string {
  return count === 1 ? '1 character' : `${count} characters`;
}

const FORMAT_WORDS: Record<string, string> = {
  email: 'Not an email address, such as name@example.com',
  url: 'Not a URL, such as https://example.com',
  date: 'Not a date, such as 2026-10-06',
  datetime: 'Not a date and time, such as 2026-10-06T14:30:00Z',
};

/** chord's words for one of zod's findings about `field`. */
export function wordsFor(field: Field, issue: Issue): string {
  if (field.kind === 'number' || field.kind === 'integer') {
    return numberWords(field);
  }

  switch (issue.code) {
    case 'too_small':
      return field.kind === 'multi'
        ? `Pick at least ${issue.minimum}`
        : `At least ${characters(Number(issue.minimum))}`;
    case 'too_big':
      return field.kind === 'multi'
        ? `Pick at most ${issue.maximum}`
        : `At most ${characters(Number(issue.maximum))}`;
    case 'invalid_format':
      return issue.format === 'regex'
        ? `Must match ${field.schema.pattern}`
        : (FORMAT_WORDS[issue.format] ?? issue.message);
    case 'invalid_value':
    case 'invalid_union':
      return 'Not one of the choices';
    default:
      return issue.message;
  }
}

/**
 * Every field's problem, in chord's words: `Required` for a required field
 * left unset, typed text that is no number, and what zod finds in the rest.
 */
export function problemsOf(form: FormState): Map<string, string> {
  const problems = new Map<string, string>();
  const content: Record<string, unknown> = {};

  for (const field of form.fields) {
    const value = form.values[field.key];

    if (value === undefined) {
      if (field.required) {
        problems.set(field.key, 'Required');
      }

      continue;
    }

    if (
      (field.kind === 'number' || field.kind === 'integer') &&
      !(field.kind === 'integer' ? INTEGER : NUMBER).test(String(value))
    ) {
      problems.set(field.key, numberWords(field));

      continue;
    }

    content[field.key] = sent(field, value);
  }

  const result = validatorOf(form.fields)?.safeParse(content);

  for (const issue of result?.success === false ? result.error.issues : []) {
    const key = issue.path[0];
    const field = form.fields.find((candidate) => candidate.key === key);

    if (field && !problems.has(field.key)) {
      problems.set(field.key, wordsFor(field, issue));
    }
  }

  return problems;
}

/** What a key press did: the form after it, and the answer if it gave one. */
export interface FormStep {
  readonly form: FormState;
  readonly response?: ElicitationReply;
}

/** The parts of a press the form reads, besides the window's. */
export interface FormKey extends KeyPress {
  readonly leftArrow?: boolean;
  readonly rightArrow?: boolean;
  readonly delete?: boolean;
}

/**
 * Moves the focus. A field the focus leaves with a problem shows it, unless
 * the problem is only that a required field is still empty: moving through
 * the form never turns it red, Accept does.
 */
function moveTo(form: FormState, focus: Focus): FormState {
  const left = focusedField(form);
  let { shown } = form;

  if (left && !shown.has(left.key)) {
    const problem = problemsOf(form).get(left.key);

    if (problem !== undefined && problem !== 'Required') {
      shown = new Set(shown).add(left.key);
    }
  }

  const { list: _, ...rest } = form;

  return {
    ...rest,
    focus,
    shown,
    cursor: cursorAtEnd(form.fields, form.values, focus),
  };
}

function step(form: FormState, by: 1 | -1): FormState {
  const count = form.fields.length;
  const at = form.focus.on === 'field' ? form.focus.index : count;
  const next = Math.min(Math.max(at + by, 0), count);

  // The buttons are one stop; ←/→ move between them.
  return next === at ? form : moveTo(form, focusAt(form.fields, next));
}

function setValue(
  form: FormState,
  key: string,
  value: FieldValue | undefined,
  cursor = form.cursor,
): FormState {
  const { [key]: _, ...others } = form.values;

  return {
    ...form,
    values: value === undefined ? others : { ...others, [key]: value },
    cursor,
  };
}

/** Typing, the cursor and deleting in a text or number field. */
function editText(
  form: FormState,
  field: Field,
  input: string,
  key: FormKey,
): FormState | undefined {
  const chars = [...((form.values[field.key] as string | undefined) ?? '')];
  const at = Math.min(form.cursor, chars.length);
  const put = (next: string[], cursor: number) =>
    setValue(
      form,
      field.key,
      next.length === 0 ? undefined : next.join(''),
      cursor,
    );

  if (key.leftArrow) {
    return { ...form, cursor: Math.max(at - 1, 0) };
  }

  if (key.rightArrow) {
    return { ...form, cursor: Math.min(at + 1, chars.length) };
  }

  if (key.home || (key.ctrl && input === 'a')) {
    return { ...form, cursor: 0 };
  }

  if (key.end || (key.ctrl && input === 'e')) {
    return { ...form, cursor: chars.length };
  }

  if (key.backspace) {
    return at === 0 ? form : put(chars.toSpliced(at - 1, 1), at - 1);
  }

  if (key.delete) {
    return at === chars.length ? form : put(chars.toSpliced(at, 1), at);
  }

  if (key.ctrl && input === 'u') {
    return put(chars.slice(at), 0);
  }

  if (key.ctrl && input === 'k') {
    return put(chars.slice(0, at), at);
  }

  if (key.ctrl && input === 'w') {
    let from = at;

    while (from > 0 && chars[from - 1] === ' ') {
      from--;
    }

    while (from > 0 && chars[from - 1] !== ' ') {
      from--;
    }

    return put(chars.toSpliced(from, at - from), from);
  }

  if (key.ctrl || input === '' || key.tab || key.return || key.escape) {
    return undefined;
  }

  // A line break pasted into one line of text is a space.
  const text = input.replaceAll(/\r\n|\r|\n/g, ' ');

  if (!typeable(field.kind, text)) {
    return form;
  }

  const inserted = [...text];

  return put(chars.toSpliced(at, 0, ...inserted), at + inserted.length);
}

/** The keys of an open choice or multi-select list. */
function listKey(
  form: FormState,
  field: Field,
  highlighted: number,
  input: string,
  key: FormKey,
): FormState {
  const count = field.options.length;
  const close = () => {
    const { list: _, ...rest } = form;

    return rest;
  };

  if (key.escape || key.leftArrow) {
    return close();
  }

  // j and k as well, as in chord's other lists.
  if (key.upArrow || input === 'k') {
    return { ...form, list: { highlighted: Math.max(highlighted - 1, 0) } };
  }

  if (key.downArrow || input === 'j') {
    return {
      ...form,
      list: { highlighted: Math.min(highlighted + 1, count - 1) },
    };
  }

  if (field.kind === 'choice') {
    const digit = /^[1-9]$/.test(input) ? Number(input) - 1 : undefined;
    const picked = digit ?? (key.return ? highlighted : undefined);
    const option = picked === undefined ? undefined : field.options[picked];

    if (!option) {
      return form;
    }

    const { list: _, ...rest } = setValue(form, field.key, option.value);

    return rest;
  }

  if (key.return) {
    return close();
  }

  if (input === ' ') {
    const option = field.options[highlighted];
    const ticked = (form.values[field.key] ?? []) as readonly string[];

    if (!option) {
      return form;
    }

    const next = ticked.includes(option.value)
      ? ticked.filter((value) => value !== option.value)
      : [...ticked, option.value];
    // Sent in the list's order, whatever order they were ticked in.
    const ordered = field.options
      .map((entry) => entry.value)
      .filter((value) => next.includes(value));

    return setValue(form, field.key, ordered.length > 0 ? ordered : undefined);
  }

  return form;
}

/** Enter on Accept: the answer when nothing is wrong, the problems if not. */
function accept(form: FormState): FormStep {
  const problems = problemsOf(form);

  if (problems.size === 0) {
    return {
      form,
      response: { action: 'accept', content: contentOf(form) },
    };
  }

  const first = form.fields.findIndex((field) => problems.has(field.key));
  const focus = focusAt(form.fields, first);
  const { list: _, ...rest } = form;

  return {
    form: {
      ...rest,
      focus,
      cursor: cursorAtEnd(form.fields, form.values, focus),
      shown: new Set([...form.shown, ...problems.keys()]),
      refused: true,
    },
  };
}

/**
 * What a key does to the form. Esc with no list open answers `cancel`. The
 * window's own keys — ctrl+c, ctrl+o, pgup and pgdn, shift+↑ and shift+↓ — do
 * nothing here.
 */
export function formKey(
  form: FormState,
  input: string,
  key: FormKey,
): FormStep {
  const field = focusedField(form);

  // shift+↑ and shift+↓ scroll the transcript; they are the window's.
  if (key.shift && (key.upArrow || key.downArrow)) {
    return { form };
  }

  if (field && form.list) {
    return { form: listKey(form, field, form.list.highlighted, input, key) };
  }

  if (key.escape) {
    return { form, response: { action: 'cancel' } };
  }

  if (key.upArrow || (key.tab && key.shift)) {
    return { form: step(form, -1) };
  }

  if (key.downArrow || key.tab) {
    return { form: step(form, 1) };
  }

  if (form.focus.on !== 'field') {
    if (key.leftArrow) {
      return { form: { ...form, focus: { on: 'accept' } } };
    }

    if (key.rightArrow) {
      return { form: { ...form, focus: { on: 'decline' } } };
    }

    if (key.return) {
      return form.focus.on === 'accept'
        ? accept(form)
        : { form, response: { action: 'decline' } };
    }

    return { form };
  }

  if (!field) {
    return { form };
  }

  if (key.return) {
    return { form: step(form, 1) };
  }

  if (typed(field.kind)) {
    return { form: editText(form, field, input, key) ?? form };
  }

  if (key.backspace || key.delete) {
    return { form: setValue(form, field.key, undefined) };
  }

  if (field.kind === 'boolean' && input === ' ') {
    return { form: setValue(form, field.key, form.values[field.key] !== true) };
  }

  if (
    (field.kind === 'choice' || field.kind === 'multi') &&
    (key.rightArrow || input === ' ') &&
    field.options.length > 0
  ) {
    const value = form.values[field.key];
    const current = field.options.findIndex((option) =>
      Array.isArray(value)
        ? value.includes(option.value)
        : option.value === value,
    );

    return { form: { ...form, list: { highlighted: Math.max(current, 0) } } };
  }

  return { form };
}

/** The mark in a field's status column. */
export type FieldStatus = 'required' | 'valid' | 'invalid' | 'none';

/** How a field's value reads in the form. */
export interface ValueView {
  readonly text: string;
  /** `not set`, and what cannot be filled in. */
  readonly dim?: boolean;
  /** Where the cursor sits in `text`, in code points, while it is typed in. */
  readonly cursor?: number;
}

/** One row of the box's field area. */
export type FormRow =
  | {
      readonly kind: 'field';
      readonly field: Field;
      readonly focused: boolean;
      readonly status: FieldStatus;
      readonly value: ValueView;
    }
  /** The focused field's description, or any field's error, under it. */
  | { readonly kind: 'note'; readonly text: string; readonly error: boolean }
  | {
      readonly kind: 'option';
      readonly option: FieldOption;
      readonly highlighted: boolean;
      /** `1.` in a choice list, none in a multi-select. */
      readonly number?: number;
      /** A multi-select's tick. */
      readonly ticked?: boolean;
      /** The choice the field holds now. */
      readonly current?: boolean;
    }
  /** Fields scrolled out of view above or below. */
  | {
      readonly kind: 'more';
      readonly direction: 'up' | 'down';
      readonly count: number;
    };

function valueView(form: FormState, field: Field, focused: boolean): ValueView {
  const value = form.values[field.key];

  if (focused && form.list) {
    return { text: '▾' };
  }

  if (typed(field.kind) && focused) {
    return { text: (value as string | undefined) ?? '', cursor: form.cursor };
  }

  if (field.kind === 'other') {
    return { text: "can't be filled in here", dim: true };
  }

  if (value === undefined) {
    return { text: 'not set', dim: true };
  }

  return { text: shownValue(field, value) };
}

/** A set value as words: `☒ Yes`, an option's title, titles joined. */
function shownValue(field: Field, value: FieldValue, box = true): string {
  const title = (chosen: string) =>
    field.options.find((option) => option.value === chosen)?.title ?? chosen;

  if (typeof value === 'boolean') {
    const word = value ? 'Yes' : 'No';

    return box ? `${value ? '☒' : '☐'} ${word}` : word;
  }

  if (Array.isArray(value)) {
    return value.map(title).join(', ');
  }

  return field.kind === 'choice' ? title(value as string) : (value as string);
}

function statusOf(
  form: FormState,
  field: Field,
  problem: string | undefined,
): FieldStatus {
  if (problem !== undefined && form.shown.has(field.key)) {
    return 'invalid';
  }

  if (form.values[field.key] === undefined) {
    return field.required ? 'required' : 'none';
  }

  return problem === undefined ? 'valid' : 'none';
}

/**
 * Each field's rows: its own, then its open list, hanging under the value,
 * then its note.
 */
function blocksOf(form: FormState): FormRow[][] {
  const problems = problemsOf(form);
  const focused = focusedField(form);

  return form.fields.map((field) => {
    const isFocused = field === focused;
    const problem = problems.get(field.key);
    const error =
      problem !== undefined && form.shown.has(field.key) ? problem : undefined;
    const rows: FormRow[] = [
      {
        kind: 'field',
        field,
        focused: isFocused,
        status: statusOf(form, field, problem),
        value: valueView(form, field, isFocused),
      },
    ];

    if (isFocused && form.list) {
      const value = form.values[field.key];

      field.options.forEach((option, index) => {
        const ticked = Array.isArray(value) && value.includes(option.value);

        rows.push({
          kind: 'option',
          option,
          highlighted: index === form.list?.highlighted,
          ...(field.kind === 'choice'
            ? { number: index + 1, current: value === option.value }
            : { ticked }),
        });
      });
    }

    if (error !== undefined) {
      rows.push({ kind: 'note', text: error, error: true });
    } else if (isFocused && field.description !== undefined) {
      rows.push({ kind: 'note', text: field.description, error: false });
    }

    return rows;
  });
}

/**
 * The field area's rows, at most `limit` of them. When the fields do not fit
 * they scroll, the focused field always in view with its note and list
 * whole, and a row above or below counts the fields out of view.
 */
export function formRows(form: FormState, limit: number): FormRow[] {
  const blocks = blocksOf(form);
  const all = blocks.flat();

  if (all.length <= limit) {
    return all;
  }

  const focused = form.focus.on === 'field' ? form.focus.index : -1;

  // The first view from the top that holds the focused field whole.
  for (let top = 0; top < blocks.length; top++) {
    const rows: FormRow[] =
      top > 0 ? [{ kind: 'more', direction: 'up', count: top }] : [];
    let end = top;

    while (end < blocks.length) {
      const block = blocks[end] ?? [];
      const below = end + 1 < blocks.length ? 1 : 0;

      if (rows.length + block.length + below > limit) {
        break;
      }

      rows.push(...block);
      end++;
    }

    if (focused < 0 || (focused >= top && focused < end) || end === top) {
      if (end < blocks.length) {
        rows.push({
          kind: 'more',
          direction: 'down',
          count: blocks.length - end,
        });
      }

      return rows;
    }
  }

  return all.slice(0, limit);
}

/** How many problems the button row counts, once Accept has been refused. */
export function toFix(form: FormState): number {
  return form.refused ? problemsOf(form).size : 0;
}

/**
 * The box's inside width from which the hint line says everything; below it,
 * as in an 80-column window, the hint keeps to the keys that matter most.
 */
export const WIDE_HINT = 100;

/**
 * The hint line's keys for where the focus is: the long form in a box at
 * least `WIDE_HINT` wide that fits it, the short one otherwise.
 */
export function formHint(form: FormState, width: number): string {
  const field = focusedField(form);
  const pick = (long: string, short = long) =>
    width >= WIDE_HINT && long.length <= width ? long : short;

  if (!field) {
    return `←→ to switch · Enter to ${
      form.focus.on === 'decline' ? 'decline' : 'accept'
    } · Esc to cancel`;
  }

  if (form.list) {
    if (field.kind === 'multi') {
      return pick(
        '↑↓ to move · Space to tick · Enter or ← to close the list · Esc to cancel',
        '↑↓ · Space to tick · Enter or ← to close · Esc to cancel',
      );
    }

    const digits = `1–${Math.min(field.options.length, 9)}`;

    return pick(
      `↑↓ to move · ${digits} or Enter to pick · ← to close the list · Esc to cancel`,
      `↑↓ · ${digits} or Enter to pick · ← to close · Esc to cancel`,
    );
  }

  switch (field.kind) {
    case 'boolean':
      return 'Space to toggle · ↑↓ to move · Esc to cancel';
    case 'choice':
    case 'multi':
      return '→ or Space to choose · ↑↓ to move · Esc to cancel';
    case 'other':
      return '↑↓ to move · Esc to cancel';
    default:
      return pick(
        'Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel',
        'Type to fill in · ↑↓ to move · Esc to cancel',
      );
  }
}

/** One row of an answered form's record, as ctrl+o shows it. */
export interface AnsweredRow {
  readonly label: string;
  readonly value: string;
}

/**
 * What an accepted form sent, field by field in the form's order, each value
 * as the form showed it: an option's title, `Yes` or `No`.
 */
export function answeredRows(
  schema: ElicitationSchema,
  content: Readonly<Record<string, ElicitationContentValue>>,
): AnsweredRow[] {
  return fieldsOf(schema).flatMap((field) => {
    const value = content[field.key];

    if (value === undefined) {
      return [];
    }

    return [
      {
        label: field.label,
        value:
          typeof value === 'number'
            ? String(value)
            : shownValue(field, value, false),
      },
    ];
  });
}

/** `Answered · 7 fields`: how many values an accepted form sent. */
export function answeredText(
  content: Readonly<Record<string, ElicitationContentValue>> | undefined,
): string {
  const count = Object.keys(content ?? {}).length;

  return count === 0
    ? 'Answered'
    : `Answered · ${count} field${count === 1 ? '' : 's'}`;
}

/**
 * The host a link opens, named under it so a long or misleading URL cannot
 * hide where it goes; none for one that does not parse or is not a web link,
 * which chord does not offer to open.
 */
export function linkHost(url: string): string | undefined {
  try {
    const parsed = new URL(url);

    return parsed.protocol === 'http:' || parsed.protocol === 'https:'
      ? parsed.hostname
      : undefined;
  } catch {
    return undefined;
  }
}
