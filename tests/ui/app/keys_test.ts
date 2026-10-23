import { describe, expect, test } from 'bun:test';
import {
  awaitedSteps,
  changeSteps,
  emptyPasteSteps,
  type KeyContext,
  keySteps,
  newerSteps,
  olderSteps,
  type Step,
  submitSteps,
} from '../../../src/ui/app/keys.ts';
import {
  type AppAction,
  keyCommand,
  reduceApp,
} from '../../../src/ui/app/state.ts';
import { fileFinder } from '../../../src/ui/prompt/state.ts';
import { emptySearch } from '../../../src/ui/prompt/search.ts';
import { emptyHistory, recorded } from '../../../src/ui/prompt/history.ts';
import { endOf, START } from '../../../src/ui/prompt/prompt.ts';
import { readKeybindings } from '../../../src/ui/shortcuts/bindings.ts';
import { busy, ctrl, escape, plain, ready } from './states.ts';

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

test('↓ on an empty draft goes into the list of agents only while there is one and history is not walked, and on a draft sets it aside', () => {
  const into: Step[] = [
    {
      type: 'dispatch',
      action: { type: 'agents_focused', focused: true },
    },
  ];
  const walked = { ...recorded(emptyHistory, 'earlier'), index: 0 };

  expect(newerSteps(context(ready, { agents: true }))).toStrictEqual(into);
  expect(newerSteps(context(ready))).toStrictEqual([]);

  // A draft goes aside first, list or none (Q183).
  for (const agents of [true, false]) {
    expect(newerSteps(context(typing('hi'), { agents }))).toStrictEqual([
      dispatched({ type: 'draft_kept' }),
      { type: 'show_draft', text: '', cursor: START },
    ]);
  }

  // A list on screen keeps its ↓.
  expect(newerSteps(context(typing('/'), { agents: true }))).toStrictEqual([]);
  // ↓ walks back to the empty draft first; only the next one goes in.
  expect(
    newerSteps(context(ready, { agents: true, history: walked })).some(
      (step) => step.type === 'history',
    ),
  ).toStrictEqual(true);
});

describe('drafts set aside (U10, Q183)', () => {
  const image = { id: 1, mediaType: 'image/png', data: 'AA==', bytes: 1 };
  const kept = reduceApp(
    reduceApp(
      reduceApp(typing('one [Image #1] two'), {
        type: 'images_added',
        images: [image],
      }),
      { type: 'bash_mode', on: true },
    ),
    { type: 'draft_set', cursor: [0, 3] as const },
  );
  const aside = reduceApp(kept, { type: 'draft_kept' });

  test('↓ keeps the whole draft with the agent and empties the box', () => {
    expect(aside.kept).toStrictEqual([
      {
        text: 'one [Image #1] two',
        cursor: [0, 3] as const,
        images: [image],
        bash: true,
      },
    ]);
    expect(aside.draft).toStrictEqual('');
    expect(aside.images).toStrictEqual([]);
    expect(aside.bash).toStrictEqual(false);
    // A new session keeps them, as it keeps the draft (Q191).
    expect(reduceApp(aside, { type: 'cleared' }).kept).toStrictEqual(
      aside.kept,
    );
  });

  test('↑ from the empty box brings the newest back whole, its cursor where it was, then the prompts sent', () => {
    const history = recorded(emptyHistory, 'sent before');
    const up = olderSteps(context(aside, { history }));

    expect(up).toStrictEqual([
      { type: 'history', history: { ...history, index: 1, draft: '' } },
      dispatched({ type: 'menu_dismissed' }),
      dispatched({ type: 'bash_mode', on: true }),
      dispatched({ type: 'images_added', images: [image] }),
      {
        type: 'show_draft',
        text: 'one [Image #1] two',
        cursor: [0, 3] as const,
      },
    ]);

    const shown = { ...history, index: 1, draft: '' };

    expect(olderSteps(context(aside, { history: shown })).at(-1)).toStrictEqual(
      {
        type: 'show_draft',
        text: 'sent before',
        cursor: endOf('sent before'),
      },
    );
    // From a kept draft ↓ walks on to the box; it sets nothing aside.
    expect(
      newerSteps(context(aside, { history: shown })).some(
        (step) => step.type === 'dispatch' && step.action.type === 'draft_kept',
      ),
    ).toStrictEqual(false);
  });

  test('a kept draft sent, or emptied by ctrl+c, leaves the stack and the walk', () => {
    const history = { ...emptyHistory, index: 0 };
    const showing = reduceApp(aside, {
      type: 'draft_set',
      text: 'one two',
      cursor: endOf('one two'),
    });
    const taken: Step[] = [
      dispatched({ type: 'kept_taken', index: 0 }),
      { type: 'history', history: { ...history, index: undefined, draft: '' } },
    ];

    expect(
      submitSteps('one two', context(showing, { history })).slice(0, 2),
    ).toStrictEqual(taken);
    expect(
      keySteps('c', ctrl, context(showing, { history })).slice(0, 2),
    ).toStrictEqual(taken);
    expect(
      reduceApp(aside, { type: 'kept_taken', index: 0 }).kept,
    ).toStrictEqual([]);
    // A prompt sent from the box leaves the stack be.
    expect(
      submitSteps('fresh', context(typing('fresh', aside))).some(
        (step) => step.type === 'dispatch' && step.action.type === 'kept_taken',
      ),
    ).toStrictEqual(false);
  });

  test('a kept draft shown and edited stays edited in its place as the walk moves on (Q195)', () => {
    // A prompt sent before it, so ↑ has somewhere to go.
    const history = { ...recorded(emptyHistory, 'sent'), index: 1 };
    const edited = reduceApp(aside, {
      type: 'draft_set',
      text: 'one [Image #1] three',
      cursor: [0, 5],
    });

    // Walked off it either way, it is written back first.
    for (const steps of [
      olderSteps(context(edited, { history })),
      newerSteps(context(edited, { history })),
    ]) {
      expect(steps[0]).toStrictEqual(
        dispatched({ type: 'kept_edited', index: 0 }),
      );
    }

    expect(
      reduceApp(reduceApp(edited, { type: 'images_added', images: [image] }), {
        type: 'kept_edited',
        index: 0,
      }).kept,
    ).toStrictEqual([
      {
        text: 'one [Image #1] three',
        cursor: [0, 5],
        images: [image],
        bash: false,
      },
    ]);
  });
});

test("a box's highlight and the plan box are kept with the session by the request they answer (Q194)", () => {
  const chosen = reduceApp(ready, {
    type: 'choice_moved',
    id: 'p1',
    highlighted: 2,
  });
  const planned = reduceApp(chosen, {
    type: 'plan_box_changed',
    id: 'plan',
    box: { row: 2, note: 'smaller' },
  });

  expect(planned.choosing).toStrictEqual({ id: 'p1', highlighted: 2 });
  expect(planned.planning).toStrictEqual({
    id: 'plan',
    box: { row: 2, note: 'smaller' },
  });
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

describe('tester: selection dispatch precedence', () => {
  test('a copy chord consumes its typed suffix and preserves the draft', () => {
    const { keymap, problems } = readKeybindings(
      JSON.stringify({
        bindings: [
          { context: 'Selection', bindings: { 'ctrl+x y': 'selection:copy' } },
        ],
      }),
    );
    const shown = {
      ...typing('keep this draft'),
      keys: keymap,
      selection: { kind: 'shown' },
    } as const;
    const prefix = keySteps('x', ctrl, context(shown));
    let pending = shown;

    for (const step of prefix) {
      if (step.type === 'dispatch') {
        pending = reduceApp(pending, step.action) as typeof shown;
      }
    }

    const suffix = keySteps(
      'y',
      { ctrl: false, escape: false },
      context(pending),
    );

    expect(problems).toStrictEqual([]);
    expect(prefix.some((step) => step.type === 'clear_selection')).toBe(false);
    expect(suffix).toContainEqual({ type: 'copy_selection' });
    expect(suffix).toContainEqual({
      type: 'show_draft',
      text: 'keep this draft',
      cursor: endOf('keep this draft'),
    });
    expect(suffix.some((step) => step.type === 'clear_selection')).toBe(false);
  });

  test('a chord miss clears the selection before discarding the prefix', () => {
    const shown = { ...ready, selection: { kind: 'shown' } } as const;
    const prefix = keySteps('x', ctrl, context(shown));
    let pending = shown;

    for (const step of prefix) {
      if (step.type === 'dispatch') {
        pending = reduceApp(pending, step.action) as typeof shown;
      }
    }

    const miss = keySteps(
      'z',
      { ctrl: false, escape: false },
      context(pending),
    );

    expect(miss[0]).toStrictEqual({ type: 'clear_selection' });
    expect(miss).toContainEqual(dispatched({ type: 'keys_pending' }));
    expect(miss.some((step) => step.type === 'copy_selection')).toBe(false);
  });

  test('scrolling preserves a selection while a copy is pending', () => {
    const copying = { ...ready, selection: { kind: 'copying' } } as const;

    for (const key of [
      { pageUp: true },
      { pageDown: true },
      { home: true },
      { end: true },
      { upArrow: true, shift: true },
      { downArrow: true, shift: true },
    ]) {
      const steps = keySteps(
        '',
        { ctrl: false, escape: false, ...key },
        context(copying),
      );

      expect(steps.some((step) => step.type === 'clear_selection')).toBe(false);
    }
  });
});

describe("Enter or Tab while the mention's match runs", () => {
  const files = reduceApp(ready, {
    type: 'files_listed',
    files: ['docs/mentions.txt', 'src/ui/prompt/mentions.ts'],
  });
  const typed = typing('@mentions.ts', files);
  const mention = { query: 'mentions.ts', line: 0, column: 0 };
  const matched = (state: typeof typed, found: string[]) =>
    reduceApp(state, {
      type: 'files_matched',
      files: state.files!,
      query: 'mentions.ts',
      matched: found,
    });

  test('an unmoved highlight waits for the match and picks its first file', () => {
    expect(submitSteps('@mentions.ts', context(typed))).toStrictEqual([
      dispatched({ type: 'pick_awaited', mention, enter: true }),
    ]);

    const waiting = reduceApp(typed, {
      type: 'pick_awaited',
      mention,
      enter: true,
    });

    // Nothing while the match runs.
    expect(awaitedSteps(context(waiting))).toStrictEqual([]);
    expect(
      awaitedSteps(context(matched(waiting, ['src/ui/prompt/mentions.ts']))),
    ).toStrictEqual([
      dispatched({ type: 'pick_settled' }),
      {
        type: 'show_draft',
        text: '@src/ui/prompt/mentions.ts ',
        cursor: [0, 27],
      },
    ]);
  });

  test('after an empty match, with no list on screen yet, Enter and Tab wait all the same', () => {
    const empty = reduceApp(files, {
      type: 'files_matched',
      files: files.files!,
      query: 'mentions.t',
      matched: [],
    });
    const next = typing('@mentions.ts', empty);

    expect(fileFinder(next, next.draft, next.cursor)).toStrictEqual(undefined);
    expect(submitSteps('@mentions.ts', context(next))).toStrictEqual([
      dispatched({ type: 'pick_awaited', mention, enter: true }),
    ]);
    expect(
      keyCommand(
        '',
        { ctrl: false, escape: false, tab: true },
        next,
        next.draft,
      ),
    ).toStrictEqual('complete_mention');
  });

  test('a moved highlight picks its row at once', () => {
    const moved = reduceApp(typed, {
      type: 'finder_moved',
      step: 1,
      count: 2,
      rows: 6,
    });

    expect(submitSteps('@mentions.ts', context(moved))).toStrictEqual([
      {
        type: 'show_draft',
        text: '@src/ui/prompt/mentions.ts ',
        cursor: [0, 27],
      },
    ]);
  });

  test('a mention changed while waiting drops the pick; an empty match sends on Enter, nothing on Tab', () => {
    const waiting = reduceApp(typed, {
      type: 'pick_awaited',
      mention,
      enter: true,
    });

    expect(
      awaitedSteps(context(typing('@mentions.tsx', waiting))),
    ).toStrictEqual([dispatched({ type: 'pick_settled' })]);

    const sent = awaitedSteps(context(matched(waiting, [])));

    expect(sent[0]).toStrictEqual(dispatched({ type: 'pick_settled' }));
    expect(sent).toContainEqual({ type: 'send', text: '@mentions.ts' });

    const tabbed = reduceApp(typed, {
      type: 'pick_awaited',
      mention,
      enter: false,
    });

    expect(awaitedSteps(context(matched(tabbed, [])))).toStrictEqual([
      dispatched({ type: 'pick_settled' }),
    ]);
  });
});

describe('a request between turns (CHD-158)', () => {
  const asked = reduceApp(ready, {
    type: 'permission_requested',
    turnId: 't0',
    permission: {
      id: 'p1',
      options: [
        { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
        { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
      ],
    },
    at: 1000,
    between: true,
  });
  /** ctrl+x, then `a`, each from the state the one before left. */
  const leaderA = (state: typeof asked) => {
    let next = state;

    for (const step of keySteps('x', ctrl, context(next))) {
      if (step.type === 'dispatch') {
        next = reduceApp(next, step.action);
      }
    }

    return keySteps('a', plain, context(next));
  };

  test('waits without the keys: esc rejects nothing, and a digit is the draft’s', () => {
    expect(keyCommand('', escape, asked, '')).not.toStrictEqual(
      'reject_permission',
    );
    expect(keyCommand('1', plain, asked, '')).toStrictEqual(undefined);
  });

  test('ctrl+x a takes the keys into it, and esc then rejects it', () => {
    expect(leaderA(asked)).toContainEqual(
      dispatched({ type: 'request_attended', id: 'p1' }),
    );

    const attended = reduceApp(asked, { type: 'request_attended', id: 'p1' });

    expect(keyCommand('', escape, attended, '')).toStrictEqual(
      'reject_permission',
    );
    // With the keys in it, ctrl+x a goes to another session as before.
    expect(leaderA(attended)).toContainEqual({ type: 'attend_session' });
  });

  test('ctrl+x a takes the keys from the list of agents or a search', () => {
    for (const from of [
      { type: 'agents_focused', focused: true },
      { type: 'searched', search: emptySearch },
    ] as AppAction[]) {
      const elsewhere = reduceApp(typing('draft', asked), from);
      const attended = reduceApp(elsewhere, {
        type: 'request_attended',
        id: 'p1',
      });

      expect(attended.agentsFocus).toStrictEqual(undefined);
      expect(attended.search).toStrictEqual(undefined);
      expect(attended.draft).toStrictEqual('draft');
      // Esc is the box's now: it rejects.
      expect(keyCommand('', escape, attended, 'draft')).toStrictEqual(
        'reject_permission',
      );
    }
  });

  test('one asked in a turn takes the keys at once, as before', () => {
    const inTurn = reduceApp(busy, {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    });

    expect(keyCommand('', escape, inTurn, '')).toStrictEqual(
      'reject_permission',
    );
    expect(leaderA(inTurn)).toContainEqual({ type: 'attend_session' });
  });
});

describe('CHD-493 U10 tester: independent draft payloads', () => {
  test('editing and taking a middle draft preserves its neighbours through clear', () => {
    const image = { id: 9, mediaType: 'image/png', data: 'AA==', bytes: 1 };
    let state = ready;

    for (const text of ['old', 'middle [Image #9]', 'new']) {
      state = reduceApp(typing(text, state), { type: 'draft_kept' });
    }

    state = reduceApp(typing('edited [Image #9]', state), {
      type: 'images_added',
      images: [image],
    });
    state = reduceApp(state, { type: 'bash_mode', on: true });
    state = reduceApp(state, { type: 'draft_set', cursor: [0, 2] });
    state = reduceApp(state, { type: 'kept_edited', index: 1 });
    state = reduceApp(state, { type: 'cleared' });

    expect(state.kept?.map((draft) => draft.text)).toStrictEqual([
      'old',
      'edited [Image #9]',
      'new',
    ]);
    expect(state.kept?.[1]).toStrictEqual({
      text: 'edited [Image #9]',
      images: [image],
      cursor: [0, 2],
      bash: true,
    });

    state = reduceApp(state, { type: 'kept_taken', index: 1 });

    expect(state.kept?.map((draft) => draft.text)).toStrictEqual([
      'old',
      'new',
    ]);
    expect(
      state.kept?.every((draft) => draft.images.length === 0 && !draft.bash),
    ).toBe(true);
  });
});
