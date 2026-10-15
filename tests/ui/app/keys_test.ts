import { expect, test } from 'bun:test';
import {
  changeSteps,
  emptyPasteSteps,
  type KeyContext,
  keySteps,
  newerSteps,
  olderSteps,
  type Step,
  submitSteps,
} from '../../../src/ui/app/keys.ts';
import { type AppAction, reduceApp } from '../../../src/ui/app/state.ts';
import { emptyHistory, recorded } from '../../../src/ui/prompt/history.ts';
import { endOf, START } from '../../../src/ui/prompt/prompt.ts';
import { busy, ctrl, escape, ready } from './states.ts';

function context(state = ready, more: Partial<KeyContext> = {}): KeyContext {
  return {
    state,
    history: emptyHistory,
    rows: 40,
    typed: { vim: state.vim, draft: state.draft, cursor: state.cursor },
    submitting: false,
    home: undefined,
    ...more,
  };
}

const typing = (text: string, state = ready) =>
  reduceApp(state, { type: 'draft_set', text, cursor: endOf(text) });

const dispatched = (action: AppAction): Step => ({ type: 'dispatch', action });

test('esc while a turn runs interrupts it', () => {
  expect(keySteps('', escape, context(busy))).toStrictEqual([
    { type: 'interrupt' },
  ]);
});

test('esc on the splash leaves it, and nothing else hears it', () => {
  expect(keySteps('', escape, context(busy, { splash: true }))).toStrictEqual([
    { type: 'leave_splash' },
  ]);
});

test('any other key on the splash goes to the window behind it', () => {
  expect(keySteps('c', ctrl, context(ready, { splash: true }))).toStrictEqual(
    keySteps('c', ctrl, context(ready)),
  );
});

test('esc puts the queued prompts back ahead of the draft first', () => {
  const queued = reduceApp(typing('typed', busy), {
    type: 'queued',
    turnId: 't2',
    text: 'second',
  });
  const [shown, interrupt] = keySteps('', escape, context(queued));

  expect(shown?.type).toStrictEqual('show_draft');
  expect(interrupt).toStrictEqual({ type: 'interrupt' });
});

test('esc with nothing running asks nothing of the window', () => {
  expect(keySteps('', escape, context())).toStrictEqual([]);
});

test('an empty paste reads the clipboard quietly, and a paste with text does not', () => {
  expect(emptyPasteSteps('', context())).toStrictEqual([
    {
      type: 'paste_image',
      quiet: true,
    },
  ]);
  expect(emptyPasteSteps('text', context())).toStrictEqual([]);
});

test('an empty paste halfway through a chord is dropped', () => {
  const pending = reduceApp(ready, {
    type: 'keys_pending',
    keys: [{ key: 'x', ctrl: true, alt: false, shift: false, cmd: false }],
  });

  expect(emptyPasteSteps('', context(pending))).toStrictEqual([]);
});

test('ctrl+c on a draft clears it', () => {
  expect(keySteps('c', ctrl, context(typing('draft')))).toStrictEqual([
    dispatched({ type: 'draft_cleared' }),
    { type: 'show_draft', text: '', cursor: START },
  ]);
});

test('enter sends a prompt, and nothing while paths are read', () => {
  const state = typing('hi');

  expect(submitSteps('hi', context(state))).toStrictEqual([
    { type: 'send', text: 'hi' },
  ]);
  expect(submitSteps('hi', context(state, { submitting: true }))).toStrictEqual(
    [],
  );
});

test('enter on a chord command runs it and empties the box', () => {
  expect(submitSteps('/clear', context(typing('/clear')))).toStrictEqual([
    { type: 'history', history: recorded(emptyHistory, '/clear') },
    { type: 'show_draft', text: '', cursor: START },
    { type: 'run_command', command: 'clear', args: '' },
  ]);
});

test('enter on a chord command keeps what was typed after its name', () => {
  expect(
    submitSteps('/new codex', context(typing('/new codex'))),
  ).toStrictEqual([
    { type: 'history', history: recorded(emptyHistory, '/new codex') },
    { type: 'show_draft', text: '', cursor: START },
    { type: 'run_command', command: 'new', args: 'codex' },
  ]);
});

test('enter in bash mode runs the command and leaves the mode', () => {
  const state = reduceApp(typing('ls'), { type: 'bash_mode', on: true });

  expect(submitSteps('ls', context(state))).toStrictEqual([
    { type: 'history', history: recorded(emptyHistory, '!ls') },
    dispatched({ type: 'bash_mode', on: false }),
    { type: 'show_draft', text: '', cursor: START },
    { type: 'run_shell', command: 'ls' },
  ]);
});

test('a `!` typed into an empty box enters bash mode', () => {
  expect(changeSteps('!', context())).toStrictEqual([
    dispatched({ type: 'bash_mode', on: true }),
    { type: 'show_draft', text: '', cursor: START },
  ]);
});

test("a `/` typed reads the agent's commands again", () => {
  expect(changeSteps('/', context())).toStrictEqual([
    dispatched({ type: 'draft_set', text: '/' }),
    dispatched({ type: 'draft_edited' }),
    dispatched({ type: 'help_closed' }),
    { type: 'read_commands' },
  ]);
});

test('↑ recalls the last prompt sent', () => {
  const history = recorded(emptyHistory, 'earlier');
  const steps = olderSteps(context(ready, { history }));

  expect(steps.slice(1)).toStrictEqual([
    dispatched({ type: 'menu_dismissed' }),
    dispatched({ type: 'bash_mode', on: false }),
    dispatched({ type: 'images_added', images: [] }),
    { type: 'show_draft', text: 'earlier', cursor: endOf('earlier') },
  ]);
});

test('↓ on an empty draft goes into the list of agents only while there is one and history is not walked', () => {
  const into: Step[] = [
    {
      type: 'dispatch',
      action: { type: 'agents_focused', focused: true },
    },
  ];
  const walked = { ...recorded(emptyHistory, 'earlier'), index: 0 };

  expect(newerSteps(context(ready, { agents: true }))).toStrictEqual(into);
  expect(newerSteps(context(ready))).toStrictEqual([]);
  expect(
    newerSteps(
      context(reduceApp(ready, { type: 'draft_set', text: 'hi' }), {
        agents: true,
      }),
    ),
  ).toStrictEqual([]);
  // ↓ walks back to the empty draft first; only the next one goes in.
  expect(
    newerSteps(context(ready, { agents: true, history: walked })).some(
      (step) => step.type === 'history',
    ),
  ).toStrictEqual(true);
});

test('in the list ↑ ↓ and j k move the pick, enter and esc go back, x closes, and other letters do nothing', () => {
  const listed = reduceApp(ready, { type: 'agents_focused', focused: true });
  // A letter would also type, and is taken back: only the rest is the list's.
  const steps = (input: string, key = {}) =>
    keySteps(
      input,
      { ctrl: false, escape: false, ...key },
      context(listed),
    ).filter((step) => step.type !== 'chord_key' && step.type !== 'show_draft');

  expect(steps('', { upArrow: true })).toStrictEqual([
    { type: 'move_agent', by: -1 },
  ]);
  expect(steps('j')).toStrictEqual([{ type: 'move_agent', by: 1 }]);
  expect(steps('', { escape: true })).toStrictEqual([
    {
      type: 'dispatch',
      action: { type: 'agents_focused', focused: false },
    },
  ]);
  expect(steps('x')).toStrictEqual([{ type: 'close_agent' }]);
  expect(steps('q')).toStrictEqual([]);
  expect(steps('?')).toStrictEqual([]);
});

test('an armed close of a child is taken back by any other key', () => {
  const armed = reduceApp(
    reduceApp(ready, { type: 'agents_focused', focused: true }),
    { type: 'agent_close_armed', key: 2 },
  );

  expect(
    keySteps('j', { ctrl: false, escape: false }, context(armed)).filter(
      (step) => step.type === 'dispatch',
    ),
  ).toStrictEqual([
    { type: 'dispatch', action: { type: 'agent_close_disarmed' } },
  ]);
});

test('a selection shown is cleared first by a key, kept by a scroll key and copied by ctrl+c (CHD-172)', () => {
  const shown = { ...busy, selection: { kind: 'shown' } } as const;
  const plain = { ctrl: false, escape: false };

  expect(keySteps('c', ctrl, context(shown))).toStrictEqual([
    { type: 'copy_selection' },
  ]);
  // Esc clears it, and interrupts on the same press.
  expect(keySteps('', escape, context(shown))).toStrictEqual([
    { type: 'clear_selection' },
    ...keySteps('', escape, context(busy)),
  ]);
  // A letter the textarea types: cleared before the textarea hears it.
  expect(keySteps('a', plain, context(shown))).toStrictEqual([
    { type: 'clear_selection' },
  ]);
  expect(
    keySteps('', { ...plain, pageUp: true }, context(shown)),
  ).toStrictEqual(keySteps('', { ...plain, pageUp: true }, context(busy)));
  // A chord's first key keeps it, for a copy key rebound to a chord.
  expect(keySteps('x', ctrl, context(shown))[0]).not.toStrictEqual({
    type: 'clear_selection',
  });
});
