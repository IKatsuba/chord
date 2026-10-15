import { expect, test } from 'bun:test';
import ru from 'convert-layout/ru.js';
import * as harness from '../harness.tsx';
import { type ReactNode, useState } from 'react';
import type {
  ElicitationPropertySchema,
  ElicitationSchema,
} from '@agentclientprotocol/sdk';
import type { Questions } from '../../../src/session/questions.ts';
import { ElicitationForm } from '../../../src/ui/dialogs/Form.tsx';
import { QuestionBox } from '../../../src/ui/dialogs/Questions.tsx';
import { PermissionPrompt } from '../../../src/ui/dialogs/Permission.tsx';
import { ModelPicker } from '../../../src/ui/pickers/Pickers.tsx';
import { PromptInput } from '../../../src/ui/prompt/Prompt.tsx';
import {
  type Action,
  DEFAULT_KEYMAP,
  type Keystroke,
  keystrokeOf,
  parseSequence,
  readKeybindings,
  type Sequence,
} from '../../../src/ui/shortcuts/bindings.ts';
import {
  columnCount,
  inColumns,
  shortcutLine,
  shortcuts,
  SHORTCUTS,
} from '../../../src/ui/shortcuts/keys.ts';
import { type Cursor, textareaDoes } from '../../../src/ui/prompt/prompt.ts';
import { emptySearch } from '../../../src/ui/prompt/search.ts';
import {
  type AppAction,
  type AppState,
  initialAppState,
  type KeyAnswer,
  keyAnswer,
  keyCommand,
  reduceApp,
} from '../../../src/ui/app/state.ts';
import { usePress } from '../../../src/ui/app/input.ts';
import type { KeyCommand, KeyPress } from '../../../src/ui/shortcuts/state.ts';
import {
  NORMAL_KEYS,
  startingVim,
  type Vim,
  vimKey,
  vimKeyNames,
} from '../../../src/ui/prompt/vim.ts';

const MODES: AppAction = {
  type: 'modes',
  modes: {
    available: [
      { id: 'default', name: 'Default' },
      { id: 'acceptEdits', name: 'Accept edits' },
      { id: 'plan', name: 'Plan' },
    ],
    current: 'default',
  },
};

function after(...actions: AppAction[]): AppState {
  return actions.reduce(reduceApp, initialAppState);
}

const prompt: AppAction = {
  type: 'prompt',
  turnId: 't1',
  text: 'hi',
  at: 0,
};

function sequence(text: string): Sequence {
  const parsed = parseSequence(text);

  if ('problem' in parsed) {
    throw new Error(parsed.problem);
  }

  return parsed.keys;
}

/** The sessions' leader pressed, its next key waited for. */
const LEADER: AppAction = { type: 'keys_pending', keys: sequence('ctrl+x') };

/** Vim mode in normal mode, as Esc leaves it. */
const VIM_NORMAL: Vim = { ...startingVim, mode: 'normal', entered: undefined };

/** Every state that changes what a key means. */
const STATES: Record<string, AppState> = {
  starting: initialAppState,
  ready: after({ type: 'connected', sessionId: 'session-1' }),
  failed: after({ type: 'connect_failed', message: 'no' }),
  busy: after({ type: 'connected', sessionId: 'session-1' }, prompt),
  asked: after({ type: 'connected', sessionId: 'session-1' }, prompt, {
    type: 'permission_requested',
    turnId: 't1',
    permission: { id: 'p1', options: [] },
  }),
  form: after({ type: 'connected', sessionId: 'session-1' }, prompt, {
    type: 'elicitation_requested',
    turnId: 't1',
    elicitation: { id: 'e1', mode: 'form', message: 'Go?', schema: {} },
  }),
  cancelling: after({ type: 'connected', sessionId: 'session-1' }, prompt, {
    type: 'cancel',
    turnId: 't1',
    at: 1,
  }),
  armed: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'quit_armed',
    },
  ),
  help: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'help_toggled',
    },
  ),
  expanded: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'expanded_toggled',
    },
  ),
  modes: after({ type: 'connected', sessionId: 'session-1' }, MODES),
  'modes, busy': after(
    { type: 'connected', sessionId: 'session-1' },
    MODES,
    prompt,
  ),
  'modes, starting': after(MODES),
  picker: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'model_picker_opened',
    },
  ),
  files: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'files_listed',
      files: ['README.md', 'src/main.ts'],
    },
  ),
  bash: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'bash_mode',
      on: true,
    },
  ),
  shell: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'shell_started',
      turnId: 's1',
      command: 'sleep 9',
    },
  ),
  search: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'searched',
      search: emptySearch,
    },
  ),
  'search, bash': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'bash_mode', on: true },
    { type: 'searched', search: emptySearch },
  ),
  'resume picker': after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'resume_asked',
      asked: 'r1',
    },
    {
      type: 'resume_listed',
      asked: 'r1',
      cwd: '/work',
      otherwise: 'none',
      windows: [],
      sessions: [
        {
          resume: { sessionId: 'session-0', cwd: '/work' },
          lastUsedAt: '2026-10-01T00:00:00.000Z',
          prompt: 'hi',
        },
      ],
    },
  ),
  'config picker': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'config_picker_opened' },
  ),
  'config values': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'config_picker_opened' },
    { type: 'config_option_opened', id: 'effort' },
  ),
  'theme picker': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'theme_picker_opened' },
  ),
  'mcp list': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'mcp_opened' },
  ),
  'teams picker': after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'teams_picker_opened',
      listing: { teams: [], runs: [], dirs: { project: '.chord/teams' } },
    },
  ),
  'sessions picker': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'sessions_picker_opened' },
  ),
  'picker, busy': after({ type: 'connected', sessionId: 'session-1' }, prompt, {
    type: 'model_picker_opened',
  }),
  vim: after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'vim_toggled',
      on: true,
    },
  ),
  'vim, normal': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'vim_toggled', on: true },
    { type: 'vim_changed', vim: VIM_NORMAL },
  ),
  'vim, normal, busy': after(
    { type: 'connected', sessionId: 'session-1' },
    prompt,
    { type: 'vim_toggled', on: true },
    { type: 'vim_changed', vim: VIM_NORMAL },
  ),
  'vim, normal, pending': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'vim_toggled', on: true },
    { type: 'vim_changed', vim: { ...VIM_NORMAL, pending: ['d'] } },
  ),
  leader: after({ type: 'connected', sessionId: 'session-1' }, LEADER),
  // ↓ moved the keys into the list of the session's agents.
  agents: after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
  ),
  'agents, close armed': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
    { type: 'agent_close_armed', key: 2 },
  ),
  // The leader's next key is its own over a permission and a form, so a
  // digit never picks one of their choices.
  'leader, asked': after(
    { type: 'connected', sessionId: 'session-1' },
    prompt,
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
    LEADER,
  ),
  'leader, form': after(
    { type: 'connected', sessionId: 'session-1' },
    prompt,
    {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: { id: 'e1', mode: 'form', message: 'Go?', schema: {} },
    },
    LEADER,
  ),
  'vim, normal, picker': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'vim_toggled', on: true },
    { type: 'vim_changed', vim: VIM_NORMAL },
    { type: 'model_picker_opened' },
  ),
};

/** `state` with a selection shown over it, as a drag leaves one. */
function selected(state: AppState): AppState {
  return { ...state, selection: { kind: 'shown' } };
}

// Spread in after the table, so each is built from the state it shows over.
Object.assign(STATES, {
  selected: selected(STATES.ready!),
  'selected, busy': selected(STATES.busy!),
  'selected, asked': selected(STATES.asked!),
  'selected, form': selected(STATES.form!),
  'selected, leader': selected(STATES.leader!),
});

const LETTERS = 'abcdefghijklmnopqrstuvwxyz';
const PRINTABLE = Array.from({ length: 95 }, (_, i) =>
  String.fromCharCode(32 + i),
);

/** Every key press worth trying, and the name the panel would give it. */
const PRESSES: { name: string; input: string; key: KeyPress }[] = [
  { name: 'esc', input: '', key: { ctrl: false, escape: true } },
  ...[...LETTERS].map((letter) => ({
    name: `ctrl + ${letter}`,
    input: letter,
    key: { ctrl: true, escape: false },
  })),
  ...PRINTABLE.map((input) => ({
    name: input,
    input,
    key: { ctrl: false, escape: false },
  })),
  ...(
    [
      ['↑', { upArrow: true }],
      ['↓', { downArrow: true }],
      ['pgup', { pageUp: true }],
      ['pgdn', { pageDown: true }],
      ['home', { home: true }],
      ['end', { end: true }],
      ['tab', { tab: true }],
      ['backspace', { backspace: true }],
    ] as const
  ).flatMap(([name, pressed]) => [
    { name, input: '', key: { ctrl: false, escape: false, ...pressed } },
    {
      name: `shift + ${name}`,
      input: '',
      key: { ctrl: false, escape: false, shift: true, ...pressed },
    },
  ]),
];

test('every key that does something is in the shortcuts panel', () => {
  const answered = new Set<KeyCommand>();

  for (const [stateName, state] of Object.entries(STATES)) {
    // A `/` opens the slash command list and an `@` the file finder, whose
    // keys are their own.
    for (const draft of ['', 'draft', '/', '@']) {
      for (const { name, input, key } of PRESSES) {
        const command = keyCommand(input, key, state, draft);

        // Any key a chord's first keys do not run drops them, as the leader
        // line's `esc never mind` says; it is no key of its own.
        if (command === undefined || command === 'key_dropped') {
          continue;
        }

        answered.add(command);
        expect(
          SHORTCUTS.some(
            (shortcut) =>
              (shortcut.presses ?? [shortcut.key]).includes(name) &&
              shortcut.commands.includes(command),
          ),
          `${name} → ${command} (${stateName}, draft "${draft}") is not listed`,
        ).toBeTruthy();
      }
    }
  }

  // And the panel promises nothing the keys do not do.
  for (const shortcut of SHORTCUTS) {
    for (const command of shortcut.commands) {
      expect(
        answered.has(command),
        `${shortcut.key} ${command} never happens`,
      ).toBeTruthy();
    }
  }
});

/**
 * Every key press worth trying on a widget, as the terminal sends it. Ctrl
 * letters that are also Tab, Enter or Backspace are left to those names.
 */
const RAW_PRESSES: { name: string; sequence: string }[] = [
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
const NINE = [...'123456789'];

/**
 * Presses every key on a numbered list and checks that each one it answers,
 * by moving its highlight or picking, is in the panel, and that each the
 * panel promises does something.
 */
async function listKeys(
  what: string,
  draw: (onPick: (value: string) => void) => ReactNode,
) {
  const chosen: string[] = [];
  const app = await harness.draw(draw((value) => chosen.push(value)));
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));
  const answered = new Set<string>();

  try {
    await settle();

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

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.choices ?? []) {
      expect(
        answered.has(name),
        `${name} does nothing in the ${what}`,
      ).toBeTruthy();
    }
  }
}

test('every key the permission prompt answers is in the panel', () =>
  listKeys('permission prompt', (onPick) => (
    <PermissionPrompt
      wait={{
        id: 'p1',
        title: 'Write notes.txt',
        options: NINE.map((digit) => ({
          optionId: digit,
          name: `Option ${digit}`,
          kind: 'allow_once',
        })),
      }}
      active
      onChoose={onPick}
    />
  )));

/** A form of one field of `property`'s kind. */
function oneField(property: ElicitationPropertySchema): ElicitationSchema {
  return {
    type: 'object',
    properties: { only: property },
  } as ElicitationSchema;
}

const CHOICE = oneField({ type: 'string', enum: [...NINE] });

/**
 * The form's states where a key does something other than type: a boolean,
 * a closed and an open choice list, an open multi-select, and the buttons,
 * each reached by the presses after its schema.
 */
const FORM_STATES: [string, ElicitationSchema, string[]][] = [
  ['boolean', oneField({ type: 'boolean', default: true }), []],
  ['choice', CHOICE, []],
  ['open choice', CHOICE, ['\x1b[C', '5']],
  [
    'open multi-select',
    oneField({ type: 'array', items: { type: 'string', enum: [...NINE] } }),
    [' ', '\x1b[B', '\x1b[B'],
  ],
  ['buttons', oneField({ type: 'boolean' }), ['\x1b[B']],
  ['decline', oneField({ type: 'boolean' }), ['\x1b[B', '\x1b[C']],
  ['text', oneField({ type: 'string' }), []],
];

/**
 * The presses worth trying on a form: every one but the printable, which
 * only type, and of those Space, the digits, `j` and `k`, which lists take,
 * and a letter to stand for the rest.
 */
const FORM_PRESSES = RAW_PRESSES.filter(
  ({ sequence }) =>
    !PRINTABLE.includes(sequence) || /^[ \djkx]$/.test(sequence),
);

/**
 * Presses every key on the form, in each of its states afresh, and checks
 * that each one it answers, by changing what it draws or by answering the
 * agent, is in the panel, and that each the panel promises does something.
 * Typing and editing in a text field, as in the prompt, are not listed.
 */
test('every key a form answers is in the panel', async () => {
  const settle = (ms = 10) => new Promise((resolve) => setTimeout(resolve, ms));
  const answered = new Set<string>();

  for (const [state, schema, prelude] of FORM_STATES) {
    const answers: unknown[] = [];
    // A fresh form in the state, drawn again only once a key has changed it.
    const draw = async () => {
      const app = await harness.draw(
        <ElicitationForm
          wait={{ id: 'e1', mode: 'form', message: 'Go?', schema }}
          agent='fake'
          windowRows={40}
          width={120}
          active
          onAnswer={(response) => answers.push(response)}
        />,
      );

      await settle();

      for (const press of prelude) {
        await app.write(press);
        await settle();
      }

      answers.length = 0;

      return app;
    };

    let app = await draw();

    try {
      for (const { name, sequence } of FORM_PRESSES) {
        const before = app.frame();

        await app.write(sequence);
        // A lone ESC waits 20 ms for the rest of a sequence that never comes.
        await settle(40);

        if (app.frame() === before && answers.length === 0) {
          continue;
        }

        await app.unmount();

        app = await draw();

        const editing =
          state === 'text' &&
          (name.length === 1 ||
            name.startsWith('ctrl + ') ||
            ['←', '→', 'home', 'end', 'backspace'].includes(name));

        if (editing) {
          continue;
        }

        answered.add(name);
        expect(
          SHORTCUTS.some(
            (shortcut) =>
              shortcut.form?.includes(name) || shortcut.choices?.includes(name),
          ),
          `${name} on a form's ${state} is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.form ?? []) {
      expect(answered.has(name), `${name} does nothing on a form`).toBeTruthy();
    }
  }
});

/** Questions with each kind of row the box has, nine options apiece. */
const ASKED: Questions = {
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
const QUESTION_STATES: [string, string[], boolean][] = [
  ['option', [], false],
  ['note', Array(9).fill('\x1b[B'), true],
  ['multi-select', ['\t'], false],
  ['multi-select own answer', ['\t', ...Array(9).fill('\x1b[B')], true],
  ['typed answer', ['\t', '\t'], true],
  ['submit', ['\t', '\t', '\t'], false],
];

/**
 * Presses every key on the question box, on each kind of row afresh, and
 * checks that each one it answers is in the panel, and that each the panel
 * promises for it does something. Typing and editing a text row are not
 * listed.
 */
test('every key the question box answers is in the panel', async () => {
  const settle = (ms = 10) => new Promise((resolve) => setTimeout(resolve, ms));
  const answered = new Set<string>();

  for (const [state, prelude, typing] of QUESTION_STATES) {
    const answers: unknown[] = [];
    const draw = async () => {
      const app = await harness.draw(
        <QuestionBox
          wait={{
            id: 'e1',
            mode: 'form',
            message: 'Go?',
            schema: { type: 'object', properties: {} },
          }}
          questions={ASKED}
          agent='fake'
          windowRows={40}
          width={120}
          active
          onAnswer={(response) => answers.push(response)}
        />,
      );

      await settle();

      for (const press of prelude) {
        await app.write(press);
        await settle();
      }

      answers.length = 0;

      return app;
    };

    let app = await draw();

    try {
      for (const { name, sequence } of FORM_PRESSES) {
        const before = app.frame();

        await app.write(sequence);
        // A lone ESC waits 20 ms for the rest of a sequence that never comes.
        await settle(40);

        if (app.frame() === before && answers.length === 0) {
          continue;
        }

        await app.unmount();

        app = await draw();

        if (
          typing &&
          (name.length === 1 ||
            name.startsWith('ctrl + ') ||
            name === 'backspace')
        ) {
          continue;
        }

        answered.add(name);
        expect(
          SHORTCUTS.some(
            (shortcut) =>
              shortcut.questions?.includes(name) ||
              shortcut.choices?.includes(name),
          ),
          `${name} on the question box's ${state} is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.questions ?? []) {
      expect(
        answered.has(name),
        `${name} does nothing on the question box`,
      ).toBeTruthy();
    }
  }
});

// The session picker's list is the model picker's, so this covers both.
test('every key the model picker answers is in the panel', () =>
  listKeys('model picker', (onPick) => (
    <ModelPicker
      models={{
        available: NINE.map((digit) => ({
          id: digit,
          name: `Model ${digit}`,
        })),
        // In the middle, so that its highlight can move either way: it stops
        // at the ends.
        current: '5',
      }}
      rows={9}
      agent='fake'
      active
      onPick={onPick}
    />
  )));

/** The prompt box with a draft, counting what each press did to it. */
async function promptBox(walking: boolean) {
  const did = { sends: 0, newlines: 0, walks: 0 };
  const app = await harness.draw(
    <PromptInput
      // A draft, so that a send has something to send.
      value='draft'
      cursor={[0, 5]}
      rows={5}
      walking={walking}
      focus
      onChange={(value) => value.includes('\n') && did.newlines++}
      onCursorChange={() => {}}
      onSubmit={() => did.sends++}
      onOlder={() => did.walks++}
      onNewer={() => did.walks++}
    />,
  );

  return { app, did };
}

test('every key the prompt sends, breaks or walks on is in the panel', async () => {
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));
  const answered = new Set<string>();

  for (const walking of [false, true]) {
    // The box's value and cursor are held, so no press changes what the next
    // one does.
    const { app, did } = await promptBox(walking);

    try {
      await settle();

      for (const { name, sequence } of RAW_PRESSES) {
        const before = JSON.stringify(did);

        await app.write(sequence);
        await settle();

        if (JSON.stringify(did) === before) {
          continue;
        }

        answered.add(name);
        expect(
          SHORTCUTS.some((shortcut) => shortcut.prompt?.includes(name)),
          `${name} in the prompt is not listed`,
        ).toBeTruthy();
      }
    } finally {
      await app.unmount();
    }
  }

  for (const shortcut of SHORTCUTS) {
    for (const name of shortcut.prompt ?? []) {
      expect(
        answered.has(name),
        `${name} does nothing in the prompt`,
      ).toBeTruthy();
    }
  }
});

/** The prompt box as the window holds it: its draft and cursor in state. */
function HeldPrompt({
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

async function heldPrompt(value: string, cursor: Cursor) {
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

const UNDO = '\x1a';
const REDO = '\x19';

for (const [name, sequence] of [
  ['↑', '\x1b[1;2A'],
  ['↓', '\x1b[1;2B'],
]) {
  // OpenTUI undoes key by key, as the owner took on CHD-306.
  test(`shift + ${name} leaves the draft its undo and redo`, async () => {
    const { app, seen, press } = await heldPrompt('', [0, 0]);

    try {
      await press('');
      await press('abc');
      await press(sequence!);
      expect(seen.value).toStrictEqual('abc');
      expect(seen.walks).toStrictEqual(0);

      await press(UNDO);
      expect(seen.value).toStrictEqual('ab');
      await press(sequence!);
      await press(REDO);
      expect(seen.value).toStrictEqual('abc');
    } finally {
      await app.unmount();
    }
  });
}

test('ctrl+z takes the key typed back out of the draft, and ctrl+y puts it back', async () => {
  const { app, seen, press } = await heldPrompt('', [0, 0]);

  try {
    await press('');
    await press('a');
    expect(seen.value).toStrictEqual('a');

    // OpenTUI's undo changes the text with no change event of its own.
    await press(UNDO);
    expect(seen.value).toStrictEqual('');
    expect(seen.cursor).toStrictEqual([0, 0]);

    await press(REDO);
    expect(seen.value).toStrictEqual('a');
    expect(seen.cursor).toStrictEqual([0, 1]);
  } finally {
    await app.unmount();
  }
});

test('after shift + ↑ in a draft of lines, ↑ still moves the cursor', async () => {
  const { app, seen, press } = await heldPrompt('one\ntwo\nthree', [1, 1]);

  try {
    await press('');
    await press('\x1b[1;2A');
    expect(seen.cursor).toStrictEqual([1, 1]);
    expect(app.frame().includes('one')).toBeTruthy();

    // The textarea once reported [0, 1] for the shifted press; a real move
    // to the same place must still arrive.
    await press('\x1b[A');
    expect(seen.cursor).toStrictEqual([0, 1]);
    await press('\x1b[1;2B');
    expect(seen.cursor).toStrictEqual([0, 1]);
    await press('\x1b[B');
    expect(seen.cursor).toStrictEqual([1, 1]);
    expect(seen.walks).toStrictEqual(0);
  } finally {
    await app.unmount();
  }
});

test('shift + tab leaves the draft as it was', async () => {
  const { app, seen, press } = await heldPrompt('abc', [0, 3]);

  try {
    await press('');
    await press('\x1b[Z');
    expect(seen.value).toStrictEqual('abc');
    expect(seen.cursor).toStrictEqual([0, 3]);
  } finally {
    await app.unmount();
  }
});

test('shift + tab asks for a mode only once the agent offers two', () => {
  const shiftTab = { ctrl: false, escape: false, shift: true, tab: true };
  const tab = { ctrl: false, escape: false, tab: true };

  expect(keyCommand('', shiftTab, STATES.modes!, '')).toStrictEqual(
    'cycle_mode',
  );
  expect(keyCommand('', shiftTab, STATES.modes!, 'draft')).toStrictEqual(
    'cycle_mode',
  );
  expect(keyCommand('', shiftTab, STATES['modes, busy']!, '')).toStrictEqual(
    'cycle_mode',
  );
  expect(keyCommand('', tab, STATES.modes!, '')).toStrictEqual(undefined);
  expect(keyCommand('', shiftTab, STATES.ready!, '')).toStrictEqual(undefined);
  expect(
    keyCommand('', shiftTab, STATES['modes, starting']!, ''),
  ).toStrictEqual(undefined);
});

test('? on an empty prompt opens the panel, and text anywhere else', () => {
  const plain = { ctrl: false, escape: false };
  const escape = { ctrl: false, escape: true };
  const { ready, busy, help } = STATES;

  expect(keyCommand('?', plain, ready!, '')).toStrictEqual('toggle_help');
  expect(keyCommand('?', plain, busy!, '')).toStrictEqual('toggle_help');
  expect(keyCommand('?', plain, ready!, 'why')).toStrictEqual(undefined);
  expect(keyCommand('?', plain, help!, '')).toStrictEqual('toggle_help');
  // Esc closes the panel before it interrupts anything.
  expect(
    keyCommand('', escape, reduceApp(busy!, { type: 'help_toggled' }), ''),
  ).toStrictEqual('close_help');
  expect(reduceApp(help!, { type: 'help_toggled' }).help).toStrictEqual(false);
  expect(reduceApp(help!, { type: 'help_closed' }).help).toStrictEqual(false);
  expect(reduceApp(help!, { type: 'quit_armed' }).help).toStrictEqual(false);
  expect(reduceApp(help!, { type: 'closing' }).help).toStrictEqual(false);
});

test('a permission asked during a search closes it and owns the keys', () => {
  const plain = { ctrl: false, escape: false };
  const asked = reduceApp(
    after({ type: 'connected', sessionId: 'session-1' }, prompt, {
      type: 'searched',
      search: emptySearch,
    }),
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
  );

  expect(asked.search).toStrictEqual(undefined);
  expect(keyCommand('', { ...plain, escape: true }, asked, '')).toStrictEqual(
    'reject_permission',
  );
  expect(keyCommand('', { ...plain, return: true }, asked, '')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('1', plain, asked, '')).toStrictEqual(undefined);
  expect(
    keyCommand('r', { ctrl: true, escape: false }, asked, ''),
  ).toStrictEqual(undefined);
});

test('while searching, typing is the query’s and Enter takes the match', () => {
  const plain = { ctrl: false, escape: false };
  const { search, ready, asked, picker } = STATES;
  const ctrlR = { ctrl: true, escape: false };

  expect(keyCommand('r', ctrlR, ready!, 'draft')).toStrictEqual(
    'search_history',
  );
  expect(keyCommand('r', ctrlR, search!, 'draft')).toStrictEqual(
    'search_older',
  );
  // A permission or the model picker holds the keys.
  expect(keyCommand('r', ctrlR, asked!, '')).toStrictEqual(undefined);
  expect(keyCommand('r', ctrlR, picker!, '')).toStrictEqual(undefined);
  expect(keyCommand('r', ctrlR, STATES['resume picker']!, '')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('', { ...plain, return: true }, search!, '')).toStrictEqual(
    'accept_search',
  );
  // ? and backspace on an empty draft edit the query, not the window.
  expect(keyCommand('?', plain, search!, '')).toStrictEqual(undefined);
  expect(
    keyCommand('', { ...plain, backspace: true }, STATES['search, bash']!, ''),
  ).toStrictEqual(undefined);
  // A / or @ under the search opens no list.
  expect(keyCommand('', { ...plain, tab: true }, search!, '/')).toStrictEqual(
    'accept_search',
  );
  expect(
    keyCommand('', { ...plain, escape: true }, STATES.busy!, ''),
  ).toStrictEqual('interrupt');
  expect(
    keyCommand(
      '',
      { ...plain, escape: true },
      reduceApp(STATES.busy!, { type: 'searched', search: emptySearch }),
      '',
    ),
  ).toStrictEqual('cancel_search');
});

test('the search closes the panel and goes when chord closes', () => {
  const open = reduceApp(STATES.help!, {
    type: 'searched',
    search: emptySearch,
  });

  expect(open.help).toStrictEqual(false);
  expect(open.search).toStrictEqual(emptySearch);
  expect(
    'search' in reduceApp(open, { type: 'searched', search: undefined }),
  ).toStrictEqual(false);
  expect('search' in reduceApp(open, { type: 'closing' })).toStrictEqual(false);
});

test('the panel reads in columns, top to bottom', () => {
  expect(inColumns([1, 2, 3, 4, 5, 6, 7], 3)).toStrictEqual([
    [1, 2, 3],
    [4, 5, 6],
    [7],
  ]);
  expect(inColumns([1, 2], 3)).toStrictEqual([[1], [2]]);
  expect(inColumns([], 3)).toStrictEqual([]);
});

test('the panel takes the most columns that fit without folding', () => {
  const lines = SHORTCUTS.map(shortcutLine);

  expect(columnCount(lines, 120)).toStrictEqual(3);
  expect(columnCount(lines, 80)).toStrictEqual(2);
  expect(columnCount(lines, 20)).toStrictEqual(1);
  // Two columns of ten and of twenty cells, with the left indent and the
  // gap; the last column may reach the edge.
  expect(columnCount(['a'.repeat(10), 'b'.repeat(20)], 35)).toStrictEqual(2);
  expect(columnCount(['a'.repeat(10), 'b'.repeat(20)], 34)).toStrictEqual(1);
});

test('ctrl+g opens the editor wherever the draft has the keys', () => {
  const ctrlG = { ctrl: true, escape: false };

  expect(keyCommand('g', ctrlG, STATES.ready!, 'draft')).toStrictEqual(
    'open_editor',
  );
  expect(keyCommand('g', ctrlG, STATES.ready!, '')).toStrictEqual(
    'open_editor',
  );
  // During a turn the draft is the next prompt.
  expect(keyCommand('g', ctrlG, STATES.busy!, 'next')).toStrictEqual(
    'open_editor',
  );
  expect(keyCommand('g', ctrlG, STATES.help!, '')).toStrictEqual('open_editor');
  // A permission, a picker or the search's match has the box.
  expect(keyCommand('g', ctrlG, STATES.asked!, 'draft')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('g', ctrlG, STATES.picker!, 'draft')).toStrictEqual(
    undefined,
  );
  expect(
    keyCommand('g', ctrlG, STATES['resume picker']!, 'draft'),
  ).toStrictEqual(undefined);
  expect(keyCommand('g', ctrlG, STATES.search!, 'draft')).toStrictEqual(
    undefined,
  );
  expect(
    keyCommand('g', ctrlG, reduceApp(STATES.ready!, { type: 'closing' }), ''),
  ).toStrictEqual(undefined);
});

test('ctrl+v pastes an image wherever a prompt has the keys', () => {
  const ctrlV = { ctrl: true, escape: false };

  expect(keyCommand('v', ctrlV, STATES.ready!, '')).toStrictEqual(
    'paste_image',
  );
  expect(keyCommand('v', ctrlV, STATES.ready!, 'draft')).toStrictEqual(
    'paste_image',
  );
  // During a turn the draft is the next prompt.
  expect(keyCommand('v', ctrlV, STATES.busy!, 'next')).toStrictEqual(
    'paste_image',
  );
  // A shell command takes no image; a list or the search has the keys.
  expect(keyCommand('v', ctrlV, STATES.bash!, '')).toStrictEqual(undefined);
  expect(keyCommand('v', ctrlV, STATES.asked!, 'draft')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('v', ctrlV, STATES.picker!, 'draft')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('v', ctrlV, STATES.search!, '')).toStrictEqual(undefined);
});

test("the editor's failure stays in the state until the draft is touched", () => {
  const failed = reduceApp(STATES.ready!, {
    type: 'editor_failed',
    message: 'vi exited with code 1; the draft is unchanged',
  });

  expect(failed.editorFailed).toStrictEqual(
    'vi exited with code 1; the draft is unchanged',
  );
  expect(
    'editorFailed' in reduceApp(failed, { type: 'draft_edited' }),
  ).toStrictEqual(false);
  expect(
    'editorFailed' in reduceApp(failed, { type: 'draft_cleared' }),
  ).toStrictEqual(false);
  expect(
    'editorFailed' in reduceApp(failed, { type: 'editor_opened' }),
  ).toStrictEqual(false);
  // The panel would cover the draft that comes back.
  expect(reduceApp(STATES.help!, { type: 'editor_opened' }).help).toStrictEqual(
    false,
  );
});

/** A press as Ink reports it. */
interface Press {
  readonly input: string;
  readonly key: KeyPress;
}

/** The press of `stroke` on a US layout, or on a Russian one. */
function pressOf(stroke: Keystroke, russian: boolean): Press {
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
function moves(stroke: Keystroke): boolean {
  return stroke.key.length === 1 && cyrillic(pressOf(stroke, true).input);
}

function cyrillic(character: string): boolean {
  return character.codePointAt(0)! >= 0x80;
}

/**
 * What the last of `presses` asks for, each one before it played as the
 * window plays it: a chord's first keys held, as read, for the next.
 */
function played(
  state: AppState,
  draft: string,
  presses: readonly Press[],
): KeyCommand | undefined {
  let now = state;
  let command: KeyCommand | undefined;

  for (const { input, key } of presses) {
    const answer = keyAnswer(input, key, now, draft);
    const stroke = keystrokeOf(answer.input, key);

    command = answer.command;
    now =
      command === 'key_pending' && stroke !== undefined
        ? reduceApp(now, {
            type: 'keys_pending',
            keys: [...(now.pendingKeys ?? []), stroke],
          })
        : reduceApp(now, { type: 'keys_pending' });
  }

  return command;
}

/** A key no default binding has, for an action to be moved onto. */
const FREE = sequence('ctrl+q')[0]!;

/** `state` with `action` moved from the textarea's own key onto `FREE`. */
function withoutTextarea(state: AppState, action: Action): AppState {
  return {
    ...state,
    keys: {
      ...state.keys,
      bindings: state.keys.bindings.map((binding) =>
        binding.action === action && textareaDoes(binding.keys, action)
          ? { ...binding, keys: [FREE] }
          : binding,
      ),
    },
  };
}

test('every letter binding runs on a Russian layout as on a US one', () => {
  const letters = DEFAULT_KEYMAP.bindings.filter(
    ({ keys }) => keys.some(moves) && keys.every(({ key }) => key.length === 1),
  );
  const ran = new Set<string>();

  for (const { keys, action } of letters) {
    // Each of the chord's keys from either layout: the leader as the control
    // byte most terminals send and its next key in Cyrillic, and the rest.
    const mixes = keys.reduce<Press[][]>(
      (sofar, stroke) =>
        sofar.flatMap((start) =>
          (moves(stroke) ? [false, true] : [false]).map((russian) => [
            ...start,
            pressOf(stroke, russian),
          ]),
        ),
      [[]],
    );

    for (const [stateName, state] of Object.entries(STATES)) {
      for (const draft of ['', 'draft']) {
        // A key the prompt's textarea acts on itself is chord's to act on
        // when it comes in Cyrillic, as the textarea hears it as typed: what
        // chord runs for the action on a key of its own is what it runs.
        const us = textareaDoes(keys, action)
          ? played(withoutTextarea(state, action), draft, [
              pressOf(FREE, false),
            ])
          : played(state, draft, mixes[0]!);

        if (us === undefined || us === 'key_dropped') {
          continue;
        }

        ran.add(action);

        for (const presses of mixes.slice(1)) {
          expect(
            played(state, draft, presses),
            `${presses.map(({ input }) => input).join(' ')} for ${action} ` +
              `(${stateName}, draft "${draft}")`,
          ).toStrictEqual(us);
        }
      }
    }
  }

  for (const { action } of letters) {
    expect(ran.has(action), `${action} never ran`).toBeTruthy();
  }
});

test("vim's normal mode reads the Russian layout's keys as the US ones", () => {
  const normal = STATES['vim, normal']!;
  const insert = STATES.vim!;
  const plain: KeyPress = { ctrl: false, escape: false };
  const moved = [...NORMAL_KEYS].filter((key) => cyrillic(ru.fromEn(key)));

  // h, j, k, l, w and the rest at least.
  expect(moved.length > 30).toBeTruthy();

  for (const key of moved) {
    const russian = ru.fromEn(key);

    expect(
      keyAnswer(russian, plain, normal, 'draft'),
      `${russian} for ${key}`,
    ).toStrictEqual({ command: 'vim_key', input: key });
    // Insert mode types it.
    expect(keyCommand(russian, plain, insert, 'draft')).toStrictEqual(
      undefined,
    );
  }

  // After f, the next key is the character looked for, as typed.
  const finding = reduceApp(normal, {
    type: 'vim_changed',
    vim: { ...VIM_NORMAL, pending: ['f'] },
  });

  expect(keyAnswer('р', plain, finding, 'draft')).toStrictEqual({
    command: 'vim_key',
    input: 'р',
  });
});

/** The draft and mode after `pending`, then `input`, in normal mode. */
function objectEdit(pending: string[], input: string) {
  const vim: Vim = { ...VIM_NORMAL, pending };
  const state = reduceApp(STATES['vim, normal']!, { type: 'vim_changed', vim });
  const plain: KeyPress = { ctrl: false, escape: false };
  const answer = keyAnswer(input, plain, state, 'one two', [0, 0]);
  const [name] = vimKeyNames(answer.input, plain);
  const step = vimKey(vim, 'one two', [0, 0], name!);

  return 'text' in step ? { text: step.text, mode: step.vim.mode } : step;
}

test("a text object's Russian key after an operator is the US one", () => {
  const objects = ['w', 'W', 'p', 's', 'b', 'B'].filter((key) =>
    cyrillic(ru.fromEn(key)),
  );

  for (const operator of ['d', 'c', 'y']) {
    for (const around of ['i', 'a']) {
      for (const key of objects) {
        expect(
          objectEdit([operator, around], ru.fromEn(key)),
          `${operator}${around}${ru.fromEn(key)}`,
        ).toStrictEqual(objectEdit([operator, around], key));
      }
    }
  }

  expect(objectEdit(['d', 'i'], 'ц')).toStrictEqual({
    text: ' two',
    mode: 'normal',
  });
  expect(objectEdit(['c', 'a'], 'ц')).toStrictEqual({
    text: 'two',
    mode: 'insert',
  });

  // After f, t and r the key is the character, Cyrillic or not.
  for (const pending of [['f'], ['t'], ['r'], ['d', 'f']]) {
    const state = reduceApp(STATES['vim, normal']!, {
      type: 'vim_changed',
      vim: { ...VIM_NORMAL, pending },
    });

    expect(
      keyAnswer('ц', { ctrl: false, escape: false }, state, 'one two').input,
      pending.join(''),
    ).toStrictEqual('ц');
  }
});

/**
 * Presses each sequence on Ink's stdin and gives what each asked for, heard
 * as the window hears it, with its base-layout key.
 */
async function heard(
  state: AppState,
  sequences: readonly string[],
  draft = '',
): Promise<KeyAnswer[]> {
  const answers: KeyAnswer[] = [];

  function Listener() {
    usePress((input, key) => {
      answers.push(keyAnswer(input, key, state, draft));
    });

    return <text>listening</text>;
  }

  const app = await harness.draw(<Listener />);
  const settle = () => new Promise((resolve) => setTimeout(resolve, 20));

  try {
    await settle();

    for (const sequence of sequences) {
      await app.write(sequence);
      await settle();
    }
  } finally {
    await app.unmount();
  }

  return answers;
}

test('ctrl+ч is ctrl+x in every form a terminal sends it', async () => {
  const leader: KeyAnswer = { command: 'key_pending', input: 'x' };

  expect(
    await heard(STATES.ready!, [
      // The control byte, which most terminals send whatever the layout.
      '\x18',
      // The kitty keyboard protocol's, with the layout's own character.
      '\x1b[1095;5u',
    ]),
  ).toStrictEqual([leader, leader]);
  expect(await heard(STATES.leader!, ['с'])).toStrictEqual([
    { command: 'new_session', input: 'c' },
  ]);
  expect(await heard(STATES.leader!, ['\x1b[1090;5u'])).toStrictEqual([
    { command: 'next_session', input: 'n' },
  ]);
});

test("a kitty press's base-layout key runs what that key is bound to", async () => {
  const leader: KeyAnswer = { command: 'key_pending', input: 'x' };

  expect(
    await heard(STATES.ready!, [
      // ctrl+ч on Russian and ctrl+χ on Greek, each on the key of US x.
      '\x1b[1095::120;5u',
      '\x1b[967::120;5u',
      // ctrl+shift+ч, its shifted character between the two, which is
      // ctrl+shift+x and bound to nothing.
      '\x1b[1095:1063:120;6u',
      // ctrl+ρ on Greek, where a US layout has r.
      '\x1b[961::114;5u',
    ]),
  ).toStrictEqual([
    leader,
    leader,
    { command: undefined, input: 'ч' },
    {
      command: 'search_history',
      input: 'r',
    },
  ]);
  // ctrl+с on Russian, its base key c, is ctrl+c as the control byte is.
  expect(await heard(STATES.ready!, ['\x1b[1089::99;5u'])).toStrictEqual(
    await heard(STATES.ready!, ['\x03']),
  );
  // Greek has no table: with no base key the press asks for nothing.
  expect(await heard(STATES.ready!, ['\x1b[967;5u'])).toStrictEqual([
    { command: undefined, input: 'χ' },
  ]);
  // A base key Ink sends no listener before the next press is never kept:
  // ctrl+χ after a press with one is still nothing.
  expect(
    await heard(STATES.ready!, ['\x1b[967::120;5u', '\x1b[967;5u']),
  ).toStrictEqual([leader, { command: undefined, input: 'χ' }]);
  // The leader's ctrl+ forms the same way: ctrl+ν is ctrl+n.
  expect(await heard(STATES.leader!, ['\x1b[957::110;5u'])).toStrictEqual([
    { command: 'next_session', input: 'n' },
  ]);
});

test('a press with a base-layout key types its own character in the prompt', async () => {
  const { app, seen, press } = await heldPrompt('', [0, 0]);

  try {
    await press('\x1b[967::120u');
    await press('\x1b[1095::120u');
    await press('χ');
    expect(seen.value).toStrictEqual('χчχ');
  } finally {
    await app.unmount();
  }

  expect(
    await heard(STATES.ready!, ['\x1b[967::120u', '\x1b[1095::120u']),
  ).toStrictEqual([
    { command: undefined, input: 'χ' },
    { command: undefined, input: 'ч' },
  ]);
});

/** The key where US has `?`, shifted, on Russian – PC: it types `,`. */
const RUSSIAN_QUESTION = '\x1b[46:44:47;2;44u';

test('the key of ? on Russian – PC asks for the shortcuts, or types its comma', async () => {
  expect(await heard(STATES.ready!, [RUSSIAN_QUESTION])).toStrictEqual([
    { command: 'toggle_help', input: '?' },
  ]);
  expect(await heard(STATES.ready!, [RUSSIAN_QUESTION], 'ч')).toStrictEqual([
    { command: undefined, input: ',' },
  ]);

  const { app, seen, press } = await heldPrompt('', [0, 0]);

  try {
    await press('\x1b[1095::120;1;1095u');
    await press(RUSSIAN_QUESTION);
    expect(seen.value).toStrictEqual('ч,');
  } finally {
    await app.unmount();
  }
});

test('every key as an escape code is the same key it was as bytes', async () => {
  // Enter, Tab, Backspace, Escape, ctrl+c and text, as a terminal reporting
  // every key sends them, ask for what their plain bytes ask for.
  for (const [kitty, plain] of [
    ['\x1b[13u', '\r'],
    ['\x1b[9u', '\t'],
    ['\x1b[127u', '\x7f'],
    ['\x1b[27u', '\x1b'],
    ['\x1b[99;5u', '\x03'],
    ['\x1b[47;1;47u', '/'],
    ['\x1b[47:63;2;63u', '?'],
  ] as const) {
    expect(
      (await heard(STATES.ready!, [kitty])).map(({ command }) => command),
      JSON.stringify(kitty),
    ).toStrictEqual(
      (await heard(STATES.ready!, [plain])).map(({ command }) => command),
    );
  }

  // A modifier pressed on its own before each key is no press, so it
  // neither answers nor ends the chord begun.
  expect(
    await heard(STATES.ready!, ['\x1b[57442;5u', '\x1b[120;5u']),
  ).toStrictEqual([{ command: 'key_pending', input: 'x' }]);
  expect(
    await heard(STATES.leader!, ['\x1b[57441;2u', '\x1b[99;1;99u']),
  ).toStrictEqual([{ command: 'new_session', input: 'c' }]);
  // A chord's bare next key on a layout with no table: Greek ψ is on c.
  expect(await heard(STATES.leader!, ['\x1b[968::99;1;968u'])).toStrictEqual([
    { command: 'new_session', input: 'c' },
  ]);

  const { app, seen, press } = await heldPrompt('', [0, 0]);

  try {
    // Text in any case and layout, shift+enter's line, and the keypad's
    // digit with num lock on, all typed as the terminal says.
    for (const sequence of [
      '\x1b[97;1;97u',
      '\x1b[57441;2u',
      '\x1b[98:66;2;66u',
      '\x1b[967;1;967u',
      '\x1b[13;2u',
      '\x1b[57400;129;49u',
      '\x1b[32;1;32u',
      '\x1b[1095::120;1;1095u',
    ]) {
      await press(sequence);
    }

    expect(seen.value).toStrictEqual('aBχ\n1 ч');
    await press('\x1b[127u');
    expect(seen.value).toStrictEqual('aBχ\n1 ');
  } finally {
    await app.unmount();
  }
});

const CTRL_C: KeyPress = { ctrl: true, escape: false };

test('ctrl+c copies a selection shown in front of every context (CHD-172)', () => {
  const contexts: Record<string, AppState> = {
    ready: STATES.ready!,
    busy: STATES.busy!,
    armed: STATES.armed!,
    permission: STATES.asked!,
    form: STATES.form!,
    search: STATES.search!,
    picker: STATES.picker!,
    'sessions picker': STATES['sessions picker']!,
    help: STATES.help!,
    agents: { ...STATES.busy!, agentsFocus: true },
  };

  for (const [name, state] of Object.entries(contexts)) {
    for (const draft of ['', 'draft']) {
      expect(
        keyCommand('c', CTRL_C, selected(state), draft),
        `${name}, draft "${draft}"`,
      ).toStrictEqual('copy_selection');
    }
  }

  // Being copied, it is still shown: a second copy is the hook's to ignore.
  expect(
    keyCommand(
      'c',
      CTRL_C,
      { ...STATES.ready!, selection: { kind: 'copying' } },
      '',
    ),
  ).toStrictEqual('copy_selection');
  // Once it has gone, ctrl+c does what it did before.
  expect(keyCommand('c', CTRL_C, STATES.form!, '')).toStrictEqual('interrupt');
  expect(
    keyCommand(
      'c',
      CTRL_C,
      { ...STATES.ready!, selection: { kind: 'none' } },
      '',
    ),
  ).toStrictEqual('arm_quit');
});

test('a chord begun keeps ctrl+c from copying (CHD-172)', () => {
  expect(
    keyCommand('c', CTRL_C, STATES['selected, leader']!, ''),
  ).not.toStrictEqual('copy_selection');
});

test('selection:copy copies on its own key, and only with a selection shown (CHD-172)', () => {
  const ctrlShiftC: KeyPress = { ctrl: true, shift: true, escape: false };

  expect(
    keyCommand('c', ctrlShiftC, STATES['selected, form']!, ''),
  ).toStrictEqual('copy_selection');
  expect(keyCommand('c', ctrlShiftC, STATES.ready!, 'draft')).not.toStrictEqual(
    'copy_selection',
  );
});

test('a copy key rebound to a chord waits for its second key and copies (CHD-172)', () => {
  const { keymap, problems } = readKeybindings(
    JSON.stringify({
      bindings: [
        { context: 'Selection', bindings: { 'ctrl+x y': 'selection:copy' } },
      ],
    }),
  );

  expect(problems).toStrictEqual([]);

  const state = selected({ ...STATES.ready!, keys: keymap });
  const x: KeyPress = { ctrl: true, escape: false };

  expect(keyCommand('x', x, state, '')).toStrictEqual('key_pending');

  const pending = { ...state, pendingKeys: sequence('ctrl+x') };

  expect(
    keyCommand('y', { ctrl: false, escape: false }, pending, ''),
  ).toStrictEqual('copy_selection');
  // With no selection the chord is not live: ctrl+x waits for the sessions'.
  expect(
    keyCommand(
      'y',
      { ctrl: false, escape: false },
      {
        ...pending,
        selection: { kind: 'none' },
      },
      '',
    ),
  ).not.toStrictEqual('copy_selection');
});

test("the panel says ctrl + c to copy, and a rebound key's first, or ctrl + c (CHD-172)", () => {
  const line = (keymap = DEFAULT_KEYMAP) =>
    shortcuts(keymap).find((shortcut) => shortcut.does === 'to copy')!.key;

  expect(line()).toStrictEqual('ctrl + c');

  const { keymap } = readKeybindings(
    JSON.stringify({
      bindings: [
        {
          context: 'Selection',
          bindings: {
            'ctrl+shift+c': null,
            'ctrl+x y': 'selection:copy',
            'ctrl+shift+y': 'selection:copy',
          },
        },
      ],
    }),
  );

  expect(line(keymap)).toStrictEqual('ctrl + x y or ctrl + c');

  // The panel is still two columns of twenty at 80 and three of fourteen at 120.
  const lines = shortcuts(keymap).map(shortcutLine);

  expect(columnCount(lines, 80)).toStrictEqual(2);
  expect(Math.ceil(lines.length / 2)).toStrictEqual(20);
  expect(columnCount(lines, 120)).toStrictEqual(3);
  expect(Math.ceil(lines.length / 3)).toStrictEqual(14);
});

test('a copy key that types, or begins a chord that does, beats a form and the search line (CHD-172)', () => {
  const { keymap, problems } = readKeybindings(
    JSON.stringify({
      bindings: [
        {
          context: 'Selection',
          bindings: { y: 'selection:copy', 'g u': 'selection:copy' },
        },
      ],
    }),
  );
  const plain: KeyPress = { ctrl: false, escape: false };

  expect(problems).toStrictEqual([]);

  for (const [name, state] of [
    ['form', STATES.form!],
    ['search', STATES.search!],
  ] as const) {
    const shown = selected({ ...state, keys: keymap });

    expect(keyCommand('y', plain, shown, ''), name).toStrictEqual(
      'copy_selection',
    );
    expect(keyCommand('g', plain, shown, ''), name).toStrictEqual(
      'key_pending',
    );
    expect(
      keyCommand('u', plain, { ...shown, pendingKeys: sequence('g') }, ''),
      name,
    ).toStrictEqual('copy_selection');
    // With no selection the field types them, as before.
    expect(
      keyCommand('y', plain, { ...state, keys: keymap }, ''),
      name,
    ).toBeUndefined();
    expect(
      keyCommand('g', plain, { ...state, keys: keymap }, ''),
      name,
    ).not.toStrictEqual('key_pending');
  }
});
