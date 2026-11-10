import { afterEach, beforeEach, describe, expect, jest, test } from 'bun:test';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { memorySecrets } from '../../src/platform/secrets.ts';
import {
  fixtureSignedIn,
  fixtureSignIn,
} from '../../src/riff/sign_in_fixture.ts';
import { readProvider } from '../../src/riff/provider_record.ts';
import type { SignInProgress } from '../../src/riff/sign_in.ts';

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'chord-sign-in-fixture-'));
});

afterEach(async () => {
  jest.useRealTimers();
  await rm(root, { recursive: true, force: true });
});

describe('offline QA sign-in', () => {
  test.each(['success', 'failure', 'expired', 'port-taken', 'waiting'])(
    '%s uses only its fake store and no fetch',
    async (outcome) => {
      const store = memorySecrets();
      const steps: SignInProgress[] = [];
      const waiting = Promise.withResolvers<void>();
      const controller = new AbortController();

      jest.useFakeTimers();

      const done = fixtureSignIn(outcome)({
        attempt: 1,
        provider: 'codex',
        way: 'browser',
        store,
        stateDir: root,
        signal: controller.signal,
        fetch: () => {
          throw new Error('fixture must not fetch');
        },
        emit: (_id, step) => {
          steps.push(step);
          waiting.resolve();
        },
      });

      await waiting.promise;

      if (outcome === 'waiting') {
        controller.abort();
      } else {
        jest.advanceTimersByTime(1500);
      }

      await done;
      expect(steps.at(-1)?.kind).toBe(
        outcome === 'success'
          ? 'success'
          : outcome === 'port-taken'
            ? 'port_taken'
            : outcome === 'waiting'
              ? 'browser'
              : outcome,
      );
      expect((await store.get('codex')) === null).toBe(outcome !== 'success');

      if (outcome === 'success') {
        expect(await readProvider(root)).toBe('codex');
      }
    },
  );

  test('fixture transition transfers only fixture provider state to the next child', () => {
    const env: Record<string, string | undefined> = {};

    fixtureSignedIn(env, 'grok');
    expect(env).toEqual({
      CHORD_RIFF_QA: '1',
      CHORD_RIFF_QA_STATE: 'signed-in',
      CHORD_RIFF_QA_PROVIDER: 'grok',
    });
    fixtureSignedIn(env, undefined);
    expect(env['CHORD_RIFF_QA_STATE']).toBe('signed-out');
  });
});
