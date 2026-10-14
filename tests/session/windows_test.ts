import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  earlierSessions,
  ResumeError,
  resumeMessage,
  type SessionRecord,
} from '../../src/session/sessions.ts';
import {
  capNote,
  earlierWindows,
  entriesIn,
  isWindowId,
  mixedRefusal,
  newWindowId,
  parseWindow,
  readWindow,
  readWindows,
  resumeEntries,
  windowAgents,
  windowDirectory,
  windowIn,
  windowMessage,
  windowOnQuit,
  type WindowRecord,
  windowRoom,
  windowSummary,
  windowTabs,
  windowText,
  writeWindow,
} from '../../src/session/windows.ts';

function record(
  name: string,
  overrides: Partial<SessionRecord> = {},
): SessionRecord {
  return {
    path: `/state/records/${name}.jsonl`,
    sessionId: `id-${name}`,
    agent: 'claude',
    cwd: '/work',
    lastUsedAt: Date.parse('2026-10-01T00:00:00.000Z'),
    prompt: name,
    ...overrides,
  };
}

const AT = Date.parse('2026-10-08T12:00:00.000Z');

const TABS = [
  { agent: 'claude', sessionId: 'id-a', cwd: '/work' },
  { agent: 'codex', sessionId: 'id-b', cwd: '/other' },
  { agent: 'claude', sessionId: 'id-c', cwd: '/other' },
];

test('a window quit with several resumable tabs is recorded, and its record reads back as it was', () => {
  const window = windowOnQuit(TABS, 1, { id: 'w-1a2b3c4d', at: AT });

  expect(window).toStrictEqual({
    id: 'w-1a2b3c4d',
    at: AT,
    tabs: TABS,
    front: 1,
  });
  expect(parseWindow(windowText(window!))).toStrictEqual(window);
  expect(windowMessage('w-1a2b3c4d')).toStrictEqual(
    'Resume this window with:\nchord --resume w-1a2b3c4d',
  );
});

test('one resumable tab is no window: its own command is printed, as before', () => {
  const [only] = TABS;

  expect(windowOnQuit([only!], 0, { id: 'w-1', at: AT })).toStrictEqual(
    undefined,
  );
  expect(windowOnQuit([], 0, { id: 'w-1', at: AT })).toStrictEqual(undefined);
  expect(resumeMessage([only!])).toStrictEqual(
    'Resume this session with:\nchord claude --resume id-a',
  );
});

test('a window id is told from a session id by its prefix, and a made one has it', () => {
  expect(isWindowId('w-1a2b3c4d')).toBeTruthy();
  expect(!isWindowId('1a2b3c4d-0000-4000-8000-000000000000')).toBeTruthy();
  expect(!isWindowId('ses_w-1')).toBeTruthy();
  expect(newWindowId()).toMatch(/^w-[0-9a-f]{8}$/);
  expect(mixedRefusal('w-1a2b3c4d').message).toStrictEqual(
    'Window w-1a2b3c4d opens on its own; --resume takes it without session ids.',
  );
});

test('what is not a window record is not read as one', () => {
  const good = windowText({ id: 'w-1', at: AT, tabs: TABS, front: 0 });

  expect(parseWindow('not json')).toStrictEqual(undefined);
  expect(parseWindow('{}')).toStrictEqual(undefined);
  expect(parseWindow(good.replace('"front": 0', '"front": 3'))).toStrictEqual(
    undefined,
  );
  expect(parseWindow(good.replace('"w-1"', '"../x"'))).toStrictEqual(undefined);
});

test('a window opened from its record and quit again rewrites the record, grown or shrunk, under the same id', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-windows-'));

  try {
    const first = windowOnQuit(TABS, 2, { id: newWindowId(), at: AT })!;

    await writeWindow(stateDir, first);
    expect(await readWindow(stateDir, first.id)).toStrictEqual(first);

    // Opened from it, one tab closed, then quit: the id it was opened by.
    const again = windowOnQuit(TABS.slice(0, 2), 0, {
      id: first.id,
      at: AT + 1000,
    })!;

    await writeWindow(stateDir, again);
    expect(await readWindow(stateDir, first.id)).toStrictEqual(again);

    const files = [
      ...readdirSync(join(stateDir, 'windows'), { withFileTypes: true }),
    ].map(({ name }) => name);

    expect(files).toStrictEqual([`${first.id}.json`]);
  } finally {
    await rm(stateDir, { recursive: true });
  }
});

test('a window chord has no record of, or an id it could not have made, is refused', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-windows-'));

  try {
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
  } finally {
    await rm(stateDir, { recursive: true });
  }
});

test("a window's tabs open in order on their recorded agents, the recorded one in front", () => {
  const window: WindowRecord = { id: 'w-1', at: AT, tabs: TABS, front: 1 };
  const records = [
    record('a'),
    record('b', { agent: 'codex', cwd: '/other' }),
    record('c', { cwd: '/other' }),
  ];
  const opened = windowTabs(records, window, {
    agent: 'claude',
    named: false,
  });

  expect(
    opened.tabs.map(({ agent, resume }) => [
      resume.sessionId,
      agent,
      resume.cwd,
      resume.record,
    ]),
  ).toStrictEqual([
    ['id-a', 'claude', '/work', '/state/records/a.jsonl'],
    ['id-b', 'codex', '/other', '/state/records/b.jsonl'],
    ['id-c', 'claude', '/other', '/state/records/c.jsonl'],
  ]);
  expect(opened.front).toStrictEqual(1);
  expect(opened.note).toStrictEqual(undefined);
});

test('a window whose session record is gone opens the rest and says which one is missing', () => {
  const records = [record('a'), record('c', { cwd: '/other' })];
  const gone = (front: number) =>
    windowTabs(
      records,
      { id: 'w-1', at: AT, tabs: TABS, front },
      {
        agent: 'claude',
        named: false,
      },
    );

  expect(gone(2).tabs.map(({ resume }) => resume.sessionId)).toStrictEqual([
    'id-a',
    'id-c',
  ]);
  // The recorded front tab keeps the front, where it now is.
  expect(gone(2).front).toStrictEqual(1);
  // The missing one was in front: the first comes forward.
  expect(gone(1).front).toStrictEqual(0);
  expect(gone(0).note).toStrictEqual(
    'Not reopened: codex tab id-b, its record is gone',
  );

  expect(
    windowTabs(
      [record('a')],
      { id: 'w-1', at: AT, tabs: TABS, front: 0 },
      {
        agent: 'claude',
        named: false,
      },
    ).note,
  ).toStrictEqual(
    'Not reopened: 2 tabs whose records are gone (codex id-b, claude id-c)',
  );

  // A session id as agents give them is cut to the eight characters the
  // status line has room for.
  expect(
    windowTabs(
      records,
      {
        id: 'w-1',
        at: AT,
        tabs: [
          ...TABS.slice(0, 1),
          { ...TABS[1]!, sessionId: 'f6b72576-96ae-4cfe-8e4b-08d16c4342b4' },
        ],
        front: 0,
      },
      { agent: 'claude', named: false },
    ).note,
  ).toStrictEqual('Not reopened: codex tab f6b72576, its record is gone');
});

test('a window with none of its sessions left, or of an agent other than the one named, is refused', () => {
  const window: WindowRecord = { id: 'w-1', at: AT, tabs: TABS, front: 0 };
  const refused = (records: SessionRecord[], named: boolean) => {
    try {
      windowTabs(records, window, { agent: 'claude', named });
    } catch (error) {
      assert(error instanceof ResumeError);

      return error.message;
    }

    throw new Error('the window opened');
  };

  expect(refused([], false)).toStrictEqual(
    "None of window w-1's sessions is among chord's records.",
  );
  expect(
    refused([record('a'), record('b', { agent: 'codex' })], true),
  ).toStrictEqual('Session id-b belongs to another agent (codex).');
});

/** A window of `agents`, each tab a session of its own in `cwd`. */
function windowOf(agents: string[], cwd = '/work') {
  return {
    tabs: agents.map((agent, index) => ({
      sessionId: `id-${index}`,
      agent,
      cwd,
    })),
    front: 0,
  };
}

test("a window's agents are named in tab order, then counted, then cut at a comma with how many are left", () => {
  expect(windowAgents(['claude', 'codex', 'claude'])).toStrictEqual(
    'claude, codex, claude',
  );
  // Past 30 columns, each once in the order it first came, with how many.
  expect(
    windowAgents(['claude', 'codex', 'claude', 'claude', 'codex', 'gemini']),
  ).toStrictEqual('claude ×3, codex ×2, gemini');
  // Still too long: the last are counted, and no name is cut in half.
  expect(
    windowAgents([
      'claude',
      'claude',
      'codex',
      'claude',
      'gemini',
      'claude',
      'codex',
      'opencode',
      'claude',
    ]),
  ).toStrictEqual('claude ×5, codex ×2, gemini +1');
  expect(
    windowAgents(['a-very-long-agent-name', 'another-long-agent-name']),
  ).toStrictEqual('a-very-long-agent-name +1');
});

test("a window's summary counts its sessions and how many are open, before its agents", () => {
  const window = windowOf(['claude', 'codex', 'claude']);

  expect(windowSummary(window, 0)).toStrictEqual(
    '▣ 3 sessions · claude, codex, claude',
  );
  expect(windowSummary(window, 2)).toStrictEqual(
    '▣ 3 sessions, 2 open · claude, codex, claude',
  );
  expect(windowSummary(window, 3)).toStrictEqual(
    '▣ 3 sessions, all open · claude, codex, claude',
  );
});

test("a window's directory is its front tab's, with +n for the others, which is never what is cut", () => {
  const shown = (cwd: string, width: number) =>
    cwd.length <= width ? cwd : `…${cwd.slice(cwd.length - width + 1)}`;
  const window = {
    tabs: [
      { sessionId: 'a', agent: 'claude', cwd: '/src/api' },
      { sessionId: 'b', agent: 'codex', cwd: '/src/app' },
      { sessionId: 'c', agent: 'claude', cwd: '/src/app' },
      { sessionId: 'd', agent: 'claude', cwd: '/src/web' },
    ],
    front: 1,
  };

  expect(windowDirectory(window, shown, 30)).toStrictEqual('/src/app +2');
  expect(windowDirectory(window, shown, 8)).toStrictEqual('…/app +2');
  expect(
    windowDirectory(windowOf(['claude', 'codex'], '/src/app'), shown, 30),
  ).toStrictEqual('/src/app');
});

test('windows and sessions are one list by time, each window just above its own sessions', () => {
  const records = [
    record('a', { lastUsedAt: AT - 60_000, prompt: 'fix the parser' }),
    record('b', { lastUsedAt: AT - 120_000, agent: 'codex' }),
    record('c', { lastUsedAt: AT - 3_600_000 }),
    record('d', { lastUsedAt: AT - 86_400_000 }),
    record('e', { lastUsedAt: AT - 90_000_000, cwd: '/other' }),
  ];
  const windows = earlierWindows(
    [
      {
        id: 'w-old',
        at: AT - 86_400_000 + 1000,
        tabs: [
          { sessionId: 'id-d', agent: 'claude', cwd: '/work' },
          { sessionId: 'id-e', agent: 'claude', cwd: '/other' },
        ],
        front: 0,
      },
      {
        id: 'w-new',
        at: AT,
        tabs: [
          { sessionId: 'id-a', agent: 'claude', cwd: '/work' },
          { sessionId: 'id-b', agent: 'codex', cwd: '/work' },
        ],
        front: 0,
      },
      // None of its sessions has a record left: Enter would open nothing.
      {
        id: 'w-gone',
        at: AT,
        tabs: [
          { sessionId: 'id-x', agent: 'claude', cwd: '/work' },
          { sessionId: 'id-y', agent: 'claude', cwd: '/work' },
        ],
        front: 0,
      },
    ],
    records,
  );

  expect(windows.map(({ id }) => id)).toStrictEqual(['w-new', 'w-old']);
  expect(windows[0]!.prompt).toStrictEqual('fix the parser');
  expect(windows[0]!.lastUsedAt).toStrictEqual(new Date(AT).toISOString());

  const entries = resumeEntries(
    earlierSessions(records, { agent: 'claude' }),
    windows,
  );
  const named = entries.map((entry) =>
    entry.kind === 'window' ? entry.window.id : entry.session.resume.sessionId,
  );

  // The codex session is not claude's, but its window is listed all the same.
  expect(named).toStrictEqual([
    'w-new',
    'id-a',
    'id-c',
    'w-old',
    'id-d',
    'id-e',
  ]);
  // A window is this directory's only when every one of its tabs is.
  expect(windowIn(windows[0]!, '/work')).toStrictEqual(true);
  expect(windowIn(windows[1]!, '/work')).toStrictEqual(false);
  expect(
    entriesIn(entries, '/work').map((entry) =>
      entry.kind === 'window'
        ? entry.window.id
        : entry.session.resume.sessionId,
    ),
  ).toStrictEqual(['w-new', 'id-a', 'id-c', 'id-d']);
});

test('the cap counts the tabs open, an empty front tab given up, and the tabs not open already', () => {
  // Seven open, a three-tab window: one too many.
  expect(windowRoom({ open: 7, reused: false, needed: 3 })).toStrictEqual({
    needs: 3,
    free: 2,
    fits: false,
  });
  // The empty front tab gives its place.
  expect(windowRoom({ open: 7, reused: true, needed: 3 }).fits).toStrictEqual(
    true,
  );
  // A fresh window takes nine.
  expect(windowRoom({ open: 1, reused: true, needed: 9 }).fits).toStrictEqual(
    true,
  );
  expect(windowRoom({ open: 9, reused: false, needed: 2 })).toStrictEqual({
    needs: 2,
    free: 0,
    fits: false,
  });
});

test("the cap's refusal says what is needed and how many to close, shorter where the line is narrow", () => {
  expect(capNote({ needs: 3, free: 2 }, 'ctrl+x k', 120)).toStrictEqual(
    'That window needs 3 tabs and 2 are free · close 1 with ctrl+x k, then /resume again',
  );
  expect(capNote({ needs: 3, free: 2 }, 'ctrl+x k', 80)).toStrictEqual(
    'That window needs 3 tabs, 2 are free · close 1 with ctrl+x k first',
  );
  expect(capNote({ needs: 2, free: 0 }, 'ctrl+x k', 80)).toStrictEqual(
    'That window needs 2 tabs, none are free · close 2 with ctrl+x k first',
  );
  expect(capNote({ needs: 2, free: 1 }, undefined, 80)).toStrictEqual(
    'That window needs 2 tabs, 1 is free · close 1 first',
  );
});

test('every window record in the state directory is read, and what is not one is left out', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    expect(await readWindows(stateDir)).toStrictEqual([]);

    const window = windowOnQuit(TABS, 0, { id: 'w-1a2b3c4d', at: AT })!;

    await writeWindow(stateDir, window);
    await writeFile(join(stateDir, 'windows', 'w-bad.json'), '{');
    // A record under another file's name is not the window it names.
    await writeFile(
      join(stateDir, 'windows', 'w-other.json'),
      windowText(window),
    );
    expect(await readWindows(stateDir)).toStrictEqual([window]);
  } finally {
    await rm(stateDir, { recursive: true });
  }
});
