import { describe, expect, test } from 'bun:test';
import { createElement } from 'react';
import {
  closeOnForcedExit,
  dieBySignal,
  leave,
} from '../../../src/ui/app/renderer.tsx';
import { draw } from '../harness.tsx';
import { until } from './render.tsx';

test('a forced exit waits for every close still asked for, a failed one too, and forgets them (CHD-331)', async () => {
  const closed: string[] = [];
  const slow = Promise.withResolvers<void>();

  closeOnForcedExit(async () => {
    await slow.promise;
    closed.push('slow');
  });

  closeOnForcedExit(() => Promise.reject(new Error('did not exit')));
  closeOnForcedExit(() => {
    closed.push('forgotten');

    return Promise.resolve();
  })();

  let left = false;
  const leaving = leave(undefined).then(() => (left = true));

  await Promise.resolve();
  expect(left).toBe(false);

  slow.resolve();
  await leaving;

  expect(closed).toEqual(['slow']);

  await leave(undefined);
  expect(closed).toEqual(['slow']);
});

test('a second forced exit waits for the closes the first one started (CHD-331)', async () => {
  const slow = Promise.withResolvers<void>();
  let closes = 0;

  closeOnForcedExit(async () => {
    closes += 1;

    await slow.promise;
  });

  const left: string[] = [];
  const first = leave(undefined).then(() => left.push('first'));
  const second = leave(undefined).then(() => left.push('second'));

  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(left).toEqual([]);

  slow.resolve();
  await Promise.all([first, second]);

  expect(left.sort()).toEqual(['first', 'second']);
  expect(closes).toBe(1);
});

test('a signal during a forced exit is held until the closes settle, then the first is raised (CHD-331)', async () => {
  const slow = Promise.withResolvers<void>();
  const raised: NodeJS.Signals[] = [];
  const hup = process.listenerCount('SIGHUP');

  closeOnForcedExit(() => slow.promise);

  const off = dieBySignal((signal) => raised.push(signal));

  try {
    process.emit('SIGTERM');
    await new Promise((resolve) => setTimeout(resolve, 0));
    process.emit('SIGHUP');
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(raised).toEqual([]);
    expect(process.listenerCount('SIGHUP')).toBe(hup + 1);

    slow.resolve();
    await until('the first signal raised', () => raised.length > 0);

    expect(raised).toEqual(['SIGTERM']);
    expect(process.listenerCount('SIGHUP')).toBe(hup);
  } finally {
    slow.resolve();
    off();
  }
});

/** The mouse modes a terminal was told to turn on, in the order told. */
async function mouseModes(mouse: boolean): Promise<string[]> {
  const log: string[] = [];
  const drawn = await draw(
    createElement('text', null, 'hi'),
    {},
    {
      log,
      mouse,
    },
  );

  await drawn.unmount();

  return log
    .join('')
    .split('\x1b[?')
    .slice(1)
    .flatMap((mode) => /^(100[0-6])h/.exec(mode)?.[1] ?? []);
}

test('the mouse is asked for with 1000, 1002 and 1006, no hover motion (CHD-172)', async () => {
  expect(new Set(await mouseModes(true))).toStrictEqual(
    new Set(['1000', '1002', '1006']),
  );
});

test('"mouse": false asks for no mouse mode (CHD-172)', async () => {
  expect(await mouseModes(false)).toStrictEqual([]);
});

describe('tester: mouse mode restoration', () => {
  test('destroy disables each requested mouse mode', async () => {
    const log: string[] = [];
    const drawn = await draw(createElement('text', null, 'inert'), {}, { log });

    await drawn.unmount();

    const written = log.join('');

    for (const mode of ['1000', '1002', '1006']) {
      expect(written).toContain(`\x1b[?${mode}h`);
      expect(written.lastIndexOf(`\x1b[?${mode}l`)).toBeGreaterThan(
        written.lastIndexOf(`\x1b[?${mode}h`),
      );
    }

    expect(written).not.toContain('\x1b[?1003h');
  });
});
