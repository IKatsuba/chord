import { describe, expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { draw } from '../harness.tsx';
import {
  earlierSessions,
  type EarlierSession,
} from '../../../src/session/sessions.ts';
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

/** `chord --resume` with no id, on `/h/src/app`, and what it was told. */
async function started() {
  const picks: (EarlierSession | undefined)[] = [];
  const app = await draw(
    <Start
      agent='claude'
      directory='~/src/app'
      home='/h'
      cwd='/h/src/app'
      sessions={SESSIONS}
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
    expect(frame()).toContain("Pick one of claude's earlier sessions to open.");
    // Sessions only: a window held several, and chord opens one (CHD-493).
    expect(frame()).toContain('❯ 1. 11 minutes ago  fix the failing date');
    expect(frame()).not.toContain('▣');
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

test('Enter on a session picks it, ctrl+a lists every directory, and Esc quits picking nothing', async () => {
  const picking = await started();

  try {
    await until('the picker', () => picking.frame().includes('❯ 1.'));
    await picking.press('\x01');
    await until('every directory', () =>
      picking.frame().includes('over in the api'),
    );
    await picking.press('\r');
    expect(picking.picks).toStrictEqual([SESSIONS[0]!]);
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

describe('CHD-445 U2 tester: titled start picker navigation and resets', () => {
  const title = Array.from({ length: 180 }, (_, at) => `token${at}`).join(' ');
  const sessions = earlierSessions(
    [
      { id: 'short', title: 'Short named session', cwd: '/work/app' },
      { id: 'tall', title, cwd: '/work/app' },
      { id: 'foreign', title: 'Other directory title', cwd: '/work/elsewhere' },
    ].map((item, index) => ({
      path: `/records/${item.id}.jsonl`,
      sessionId: item.id,
      agent: 'fake',
      cwd: item.cwd,
      lastUsedAt: NOW - (index + 1) * 60_000,
      prompt: `original prompt for ${item.id}`,
      title: item.title,
    })),
    { agent: 'fake' },
  );

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const reset of [false, true]) {
      test(`${reset ? 'height and scope reset a scrolled title' : 'Enter picks the title while its first line is off screen'} at ${columns}×${rows}`, async () => {
        const picks: (EarlierSession | undefined)[] = [];
        const app = await draw(
          <Start
            agent='fake'
            directory='/work/app'
            home={undefined}
            cwd='/work/app'
            sessions={sessions}
            colours={paletteOf('dark', false)}
            keymap={DEFAULT_KEYMAP}
            onPick={(chosen) => picks.push(chosen)}
          />,
          { columns, rows },
        );
        const frame = () => stripAnsi(app.frame());
        const readToEnd = async () => {
          for (let press = 0; !frame().includes('token179'); press++) {
            expect(press).toBeLessThan(80);
            await app.write('j');
          }
        };

        try {
          await until('the titled start picker', () =>
            frame().includes('Short named session'),
          );
          expect(frame()).not.toContain('original prompt');
          expect(frame()).not.toContain('Other directory title');
          await app.write('j');
          await readToEnd();
          expect(frame()).not.toContain('token0 ');
          expect(
            frame()
              .split('\n')
              .filter((line) => line.startsWith('│')).length,
          ).toBeLessThanOrEqual(Math.floor(rows / 4) + 6);

          if (reset) {
            await app.resize({ rows: rows + 4 });
            await until(
              'the highlighted title from its first line after resize',
              () => frame().includes('token0 '),
            );
            await readToEnd();
            await app.resize({ columns: columns === 80 ? 120 : 80 });
            await until(
              'the highlighted title from its first line after a width change',
              () => frame().includes('token0 '),
            );
            await readToEnd();
            await app.write('\x01');
            await until(
              'the new scope from its top',
              () =>
                /❯\s*1\./.test(frame()) &&
                frame().includes('Short named session'),
            );
            expect(frame()).not.toContain('token179');
            await app.write('\r');
            expect(picks[0]?.resume.sessionId).toBe('short');
          } else {
            await app.write('k');
            await app.write('\r');
            expect(picks[0]?.resume.sessionId).toBe('tall');
            expect(picks[0]?.resume.title).toBe(title);
          }

          expect(picks).toHaveLength(1);
        } finally {
          await app.unmount();
        }
      });
    }
  }
});
