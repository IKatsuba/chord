import { expect, test } from 'bun:test';
import { draw } from '../harness.tsx';
import type { OpenSession } from '../../../src/session/conversation.ts';
import { App } from '../../../src/ui/app/App.tsx';
import {
  CTRL_C,
  ESC,
  quitAll,
  ready,
  until,
  withWindow,
} from '../app/render.tsx';

/** chord's window with the splash on, 80×24, on the session `open` gives. */
async function splashWindow(open: OpenSession) {
  const app = await draw(
    <App
      agent='fake'
      cwd='.'
      // Never chord's own state directory, though nothing is sent here.
      stateDir='/nonexistent/chord-state'
      open={open}
      splash
    />,
    { rows: 24, columns: 80 },
  );

  const frame = () => app.frame();
  const shows = (text: string) =>
    until(`"${text}" on screen`, () => frame().includes(text)).catch(
      (error: Error) => {
        throw new Error(`${error.message}; the screen:\n${frame()}`);
      },
    );
  const press = async (key: string) => {
    await app.write(key);
    await new Promise((resolve) => setTimeout(resolve, 50));
  };

  return { app, frame, shows, press };
}

// A start that never ends, so the splash stays.
const hanging: OpenSession = () => new Promise(() => {});

test('the splash holds the screen while the agent starts', async () => {
  const { app, frame, shows } = await splashWindow(hanging);

  try {
    await shows('Starting fake…');

    const lines = frame().split('\n');

    // Centred, as the 80×24 frames have it, and nothing of the window.
    expect(lines[16] ?? '').toContain(' '.repeat(32) + 'Starting fake…');
    expect(
      lines.slice(5, 15).some((line) => line.includes('██████')),
    ).toBeTruthy();
    expect(!frame().includes('chord v'), frame()).toBeTruthy();
    expect(!frame().includes('╭'), frame()).toBeTruthy();
  } finally {
    await app.unmount();
  }
});

test('the mark drifts a step at a time on its own timer', async () => {
  const { app, frame, shows } = await splashWindow(hanging);

  try {
    await shows('Starting fake…');
    // Past the frames the size settling draws.
    await new Promise((resolve) => setTimeout(resolve, 20));

    const first = frame();
    const from = Date.now();

    await until('the next step', () => frame() !== first, 2_000);
    // A step is 300 ms, give or take the timer's start.
    expect(
      Date.now() - from >= 150,
      `stepped after ${Date.now() - from} ms`,
    ).toBeTruthy();
  } finally {
    await app.unmount();
  }
});

test('the splash is cut once the agent is up', () =>
  withWindow(
    async (window) => {
      await ready(window);
      expect(window.frame()).toContain('chord v');
      expect(
        !window.frame().includes('Starting fake…'),
        window.frame(),
      ).toBeTruthy();
      await quitAll(window);
    },
    { columns: 80, rows: 24, splash: true },
  ));

test('keys on the splash are kept for the window, and esc opens it', async () => {
  const { app, frame, shows, press } = await splashWindow(hanging);

  try {
    await shows('Starting fake…');
    await press('hi');
    expect(!frame().includes('hi'), frame()).toBeTruthy();
    await press(ESC);
    await shows('chord v');
    await shows('› hi');
    // The window's own line says the start goes on.
    await shows('Starting fake…');
  } finally {
    await app.unmount();
  }
});

test('ctrl+c on the splash arms the quit as the status line would', async () => {
  const { app, shows, press } = await splashWindow(hanging);

  try {
    await shows('Starting fake…');
    await press(CTRL_C);
    await shows('Press ctrl+c again to quit');
  } finally {
    await app.unmount();
  }
});

test('a failed start cuts to the window and its error', async () => {
  const { app, frame, shows } = await splashWindow(() =>
    Promise.reject(new Error('spawn fake ENOENT')),
  );

  try {
    await shows('fake did not start: spawn fake ENOENT');
    expect(frame()).toContain('chord v');
  } finally {
    await app.unmount();
  }
});
