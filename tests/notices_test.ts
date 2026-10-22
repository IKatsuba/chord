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
  const at = (id: string, value: string, agent = 'dimcode') =>
    watch.heard(id, agent, [permission(value)]);

  expect(at('a', 'read-only')).toBe(undefined);

  const first = at('a', 'full-access');

  expect(first).toBeNumber();
  // Still there, and from one value at risk to another: not again.
  expect(at('a', 'full-access')).toBe(undefined);
  expect(at('a', 'workspace-write')).toBe(undefined);
  expect(watch.holds('a', first!)).toBe(true);

  // Another session, while the first is at risk, is due of its own.
  const other = at('b', 'full-access');

  expect(other).toBeNumber();
  expect(other).not.toBe(first);
  expect(at('a', 'read-only')).toBe(undefined);
  expect(watch.holds('a', first!)).toBe(false);
  expect(watch.holds('b', other!)).toBe(true);
  expect(at('a', 'full-access')).toBeNumber();
  expect(at('c', 'full-access', 'codex')).toBe(undefined);
});

test('a read that finishes after its session closed, was cleared, or came due again holds for none but the latest (CHD-434)', () => {
  const watch = new NoticeWatch();
  const full = [permission('full-access')];
  const held = watch.heard('main:1', 'dimcode', full)!;

  // Cleared: the session after it, under the same id, at full-access too.
  watch.gone('main:1');
  expect(watch.holds('main:1', held)).toBe(false);

  const next = watch.heard('main:1', 'dimcode', full)!;

  expect(next).not.toBe(held);
  // The read begun before the clear still finds nothing to show for.
  expect(watch.holds('main:1', held)).toBe(false);
  expect(watch.holds('main:1', next)).toBe(true);
  watch.gone('main:1');
  expect(watch.holds('main:1', next)).toBe(false);
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
