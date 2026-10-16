import { expect, test } from 'bun:test';
import {
  detectManager,
  installArgv,
  ManagerProvider,
  type Manager,
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
