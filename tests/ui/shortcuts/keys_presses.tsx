/**
 * The presses, states and boxes the key tests share: `keys_test.tsx` and
 * the files split from it (CHD-501).
 */
import { expect } from 'bun:test';
import ru from 'convert-layout/ru.js';
import * as harness from '../harness.tsx';
import { type ReactNode, useState } from 'react';
import type { Questions } from '../../../src/session/questions.ts';
import type { PlanWait } from '../../../src/session/transcript/types.ts';
import { PromptInput } from '../../../src/ui/prompt/Prompt.tsx';
import {
  type Keystroke,
  parseSequence,
  type Sequence,
} from '../../../src/ui/shortcuts/bindings.ts';
import { SHORTCUTS } from '../../../src/ui/shortcuts/keys.ts';
import { type Cursor } from '../../../src/ui/prompt/prompt.ts';
import {
  type AppAction,
  type AppState,
  initialAppState,
  reduceApp,
} from '../../../src/ui/app/state.ts';
import type { KeyPress } from '../../../src/ui/shortcuts/state.ts';

export function after(...actions: AppAction[]): AppState {
  return actions.reduce(reduceApp, initialAppState);
}

export const prompt: AppAction = {
  type: 'prompt',
  turnId: 't1',
  text: 'hi',
  at: 0,
};

export function sequence(text: string): Sequence {
  const parsed = parseSequence(text);

  if ('problem' in parsed) {
    throw new Error(parsed.problem);
  }

  return parsed.keys;
}

export const LETTERS = 'abcdefghijklmnopqrstuvwxyz';

export const PRINTABLE = Array.from({ length: 95 }, (_, i) =>
  String.fromCharCode(32 + i),
);

/**
 * Every key press worth trying on a widget, as the terminal sends it. Ctrl
 * letters that are also Tab, Enter or Backspace are left to those names.
 */
export const RAW_PRESSES: { name: string; sequence: string }[] = [
  { name: 'esc', sequence: '\x1b' },
  { name: 'enter', sequence: '\r' },
  // The kitty keyboard protocol's form, the one Ink reads as shift+return.
  { name: 'shift + enter', sequence: '\x1b[13;2u' },
  { name: 'alt + enter', sequence: '\x1b\r' },
  { name: 'tab', sequence: '\t' },
  { name: 'backspace', sequence: '\x7f' },
  { name: '↑', sequence: '\x1b[A' },
  { name: '↓', sequence: '\x1b[B' },
  { name: '→', sequence: '\x1b[C' },
  { name: '←', sequence: '\x1b[D' },
  // The window's keys, which no widget may act on as well.
  { name: 'shift + ↑', sequence: '\x1b[1;2A' },
  { name: 'shift + ↓', sequence: '\x1b[1;2B' },
  { name: 'pgup', sequence: '\x1b[5~' },
  { name: 'pgdn', sequence: '\x1b[6~' },
  { name: 'home', sequence: '\x1b[H' },
  { name: 'end', sequence: '\x1b[F' },
  { name: 'shift + tab', sequence: '\x1b[Z' },
  ...[...LETTERS]
    .filter((letter) => !'him'.includes(letter))
    .map((letter) => ({
      name: `ctrl + ${letter}`,
      sequence: String.fromCharCode(letter.charCodeAt(0) - 96),
    })),
  ...PRINTABLE.map((sequence) => ({ name: sequence, sequence })),
];

/** Nine choices, so that every digit has one to pick. */
export const NINE = [...'123456789'];

/**
 * Presses every key on a numbered list and checks that each one it answers,
 * by moving its highlight or picking, is in the panel, and that each the
 * panel promises does something: each digit up to its `count` choices.
 * A list too short to open in its middle is tried once from each place
 * `openings` presses it to, as its highlight stops at either end.
 */
export async function listKeys(
  what: string,
  draw: (onPick: (value: string) => void) => ReactNode,
  count = NINE.length,
  openings = [''],
) {
  const answered = new Set<string>();

  for (const opening of openings) {
    await listPresses(what, draw, opening, answered);
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.choices ?? []) {
      if (/^[1-9]$/.test(name) && Number(name) > count) {
        continue;
      }

      expect(
        answered.has(name),
        `${name} does nothing in the ${what}`,
      ).toBeTruthy();
    }
  }
}

/** Presses every key on a list opened with `opening`, adding each answered. */
export async function listPresses(
  what: string,
  draw: (onPick: (value: string) => void) => ReactNode,
  opening: string,
  answered: Set<string>,
) {
  const chosen: string[] = [];
  const app = await harness.draw(draw((value) => chosen.push(value)));
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));

  try {
    await settle();

    if (opening !== '') {
      await app.write(opening);
      await settle();
    }

    for (const { name, sequence } of RAW_PRESSES) {
      const before = app.frame();
      const picks = chosen.length;

      await app.write(sequence);
      await settle();

      if (app.frame() === before && chosen.length === picks) {
        continue;
      }

      answered.add(name);
      expect(
        SHORTCUTS.some((shortcut) => shortcut.choices?.includes(name)),
        `${name} in the ${what} is not listed`,
      ).toBeTruthy();
    }
  } finally {
    await app.unmount();
  }
}

/**
 * The presses worth trying on a form: every one but the printable, which
 * only type, and of those Space, the digits, `j` and `k`, which lists take,
 * and a letter to stand for the rest.
 */
export const FORM_PRESSES = RAW_PRESSES.filter(
  ({ sequence }) =>
    !PRINTABLE.includes(sequence) || /^[ \djkx]$/.test(sequence),
);

/** Questions with each kind of row the box has, nine options apiece. */
export const ASKED: Questions = {
  agent: 'claude',
  questions: [
    {
      id: 'one',
      text: 'One?',
      options: NINE.map((digit) => ({ value: digit, title: digit })),
      multiSelect: false,
      required: false,
      own: { field: 'one_note', mode: 'beside' },
    },
    {
      id: 'many',
      text: 'Many?',
      options: NINE.map((digit) => ({ value: digit, title: digit })),
      multiSelect: true,
      required: false,
      own: { field: 'many_other', mode: 'withValue', value: 'other' },
    },
    {
      id: 'typed',
      text: 'Typed?',
      options: [],
      multiSelect: false,
      required: false,
    },
  ],
};

/**
 * The question box's rows, each reached by the presses after its name, and
 * whether text typed there is the row's own.
 */
export const QUESTION_STATES: [string, string[], boolean][] = [
  ['option', [], false],
  ['note', Array(9).fill('\x1b[B'), true],
  ['multi-select', ['\t'], false],
  ['multi-select own answer', ['\t', ...Array(9).fill('\x1b[B')], true],
  ['typed answer', ['\t', '\t'], true],
  ['submit', ['\t', '\t', '\t'], false],
];

/**
 * The plan box's rows for each agent's plan, each reached by the presses
 * after its name, and whether text typed there is the row's own (CHD-437).
 */
export const PLAN_STATES: [PlanWait['agent'], string, string[], boolean][] = [
  ['cursor', 'choice', [], false],
  ['cursor', 'note', ['\x1b[B', '\x1b[B'], true],
  ['grok', 'choice', [], false],
  ['grok', 'note', ['\x1b[B', '\x1b[B', '\x1b[B'], true],
];

/** The prompt box as the window holds it: its draft and cursor in state. */
export function HeldPrompt({
  start,
  seen,
}: {
  start: { value: string; cursor: Cursor };
  seen: { value: string; cursor: Cursor; walks: number };
}) {
  const [value, setValue] = useState(start.value);
  const [cursor, setCursor] = useState(start.cursor);

  seen.value = value;
  seen.cursor = cursor;

  return (
    <PromptInput
      value={value}
      cursor={cursor}
      rows={5}
      walking={false}
      focus
      onChange={setValue}
      onCursorChange={setCursor}
      onSubmit={() => {}}
      onOlder={() => seen.walks++}
      onNewer={() => seen.walks++}
    />
  );
}

export async function heldPrompt(value: string, cursor: Cursor) {
  const seen = { value, cursor, walks: 0 };
  const app = await harness.draw(
    <HeldPrompt start={{ value, cursor }} seen={seen} />,
  );
  const press = async (sequence: string) => {
    await app.write(sequence);
    await new Promise((resolve) => setTimeout(resolve, 20));
  };

  return { app, seen, press };
}

export const UNDO = '\x1a';

export const REDO = '\x19';

/** A press as Ink reports it. */
export interface Press {
  readonly input: string;
  readonly key: KeyPress;
}

/** The press of `stroke` on a US layout, or on a Russian one. */
export function pressOf(stroke: Keystroke, russian: boolean): Press {
  const character =
    stroke.shift && stroke.key.length === 1
      ? stroke.key.toUpperCase()
      : stroke.key;

  return {
    input: russian ? ru.fromEn(character) : character,
    key: {
      ctrl: stroke.ctrl,
      meta: stroke.alt,
      shift: stroke.shift,
      super: stroke.cmd,
      escape: false,
    },
  };
}

/**
 * Whether a Russian layout types a character of its own where `stroke`'s key
 * is, one a US layout has none of: punctuation it moves, such as `,` where
 * `?` is on Russian – PC, is a US key too and stays as typed.
 */
export function moves(stroke: Keystroke): boolean {
  return stroke.key.length === 1 && cyrillic(pressOf(stroke, true).input);
}

export function cyrillic(character: string): boolean {
  return character.codePointAt(0)! >= 0x80;
}
