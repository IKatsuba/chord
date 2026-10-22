import { expect, test } from 'bun:test';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  DIMCODE_NOTICE,
  dimcodeAtRisk,
  dismissNotice,
  dismissedNotices,
  noticesFile,
  NoticeWatch,
} from '../src/notices.ts';

const permission = (current: string) => ({
  id: 'permission',
  name: 'Permission',
  current,
  values: ['read-only', 'workspace-write', 'full-access'].map((value) => ({
    value,
    name: value,
  })),
});

test("dimcode's notice is due once its permission is at anything but read-only, from dimcode alone (CHD-434)", () => {
  expect(dimcodeAtRisk('dimcode', [permission('full-access')])).toBe(true);
  expect(dimcodeAtRisk('dimcode', [permission('workspace-write')])).toBe(true);
  expect(dimcodeAtRisk('dimcode', [permission('read-only')])).toBe(false);
  expect(dimcodeAtRisk('dimcode', [])).toBe(false);
  expect(dimcodeAtRisk('codex', [permission('full-access')])).toBe(false);
});

test('each session comes due on its own way out of read-only, whatever another is at, and anew after going back (CHD-434)', () => {
  const watch = new NoticeWatch();

  expect(watch.heard('a', 'dimcode', [permission('read-only')])).toBe(false);
  expect(watch.heard('a', 'dimcode', [permission('full-access')])).toBe(true);
  // Still there, and from one value at risk to another: not again.
  expect(watch.heard('a', 'dimcode', [permission('full-access')])).toBe(false);
  expect(watch.heard('a', 'dimcode', [permission('workspace-write')])).toBe(
    false,
  );
  // Another session, while the first is at risk, is due of its own.
  expect(watch.heard('b', 'dimcode', [permission('full-access')])).toBe(true);
  expect(watch.heard('a', 'dimcode', [permission('read-only')])).toBe(false);
  expect(watch.atRisk('a')).toBe(false);
  expect(watch.heard('a', 'dimcode', [permission('full-access')])).toBe(true);
  expect(watch.heard('c', 'codex', [permission('full-access')])).toBe(false);
});

test('a session closed is at risk no longer, so a read finishing after applies to none', () => {
  const watch = new NoticeWatch();

  watch.heard('a', 'dimcode', [permission('full-access')]);
  expect(watch.atRisk('a')).toBe(true);
  watch.gone('a');
  expect(watch.atRisk('a')).toBe(false);
});

test('its dismissal is recorded beside the user settings file, others kept, and read back', async () => {
  const home = await mkdtemp(join(tmpdir(), 'chord-notices-'));
  const file = noticesFile(home)!;

  try {
    expect(file).toBe(join(home, 'chord', 'notices.json'));
    expect(noticesFile(undefined)).toBe(undefined);
    expect([...(await dismissedNotices(file))]).toStrictEqual([]);

    await dismissNotice(file, 'another');
    await dismissNotice(file, DIMCODE_NOTICE);
    await dismissNotice(file, DIMCODE_NOTICE);

    expect([...(await dismissedNotices(file))]).toStrictEqual([
      'another',
      DIMCODE_NOTICE,
    ]);
    expect(JSON.parse(await readFile(file, 'utf8'))).toStrictEqual({
      dismissed: ['another', DIMCODE_NOTICE],
    });

    // A record that does not read shows the notice again, never throws.
    await writeFile(file, '{ not json');
    expect([...(await dismissedNotices(file))]).toStrictEqual([]);
    await writeFile(file, JSON.stringify({ dismissed: 'all' }));
    expect([...(await dismissedNotices(file))]).toStrictEqual([]);
    expect([...(await dismissedNotices(undefined))]).toStrictEqual([]);
  } finally {
    await rm(home, { recursive: true });
  }
});
