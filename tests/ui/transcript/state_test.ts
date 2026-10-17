import { expect, test } from 'bun:test';
import {
  type AppAction,
  type AppState,
  keyCommand,
  reduceApp,
} from '../../../src/ui/app/state.ts';
import { after, busy, ctrl, plain, ready } from '../app/states.ts';

test('ctrl+o expands and folds, mid-turn and with a draft', () => {
  expect(ready.expanded).toStrictEqual(false);
  expect(keyCommand('o', ctrl, ready, '')).toStrictEqual('toggle_expanded');
  expect(keyCommand('o', ctrl, busy, 'draft')).toStrictEqual('toggle_expanded');
  expect(keyCommand('o', plain, ready, '')).toStrictEqual(undefined);

  const open = reduceApp(ready, { type: 'expanded_toggled' });

  expect(open.expanded).toStrictEqual(true);
  expect(reduceApp(open, { type: 'expanded_toggled' }).expanded).toStrictEqual(
    false,
  );
});

test('a wheel step scrolls a line as shift+↑ does, but not once closing', () => {
  const tall = after({ type: 'scroll_measured', content: 100, view: 20 });
  const up = reduceApp(tall, { type: 'wheeled', step: 'line_up' });

  expect(up.scroll).toStrictEqual(
    reduceApp(tall, { type: 'scrolled', step: 'line_up' }).scroll,
  );
  expect(up.scroll.following).toStrictEqual(false);
  expect(
    reduceApp(up, { type: 'wheeled', step: 'line_down' }).scroll.following,
  ).toStrictEqual(true);

  const closing = reduceApp(tall, { type: 'closing' });

  expect(
    reduceApp(closing, { type: 'wheeled', step: 'line_up' }),
  ).toStrictEqual(closing);
});

/** `busy` with a transcript of 90 rows in a 33-row area, a page scrolled back. */
const scrolledBack = [
  { type: 'scroll_measured', content: 90, view: 33 },
  { type: 'scrolled', step: 'page_up' },
].reduce<AppState>(
  (state, action) => reduceApp(state, action as AppAction),
  busy,
);

function chunk(text: string): AppAction {
  return {
    type: 'update',
    turnId: 't1',
    update: {
      sessionUpdate: 'agent_message_chunk',
      content: { type: 'text', text },
    },
  };
}

test('the view keys scroll, with or without shift on the big keys', () => {
  const keys = [
    [{ pageUp: true }, 'scroll_page_up'],
    [{ pageDown: true }, 'scroll_page_down'],
    [{ home: true }, 'scroll_top'],
    [{ end: true }, 'scroll_bottom'],
    [{ shift: true, upArrow: true }, 'scroll_line_up'],
    [{ shift: true, downArrow: true }, 'scroll_line_down'],
  ] as const;

  for (const [pressed, command] of keys) {
    expect(keyCommand('', { ...plain, ...pressed }, busy, '')).toStrictEqual(
      command,
    );
    expect(
      keyCommand('', { ...plain, shift: true, ...pressed }, ready, 'draft'),
    ).toStrictEqual(command);
  }

  // A plain arrow is prompt history's.
  expect(keyCommand('', { ...plain, upArrow: true }, ready, '')).toStrictEqual(
    undefined,
  );
});

test('output while scrolled back is news, and does not move the view', () => {
  expect(scrolledBack.scroll.following).toStrictEqual(false);
  expect(scrolledBack.scroll.news).toStrictEqual(false);

  const told = reduceApp(scrolledBack, chunk('more'));

  expect(told.scroll.news).toStrictEqual(true);
  expect(told.scroll.top).toStrictEqual(scrolledBack.scroll.top);
  // The end of a turn adds nothing to read.
  expect(
    reduceApp(scrolledBack, {
      type: 'result',
      turnId: 't1',
      result: { stopReason: 'end_turn' },
    } as AppAction).scroll.news,
  ).toStrictEqual(false);
  // Following, output is not news.
  expect(reduceApp(busy, chunk('more')).scroll.news).toStrictEqual(false);
});

test('sending a prompt brings the view back to the bottom', () => {
  const told = reduceApp(scrolledBack, chunk('more'));
  const sent = reduceApp(told, {
    type: 'prompt',
    turnId: 't2',
    text: 'next',
    at: 1,
  });

  expect(sent.scroll.following).toStrictEqual(true);
  expect(sent.scroll.news).toStrictEqual(false);
});

test('a report goes into the transcript and brings the view down', () => {
  const back: AppState = {
    ...ready,
    scroll: { content: 80, view: 20, following: false, top: 10, news: false },
  };
  const state = reduceApp(back, {
    type: 'reported',
    turnId: 'r1',
    command: 'cost',
    rows: [{ text: 'fake has not reported what this session has used.' }],
  });

  expect(state.transcript.entries).toStrictEqual([
    {
      kind: 'report',
      turnId: 'r1',
      command: 'cost',
      rows: [{ text: 'fake has not reported what this session has used.' }],
    },
  ]);
  expect(state.scroll.following).toStrictEqual(true);
  expect(state.transcript.turn).toStrictEqual({ status: 'idle' });
});

test('the tail is held as the view leaves the bottom, grows on the way up, and goes back there', () => {
  const entries = Array.from({ length: 200 }, (_, at) => ({
    kind: 'assistant' as const,
    turnId: 't1',
    text: `reply ${at}`,
  }));
  const long = reduceApp(
    { ...ready, transcript: { ...ready.transcript, entries } },
    { type: 'scroll_measured', content: 400, view: 20 },
  );

  expect(long.mounted).toBeUndefined();

  const back = reduceApp(long, { type: 'scrolled', step: 'page_up' });

  expect(back.mounted).toStrictEqual(160);

  const older = reduceApp(back, { type: 'backfilled', from: 160 });

  expect(older.mounted).toStrictEqual(100);
  // A second ask from the window before is late, and changes nothing.
  expect(reduceApp(older, { type: 'backfilled', from: 160 })).toBe(older);
  expect(
    reduceApp(older, { type: 'scrolled', step: 'bottom' }).mounted,
  ).toBeUndefined();
  expect(reduceApp(long, { type: 'scrolled', step: 'top' }).mounted).toBe(0);
});

test('a jump scrolls the view back and mounts its entry, until the measure has put it on top or the view follows again', () => {
  const tall = after({ type: 'scroll_measured', content: 100, view: 20 });
  const jumped = reduceApp(tall, { type: 'jumped_to', entry: 0 });

  expect(jumped.jump).toStrictEqual(0);
  expect(jumped.scroll.following).toStrictEqual(false);
  expect(jumped.mounted).toStrictEqual(0);
  expect(reduceApp(jumped, { type: 'jump_done' }).jump).toStrictEqual(
    undefined,
  );

  // end before the measure: nothing is left to scroll to.
  const back = reduceApp(jumped, { type: 'scrolled', step: 'bottom' });

  expect(back.jump).toStrictEqual(undefined);
  expect(back.scroll.following).toStrictEqual(true);
});
