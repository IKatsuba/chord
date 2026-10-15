import { expect, test } from 'bun:test';
import {
  type AppAction,
  type AppState,
  canSend,
  frontState,
  initialAppState,
  keyCommand,
  modeAfter,
  reduceApp,
  reduceWindowed,
  resumableSession,
  windowed,
  type WindowedAction,
} from '../../../src/ui/app/state.ts';
import { openForm } from '../../../src/ui/dialogs/form.ts';
import { emptySearch } from '../../../src/ui/prompt/search.ts';
import { after, busy, ctrl, escape, plain, ready } from './states.ts';

test('the session starts, connects or fails, and closes', () => {
  expect(initialAppState.connection).toStrictEqual({ status: 'starting' });
  expect(ready.connection).toStrictEqual({ status: 'ready' });
  expect(
    after({ type: 'connect_failed', message: 'no' }).connection,
  ).toStrictEqual({
    status: 'failed',
    message: 'no',
  });
  expect(reduceApp(ready, { type: 'closing' }).connection).toStrictEqual({
    status: 'closing',
  });
  // A session that opens after quitting began stays closing.
  expect(
    after({ type: 'closing' }, { type: 'connected', sessionId: 'session-1' })
      .connection,
  ).toStrictEqual({ status: 'closing' });
});

test('a prompt is sent only when the session is ready', () => {
  expect(canSend(initialAppState, 'hi')).toStrictEqual(false);
  expect(canSend(ready, 'hi')).toStrictEqual(true);
  expect(canSend(ready, '   ')).toStrictEqual(false);
  // It queues behind the turn in flight.
  expect(canSend(busy, 'hi')).toStrictEqual(true);
  expect(
    canSend(after({ type: 'connect_failed', message: 'no' }), 'hi'),
  ).toStrictEqual(false);
});

test('esc interrupts a turn in flight and nothing else', () => {
  expect(keyCommand('', escape, busy, '')).toStrictEqual('interrupt');
  expect(keyCommand('', escape, ready, '')).toStrictEqual(undefined);
  expect(keyCommand('x', plain, busy, '')).toStrictEqual(undefined);
});

test('esc rejects a permission request instead of interrupting', () => {
  const asked = reduceApp(busy, {
    type: 'permission_requested',
    turnId: 't1',
    permission: { id: 'p1', options: [] },
  });

  expect(keyCommand('', escape, asked, '')).toStrictEqual('reject_permission');
  expect(
    keyCommand(
      '',
      escape,
      reduceApp(asked, {
        type: 'permission_settled',
        turnId: 't1',
        id: 'p1',
        answer: { type: 'rejected' },
      }),
      '',
    ),
  ).toStrictEqual('interrupt');
});

test('ctrl+c quits on the second press, while it is armed', () => {
  expect(keyCommand('c', ctrl, ready, '')).toStrictEqual('arm_quit');

  const armed = reduceApp(ready, { type: 'quit_armed' });

  expect(keyCommand('c', ctrl, armed, '')).toStrictEqual('quit');
  expect(
    keyCommand('c', ctrl, reduceApp(armed, { type: 'quit_disarmed' }), ''),
  ).toStrictEqual('arm_quit');
  // During a turn too: ctrl+c is quit, esc is interrupt.
  expect(keyCommand('c', ctrl, busy, '')).toStrictEqual('arm_quit');
});

test('ctrl+c clears a draft instead of arming quit', () => {
  expect(keyCommand('c', ctrl, ready, 'draft')).toStrictEqual('clear_draft');
  expect(
    keyCommand('c', ctrl, reduceApp(ready, { type: 'quit_armed' }), 'draft'),
  ).toStrictEqual('clear_draft');
  expect(keyCommand('c', ctrl, busy, 'draft')).toStrictEqual('clear_draft');
});

test('clearing a draft takes back an armed quit', () => {
  const armed = reduceApp(ready, { type: 'quit_armed' });
  const cleared = reduceApp(armed, { type: 'draft_cleared' });

  expect(cleared.quitArmed).toStrictEqual(false);
  expect(keyCommand('c', ctrl, cleared, '')).toStrictEqual('arm_quit');
});

test('ctrl+d quits on an empty prompt and edits nothing otherwise', () => {
  expect(keyCommand('d', ctrl, ready, '')).toStrictEqual('quit');
  expect(keyCommand('d', ctrl, initialAppState, '')).toStrictEqual('quit');
  expect(keyCommand('d', ctrl, ready, 'draft')).toStrictEqual(undefined);
});

test('no key does anything once the window is closing', () => {
  const closing = reduceApp(reduceApp(busy, { type: 'quit_armed' }), {
    type: 'closing',
  });

  expect(closing.quitArmed).toStrictEqual(false);
  expect(keyCommand('c', ctrl, closing, '')).toStrictEqual(undefined);
  expect(keyCommand('d', ctrl, closing, '')).toStrictEqual(undefined);
  expect(keyCommand('', escape, closing, '')).toStrictEqual(undefined);
});

const MODELS = {
  available: [
    { id: 'fake-large', name: 'Fake Large' },
    { id: 'fake-small', name: 'Fake Small' },
  ],
  current: 'fake-large',
};

test('the models are the last ones the agent named', () => {
  const named = reduceApp(ready, { type: 'model', models: MODELS });

  expect(named.models).toStrictEqual(MODELS);
  expect(
    reduceApp(named, {
      type: 'model',
      models: { ...MODELS, available: [...MODELS.available] },
    }),
  ).toStrictEqual(named);
  expect(
    reduceApp(named, {
      type: 'model',
      models: { ...MODELS, current: 'fake-small' },
    }).models?.current,
  ).toStrictEqual('fake-small');
  expect(
    'models' in reduceApp(named, { type: 'model', models: undefined }),
  ).toStrictEqual(false);
});

test('the header keeps the model the session started on', () => {
  const none = reduceApp(ready, { type: 'model', models: undefined });

  expect(none.startedModel).toStrictEqual(undefined);

  const named = reduceApp(none, { type: 'model', models: MODELS });

  expect(named.startedModel).toStrictEqual('Fake Large');
  expect(
    reduceApp(named, {
      type: 'model',
      models: { ...MODELS, current: 'fake-small' },
    }).startedModel,
  ).toStrictEqual('Fake Large');
});

test('a resumed session is marked so until /clear starts a new one', () => {
  const resumed = after(
    { type: 'resumed', lastUsedAt: 20, prompt: 'fix it' },
    { type: 'model', models: MODELS },
  );

  expect(resumed.resumed).toStrictEqual({ lastUsedAt: 20, prompt: 'fix it' });
  expect(after({ type: 'resumed' }).resumed).toStrictEqual({});

  const cleared = reduceApp(resumed, { type: 'cleared' });

  expect(cleared.resumed).toStrictEqual(undefined);
  expect(cleared.startedModel).toStrictEqual(undefined);
});

test("the agent's modes and the one it reports land in the state", () => {
  const available = [
    { id: 'default', name: 'Default' },
    { id: 'plan', name: 'Plan' },
  ];
  const offered = reduceApp(ready, {
    type: 'modes',
    modes: { available, current: 'plan' },
  });

  expect(offered.modes).toStrictEqual(available);
  expect(offered.transcript.mode).toStrictEqual('plan');
  expect(modeAfter(offered)).toStrictEqual('default');
  // A reading that names no current mode leaves the one on screen.
  expect(
    reduceApp(offered, { type: 'modes', modes: { available } }).transcript.mode,
  ).toStrictEqual('plan');
  expect(
    reduceApp(offered, { type: 'modes', modes: undefined }).modes,
  ).toStrictEqual([]);
});

test('a mode the agent changes in a turn is the one shift+tab starts from', () => {
  const offered = reduceApp(ready, {
    type: 'modes',
    modes: {
      available: [
        { id: 'default', name: 'Default' },
        { id: 'acceptEdits', name: 'Accept edits' },
        { id: 'plan', name: 'Plan' },
      ],
      current: 'default',
    },
  });
  const planned = reduceApp(
    reduceApp(offered, { type: 'prompt', turnId: 't1', text: 'go', at: 0 }),
    {
      type: 'update',
      turnId: 't1',
      update: { sessionUpdate: 'current_mode_update', currentModeId: 'plan' },
    },
  );

  expect(planned.transcript.mode).toStrictEqual('plan');
  expect(modeAfter(planned)).toStrictEqual('default');
});

test('a mode change the agent refused is an error line', () => {
  const failed = reduceApp(ready, {
    type: 'failed',
    turnId: 'mode-1',
    message: 'Could not switch to plan mode: no',
  });

  expect(failed.transcript.entries).toStrictEqual([
    {
      kind: 'error',
      turnId: 'mode-1',
      message: 'Could not switch to plan mode: no',
    },
  ]);
  expect(failed.transcript.turn.status).toStrictEqual('idle');
});

test('a quick second shift+tab walks on from the mode still asked for', () => {
  const offered = reduceApp(ready, {
    type: 'modes',
    modes: {
      available: [
        { id: 'default', name: 'Default' },
        { id: 'acceptEdits', name: 'Accept edits' },
        { id: 'plan', name: 'Plan' },
      ],
      current: 'default',
    },
  });
  const asked = reduceApp(offered, { type: 'mode_asked', id: 'acceptEdits' });

  expect(modeAfter(asked)).toStrictEqual('plan');
  // Asking changes nothing on screen.
  expect(asked.transcript.mode).toStrictEqual('default');

  const twice = reduceApp(asked, { type: 'mode_asked', id: 'plan' });

  // An answer to the first leaves the second still asked for.
  expect(
    reduceApp(twice, { type: 'mode_answered', id: 'acceptEdits' }).modeAsked,
  ).toStrictEqual('plan');
  expect(
    'modeAsked' in reduceApp(twice, { type: 'mode_answered', id: 'plan' }),
  ).toStrictEqual(false);
});

test('a cleared session starts over, keeping only the window', () => {
  const used = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'model', models: MODELS },
    { type: 'commands', commands: [{ name: 'greet', description: '' }] },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'expanded_toggled' },
  );
  const cleared = reduceApp(used, { type: 'cleared' });

  expect(cleared).toStrictEqual({ ...initialAppState, expanded: true });
});

test('the window keeps when the session came up and what it spent', () => {
  const state = after(
    { type: 'connected', sessionId: 'session-1', at: 5000 },
    { type: 'usage', turnId: 'a', usage: { inputTokens: 10 } },
    { type: 'usage', turnId: 'b', usage: { inputTokens: 5, outputTokens: 1 } },
  );

  expect([state.since, state.spent]).toStrictEqual([
    5000,
    {
      turns: {
        a: { inputTokens: 10 },
        b: { inputTokens: 5, outputTokens: 1 },
      },
    },
  ]);
  // A new session spent nothing yet.
  expect(reduceApp(state, { type: 'cleared' }).spent).toStrictEqual(undefined);
});

test('a change noted goes into the transcript as a line of its own', () => {
  const noted = reduceApp(ready, {
    type: 'noted',
    turnId: 'n1',
    command: 'config',
    text: 'Effort set to High',
    failed: false,
  });

  expect(noted.transcript.entries).toStrictEqual([
    {
      kind: 'note',
      turnId: 'n1',
      command: 'config',
      text: 'Effort set to High',
      failed: false,
    },
  ]);
});

test('two sessions keep their own draft, scroll and permission', () => {
  const inOne = (action: AppAction): WindowedAction => ({
    type: 'in_session',
    key: 1,
    action,
  });
  const actions: WindowedAction[] = [
    { type: 'expanded_toggled' },
    { type: 'draft_set', text: 'half typed', cursor: [0, 4] },
    inOne({ type: 'connected', sessionId: 'session-1' }),
    inOne({ type: 'prompt', turnId: 't1', text: 'hi', at: 0 }),
    inOne({ type: 'scroll_measured', content: 90, view: 33 }),
    { type: 'scrolled', step: 'page_up' },
    { type: 'session_opened', key: 2 },
    // Tab 1 asks while tab 2 is in front.
    inOne({
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    }),
    {
      type: 'in_session',
      key: 2,
      action: { type: 'connected', sessionId: 'session-2' },
    },
    { type: 'draft_set', text: 'other' },
  ];
  const both = actions.reduce(reduceWindowed, windowed(initialAppState, 1));
  const two = frontState(both);

  expect(two.sessionId).toStrictEqual('session-2');
  expect(two.draft).toStrictEqual('other');
  expect(two.scroll.following).toStrictEqual(true);
  expect(two.transcript.turn.status).toStrictEqual('idle');
  expect(keyCommand('', escape, two, '')).toStrictEqual(undefined);
  // ctrl+o's view is the window's, whichever session is in front.
  expect(two.expanded).toStrictEqual(true);

  const one = frontState(
    reduceWindowed(both, { type: 'session_shown', key: 1 }),
  );

  expect(one.sessionId).toStrictEqual('session-1');
  expect(one.draft).toStrictEqual('half typed');
  expect(one.cursor).toStrictEqual([0, 4]);
  expect(one.scroll.following).toStrictEqual(false);
  expect(one.transcript.turn.status).toStrictEqual('awaiting_permission');
  expect(keyCommand('', escape, one, '')).toStrictEqual('reject_permission');
  expect(one.expanded).toStrictEqual(true);
});

test("a form filled in so far is the session's, and comes back with it", () => {
  const form = openForm({
    type: 'object',
    properties: { name: { type: 'string' } },
  });
  const filled = { ...form, values: { name: 'keep' } };
  const left = (
    [
      { type: 'form_filled', id: 'e1', form: filled },
      { type: 'session_opened', key: 2 },
    ] satisfies WindowedAction[]
  ).reduce(reduceWindowed, windowed(ready, 1));

  expect(frontState(left).filling).toStrictEqual(undefined);
  expect(
    frontState(reduceWindowed(left, { type: 'session_shown', key: 1 })).filling,
  ).toStrictEqual({ id: 'e1', form: filled });
});

test('a session behind leaves the window as the person has it', () => {
  const inOne = (action: AppAction): WindowedAction => ({
    type: 'in_session',
    key: 1,
    action,
  });
  const asking = inOne({
    type: 'permission_requested',
    turnId: 't1',
    permission: { id: 'p1', options: [] },
  });
  const searching = (
    [
      inOne({ type: 'prompt', turnId: 't1', text: 'hi', at: 0 }),
      { type: 'session_opened', key: 2 },
      { type: 'searched', search: emptySearch },
    ] satisfies WindowedAction[]
  ).reduce(reduceWindowed, windowed(ready, 1));
  const asked = reduceWindowed(searching, asking);

  // A permission in front closes the search; one behind leaves it open.
  expect(frontState(asked).search).toStrictEqual(emptySearch);
  expect(
    frontState(reduceWindowed(asked, { type: 'session_shown', key: 1 }))
      .transcript.turn.status,
  ).toStrictEqual('awaiting_permission');
  expect(
    frontState(
      [{ type: 'session_shown', key: 1 } as const, asking].reduce(
        reduceWindowed,
        searching,
      ),
    ).search,
  ).toStrictEqual(undefined);
  // A session that is not open changes nothing.
  expect(
    reduceWindowed(asked, {
      type: 'in_session',
      key: 3,
      action: { type: 'cleared' },
    }),
  ).toStrictEqual(asked);
});

test('a session is left to resume once a prompt or a message went to it', () => {
  const session = (entries: AppState['transcript']['entries']) => ({
    sessionId: 's1',
    transcript: { ...initialAppState.transcript, entries },
  });

  expect(resumableSession(session([]))).toStrictEqual(undefined);
  expect(
    resumableSession(session([{ kind: 'user', turnId: 't1', text: 'hi' }])),
  ).toStrictEqual('s1');
  // A child reopened through /resume began with its parent's message.
  expect(
    resumableSession(
      session([
        {
          kind: 'message',
          turnId: 't1',
          from: { name: 'main', reachable: true },
          text: 'agentchild',
        },
      ]),
    ),
  ).toStrictEqual('s1');
});

test("a selection's life: a press holds the view, release shows it, a copy notes it (CHD-172)", () => {
  const pressed = reduceApp(ready, { type: 'selection_started' });

  expect(pressed.selection).toStrictEqual({
    kind: 'dragging',
    wasFollowing: true,
    moved: false,
  });
  // A scroll that moves nothing, as on a transcript that fits, is no move.
  expect(
    reduceApp(pressed, { type: 'scrolled', step: 'line_up' }).selection,
  ).toStrictEqual(pressed.selection);

  const shown = reduceApp(pressed, { type: 'selection_released', text: 'hi' });

  expect(shown.selection).toStrictEqual({ kind: 'shown' });
  expect(shown.scroll.following).toBe(true);
  expect(shown.scroll.held).toBeUndefined();

  const copying = reduceApp(shown, { type: 'copy_started' });
  const noted = reduceApp(copying, {
    type: 'copy_noted',
    result: { kind: 'copied', chars: 2 },
    auto: true,
  });

  expect(noted.selection).toStrictEqual({ kind: 'shown' });
  expect(noted.copied?.auto).toBe(true);

  // Release's selection goes with its note.
  const gone = reduceApp(noted, { type: 'copied_gone', id: noted.copied!.id });

  expect(gone.selection).toBeUndefined();
  expect(gone.copied).toBeUndefined();

  // The copy key's goes as soon as it has copied; a failure's stays.
  const keyed = reduceApp(reduceApp(shown, { type: 'copy_started' }), {
    type: 'copy_noted',
    result: { kind: 'copied', chars: 2 },
    auto: false,
  });

  expect(keyed.selection).toBeUndefined();

  const failed = reduceApp(reduceApp(shown, { type: 'copy_started' }), {
    type: 'copy_noted',
    result: { kind: 'failed', reason: 'no' },
    auto: true,
  });

  expect(failed.selection).toStrictEqual({ kind: 'shown' });
  // Cleared, the failure's note goes with it.
  expect(reduceApp(failed, { type: 'selection_gone' }).copied).toBeUndefined();
});

test('a tab switched, ctrl+o and the editor clear a selection (CHD-172)', () => {
  const shown = { ...ready, selection: { kind: 'shown' } } as const;

  expect(
    reduceApp(shown, { type: 'expanded_toggled' }).selection,
  ).toBeUndefined();
  expect(reduceApp(shown, { type: 'editor_opened' }).selection).toBeUndefined();

  const two = reduceWindowed(
    reduceWindowed(windowed(shown, 1), { type: 'session_opened', key: 2 }),
    { type: 'selection_started' },
  );

  expect(two.window.selection?.kind).toBe('dragging');
  expect(
    reduceWindowed(two, { type: 'session_shown', key: 1 }).window.selection,
  ).toBeUndefined();
});
