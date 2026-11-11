import {
  afterEach,
  beforeEach,
  describe,
  expect,
  mock,
  spyOn,
  test,
} from 'bun:test';
import {
  riffAccess,
  QA_ENV,
  QA_STATE_ENV,
  QA_PROVIDER_ENV,
  QA_STORE_ENV,
} from '../../src/riff/qa.ts';
import { FAKE_PROVIDER_ENV } from '../../src/riff/start.ts';
import { memorySecrets } from '../../src/platform/secrets.ts';

let realCalls = 0;

beforeEach(() => {
  realCalls = 0;

  const forbidden = () => {
    realCalls++;

    throw new Error('Real credential store reached by a QA test.');
  };

  spyOn(Bun.secrets, 'get').mockImplementation(forbidden);
  spyOn(Bun.secrets, 'set').mockImplementation(forbidden);
  spyOn(Bun.secrets, 'delete').mockImplementation(forbidden);
});

describe('CHD-606 tester: QA provider network isolation', () => {
  test('both fixture plans answer through their injected fetch without global fetch or a system-store factory', async () => {
    let systemCalls = 0;
    const network = spyOn(globalThis, 'fetch').mockRejectedValue(
      new Error('Global network reached by QA.'),
    );

    for (const provider of ['codex', 'grok']) {
      const access = riffAccess(
        {
          [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
          [QA_ENV]: '1',
          [QA_STATE_ENV]: 'signed-in',
          [QA_PROVIDER_ENV]: provider,
        },
        () => {
          systemCalls++;

          throw new Error('System-store factory reached by QA.');
        },
      );
      const response = await access.fetch(
        provider === 'codex'
          ? 'https://registry.npmjs.org/@openai/codex/latest'
          : 'https://x.ai/cli/stable',
        {},
      );

      expect(response.ok).toBe(true);
      await response.text();
    }

    expect(network).not.toHaveBeenCalled();
    expect(systemCalls).toBe(0);
  });
});

afterEach(() => {
  mock.restore();
  expect(realCalls).toBe(0);
});

describe('riff fixture store isolation', () => {
  test('fake and every QA state never call Bun.secrets', async () => {
    const fake = riffAccess({
      [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
      [QA_STATE_ENV]: 'no-store',
    });

    await fake.secrets.set('codex', 'fixture');
    expect(await fake.secrets.get('codex')).toBe('fixture');
    await fake.secrets.delete('codex');

    for (const state of [
      'signed-in',
      'signed-out',
      'no-store',
      'unsaved',
      'saved',
      'removed',
      'account-changed',
    ]) {
      for (const provider of ['codex', 'grok']) {
        const access = riffAccess({
          [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
          [QA_ENV]: '1',
          [QA_STATE_ENV]: state,
          [QA_PROVIDER_ENV]: provider,
        });

        if (state === 'no-store') {
          await expect(access.secrets.get('codex')).rejects.toThrow(
            'credential store',
          );
        } else {
          expect(access.provider).toBeUndefined();
          expect(
            (await access.secrets.get(
              provider === 'codex' ? 'codex' : 'grok',
            )) === null,
          ).toBe(state === 'signed-out');
        }
      }
    }

    expect(realCalls).toBe(0);
  });

  test('no-store QA names the requested platform and its remedy', async () => {
    for (const [platform, remedy] of [
      ['darwin', 'Keychain Access'],
      ['linux', 'Start one'],
      ['win32', 'Enable the Credential Manager service'],
    ]) {
      const access = riffAccess({
        [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
        [QA_ENV]: '1',
        [QA_STATE_ENV]: 'no-store',
        [QA_STORE_ENV]: platform,
      });

      await expect(access.secrets.get('codex')).rejects.toThrow(remedy);
    }
  });
});

describe("riff's own files by launch", () => {
  const user = () => ({ home: '/fixture/home', configHome: '/fixture/config' });
  const noStore = () => {
    throw new Error('System store reached.');
  };

  test('a real launch reads the home skills and the user AGENTS.md', () => {
    expect(riffAccess({}, memorySecrets, user).user).toEqual(user());
  });

  test('--fake and every --qa launch read neither', () => {
    let reached = 0;
    const counted = () => {
      reached++;

      return user();
    };

    expect(
      riffAccess(
        { [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1' },
        noStore,
        counted,
      ).user,
    ).toEqual({});
    expect(
      riffAccess(
        {
          [FAKE_PROVIDER_ENV]: 'http://localhost:1/v1',
          [QA_ENV]: '1',
          [QA_STATE_ENV]: 'signed-in',
        },
        noStore,
        counted,
      ).user,
    ).toEqual({});
    expect(reached).toBe(0);
  });
});
