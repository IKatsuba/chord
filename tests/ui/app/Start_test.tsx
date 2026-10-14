import { expect, test } from 'bun:test';
import { draw } from '../harness.tsx';
import type { EarlierSession } from '../../../src/session/sessions.ts';
import type {
  EarlierWindow,
  ResumeEntry,
} from '../../../src/session/windows.ts';
import { Start } from '../../../src/ui/app/Start.tsx';
import { DEFAULT_KEYMAP } from '../../../src/ui/shortcuts/bindings.ts';
import { paletteOf } from '../../../src/ui/theme/theme.ts';
import { ESC, until } from './render.tsx';

const NOW = Date.now();
const ago = (minutes: number) => new Date(NOW - minutes * 60_000).toISOString();

const SESSIONS: EarlierSession[] = [
  {
    resume: { sessionId: 's1', cwd: '/h/src/app' },
    lastUsedAt: ago(11),
    prompt: 'fix the failing date test',
  },
  {
    resume: { sessionId: 's9', cwd: '/h/src/api' },
    lastUsedAt: ago(30),
    prompt: 'over in the api',
  },
];

const WINDOWS: EarlierWindow[] = [
  {
    id: 'w-1a2b3c4d',
    lastUsedAt: ago(10),
    tabs: [
      { sessionId: 's1', agent: 'claude', cwd: '/h/src/app' },
      { sessionId: 's2', agent: 'codex', cwd: '/h/src/app' },
    ],
    front: 0,
    opening: { tabs: [], front: 0 },
    prompt: 'fix the failing date test',
  },
];

/** `chord --resume` with no id, on `/h/src/app`, and what it was told. */
async function started() {
  const picks: (ResumeEntry | undefined)[] = [];
  const app = await draw(
    <Start
      agent='claude'
      directory='~/src/app'
      home='/h'
      cwd='/h/src/app'
      sessions={SESSIONS}
      windows={WINDOWS}
      colours={paletteOf('dark', false)}
      keymap={DEFAULT_KEYMAP}
      onPick={(chosen) => picks.push(chosen)}
    />,
  );
  const frame = () => app.frame();
  const press = async (key: string) => {
    await app.write(key);
    await new Promise((resolve) => setTimeout(resolve, 50));
  };

  return { app, frame, press, picks };
}

test('chord --resume with no id draws the picker, with no prompt box, before anything is open', async () => {
  const { app, frame } = await started();

  try {
    await until('the picker', () => frame().includes('Resume a session'));
    expect(frame()).toContain('chord');
    expect(frame()).toContain('claude · ~/src/app');
    expect(frame()).toContain(
      "Pick one of claude's earlier sessions, or a saved window, to open.",
    );
    expect(frame()).toContain(
      '❯ 1. 10 minutes ago  ▣ 2 sessions · claude, codex · fix the failing',
    );
    expect(frame()).toContain('2. 11 minutes ago  fix the failing date');
    // Another directory's session waits for ctrl+a.
    expect(!frame().includes('over in the api'), frame()).toBeTruthy();
    expect(frame()).toContain(
      'Enter to resume · Ctrl+a for all directories · Esc to quit',
    );
    expect(!frame().includes('›'), 'a prompt box').toBeTruthy();
  } finally {
    await app.unmount();
  }
});

test('Enter on a window picks it, ctrl+a lists every directory, and Esc quits picking nothing', async () => {
  const picking = await started();

  try {
    await until('the picker', () => picking.frame().includes('❯ 1.'));
    await picking.press('\x01');
    await until('every directory', () =>
      picking.frame().includes('over in the api'),
    );
    await picking.press('\r');
    expect(picking.picks).toStrictEqual([
      { kind: 'window', window: WINDOWS[0]! },
    ]);
  } finally {
    await picking.app.unmount();
  }

  const leaving = await started();

  try {
    await until('the picker', () => leaving.frame().includes('❯ 1.'));
    await leaving.press(ESC);
    expect(leaving.picks).toStrictEqual([undefined]);
    // Picked once: a key after it picks nothing more.
    await leaving.press('\r');
    expect(leaving.picks).toStrictEqual([undefined]);
  } finally {
    await leaving.app.unmount();
  }
});
