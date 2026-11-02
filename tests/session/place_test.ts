import { expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  placeOf,
  readPlace,
  type PlaceReading,
} from '../../src/session/place.ts';
import { loadSettings, type SettingsProblem } from '../../src/settings.ts';

async function withDirs(
  body: (dirs: { home: string; here: string; there: string }) => Promise<void>,
) {
  const root = await mkdtemp(join(tmpdir(), 'chord-place-'));

  try {
    const dirs = {
      home: join(root, 'home'),
      here: join(root, 'here'),
      there: join(root, 'there'),
    };

    await Promise.all(
      [dirs.home, join(dirs.here, '.chord'), join(dirs.there, '.chord')].map(
        (dir) => mkdir(dir, { recursive: true }),
      ),
    );
    await body(dirs);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function reading(
  { home, here }: { home: string; here: string },
  flags: PlaceReading['flags'] = {},
) {
  const configHome = join(home, 'chord-config');
  const reported: SettingsProblem[][] = [];
  const loaded = await loadSettings({ configHome, cwd: here, home });

  return {
    reported,
    with: {
      configHome,
      home,
      invokedAs: { agent: 'codex' },
      flags,
      loadedAt: here,
      loaded,
      problems: [...loaded.problems],
      report: (found: SettingsProblem[]) => {
        reported.push(found);

        return Promise.resolve();
      },
    } satisfies PlaceReading,
  };
}

const settings = (dir: string, body: string) =>
  writeFile(join(dir, '.chord', 'settings.json'), body);

test('a directory already loaded is not read again', async () => {
  await withDirs(async (dirs) => {
    const given = await reading(dirs);

    await settings(dirs.here, '{"agents":{"codex":{"model":"written-late"}}}');

    const read = await readPlace(dirs.here, given.with);

    expect(read.cwd).toBe(dirs.here);
    expect(read.model).toBeUndefined();
  });
});

test('another directory speaks for a session working there', async () => {
  await withDirs(async (dirs) => {
    const given = await reading(dirs);

    await settings(dirs.there, '{"agents":{"codex":{"model":"there"}}}');

    const read = await readPlace(dirs.there, given.with);

    expect(read.cwd).toBe(dirs.there);
    expect(read.model?.id).toBe('there');
  });
});

test('each problem is said once, however many directories read it', async () => {
  await withDirs(async (dirs) => {
    const given = await reading(dirs);

    await settings(dirs.there, '{ not json');

    await readPlace(dirs.there, given.with);
    await readPlace(dirs.there, given.with);

    expect(given.reported.map((found) => found.length)).toStrictEqual([1, 0]);
    expect(given.with.problems).toHaveLength(1);
  });
});

test('a place shows its paths as the window does', async () => {
  await withDirs(async (dirs) => {
    const given = await reading(dirs);

    await settings(dirs.there, '{"agents":{"codex":{"model":"there"}}}');

    const place = placeOf(await readPlace(dirs.there, given.with), given.with);

    expect(place.cwd).toBe(dirs.there);
    expect(place.startupOf('codex')?.starting?.model).toStrictEqual({
      id: 'there',
      from: 'set in .chord/settings.json',
    });
  });
});

test("a place's files refuse the window's agent unless a flag gave its command", async () => {
  await withDirs(async (dirs) => {
    await settings(dirs.there, '{"agents":{"codex":{"command":1}}}');

    const refusing = await reading(dirs);
    const refused = placeOf(
      await readPlace(dirs.there, refusing.with),
      refusing.with,
    );

    expect(refused.startupOf('codex')?.refused).toContain(
      'codex not started: agents.codex.command in .chord/settings.json',
    );

    const flagged = await reading(dirs, { agentCommand: 'mine' });
    const given = {
      ...flagged.with,
      invokedAs: { agent: 'codex', agentCommand: 'mine' },
    };
    const started = placeOf(await readPlace(dirs.there, given), given);

    expect(started.startupOf('codex')?.refused).toBeUndefined();
    expect(started.startupOf('codex')?.agentCommand).toBe('mine');
  });
});

test('an agent chord cannot start has no startup', async () => {
  await withDirs(async (dirs) => {
    const given = await reading(dirs);
    const place = placeOf(await readPlace(dirs.there, given.with), given.with);

    expect(place.startupOf('no-such-agent')).toBeUndefined();
  });
});
