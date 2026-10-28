import { describe, expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import { act, createElement, useState } from 'react';
import {
  type AppAction,
  COPIED_NOTE_MS,
  initialAppState,
  reduceApp,
  type WindowedAction,
} from '../../../src/ui/app/state.ts';
import { useTimers } from '../../../src/ui/app/timers.ts';
import { draw } from '../harness.tsx';
import { until } from './render.tsx';

describe('CHD-394 U3 tester: note timer lapse', () => {
  test('failed block and draft notes expire through the hook while a failed selection note stays', async () => {
    const result = { kind: 'failed', reason: 'clipboard unavailable' } as const;
    const block = reduceApp(initialAppState, {
      type: 'block_copy_noted',
      result,
    });
    const drafted = reduceApp(block, { type: 'draft_held' });
    const selected = reduceApp(
      reduceApp(initialAppState, { type: 'selection_started' }),
      { type: 'selection_released', text: 'selected text' },
    );
    const selection = reduceApp(reduceApp(selected, { type: 'copy_started' }), {
      type: 'copy_noted',
      result,
      auto: false,
    });
    const events: WindowedAction[] = [];
    const selectionEvents: WindowedAction[] = [];
    const Probe = () => {
      useTimers(drafted, (action) => events.push(action));
      useTimers(selection, (action) => selectionEvents.push(action));

      return createElement('text', null, 'notes');
    };

    const screen = await draw(createElement(Probe), { columns: 80, rows: 24 });

    try {
      assert(drafted.copied !== undefined && drafted.draftHeld !== undefined);
      expect(events).toStrictEqual([]);
      await until(
        'both notes lapse',
        () => events.length === 2,
        COPIED_NOTE_MS + 5000,
      );
      expect(events).toContainEqual({
        type: 'copied_gone',
        id: drafted.copied.id,
      });
      expect(events).toContainEqual({
        type: 'draft_held_gone',
        id: drafted.draftHeld,
      });
      expect(selectionEvents).toStrictEqual([]);
      expect(selection.copied?.result.kind).toBe('failed');
    } finally {
      await screen.unmount();
    }
  });
});

describe('CHD-535 U2 tester: steering note lifetime', () => {
  test('the hook restarts three seconds from the latest note and ignores a stale expiry', async () => {
    let current = initialAppState;
    let change: (action: WindowedAction) => void = () => {};

    const events: WindowedAction[] = [];
    const Probe = () => {
      const [state, setState] = useState(initialAppState);

      current = state;
      change = (action) =>
        setState((before) => reduceApp(before, action as AppAction));

      useTimers(state, (action) => {
        events.push(action);
        change(action);
      });

      return createElement('text', null, 'steering note');
    };

    const screen = await draw(createElement(Probe), { columns: 80, rows: 24 });

    const environment = globalThis as {
      IS_REACT_ACT_ENVIRONMENT?: boolean | undefined;
    };
    const previous = environment.IS_REACT_ACT_ENVIRONMENT;

    environment.IS_REACT_ACT_ENVIRONMENT = true;

    jest.useFakeTimers({ now: 0 });

    try {
      act(() => change({ type: 'steer_refused', refused: false }));

      const first = current.steerRefused;

      assert(first !== undefined);
      act(() => jest.advanceTimersByTime(2999));
      expect(events).toEqual([]);
      act(() => change({ type: 'steer_refused', refused: true }));

      const latest = current.steerRefused;

      assert(latest !== undefined);
      expect(latest.id).not.toBe(first.id);
      act(() => change({ type: 'steer_note_gone', id: first.id }));
      expect(current.steerRefused).toEqual(latest);
      act(() => jest.advanceTimersByTime(2999));
      expect(events).toEqual([]);
      expect(current.steerRefused).toEqual(latest);
      act(() => jest.advanceTimersByTime(1));
      expect(events).toEqual([{ type: 'steer_note_gone', id: latest.id }]);
      expect(current.steerRefused).toBeUndefined();
    } finally {
      jest.useRealTimers();

      environment.IS_REACT_ACT_ENVIRONMENT = previous;

      await screen.unmount();
    }
  });
});
