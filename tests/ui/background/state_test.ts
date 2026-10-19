import { describe, expect, test } from 'bun:test';
import {
  backgroundShown,
  initialBackground,
  reduceBackground,
} from '../../../src/ui/background/state.ts';
import {
  type AppState,
  frontState,
  initialAppState,
  keyCommand,
  reduceApp,
  reduceWindowed,
  windowed,
  type WindowedAction,
} from '../../../src/ui/app/state.ts';
import { askedIds } from '../../../src/ui/dialogs/state.ts';
import { busy, escape, plain } from '../app/states.ts';

test("the person's prompt in a tab marks when its ended items were cleared, each tab its own", () => {
  const once = reduceBackground(initialBackground, {
    type: 'background_cleared',
    tab: 1,
    at: 100,
  });
  const twice = reduceBackground(once, {
    type: 'background_cleared',
    tab: 2,
    at: 200,
  });

  expect(twice.backgroundCleared).toStrictEqual({ 1: 100, 2: 200 });
  expect(
    reduceBackground(twice, { type: 'background_cleared', tab: 1, at: 300 })
      .backgroundCleared,
  ).toStrictEqual({ 1: 300, 2: 200 });
});

test("another tab's /clear leaves each tab's clearing as it was, so no ended item comes back", () => {
  const both = (
    [
      { type: 'session_opened', key: 2 },
      { type: 'background_cleared', tab: 1, at: 100 },
      { type: 'background_cleared', tab: 2, at: 200 },
      { type: 'in_session', key: 2, action: { type: 'cleared' } },
    ] satisfies WindowedAction[]
  ).reduce(reduceWindowed, windowed(initialAppState, 1));

  expect(frontState(both).backgroundCleared).toStrictEqual({ 1: 100, 2: 200 });
});

test("a stop's hint is said only for the stop x last asked for, while the ❯ has stayed on its row since", () => {
  const a = { key: 1, id: 'a' };
  const b = { key: 1, id: 'b' };
  const hint = 'could not stop: Session not found';
  const run = (...actions: Parameters<typeof reduceBackground>[1][]) =>
    actions.reduce(reduceBackground, initialBackground).backgroundView;
  const asked = (token: string) =>
    ({ type: 'background_stop_asked', focus: a, token }) as const;
  const refused = (token: string) =>
    ({ type: 'background_hinted', token, hint }) as const;
  const opened = [
    { type: 'background_opened' },
    { type: 'background_focused', focus: a },
    asked('t1'),
  ] as const;

  expect(run(...opened, refused('t1'))?.hint).toBe(hint);
  // Kept while the ❯ stays; gone once it moves.
  expect(
    run(...opened, refused('t1'), { type: 'background_focused', focus: a })
      ?.hint,
  ).toBe(hint);
  expect(
    run(...opened, refused('t1'), { type: 'background_focused', focus: b }),
  ).toStrictEqual({ focus: b });
  // An answer after the ❯ left, even if it came back, or after the view
  // closed and opened again, is not said.
  expect(
    run(
      ...opened,
      { type: 'background_focused', focus: b },
      { type: 'background_focused', focus: a },
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  expect(
    run(
      ...opened,
      { type: 'background_closed' },
      { type: 'background_opened' },
      { type: 'background_focused', focus: a },
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  // Nor is an earlier stop's once a later one on the same row was asked.
  expect(
    run(
      ...opened,
      { type: 'background_focused', focus: b },
      { type: 'background_focused', focus: a },
      asked('t2'),
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  expect(run(refused('t1'))).toBe(undefined);
});

describe('CHD-2 tester: stop attempt token ordering', () => {
  test('an old refusal cannot disarm a newer attempt and the new hint clears on owner change', () => {
    const focus = { key: 1, id: 'same' };
    let state = reduceBackground(initialBackground, {
      type: 'background_opened',
    });

    state = reduceBackground(state, { type: 'background_focused', focus });
    state = reduceBackground(state, {
      type: 'background_stop_asked',
      focus,
      token: 'old',
    });
    state = reduceBackground(state, {
      type: 'background_stop_asked',
      focus,
      token: 'new',
    });

    const late = reduceBackground(state, {
      type: 'background_hinted',
      token: 'old',
      hint: 'old refusal',
    });

    expect(late).toBe(state);
    expect(late.backgroundView?.stopping?.token).toBe('new');

    const refused = reduceBackground(late, {
      type: 'background_hinted',
      token: 'new',
      hint: 'new refusal',
    });

    expect(refused.backgroundView?.hint).toBe('new refusal');
    expect(refused.backgroundView?.stopping).toBeUndefined();
    expect(
      reduceBackground(refused, {
        type: 'background_focused',
        focus: { key: 2, id: 'same' },
      }).backgroundView?.hint,
    ).toBeUndefined();
  });
});

describe('the view over requests the front tab asks (CHD-462)', () => {
  const FORM = {
    id: 'e1',
    mode: 'form',
    message: 'Set up the deploy target',
    schema: { type: 'object', properties: {} },
  } as const;
  const PERMISSION = {
    id: 'p1',
    options: [
      { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ],
  } as const;
  const formAsked = reduceApp(busy, {
    type: 'elicitation_requested',
    turnId: 't1',
    elicitation: FORM,
  });
  const permissionAsked = reduceApp(busy, {
    type: 'permission_requested',
    turnId: 't1',
    permission: PERMISSION,
    at: 0,
  });
  const opened = (state: AppState) =>
    reduceApp(state, {
      type: 'background_opened',
      over: askedIds(state.transcript),
    });
  const enter = { ...plain, return: true };

  test('opened over a form that has the keys, the view stands and takes them all, x and typing too', () => {
    const over = opened(formAsked);

    expect(backgroundShown(over)).toBeTruthy();
    expect(keyCommand('x', plain, over, '')).toBe('stop_background');
    expect(keyCommand('j', plain, over, '')).toBe('background_down');
    expect(keyCommand('k', plain, over, '')).toBe('background_up');
    expect(keyCommand('', enter, over, '')).toBe('go_to_call');
    expect(keyCommand('', escape, over, '')).toBe('close_background');
    // Nothing typed reaches the form beneath.
    expect(keyCommand('a', plain, over, '')).toBe(undefined);
  });

  test('opened over a permission waiting, esc closes the view and rejects nothing', () => {
    const over = opened(permissionAsked);

    expect(backgroundShown(over)).toBeTruthy();
    expect(keyCommand('', escape, over, '')).toBe('close_background');
    expect(keyCommand('', enter, over, '')).toBe('go_to_call');
  });

  test('a request that arrives once it is open hides it and takes the keys; answered, the view is back as it was', () => {
    const open = reduceApp(
      { ...busy, agentsFocus: true },
      { type: 'background_opened', over: [] },
    );

    expect(backgroundShown(open)).toBeTruthy();

    const arrived = reduceApp(open, {
      type: 'permission_requested',
      turnId: 't1',
      permission: PERMISSION,
      at: 0,
    });

    expect(backgroundShown(arrived)).toBeFalsy();
    expect(keyCommand('', escape, arrived, '')).toBe('reject_permission');

    const answered = reduceApp(arrived, {
      type: 'permission_settled',
      turnId: 't1',
      id: 'p1',
      answer: { type: 'chosen', optionId: 'allow' },
    });

    expect(backgroundShown(answered)).toBeTruthy();
    expect(answered.backgroundView).toStrictEqual(open.backgroundView);
  });

  test('a form that arrives once it is open hides it too, even over a permission it stood over', () => {
    const over = opened(permissionAsked);
    const arrived = reduceApp(over, {
      type: 'elicitation_requested',
      turnId: 't1',
      elicitation: FORM,
    });

    expect(backgroundShown(arrived)).toBeFalsy();
  });
});

test('another size clears where the frame was scrolled to, keeping the ❯ on its item (CHD-430)', () => {
  const focus = { key: 1, id: 't1' };
  const scrolled = [
    { type: 'background_opened' },
    { type: 'background_focused', focus, top: 7, laid: '76x6' },
  ] as const;
  const resized = [...scrolled, { type: 'background_resized' } as const].reduce(
    reduceBackground,
    initialBackground,
  );

  expect(resized.backgroundView).toStrictEqual({ focus });
  // A move after it is laid out anew.
  expect(
    reduceBackground(resized, { type: 'background_focused', focus })
      .backgroundView,
  ).toStrictEqual({ focus });
});
