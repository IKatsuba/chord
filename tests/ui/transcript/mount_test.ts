import { expect, test } from 'bun:test';
import type { Entry, Subagent } from '../../../src/session/transcript/types.ts';
import {
  backfilled,
  BACKFILL_ENTRIES,
  entriesBefore,
  entryWeight,
  firstMounted,
  heldMount,
  type Mounting,
  TAIL_ENTRIES,
} from '../../../src/ui/transcript/mount.ts';
import {
  initialScroll,
  type Scroll,
} from '../../../src/ui/transcript/scroll.ts';

const T = 't1';

function say(text: string): Entry {
  return { kind: 'assistant', turnId: T, text };
}

function agent(id: string, work: number): Entry {
  const subagent: Subagent = {
    id,
    state: 'completed',
    entries: Array.from({ length: work }, (_, at) => say(`${id} ${at}`)),
    plan: [],
  };

  return { kind: 'subagent', turnId: T, subagent };
}

function replies(count: number): Entry[] {
  return Array.from({ length: count }, (_, at) => say(`reply ${at}`));
}

const FOLLOWING: Scroll = { ...initialScroll, content: 400, view: 20 };
const BACK: Scroll = { ...FOLLOWING, following: false, top: 100 };

function mounting(
  entries: readonly Entry[],
  scroll: Scroll,
  mounted?: number,
  expanded = false,
): Mounting {
  return {
    transcript: { entries },
    expanded,
    scroll,
    ...(mounted === undefined ? {} : { mounted }),
  };
}

test('an entry costs one, a folded subagent group one, an opened one its work too', () => {
  const entries = [say('before'), agent('a', 3), agent('b', 2), say('after')];

  expect(entries.map((_, at) => entryWeight(entries, at, false))).toEqual([
    1, 1, 0, 1,
  ]);
  // The group's row, then each of its agents' five blocks of work.
  expect(entries.map((_, at) => entryWeight(entries, at, true))).toEqual([
    1, 6, 0, 1,
  ]);
});

test('the entries before an end are counted back until they cost the budget', () => {
  const entries = replies(100);

  expect(entriesBefore(entries, 100, 40, false)).toBe(60);
  expect(entriesBefore(entries, 60, 60, false)).toBe(0);
  expect(entriesBefore(entries, 0, 60, false)).toBe(0);

  // An opened group spends the budget the entries before it would have.
  const grouped = [...replies(50), agent('a', 30), ...replies(20)];

  expect(entriesBefore(grouped, grouped.length, 40, false)).toBe(31);
  expect(entriesBefore(grouped, grouped.length, 40, true)).toBe(50);
});

test('following, the tail is mounted, and at least a view of it', () => {
  const entries = replies(200);

  expect(firstMounted(mounting(entries, FOLLOWING))).toBe(200 - TAIL_ENTRIES);
  // A view taller than the tail's entries mounts one more than its rows.
  expect(firstMounted(mounting(entries, { ...FOLLOWING, view: 60 }))).toBe(139);
  expect(firstMounted(mounting(replies(10), FOLLOWING))).toBe(0);
});

test('leaving the bottom holds the tail; new output does not move it', () => {
  const entries = replies(200);
  const before = mounting(entries, FOLLOWING);
  const held = heldMount(before, mounting(entries, BACK), false);

  expect(held).toBe(160);

  // Fifty more entries arrive while scrolled back: the window stays.
  const longer = mounting([...entries, ...replies(50)], BACK, held);

  expect(firstMounted(longer)).toBe(160);
  expect(heldMount(longer, longer, false)).toBe(160);
});

test('back at the bottom nothing is held, and the tail is mounted again', () => {
  const entries = replies(200);

  expect(
    heldMount(
      mounting(entries, BACK, 40),
      mounting(entries, FOLLOWING, 40),
      false,
    ),
  ).toBeUndefined();
});

test('home holds the very first entry', () => {
  const entries = replies(200);

  expect(
    heldMount(mounting(entries, FOLLOWING), mounting(entries, BACK), true),
  ).toBe(0);
  expect(firstMounted(mounting(entries, { ...BACK, top: 0 }, 0))).toBe(0);
});

test('ctrl+o folding the tail past the held entry mounts more above it', () => {
  const entries = [...replies(200), agent('a', 50)];
  const opened = heldMount(
    mounting(entries, FOLLOWING, undefined, true),
    mounting(entries, BACK, undefined, true),
    false,
  );

  // Opened, the group alone is the tail.
  expect(opened).toBe(200);
  expect(firstMounted(mounting(entries, BACK, opened, false))).toBe(161);
});

test('a backfill mounts the chunk above, once for the window it was asked from', () => {
  const entries = replies(200);
  const state = mounting(entries, BACK, 160);

  expect(backfilled(state, 160)).toBe(160 - BACKFILL_ENTRIES);
  // Asked again before React drew the first: the window has moved on.
  expect(backfilled(mounting(entries, BACK, 100), 160)).toBeUndefined();
  expect(backfilled(mounting(entries, BACK, 0), 0)).toBeUndefined();
  expect(backfilled(mounting(entries, FOLLOWING), 160)).toBeUndefined();
});
