import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  detectManager,
  installArgv,
  ManagerProvider,
  type Manager,
  upgradeCommand,
} from '../src/upgrade.ts';

const BIN = 'node_modules/@chorded/chord-darwin-arm64/bin/chord';

test('the manager is read off where a global install puts the binary', () => {
  const rows: [string, Manager | null][] = [
    [`/var/u/.bun/install/global/${BIN}`, 'bun'],
    [
      `/var/u/Library/pnpm/global/5/node_modules/.pnpm/@chorded+chord-darwin-arm64@0.54.0/${BIN}`,
      'pnpm',
    ],
    [
      `/var/u/.local/share/pnpm/global/v11/abc-1/node_modules/.pnpm/@chorded+chord-linux-x64@0.54.0/node_modules/@chorded/chord-linux-x64/bin/chord`,
      'pnpm',
    ],
    [`/var/u/.config/yarn/global/${BIN}`, 'yarn'],
    [`/opt/homebrew/lib/node_modules/@chorded/chord/${BIN}`, 'npm'],
    [
      '/usr/lib/node_modules/@chorded/chord/node_modules/@chorded/chord-linux-arm64/bin/chord',
      'npm',
    ],
    // Caches, a build from source and a local install are no global install.
    [`/var/u/.npm/_npx/1a2b/${BIN}`, null],
    [`/private/tmp/bunx-501-@chorded/chord@latest/${BIN}`, null],
    ['/var/u/.local/bin/chord', null],
    ['/opt/homebrew/bin/bun', null],
    [`/var/u/src/app/${BIN}`, null],
  ];

  for (const [path, manager] of rows) {
    expect(detectManager(path), path).toBe(manager);
  }
});

test('each manager installs the exact version globally', () => {
  expect(installArgv('npm', '0.55.0')).toStrictEqual([
    'npm',
    'install',
    '--global',
    '@chorded/chord@0.55.0',
  ]);
  expect(installArgv('bun', '0.55.0')).toStrictEqual([
    'bun',
    'add',
    '--global',
    '@chorded/chord@0.55.0',
  ]);
  expect(installArgv('pnpm', '0.55.0')).toStrictEqual([
    'pnpm',
    'add',
    '--global',
    '@chorded/chord@0.55.0',
  ]);
  expect(installArgv('yarn', '0.55.0')).toStrictEqual([
    'yarn',
    'global',
    'add',
    '@chorded/chord@0.55.0',
  ]);
});

/**
 * Upgrades from 0.54.0 to 0.55.0, with what the upgrade says to the person
 * kept in `said` rather than printed among the test run's own lines.
 */
function upgradeWith(provider: ManagerProvider, said: string[] = []) {
  const keep = (...data: unknown[]) => void said.push(data.join(' '));

  provider.setLogger({ log: keep, info: keep, warn: keep, error: keep });

  return provider.upgrade({
    name: 'chord',
    from: '0.54.0',
    to: '0.55.0',
  });
}

test('the upgrade runs the manager that installed chord', async () => {
  const ran: string[][] = [];
  const provider = new ManagerProvider('bun', {}, undefined, (argv) => {
    ran.push([...argv]);

    return Promise.resolve();
  });

  const said: string[] = [];

  await upgradeWith(provider, said);

  expect(ran).toStrictEqual([
    ['bun', 'add', '--global', '@chorded/chord@0.55.0'],
  ]);
  expect(said).toStrictEqual([
    '$ bun add --global @chorded/chord@0.55.0',
    'A chord already running keeps 0.54.0 until it is started again.',
  ]);
});

test('a chord no manager installed is refused with how to upgrade it', async () => {
  let ran = false;
  const provider = new ManagerProvider(
    'npm',
    {},
    '/var/u/.local/bin/chord',
    () => {
      ran = true;

      return Promise.resolve();
    },
  );

  await expect(upgradeWith(provider)).rejects.toThrow(
    'chord cannot tell which package manager installed /var/u/.local/bin/chord. If one did, upgrade with it: npm install --global @chorded/chord@0.55.0, bun add --global @chorded/chord@0.55.0, pnpm add --global @chorded/chord@0.55.0, yarn global add @chorded/chord@0.55.0.',
  );
  expect(ran).toBe(false);
});

test('a manager missing from PATH is said by name', async () => {
  const provider = new ManagerProvider('pnpm', {}, undefined, () =>
    Promise.reject(
      Object.assign(new Error('spawn pnpm ENOENT'), { code: 'ENOENT' }),
    ),
  );

  const said: string[] = [];

  await expect(upgradeWith(provider, said)).rejects.toThrow(
    'pnpm is not on PATH. Install pnpm, or upgrade chord with the manager that installed it.',
  );
  expect(said).toStrictEqual(['$ pnpm add --global @chorded/chord@0.55.0']);
});

test('latest is resolved to an exact version for the manager', async () => {
  const provider = new ManagerProvider('bun', {});

  provider.getVersions = () =>
    Promise.resolve({ latest: '0.56.0', versions: ['0.56.0', '0.55.0'] });

  expect(await provider.resolveVersion('chord', 'latest')).toBe('0.56.0');
  expect(await provider.resolveVersion('chord', '0.55.0')).toBe('0.55.0');
});

describe('the tag chord upgrade follows', () => {
  const DOCUMENT = {
    'dist-tags': {
      latest: '0.67.0',
      next: '1.0.0-next.4',
      beta: '1.0.0-beta.1',
    },
    versions: {
      '0.67.0': {},
      '1.0.0-beta.1': {},
      '1.0.0-next.4': {},
    },
  };
  const realFetch = globalThis.fetch;
  let asked: string[];

  function registry(answer: () => Response): void {
    globalThis.fetch = ((url: URL | string) => {
      asked.push(String(url));

      return Promise.resolve(answer());
    }) as typeof fetch;
  }

  const provider = (running?: string) =>
    new ManagerProvider('bun', {}, undefined, undefined, running);

  beforeEach(() => {
    asked = [];

    registry(() => Response.json(DOCUMENT));
  });

  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  test.each([
    ['0.66.0', '0.67.0'],
    ['1.0.0', '0.67.0'],
    ['1.0.0-next.3', '1.0.0-next.4'],
    ['1.0.0-next.4', '1.0.0-next.4'],
    ['1.0.0-beta.0', '1.0.0-beta.1'],
  ])('a build of %s follows %s', async (running, latest) => {
    expect((await provider(running).getVersions('chord')).latest).toBe(latest);
    expect(await provider(running).resolveVersion('chord', 'latest')).toBe(
      latest,
    );
    expect(new Set(asked)).toStrictEqual(
      new Set(['https://registry.npmjs.org/@chorded/chord']),
    );
  });

  test('a channel lists every version, as a stable build does', async () => {
    const channel = await provider('1.0.0-next.3').getVersions('chord');
    const stable = await provider('0.66.0').getVersions('chord');

    expect(channel.versions).toStrictEqual(stable.versions);
    expect(channel.versions).toStrictEqual([
      '1.0.0-next.4',
      '1.0.0-beta.1',
      '0.67.0',
    ]);
  });

  test('a provider told no version follows latest', async () => {
    expect((await provider().getVersions('chord')).latest).toBe('0.67.0');
  });

  test('a channel with no tag fails naming it, and never falls back to latest', async () => {
    await expect(
      provider('1.0.0-rc.0').resolveVersion('chord', 'latest'),
    ).rejects.toThrow(
      'chord could not read the versions of @chorded/chord from the npm registry: it has no tag rc, the channel this chord is on',
    );
  });

  test('a failed read on a channel says so', async () => {
    registry(() => new Response('', { status: 503 }));

    await expect(provider('1.0.0-next.3').getVersions('chord')).rejects.toThrow(
      'chord could not read the versions of @chorded/chord from the npm registry: the registry answered 503',
    );
  });

  test('a version named is taken as it is, on any build', async () => {
    expect(
      await provider('1.0.0-next.3').resolveVersion('chord', '0.67.0'),
    ).toBe('0.67.0');
    expect(asked).toStrictEqual([]);
  });

  test('a version no channel can have stops the upgrade, not the command', async () => {
    expect(() =>
      upgradeCommand('/var/u/.local/bin/chord', {}, '1.0.0-next'),
    ).not.toThrow();
    await expect(provider('1.0.0-next').getVersions('chord')).rejects.toThrow(
      'a pre-release is written <x.y.z>-<channel>.<n>',
    );
    expect(asked).toStrictEqual([]);
  });

  test('upgradeCommand gives the provider the running version', async () => {
    const command = upgradeCommand(
      '/var/u/.bun/install/global/node_modules/@chorded/chord-darwin-arm64/bin/chord',
      {},
      '1.0.0-beta.0',
    );

    expect(await command.getLatestVersion()).toBe('1.0.0-beta.1');
  });
});
