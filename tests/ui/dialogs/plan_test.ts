import { describe, expect, test } from 'bun:test';
import {
  noteLines,
  OPEN_PLAN_BOX,
  planChoices,
  planHint,
  planKey,
  planPaste,
  planQuestion,
} from '../../../src/ui/dialogs/plan.ts';

const key = (more: Record<string, boolean> = {}) => ({
  ctrl: false,
  escape: false,
  ...more,
});

test("each agent's choices: cursor's yes and no; grok's, and its way out of plan mode (CHD-437, 3A)", () => {
  expect(planChoices('cursor').map(({ label }) => label)).toStrictEqual([
    'Yes, accept the plan',
    'No, keep planning',
  ]);
  expect(planChoices('grok').map(({ label }) => label)).toStrictEqual([
    'Yes, start implementing',
    'No, keep planning',
    'No, and leave plan mode',
  ]);
});

test('the question names the agent, and says so when grok wrote no plan (CHD-457)', () => {
  const wait = { id: 'p', agent: 'grok', toolCallId: 'c' } as const;

  expect(planQuestion('grok', { ...wait, plan: '# Route' })).toBe(
    'grok has a plan. Do you want to proceed?',
  );
  expect(planQuestion('grok', wait)).toBe(
    'grok has written no plan. Do you want to proceed?',
  );
});

describe('a press in the plan box', () => {
  test('↑ ↓ and j k move, the Note row past the last choice; ↑ leaves it', () => {
    let state = OPEN_PLAN_BOX;

    for (const [input, more, row] of [
      ['j', {}, 1],
      ['', { downArrow: true }, 2],
      ['', { downArrow: true }, 2],
      ['', { upArrow: true }, 1],
      ['k', {}, 0],
      ['k', {}, 0],
    ] as const) {
      state = planKey('cursor', state, input, key(more)).state;

      expect(state.row).toBe(row);
    }
  });

  test("shift with an arrow is the window's scroll, and moves nothing in the box", () => {
    for (const row of [0, 2]) {
      for (const more of [
        { shift: true, upArrow: true },
        { shift: true, downArrow: true },
      ]) {
        expect(
          planKey('cursor', { row, note: '' }, '', key(more)).state.row,
        ).toBe(row);
      }
    }
  });

  test('a digit picks its choice; enter the one under the ❯; esc keeps planning with no note', () => {
    expect(planKey('grok', OPEN_PLAN_BOX, '3', key()).answer).toStrictEqual({
      type: 'left',
    });
    expect(planKey('cursor', OPEN_PLAN_BOX, '9', key()).answer).toBe(undefined);
    expect(
      planKey('cursor', OPEN_PLAN_BOX, '', key({ return: true })).answer,
    ).toStrictEqual({ type: 'accepted' });
    expect(
      planKey('grok', { row: 3, note: 'typed' }, '', key({ escape: true }))
        .answer,
    ).toStrictEqual({ type: 'kept' });
  });

  test('on the Note row digits and j k type, and enter keeps planning with the note', () => {
    let state = { ...OPEN_PLAN_BOX, row: 2 };

    for (const input of ['k', 'e', 'e', 'p', ' ', '2', 'j']) {
      state = planKey('cursor', state, input, key()).state;
    }

    expect(state).toStrictEqual({ row: 2, note: 'keep 2j' });

    state = planKey('cursor', state, '', key({ backspace: true })).state;

    expect(
      planKey('cursor', state, '', key({ return: true })).answer,
    ).toStrictEqual({ type: 'kept', note: 'keep 2' });
    // Nothing but spaces is no note.
    expect(
      planKey('cursor', { row: 2, note: '  ' }, '', key({ return: true }))
        .answer,
    ).toStrictEqual({ type: 'kept' });
  });

  test('a note typed stays on the choices and goes with keep planning alone', () => {
    const typed = { row: 0, note: 'smaller' };

    expect(planKey('grok', typed, '2', key()).answer).toStrictEqual({
      type: 'kept',
      note: 'smaller',
    });
    expect(planKey('grok', typed, '1', key()).answer).toStrictEqual({
      type: 'accepted',
    });
    expect(planKey('grok', typed, '3', key()).answer).toStrictEqual({
      type: 'left',
    });
  });

  test('a paste goes into the note on its row, one line, and nowhere else', () => {
    expect(planPaste('cursor', { row: 2, note: 'a ' }, 'b\nc')).toStrictEqual({
      row: 2,
      note: 'a b c',
    });
    expect(planPaste('cursor', OPEN_PLAN_BOX, 'b')).toStrictEqual(
      OPEN_PLAN_BOX,
    );
  });
});

test("the hint names the choices' count, and on the Note row what enter does there", () => {
  expect(planHint('cursor', OPEN_PLAN_BOX)).toBe(
    'Enter to pick · 1–2 · ↑↓ to move · Esc to keep planning',
  );
  expect(planHint('grok', OPEN_PLAN_BOX)).toBe(
    'Enter to pick · 1–3 · ↑↓ to move · Esc to keep planning',
  );
  expect(planHint('grok', { row: 3, note: '' })).toBe(
    'Enter to keep planning with this note · ↑ to the options · Esc to keep planning',
  );
});

test("the Note's lines wrap at its spaces, never cut, a cell left for the cursor", () => {
  expect(noteLines('', 10)).toStrictEqual(['']);
  expect(noteLines('one two three four', 10)).toStrictEqual([
    'one two',
    'three four',
    // A full line leaves the cursor's cell to the next.
    '',
  ]);
  // No line starts with the space it broke at, however narrow (CHD-437).
  expect(noteLines('test it; step 40 keep it small', 9)).toStrictEqual([
    'test it;',
    'step 40',
    'keep it',
    'small',
  ]);
  // The spaces typed last stay, so the cursor is after them.
  expect(noteLines('keep it ', 10)).toStrictEqual(['keep it ']);
  expect(noteLines('abcdefghijkl', 5).join('')).toBe('abcdefghijkl');
});
