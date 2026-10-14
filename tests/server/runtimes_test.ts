import { expect, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import {
  type Offered,
  Runtimes,
  sessionProbe,
} from '../../src/server/runtimes.ts';
import { fakeAgentCommand } from '../fixtures/fake.ts';

const OFFERED: Offered = {
  models: { available: [{ id: 'm', name: 'M' }], current: 'm' },
  modes: { available: [{ id: 'plan', name: 'Plan' }], current: 'plan' },
  efforts: {
    option: 'effort',
    available: [
      { id: 'low', name: 'Low' },
      { id: 'high', name: 'High' },
    ],
    current: 'low',
  },
};
const OFFER = {
  models: [
    {
      id: 'm',
      name: 'M',
      efforts: [
        { id: 'low', name: 'Low' },
        { id: 'high', name: 'High' },
      ],
      effort: 'low',
    },
  ],
  current: 'm',
  modes: [{ id: 'plan', name: 'Plan' }],
  currentMode: 'plan',
};

test('a runtime is read once for the window, and never unasked', async () => {
  const probed: string[] = [];
  const runtimes = new Runtimes({
    probe: (runtime) => {
      probed.push(runtime);

      return delay(10).then(() => OFFERED);
    },
  });

  expect(await runtimes.read('claude', false)).toStrictEqual(undefined);

  const [one, two] = await Promise.all([
    runtimes.read('claude', true),
    runtimes.read('claude', true),
  ]);

  expect(one).toStrictEqual(OFFER);
  expect(two).toStrictEqual(one);
  expect(await runtimes.read('claude', false)).toStrictEqual(one);
  expect(probed).toStrictEqual(['claude']);
});

test("an open session's models and modes are the runtime's, with no session started", async () => {
  const runtimes = new Runtimes({
    probe: () => Promise.reject(new Error('not to be started')),
  });

  runtimes.heard('fake', OFFERED);

  expect(await runtimes.read('fake', true)).toStrictEqual(OFFER);
});

test('a session that has said nothing yet leaves its runtime unread', async () => {
  const runtimes = new Runtimes({
    probe: () => Promise.resolve(OFFERED),
  });

  runtimes.heard('fake', {
    models: undefined,
    modes: undefined,
    efforts: undefined,
  });

  expect(await runtimes.read('fake', false)).toStrictEqual(undefined);
});

test('a runtime that offers modes and no models gives its modes', async () => {
  const runtimes = new Runtimes({
    probe: () =>
      Promise.resolve({
        models: undefined,
        modes: OFFERED.modes,
        efforts: undefined,
      }),
  });

  expect(await runtimes.read('modal', true)).toStrictEqual({
    models: [],
    current: undefined,
    modes: [{ id: 'plan', name: 'Plan' }],
    currentMode: 'plan',
  });
});

test('a runtime that names no model it is on gives its efforts beside its models', async () => {
  const runtimes = new Runtimes({
    probe: () =>
      Promise.resolve({
        models: { available: [{ id: 'm', name: 'M' }] },
        modes: undefined,
        efforts: OFFERED.efforts,
      }),
  });

  expect(await runtimes.read('vague', true)).toStrictEqual({
    models: [{ id: 'm', name: 'M' }],
    current: undefined,
    efforts: [
      { id: 'low', name: 'Low' },
      { id: 'high', name: 'High' },
    ],
    currentEffort: 'low',
  });
});

test('a runtime that fails says why, and is tried again when asked again', async () => {
  let tries = 0;
  const runtimes = new Runtimes({
    probe: () => {
      tries++;

      return Promise.reject(new Error('npx: not found'));
    },
  });

  expect(await runtimes.read('codex', true)).toStrictEqual({
    error: 'npx: not found',
  });
  expect(await runtimes.read('codex', true)).toStrictEqual({
    error: 'npx: not found',
  });
  expect(tries).toStrictEqual(2);
});

test('a runtime that does not answer in time is given up on', async () => {
  let gaveUp = false;
  const runtimes = new Runtimes({
    bound: 20,
    probe: (_runtime, signal) =>
      new Promise((_resolve, reject) =>
        signal.addEventListener('abort', () => {
          gaveUp = true;

          reject(signal.reason);
        }),
      ),
  });

  expect(await runtimes.read('slow', true)).toStrictEqual({
    error: 'it did not open a session within 0.02 s',
  });
  expect(gaveUp).toStrictEqual(true);
});

test('closing the window gives up on a read under way', async () => {
  const runtimes = new Runtimes({
    probe: (_runtime, signal) =>
      new Promise((_resolve, reject) =>
        signal.addEventListener('abort', () => reject(signal.reason)),
      ),
  });
  const reading = runtimes.read('slow', true);

  runtimes.close();

  expect(await reading).toStrictEqual({ error: 'chord is closing' });
});

test("the probe reads the fake agent's two models, three modes and its model's efforts from a session it closes", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-probe-'));

  try {
    const probe = sessionProbe(dir, () => fakeAgentCommand());

    expect(await probe('fake', new AbortController().signal)).toStrictEqual({
      models: {
        available: [
          { id: 'fake-large', name: 'Fake Large with a 1M context window' },
          { id: 'fake-small', name: 'Fake Small' },
        ],
        current: 'fake-large',
      },
      modes: {
        available: [
          { id: 'default', name: 'Default' },
          { id: 'acceptEdits', name: 'Accept edits' },
          { id: 'plan', name: 'Plan' },
        ],
        current: 'default',
      },
      efforts: {
        option: 'effort',
        available: [
          { id: 'low', name: 'Low' },
          { id: 'medium', name: 'Medium' },
          { id: 'high', name: 'High' },
        ],
        current: 'medium',
      },
    });
  } finally {
    await rm(dir, { recursive: true });
  }
});
