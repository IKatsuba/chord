import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { riffStore, type Sidecar } from '../../src/riff/store.ts';

let stateDir: string;

const SIDECAR: Sidecar = {
  provider: 'fake',
  account: null,
  model: 'fake',
  effort: 'default',
  mode: 'ask',
};

beforeEach(async () => {
  stateDir = await mkdtemp(join(tmpdir(), 'chord-riff-store-'));
});

afterEach(async () => {
  await rm(stateDir, { recursive: true, force: true });
});

describe('tester: riff sidecar boundaries', () => {
  test('two sessions keep distinct sidecars across store instances', async () => {
    const store = riffStore(stateDir);

    await store.write('wrun_first', SIDECAR);
    await store.write('wrun_second', { ...SIDECAR, mode: 'auto' });
    await store.write('wrun_first', { ...SIDECAR, effort: 'low' });

    const reopened = riffStore(stateDir);

    expect(await reopened.read('wrun_first')).toStrictEqual({
      ...SIDECAR,
      effort: 'low',
    });
    expect(await reopened.read('wrun_second')).toStrictEqual({
      ...SIDECAR,
      mode: 'auto',
    });
    expect(
      (await readdir(join(stateDir, 'riff', 'sidecars'))).sort(),
    ).toStrictEqual(['wrun_first.json', 'wrun_second.json']);
  });

  test.each(['', '../outside', 'wrun/nested', 'a'.repeat(129)])(
    'invalid session id %p cannot read or write a sidecar',
    async (id) => {
      const store = riffStore(stateDir);

      expect(await store.read(id)).toBeUndefined();
      await expect(store.write(id, SIDECAR)).rejects.toThrow(
        'Not a riff session id',
      );
    },
  );
});

describe('CHD-611 tester: prior sidecar effort compatibility', () => {
  test.each(['default', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'])(
    'a raw sidecar with %s remains readable without model-level filtering',
    async (effort) => {
      const store = riffStore(stateDir);

      await store.write('wrun_legacy', SIDECAR);

      const sidecar = { ...SIDECAR, model: 'grok-4.5', effort };

      await writeFile(
        join(stateDir, 'riff', 'sidecars', 'wrun_legacy.json'),
        JSON.stringify(sidecar),
      );
      expect(await riffStore(stateDir).read('wrun_legacy')).toStrictEqual(
        sidecar,
      );
    },
  );
});
