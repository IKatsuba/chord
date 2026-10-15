import { describe, expect, test } from 'bun:test';
import type { ClipboardWriteResult } from '@opentui/core';
import {
  COPY_BOUND_MS,
  COPY_TIMEOUT_MS,
  copies,
  copyable,
  copyNote,
  copyRejected,
  copyResult,
  graphemes,
  NO_SELECTION,
  pressed,
  released,
  scrolled,
} from '../../../src/ui/app/selection.ts';

const ATTEMPTED = { status: 'attempted', capability: 'supported' } as const;
const NOT_ATTEMPTED = {
  status: 'not-attempted',
  capability: 'unknown',
} as const;

test('a press starts a drag that remembers whether the view followed', () => {
  expect(pressed(true)).toStrictEqual({
    kind: 'dragging',
    wasFollowing: true,
    moved: false,
  });
  expect(scrolled(pressed(false))).toStrictEqual({
    kind: 'dragging',
    wasFollowing: false,
    moved: true,
  });
  expect(scrolled(NO_SELECTION)).toStrictEqual(NO_SELECTION);
});

test('a release shows what it selected, and follows again unless the view moved', () => {
  expect(released(pressed(true), 'hello')).toStrictEqual({
    selection: { kind: 'shown' },
    follow: true,
  });
  expect(released(scrolled(pressed(true)), 'hello').follow).toBe(false);
  expect(released(pressed(false), 'hello').follow).toBe(false);
  expect(released(NO_SELECTION, 'hello').follow).toBe(false);
});

test('a release with nothing selected, a click, leaves none', () => {
  expect(released(pressed(true), '')).toStrictEqual({
    selection: NO_SELECTION,
    follow: true,
  });
});

test('only a shown selection copies, one copy at a time', () => {
  expect(copyable({ kind: 'shown' })).toBe(true);
  expect(copyable({ kind: 'copying' })).toBe(false);
  expect(copyable(pressed(true))).toBe(false);
  expect(copyable(NO_SELECTION)).toBe(false);
});

test('a copy counts graphemes, not code units', () => {
  expect(graphemes('abc')).toBe(3);
  expect(graphemes('é')).toBe(1);
  expect(graphemes('👍🏽 ok')).toBe(4);
  expect(graphemes('')).toBe(0);
});

test("each of OpenTUI's results is said as the design's table says it", () => {
  const said = (result: ClipboardWriteResult) => {
    const copied = copyResult('héllo', result);

    return copied && copyNote(copied);
  };

  expect(said({ host: { status: 'written' }, terminal: NOT_ATTEMPTED })).toBe(
    'copied 5 chars to clipboard',
  );
  expect(
    said({
      host: { status: 'failed', error: new Error('no pasteboard') },
      terminal: ATTEMPTED,
    }),
  ).toBe("sent 5 chars to the terminal's clipboard");
  expect(said({ host: { status: 'unsupported' }, terminal: ATTEMPTED })).toBe(
    "sent 5 chars to the terminal's clipboard",
  );
  // Over SSH the host is never asked.
  expect(said({ host: { status: 'not-attempted' }, terminal: ATTEMPTED })).toBe(
    "sent 5 chars to the terminal's clipboard",
  );
  expect(said({ host: { status: 'timed-out' }, terminal: NOT_ATTEMPTED })).toBe(
    'could not copy: the clipboard did not answer · ctrl + c to try again',
  );
  expect(
    said({
      host: { status: 'failed', error: new Error('no\n  pasteboard') },
      terminal: { status: 'local-failure', capability: 'unknown' },
    }),
  ).toBe('could not copy: no pasteboard · ctrl + c to try again');
  expect(
    said({ host: { status: 'unsupported' }, terminal: NOT_ATTEMPTED }),
  ).toBe('could not copy: no clipboard to write to · ctrl + c to try again');
  // Only chord's own abort cancels, and it says nothing.
  expect(
    said({ host: { status: 'cancelled' }, terminal: NOT_ATTEMPTED }),
  ).toBeUndefined();
});

test("a copy over the service's bound is too large, any other throw said as it is", () => {
  expect(
    copyNote(
      copyRejected(
        new RangeError('writeText exceeds the configured 8388608 byte limit'),
      ),
    ),
  ).toBe('could not copy: too large to copy · ctrl + c to try again');
  expect(copyNote(copyRejected(new Error('closed')))).toBe(
    'could not copy: closed · ctrl + c to try again',
  );
});

test("chord's bound is the host's timeout and a margin", () => {
  expect(COPY_TIMEOUT_MS).toBe(1_000);
  expect(COPY_BOUND_MS).toBe(1_200);
});

/** Timers run by hand: each set kept until the test fires it. */
function handTimers() {
  const set = new Map<number, () => void>();
  let next = 0;

  return {
    timers: {
      set: (run: () => void) => {
        set.set(++next, run);

        return next;
      },
      clear: (timer: unknown) => void set.delete(timer as number),
    },
    fire: () => {
      for (const [id, run] of set) {
        set.delete(id);
        run();
      }
    },
    pending: () => set.size,
  };
}

const WRITTEN: ClipboardWriteResult = {
  host: { status: 'written' },
  terminal: NOT_ATTEMPTED,
};

test('a copy says what it came to, and leaves no timer behind', async () => {
  const { timers, pending } = handTimers();
  const window = copies(() => Promise.resolve(WRITTEN), 1_200, timers);

  expect(await window.start('abc')).toStrictEqual({
    kind: 'copied',
    chars: 3,
  });
  expect(pending()).toBe(0);
});

test('a new copy aborts the one in flight, which then says nothing', async () => {
  const signals: AbortSignal[] = [];
  const answers: ((result: ClipboardWriteResult) => void)[] = [];
  const { timers } = handTimers();
  const window = copies(
    (_text, signal) => {
      signals.push(signal);

      return new Promise((resolve) => answers.push(resolve));
    },
    1_200,
    timers,
  );
  const first = window.start('first');
  const second = window.start('second');

  expect(signals[0]!.aborted).toBe(true);
  expect(signals[1]!.aborted).toBe(false);

  // The superseded host answers anyway, and late.
  answers[0]!(WRITTEN);
  answers[1]!(WRITTEN);

  expect(await first).toBeUndefined();
  expect(await second).toStrictEqual({ kind: 'copied', chars: 6 });
});

test('a copy unanswered at the bound is timed out, its late answer dropped', async () => {
  const { timers, fire } = handTimers();
  let answer: ((result: ClipboardWriteResult) => void) | undefined;
  const window = copies(
    () => new Promise((resolve) => (answer = resolve)),
    1_200,
    timers,
  );
  const copying = window.start('abc');

  fire();

  expect(await copying).toStrictEqual({
    kind: 'failed',
    reason: 'the clipboard did not answer',
  });

  // Nothing is left waiting on the late answer.
  answer!(WRITTEN);
});

test('a disposed window aborts its copy, says nothing of it, and starts none', async () => {
  let signal: AbortSignal | undefined;
  let answer: ((result: ClipboardWriteResult) => void) | undefined;
  let started = 0;
  const { timers } = handTimers();
  const window = copies(
    (_text, given) => {
      started += 1;
      signal = given;

      return new Promise((resolve) => (answer = resolve));
    },
    1_200,
    timers,
  );
  const copying = window.start('abc');

  window.dispose();
  expect(signal!.aborted).toBe(true);
  answer!(WRITTEN);
  expect(await copying).toBeUndefined();
  expect(await window.start('again')).toBeUndefined();
  expect(started).toBe(1);
});

test('a copy that throws is said as a failure', async () => {
  const window = copies(() => Promise.reject(new Error('closed')));

  expect(await window.start('abc')).toStrictEqual({
    kind: 'failed',
    reason: 'closed',
  });
});

describe('tester: selection copy races and failures', () => {
  test('a synchronous clipboard failure becomes a retryable result', async () => {
    const { timers, pending } = handTimers();
    const window = copies(
      () => {
        throw new Error('clipboard closed');
      },
      COPY_BOUND_MS,
      timers,
    );

    expect(await window.start('hello')).toStrictEqual({
      kind: 'failed',
      reason: 'clipboard closed',
    });
    expect(pending()).toBe(0);
  });

  test('an older completion cannot detach the newer abort controller', async () => {
    const { timers, pending } = handTimers();
    const first = Promise.withResolvers<ClipboardWriteResult>();
    const second = Promise.withResolvers<ClipboardWriteResult>();
    const signals: AbortSignal[] = [];
    const window = copies(
      (_text, signal) => {
        signals.push(signal);

        return signals.length === 1 ? first.promise : second.promise;
      },
      COPY_BOUND_MS,
      timers,
    );
    const old = window.start('old');
    const current = window.start('current');

    first.resolve(WRITTEN);
    expect(await old).toBeUndefined();
    expect(pending()).toBe(1);

    window.dispose();
    expect(signals[1]!.aborted).toBe(true);
    second.reject(new Error('late failure'));
    expect(await current).toBeUndefined();
    expect(pending()).toBe(0);
  });

  test('disposal with a host that never answers settles silently at the bound', async () => {
    const { timers, fire, pending } = handTimers();
    const window = copies(() => new Promise(() => {}), COPY_BOUND_MS, timers);
    const copying = window.start('held');

    window.dispose();
    fire();

    expect(await copying).toBeUndefined();
    expect(pending()).toBe(0);
  });

  test('emoji joins, flags and CRLF count as graphemes in the result', () => {
    expect(copyResult('👨‍👩‍👧‍👦🇪🇸\r\né', WRITTEN)).toStrictEqual({
      kind: 'copied',
      chars: 4,
    });
  });
});
