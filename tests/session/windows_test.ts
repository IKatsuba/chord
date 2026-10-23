import { expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ResumeError } from '../../src/session/sessions.ts';
import {
  isWindowId,
  parseWindow,
  readWindow,
  windowGone,
  type WindowRecord,
  windowsDir,
} from '../../src/session/windows.ts';

const AT = Date.parse('2026-10-08T12:00:00.000Z');

const TABS = [
  { agent: 'claude', sessionId: 'id-a', cwd: '/work' },
  { agent: 'codex', sessionId: 'id-b', cwd: '/work/my app' },
  { agent: 'claude', sessionId: 'id-c', cwd: '/other' },
];

/** A window record as 0.54.0–0.57.0 wrote it: pretty JSON, a newline last. */
function written(record: WindowRecord): string {
  return `${JSON.stringify(record, null, 2)}\n`;
}

test('a window id is told from a session id by its prefix', () => {
  expect(isWindowId('w-1a2b3c4d')).toBeTruthy();
  expect(!isWindowId('1a2b3c4d-0000-4000-8000-000000000000')).toBeTruthy();
  expect(!isWindowId('ses_w-1')).toBeTruthy();
});

test('what is not a window record is not read as one', () => {
  const good = written({ id: 'w-1', at: AT, tabs: TABS, front: 0 });

  expect(parseWindow(good)).toStrictEqual({
    id: 'w-1',
    at: AT,
    tabs: TABS,
    front: 0,
  });
  expect(parseWindow('not json')).toStrictEqual(undefined);
  expect(parseWindow('{}')).toStrictEqual(undefined);
  expect(parseWindow(good.replace('"front": 0', '"front": 3'))).toStrictEqual(
    undefined,
  );
  expect(parseWindow(good.replace('"w-1"', '"../x"'))).toStrictEqual(undefined);
});

test('a window chord wrote before 0.58.0 reads back; one it has no record of, an id it could not have made or one it cannot read is refused', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-windows-'));

  try {
    const record = { id: 'w-1a2b3c4d', at: AT, tabs: TABS, front: 1 };

    await mkdir(windowsDir(stateDir), { recursive: true });
    await writeFile(
      join(windowsDir(stateDir), `${record.id}.json`),
      written(record),
    );
    expect(await readWindow(stateDir, record.id)).toStrictEqual(record);

    const unknown = readWindow(stateDir, 'w-00000000');

    await expect(unknown).rejects.toThrow(ResumeError);
    await expect(unknown).rejects.toThrow(
      "No window w-00000000 among chord's records.",
    );

    const forged = readWindow(stateDir, 'w-../../records/x');

    await expect(forged).rejects.toThrow(ResumeError);
    await expect(forged).rejects.toThrow(
      "No window w-../../records/x among chord's records.",
    );

    await writeFile(join(windowsDir(stateDir), 'w-broken.json'), '{');

    const broken = readWindow(stateDir, 'w-broken');

    await expect(broken).rejects.toThrow(ResumeError);
    await expect(broken).rejects.toThrow(
      "Window w-broken's record cannot be read.",
    );
  } finally {
    await rm(stateDir, { recursive: true });
  }
});

test("--resume w-… says each session back as a command of its own, in tab order, in its tab's directory, a quoted one too", () => {
  expect(
    windowGone({ id: 'w-1a2b3c4d', at: AT, tabs: TABS, front: 2 }).split('\n'),
  ).toStrictEqual([
    'w-1a2b3c4d was a window of 3 sessions; chord opens one session per run now. Resume each with:',
    'chord claude --cwd /work --resume id-a',
    "chord codex --cwd '/work/my app' --resume id-b",
    'chord claude --cwd /other --resume id-c',
  ]);
});

test('a tab whose session record is gone is said all the same, in its own directory, which --resume alone would not reach', () => {
  // windowGone reads no session record: each tab is said as the window kept
  // it, so one chord has no record of goes to its agent in its directory.
  expect(
    windowGone({
      id: 'w-gone',
      at: AT,
      tabs: [{ agent: 'codex', sessionId: 'id-lost', cwd: '/elsewhere' }],
      front: 0,
    }),
  ).toStrictEqual(
    'w-gone was a window of 1 session; chord opens one session per run now. Resume it with:\n' +
      'chord codex --cwd /elsewhere --resume id-lost',
  );
});
