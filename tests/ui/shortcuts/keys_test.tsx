/**
 * Every key chord answers is in the shortcuts panel: the panel's own, the
 * permission prompt's and a form's, and the keys on other layouts, as
 * escape codes and as copies.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import ru from 'convert-layout/ru.js';
import * as harness from '../harness.tsx';
import type {
  ElicitationPropertySchema,
  ElicitationSchema,
} from '@agentclientprotocol/sdk';
import { ElicitationForm } from '../../../src/ui/dialogs/Form.tsx';
import { PermissionPrompt } from '../../../src/ui/dialogs/Permission.tsx';
import {
  type Action,
  DEFAULT_KEYMAP,
  keystrokeOf,
  readKeybindings,
} from '../../../src/ui/shortcuts/bindings.ts';
import {
  columnCount,
  inColumns,
  shortcutLine,
  shortcuts,
  SHORTCUTS,
} from '../../../src/ui/shortcuts/keys.ts';
import { textareaDoes } from '../../../src/ui/prompt/prompt.ts';
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
import { CrashBoundary } from '../../../src/ui/app/Crash.tsx';
import { until } from '../app/render.tsx';
import type { KeyCommand, KeyPress } from '../../../src/ui/shortcuts/state.ts';
import {
  NORMAL_KEYS,
  startingVim,
  type Vim,
  vimKey,
  vimKeyNames,
} from '../../../src/ui/prompt/vim.ts';
import {
  after,
  prompt,
  sequence,
  LETTERS,
  PRINTABLE,
  RAW_PRESSES,
  NINE,
  listKeys,
  FORM_PRESSES,
  heldPrompt,
  UNDO,
  REDO,
  Press,
  pressOf,
  cyrillic,
  moves,
} from './keys_presses.tsx';

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
  // Its request runs past the box, so the scroll keys move it (CHD-246).
  'asked, overflowing': after(
    { type: 'connected', sessionId: 'session-1' },
    prompt,
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
    { type: 'request_overflowed', id: 'p1', overflows: true },
  ),
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
  notice: after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'notice_opened', id: 'dimcode-agents' },
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
  // On to the background's summary line, the list's last stop.
  summary: after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
    { type: 'summary_focused', focused: true },
  ),
  // Enter there opened the background view, which takes every key.
  'background view': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
    { type: 'summary_focused', focused: true },
    { type: 'background_opened' },
  ),
  // Enter on a monitor's row there opened its detail (CHD-481).
  'background detail': after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
    { type: 'summary_focused', focused: true },
    { type: 'background_opened' },
    { type: 'background_detail_opened', focus: { key: 1, id: 'm1' } },
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
 * Presses every key on the form, in each of its states afresh, and checks
 * that each one it answers, by changing what it draws or by answering the
 * agent, is in the panel, and that each the panel promises does something.
 * Typing and editing in a text field, as in the prompt, are not listed.
 */
test('every key a form answers is in the panel', async () => {
  // A lone ESC waits 20 ms for the rest of a sequence that never comes; the
  // harness's own wait is for what a key draws, so this one is the ESC's.
  const escaped = () => new Promise((resolve) => setTimeout(resolve, 40));
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

      for (const press of prelude) {
        await app.write(press);
      }

      answers.length = 0;

      return app;
    };

    let app = await draw();

    try {
      for (const { name, sequence } of FORM_PRESSES) {
        const before = app.frame();

        await app.write(sequence);

        if (sequence === '\x1b') {
          await escaped();
        }

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

  // The register too: a yank leaves the text as it was either way.
  return 'text' in step
    ? { text: step.text, mode: step.vim.mode, register: step.vim.register }
    : step;
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
    register: { text: 'one', linewise: false },
  });
  expect(objectEdit(['c', 'a'], 'ц')).toStrictEqual({
    text: 'two',
    mode: 'insert',
    register: { text: 'one ', linewise: false },
  });
  expect(objectEdit(['y', 'i'], 'ц')).toStrictEqual({
    text: 'one two',
    mode: 'normal',
    register: { text: 'one', linewise: false },
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

test("enter opens the background view from the summary line, and in it a monitor's details or a row's call, as the panel's enter line says (CHD-481)", () => {
  const enter: KeyPress = { ctrl: false, escape: false, return: true };

  expect(keyCommand('\r', enter, STATES.summary!, '')).toStrictEqual(
    'open_background',
  );
  expect(keyCommand('\r', enter, STATES['background view']!, '')).toStrictEqual(
    'go_to_call',
  );
  // On an agent row, enter goes back to the box as before.
  expect(keyCommand('\r', enter, STATES.agents!, '')).toStrictEqual(
    'agents_leave',
  );
  // In a detail too it is the window's go_to_call, which goes to the call.
  expect(
    keyCommand('\r', enter, STATES['background detail']!, ''),
  ).toStrictEqual('go_to_call');
  expect(shortcuts().map(shortcutLine)).toContain(
    'enter for background, details, a call',
  );
});

test("in an agent's or a task's detail, every key the panel names does what it says, its pages and end the log's (CHD-487)", () => {
  const detail = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'agents_focused', focused: true },
    { type: 'summary_focused', focused: true },
    { type: 'background_opened' },
    { type: 'background_detail_opened', focus: { key: 1, id: 'agent-1' } },
  );
  const press = (input: string, key: Partial<KeyPress>) =>
    keyCommand(input, { ctrl: false, escape: false, ...key }, detail, '');
  const answers = {
    enter: press('\r', { return: true }),
    '↑': press('', { upArrow: true }),
    '↓': press('', { downArrow: true }),
    k: press('k', {}),
    j: press('j', {}),
    x: press('x', {}),
    esc: press('', { escape: true }),
    '←': press('', { leftArrow: true }),
    pgup: press('', { pageUp: true }),
    pgdn: press('', { pageDown: true }),
    home: press('', { home: true }),
    end: press('', { end: true }),
  };

  expect(answers).toStrictEqual({
    enter: 'go_to_call',
    '↑': 'background_up',
    '↓': 'background_down',
    k: 'background_up',
    j: 'background_down',
    x: 'stop_background',
    esc: 'background_back',
    '←': 'background_back',
    pgup: 'background_page_up',
    pgdn: 'background_page_down',
    home: 'background_top',
    end: 'background_bottom',
  });

  // Each is one the shortcuts panel lists; none is new. Enter is the
  // panel's enter line, which names no command, as the key test presses no
  // bare enter on the window.
  expect(shortcuts().map(shortcutLine)).toContain(
    'enter for background, details, a call',
  );

  for (const command of Object.values(answers).filter(
    (each) => each !== 'go_to_call',
  )) {
    expect(
      shortcuts().some((shortcut) =>
        (shortcut.commands as readonly string[] | undefined)?.includes(
          command as string,
        ),
      ),
      `${command} is in the panel`,
    ).toBe(true);
  }
});

describe('CHD-386 tester: movement panel entries', () => {
  test('word and line moves follow paste, before history, in both layouts', () => {
    const lines = shortcuts().map(shortcutLine);
    const paste = lines.indexOf('ctrl + v to paste an image');

    expect(lines.slice(paste + 1, paste + 4)).toStrictEqual([
      'alt + ← → to move by word',
      'cmd + ← → to line start or end',
      '↑ ↓ for prompts, agents, background',
    ]);
    expect(lines).toHaveLength(40);
    expect(
      inColumns(lines, columnCount(lines, 80)).map((c) => c.length),
    ).toStrictEqual([20, 20]);
    expect(
      inColumns(lines, columnCount(lines, 120)).map((c) => c.length),
    ).toStrictEqual([14, 14, 12]);
    expect(lines).toContain('/ @ for commands or files');
    expect(lines).toContain('↑ ↓ to pick a command or file');
    expect(lines).toContain('tab to complete a command');
    expect(lines).toContain('tab enter to add a file');
    expect(lines).toContain('esc ← to leave a picker or shortcuts');
    expect(lines.at(-2)).toStrictEqual('? for shortcuts');
    expect(lines.at(-1)).toStrictEqual('any key to quit the crash screen');
  });

  test('the shared navigation line follows rebound keys once and disappears when unbound', () => {
    const { keymap, problems } = readKeybindings(
      JSON.stringify({
        bindings: [
          {
            context: 'Autocomplete',
            bindings: {
              up: null,
              down: null,
              'ctrl+p': 'autocomplete:previous',
              'ctrl+n': 'autocomplete:next',
            },
          },
        ],
      }),
    );

    expect(problems).toStrictEqual([]);

    const shown = shortcuts(keymap);
    const navigation = shown.filter(
      (entry) => entry.does === 'to pick a command or file',
    );

    expect(navigation).toHaveLength(1);
    expect(shortcutLine(navigation[0]!)).toStrictEqual(
      'ctrl + p ctrl + n to pick a command or file',
    );
    expect(navigation[0]!.commands).toStrictEqual([
      'menu_up',
      'menu_down',
      'finder_up',
      'finder_down',
    ]);

    const unbound = readKeybindings(
      JSON.stringify({
        bindings: [
          { context: 'Autocomplete', bindings: { up: null, down: null } },
        ],
      }),
    );

    expect(unbound.problems).toStrictEqual([]);
    expect(
      shortcuts(unbound.keymap).some(
        (entry) => entry.does === 'to pick a command or file',
      ),
    ).toBeFalse();
    expect(shortcuts(unbound.keymap).map(shortcutLine)).toContain(
      '/ @ for commands or files',
    );
  });
});

describe('CHD-424 tester: shared background keys', () => {
  test('navigation, stop and enter stay adjacent in the default panel', () => {
    const lines = shortcuts().map(shortcutLine);
    const at = lines.indexOf('↑ ↓ for prompts, agents, background');

    expect(lines.slice(at, at + 3)).toStrictEqual([
      '↑ ↓ for prompts, agents, background',
      'x to close an agent, stop background',
      'enter for background, details, a call',
    ]);
    expect(
      lines.filter((line) => line === 'esc ← to leave a picker or shortcuts'),
    ).toHaveLength(1);
  });

  test('shift arrows do nothing in the modal view, and rebinding stop moves both contexts', () => {
    const plain: KeyPress = { ctrl: false, escape: false };
    const { keymap, problems } = readKeybindings(
      JSON.stringify({
        bindings: [
          { context: 'Agents', bindings: { x: null, z: 'agents:close' } },
        ],
      }),
    );

    expect(problems).toStrictEqual([]);

    for (const [name, expected] of [
      ['agents', 'close_agent'],
      ['background view', 'stop_background'],
    ] as const) {
      const state = { ...STATES[name]!, keys: keymap };

      expect(keyCommand('z', plain, state, '')).toBe(expected);
      expect(keyCommand('x', plain, state, '')).toBeUndefined();
    }

    for (const key of [{ upArrow: true }, { downArrow: true }]) {
      expect(
        keyCommand(
          '',
          { ...plain, shift: true, ...key },
          STATES['background view']!,
          '',
        ),
      ).toBeUndefined();
    }

    expect(shortcuts(keymap).map(shortcutLine)).toContain(
      'z to close an agent, stop background',
    );
  });
});

test("every key quits the crash screen, as the panel's any key line says (CHD-468)", async () => {
  expect(
    SHORTCUTS.some(
      (shortcut) =>
        shortcut.key === 'any key' &&
        shortcut.does === 'to quit the crash screen',
    ),
  ).toBeTruthy();

  let quits = 0;

  function Throws(): never {
    throw new Error('broken');
  }

  // React writes the caught error to stderr itself, as it does in chord.
  const logged = spyOn(console, 'error').mockImplementation(() => {});

  const crash = await harness.draw(
    <CrashBoundary quit={() => quits++}>
      <Throws />
    </CrashBoundary>,
  );

  logged.mockRestore();

  try {
    for (const { name, sequence } of RAW_PRESSES) {
      const before = quits;

      await crash.write(sequence);
      // A lone Esc is held a moment before OpenTUI calls it one.
      await until(
        `${name} to quit the crash screen`,
        () => quits > before,
        1000,
      );
      expect(quits, `${name} quit the crash screen twice`).toBe(before + 1);
    }
  } finally {
    await crash.unmount();
  }
});
