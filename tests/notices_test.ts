import { describe, expect, test } from 'bun:test';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  DIMCODE_NOTICE,
  dimcodeAtRisk,
  dismissNotice,
  dismissedNotices,
  noticesFile,
  NoticeGate,
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

describe('CHD-434 U1 tester: machine records and independent eligibility', () => {
  test('a late ticket cannot cross session ids or survive lost eligibility, even after repeated id reuse', () => {
    const watch = new NoticeWatch();
    const tickets: number[] = [];
    const other = watch.heard('other', 'dimcode', [
      permission('workspace-write'),
    ])!;

    for (let cycle = 0; cycle < 30; cycle++) {
      const ticket = watch.heard('reused', 'dimcode', [
        permission('full-access'),
      ])!;

      expect(ticket).toBeNumber();
      expect(tickets).not.toContain(ticket);
      expect(watch.holds('other', ticket)).toBe(false);
      tickets.push(ticket);
      expect(
        watch.heard('reused', 'dimcode', [permission('workspace-write')]),
      ).toBeUndefined();
      expect(watch.holds('reused', ticket)).toBe(true);

      if (cycle % 3 === 0) {
        watch.gone('reused');
      } else if (cycle % 3 === 1) {
        watch.heard('reused', 'dimcode', []);
      } else {
        watch.heard('reused', 'fake', [permission('full-access')]);
      }

      for (const stale of tickets) {
        expect(watch.holds('reused', stale)).toBe(false);
      }

      expect(watch.holds('other', other)).toBe(true);
    }
  });

  test('future permission values remain eligible, while a similarly named option or runtime does not', () => {
    expect(dimcodeAtRisk('dimcode', [permission('future-access')])).toBe(true);
    expect(
      dimcodeAtRisk('dimcode', [
        { ...permission('full-access'), id: 'permissionMode' },
      ]),
    ).toBe(false);
    expect(dimcodeAtRisk('Dimcode', [permission('full-access')])).toBe(false);

    const watch = new NoticeWatch();
    const ticket = watch.heard('a', 'dimcode', [permission('future-access')])!;

    watch.heard('a', 'dimcode', [permission('read-only')]);
    expect(watch.holds('a', ticket)).toBe(false);
  });

  test('empty and structurally corrupt records fail open; a failed write leaves no temporary record', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-corrupt-'));
    const file = join(dir, 'notices.json');

    try {
      for (const text of [
        '',
        'null',
        '[]',
        '{"dismissed":[1]}',
        '{"dismissed":null}',
      ]) {
        await writeFile(file, text);
        expect([...(await dismissedNotices(file))]).toEqual([]);
      }

      await rm(file);
      await mkdir(file);
      await expect(dismissedNotices(file)).rejects.toThrow();
      await expect(dismissNotice(file, DIMCODE_NOTICE)).rejects.toThrow();
      expect(await readdir(dir)).toEqual(['notices.json']);
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  test('dismissal is shared within one user directory, not another machine directory or the project', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-notice-machines-'));
    const first = noticesFile(join(dir, 'one'))!;
    const second = noticesFile(join(dir, 'two'))!;

    try {
      await dismissNotice(first, 'unrelated');
      await dismissNotice(first, DIMCODE_NOTICE);
      expect((await dismissedNotices(first)).has(DIMCODE_NOTICE)).toBe(true);
      expect((await dismissedNotices(second)).has(DIMCODE_NOTICE)).toBe(false);
      expect([...(await dismissedNotices(first))]).toEqual([
        'unrelated',
        DIMCODE_NOTICE,
      ]);
      expect((await readdir(dir)).sort()).toEqual(['one']);
    } finally {
      await rm(dir, { recursive: true });
    }
  });
});

describe("CHD-434: the window's gate between the record's reads and its write", () => {
  /** A read or write held until the test lets it go. */
  const held = <T>() => Promise.withResolvers<T>();
  const always = () => true;

  test('a read begun before 1 that finds the record empty shows nothing', async () => {
    const read = held<ReadonlySet<string>>();
    const gate = new NoticeGate(
      () => read.promise,
      () => Promise.resolve(),
    );
    const due = gate.due(DIMCODE_NOTICE, always);

    await gate.dismiss(DIMCODE_NOTICE);
    read.resolve(new Set());
    expect(await due).toBe(false);
  });

  test('while 1 is still being written, another session coming due shows nothing', async () => {
    const write = held<void>();
    const gate = new NoticeGate(
      () => Promise.resolve(new Set()),
      () => write.promise,
    );
    const dismissed = gate.dismiss(DIMCODE_NOTICE);

    // The rename has not landed: the record still reads empty.
    expect(await gate.due(DIMCODE_NOTICE, always)).toBe(false);
    write.resolve();
    await dismissed;
    expect(await gate.due(DIMCODE_NOTICE, always)).toBe(false);
  });

  test('a write that fails gives it back, to show the next time it comes due, and no read begun before shows it', async () => {
    const write = held<void>();
    const read = held<ReadonlySet<string>>();
    let reads = 0;
    const gate = new NoticeGate(
      () => (reads++ === 0 ? read.promise : Promise.resolve(new Set())),
      () => write.promise,
    );
    const before = gate.due(DIMCODE_NOTICE, always);
    const dismissed = gate.dismiss(DIMCODE_NOTICE);

    write.reject(new Error('read-only file system'));
    await dismissed;
    read.resolve(new Set());
    expect(await before).toBe(false);
    expect(await gate.due(DIMCODE_NOTICE, always)).toBe(true);
  });

  test('a session come due while the write is pending is spent, though the write then fails; the next one shows it', async () => {
    const write = held<void>();
    const read = held<ReadonlySet<string>>();
    let reads = 0;
    const gate = new NoticeGate(
      () => (reads++ === 0 ? read.promise : Promise.resolve(new Set())),
      () => write.promise,
    );
    const dismissed = gate.dismiss(DIMCODE_NOTICE);
    const during = gate.due(DIMCODE_NOTICE, always);

    write.reject(new Error('read-only file system'));
    await dismissed;
    read.resolve(new Set());
    expect(await during).toBe(false);
    expect(await gate.due(DIMCODE_NOTICE, always)).toBe(true);
  });

  test('a record that does not read shows it; one that names it, or a session no longer at risk, does not', async () => {
    const failing = new NoticeGate(
      () => Promise.reject(new Error('EISDIR')),
      () => Promise.resolve(),
    );

    expect(await failing.due(DIMCODE_NOTICE, always)).toBe(true);
    expect(await failing.due(DIMCODE_NOTICE, () => false)).toBe(false);

    const recorded = new NoticeGate(
      () => Promise.resolve(new Set([DIMCODE_NOTICE])),
      () => Promise.resolve(),
    );

    expect(await recorded.due(DIMCODE_NOTICE, always)).toBe(false);
  });
});
