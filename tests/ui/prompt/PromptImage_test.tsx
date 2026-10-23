/**
 * Images in the prompt: ctrl+v, bracketed pastes, typed and pasted paths,
 * their placeholders, and a clipboard read while an agent starts.
 */
import { describe, expect, test } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { openSession } from '../../../src/session/session.ts';
import type { ClipboardReader } from '../../../src/images.ts';
import { fakeAgentCommand, gatedCommand } from '../../fixtures/fake.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import {
  CTRL_C,
  CTRL_R,
  DOWN,
  ESC,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

import {
  LEFT,
  BACKSPACE,
  pixelClipboard,
  connected,
  RECEIVED,
} from './prompt_window.tsx';

const CTRL_V = '\x16';
const CTRL_W = '\x17';
const CTRL_Y = '\x19';
const CTRL_Z = '\x1a';

test('ctrl+v puts the clipboard image in the prompt and sends it with the text', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('ctrl+v on an empty clipboard says so in the status line', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('No image in the clipboard');
      expect(!window.frame().includes('[Image #')).toBeTruthy();
      await window.type('x');
      await until(
        'the message to go',
        () => !window.frame().includes('No image in the clipboard'),
      );
    },
    {
      clipboard: () => Promise.resolve({ failed: 'No image in the clipboard' }),
    },
  ));

test('ctrl+v says when the agent takes no images, and reads nothing', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('fake does not take images');
      expect(clipboard.reads).toStrictEqual(0);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

/** A clipboard holding no image, counting its reads. */
function emptyClipboard(): ClipboardReader & { reads: number } {
  const read = Object.assign(
    () => {
      read.reads++;

      return Promise.resolve({ failed: 'No image in the clipboard' });
    },
    { reads: 0 },
  );

  return read;
}

test('an empty bracketed paste puts the clipboard image at the cursor', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      // cmd+V of an image-only clipboard, as Ghostty sends it.
      await window.paste('');
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('an empty bracketed paste cut across two reads is still one', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('\x1b[200~\x1b[2');
      await window.type('01~');
      await window.shows('› [Image #1]');
    },
    { clipboard: pixelClipboard() },
  ));

test('an empty bracketed paste of an empty clipboard changes nothing and says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.type('keep');
      await window.shows('› keep');

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
      // The draft and its cursor are as they were.
      await window.type('s');
      await window.shows('› keeps');
    },
    { clipboard },
  );
});

test('an empty bracketed paste says when the agent takes no images, only of an image', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste('');
      await window.shows('fake does not take images');
      expect(clipboard.reads).toStrictEqual(1);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

test('an empty bracketed paste of nothing to an agent that takes no images says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await connected(window);

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

test('a bracketed paste of text is the text, and reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste('hello there');
      await window.shows('› hello there');
      expect(!window.frame().includes('[Image #'), window.frame()).toBeTruthy();
      expect(clipboard.reads).toStrictEqual(0);
    },
    { clipboard },
  );
});

test('a bracketed paste of an image path goes in as the image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.paste("'/shots/my shot.png' ");
      await window.shows('› [Image #1]');
    },
    {
      readImage: () =>
        Promise.resolve({
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        }),
    },
  ));

test('in normal mode an empty bracketed paste puts the image at the cursor, as ctrl+v does', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      await window.paste('');
      await window.shows('› kee [Image #1] p');
      expect(clipboard.reads).toStrictEqual(1);
      await window.press(CTRL_V);
      await until('the second read', () => clipboard.reads === 2);
      await window.shows('[Image #2]');
    },
    { clipboard, vim: true },
  );
});

test('in normal mode an empty bracketed paste of an empty clipboard changes nothing and says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
    },
    { clipboard, vim: true },
  );
});

test('in normal mode a bracketed paste of text reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      // Dropped: Ink ran it as normal mode's keys, so a pasted x deleted.
      await window.paste('x');
      await new Promise((resolve) => setTimeout(resolve, 200));

      const draft = window
        .frame()
        .split('\n')
        .find((line) => line.includes('› '));

      expect(draft?.replace(/│/g, '').trim()).toStrictEqual('› keep');
      expect(clipboard.reads).toStrictEqual(0);
    },
    { clipboard, vim: true },
  );
});

test('an empty bracketed paste on the search line reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_R);
      await window.shows('search prompts:');
      await window.paste('');
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(clipboard.reads).toStrictEqual(0);
      expect(!window.frame().includes('[Image #'), window.frame()).toBeTruthy();
    },
    { clipboard },
  );
});

test('deleting the placeholder sends the prompt without its image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('› [Image #1]');
      await window.press(CTRL_C);
      await send(window, 'text');
      await window.shows('came in chunks');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test('backspace after a placeholder takes it whole, image and all', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');

      // Back past ` this?`, to just after the `]`.
      for (let step = 0; step < 6; step++) {
        await window.press(LEFT);
      }

      await window.press(BACKSPACE);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image #'),
      );
      // The cursor is where the placeholder was, not where the textarea left it.
      await window.type('x');
      await window.press('\r');
      await window.shows('› what is x this?');
      await window.shows('came in chunks');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test('a pasted path to an image file goes in as the image', () => {
  const asked: string[] = [];

  return withWindow(
    async (window) => {
      await connected(window);
      // One write, as a terminal pastes a dropped file.
      await window.type("'/shots/my shot.png' ");
      await window.shows('› [Image #1]');
      expect(asked).toStrictEqual(['/shots/my shot.png']);
      await window.type('see');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    {
      readImage: (path) => {
        asked.push(path);

        return Promise.resolve({
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        });
      },
    },
  );
});

test('a typed path to an image file goes as the image when sent', () =>
  withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.shows('› see /shots/a.png');
      await window.press('\r');
      await window.shows('› see [Image #1]');
      await window.shows(RECEIVED);
    },
    {
      readImage: () =>
        Promise.resolve({
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        }),
    },
  ));

/** A file reader that holds each read until the test lets it go. */
function heldReader() {
  const waiting: (() => void)[] = [];

  return {
    waiting,
    readImage: () =>
      new Promise<{ mediaType: string; data: string; bytes: number }>(
        (resolve) =>
          waiting.push(() =>
            resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
          ),
      ),
  };
}

test('a draft typed while a typed path is read stays once the prompt goes', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await until('the read', () => reader.waiting.length === 1);
      await window.type(' next');
      reader.waiting[0]?.();
      await window.shows('› see [Image #1]');
      await window.shows(RECEIVED);
      await window.shows('› see /shots/a.png next');
    },
    { readImage: reader.readImage },
  );
});

test('Enter again while a typed path is read sends the prompt once', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await window.press('\r');
      await until('the read', () => reader.waiting.length > 0);
      reader.waiting.forEach((release) => release());
      await window.shows(RECEIVED);
      await until('the turn to end', () => !window.frame().includes('Working'));
      expect(reader.waiting.length).toStrictEqual(1);
      expect(window.frame().split(RECEIVED).length).toStrictEqual(2);
    },
    { readImage: reader.readImage },
  );
});

test('a typed path read while another tab comes forward goes from its own tab', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await until('the read', () => reader.waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      reader.waiting[0]?.();
      await leader(window, '1');
      await window.shows('› see [Image #1]');
      await window.shows(RECEIVED);
      expect(
        !window.frame().includes('see /shots/a.png'),
        'the draft stayed',
      ).toBeTruthy();
      await leader(window, '2');
      await until('the second tab', () => !window.frame().includes(RECEIVED));
      expect(
        !window.frame().includes('[Image #1]'),
        'the image went to tab 2',
      ).toBeTruthy();
      await quitAll(window);
    },
    { columns: 120, rows: 40, readImage: reader.readImage },
  );
});

test('a clipboard image read while another tab comes forward goes into its own draft', () => {
  const waiting: (() => void)[] = [];
  const clipboard: ClipboardReader = () =>
    new Promise((resolve) =>
      waiting.push(() =>
        resolve({
          image: {
            mediaType: 'image/png',
            data: PIXEL_PNG,
            bytes: PIXEL_BYTES.length,
          },
        }),
      ),
    );

  return withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await until('the read', () => waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      waiting[0]?.();
      await leader(window, '1');
      await window.shows('› what is [Image #1]');
      await leader(window, '2');
      await until('the second tab', () => !window.frame().includes('what is'));
      expect(
        !window.frame().includes('[Image #1]'),
        'the image went to tab 2',
      ).toBeTruthy();
      await quitAll(window);
    },
    { columns: 120, rows: 40, clipboard },
  );
});

test('a pasted image path read while another tab comes forward goes into its own draft (CHD-128)', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste("'/shots/a.png'");
      await until('the read', () => reader.waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await window.type('tab two draft');
      await window.shows('› tab two draft');
      reader.waiting[0]?.();
      // The finish has no mark of its own on tab 2; a pause lets it land.
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(promptRow(window)).toContain('› tab two draft');
      expect(window.frame()).not.toContain('[Image #');
      await leader(window, '1');
      await window.shows('› [Image #1]');
      expect(window.frame()).not.toContain('/shots/a.png');
      await window.press('\r');
      await window.shows(RECEIVED);
      await leader(window, '2');
      await window.shows('› tab two draft');
      expect(window.frame()).not.toContain('Received an image');
      expect(window.frame()).not.toContain('[Image #');
      // A draft left in the box would take ctrl+d as a key, not a quit.
      await window.press(CTRL_C);
      await until(
        'the draft to clear',
        () => !window.frame().includes('tab two draft'),
      );
      await quitAll(window);
    },
    { columns: 120, rows: 40, readImage: reader.readImage },
  );
});

test('a recalled prompt sends its image again', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.type('once');
      await window.press('\r');
      await window.shows(RECEIVED);
      await until('the turn to end', () => !window.frame().includes('Working'));
      await window.press(UP);
      await window.shows('› [Image #1] once');
      await window.press('\r');
      await until(
        'the second acknowledgement',
        () => window.frame().split(RECEIVED).length > 2,
      );
    },
    { clipboard: pixelClipboard() },
  ));

test('an interrupt gives a queued prompt back with its image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await send(window, 'slow');
      await window.press(CTRL_V);
      await window.type('later');
      await window.press('\r');
      await window.shows('[Image #1] later');
      await window.press(ESC);
      await window.shows('› [Image #1] later');
      await until(
        'the turn to end',
        () => !window.frame().includes('Interrupting'),
      );
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('ctrl+w straight after a paste takes the placeholder whole (CHD-302 part 3)', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('cut');
      await window.press(CTRL_V);
      await window.shows('› cut [Image #1]');
      // The paste's own trailing space is in the word ctrl+w takes.
      await window.press(CTRL_W);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image'),
      );
      await window.type('x');
      await window.press('\r');
      await window.shows('› cut x');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test("the placeholder ctrl+w took is the textarea's to undo and redo, and comes back with its image", () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('cut');
      await window.press(CTRL_V);
      await window.shows('› cut [Image #1]');
      await window.press(CTRL_W);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image'),
      );
      await window.press(CTRL_Z);
      await window.shows('› cut [Image #1]');
      await window.press(CTRL_Y);
      await until(
        'the placeholder to go again',
        () => !window.frame().includes('Image'),
      );
      await window.press(CTRL_Z);
      await window.shows('› cut [Image #1]');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

describe('ctrl+v while an agent starts says so only until it has started, or failed to (CHD-490)', () => {
  const NO_IMAGE: ClipboardReader = () =>
    Promise.resolve({ failed: 'No image in the clipboard' });

  /**
   * A window of `size` whose second agent, codex, is a tab opened by `/new`
   * or a child of main, picked; its agent runs `codex` once `body` has
   * written the gate it is given.
   */
  async function onCodex(
    size: { readonly columns: number; readonly rows: number },
    as: 'tab' | 'child',
    codex: readonly string[],
    body: (window: Window, open: () => Promise<void>) => Promise<void>,
    clipboard: ClipboardReader = NO_IMAGE,
  ): Promise<void> {
    const gates = await mkdtemp(join(tmpdir(), 'chord-gate-'));
    const gate = join(gates, 'open');
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    const command = fakeAgentCommand();

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          if (as === 'tab') {
            await window.type('/new codex');
            await window.press('\r');
          } else {
            if (main === undefined) {
              throw new Error('main was not admitted');
            }

            await main.window.open(main.key, {
              agent: 'codex',
              name: 'foreign',
              prompt: 'text',
            });
            await window.shows('foreign');
            await window.press(DOWN);
            await window.press(DOWN);
            await window.press('\r');
            await window.shows('╭─ foreign ─');
          }

          await window.shows('Starting codex…');
          await body(window, () => writeFile(gate, ''));
        },
        {
          ...size,
          server,
          clipboard,
          runtimes: ['fake', 'codex'],
          agentCommand: command,
          startupOf: (agent) => ({
            agentCommand:
              agent === 'codex' ? gatedCommand(gate, codex) : command,
          }),
        },
      );
    } finally {
      await server.close();
      await rm(gates, { recursive: true, force: true });
    }
  }

  for (const size of [
    { columns: 120, rows: 40 },
    { columns: 80, rows: 24 },
  ]) {
    const at = `${size.columns}x${size.rows}`;

    for (const as of ['tab', 'child'] as const) {
      test(`at ${at}, a ${as}'s notice goes once its agent has started`, () =>
        onCodex(size, as, fakeAgentCommand(), async (window, open) => {
          await window.press(CTRL_V);
          await window.shows('codex has not started yet');
          await open();
          await until(
            'the start',
            () => !window.frame().includes('Starting codex…'),
          );
          await until(
            'the notice to go',
            () => !window.frame().includes('codex has not started yet'),
          );
        }));

      test(`at ${at}, a ${as}'s notice goes once its agent has failed to start`, () =>
        onCodex(size, as, ['sh', '-c', 'exit 1'], async (window, open) => {
          await window.press(CTRL_V);
          await window.shows('codex has not started yet');
          await open();
          await window.shows('codex did not start');
          expect(window.frame()).not.toContain('codex has not started yet');
        }));

      for (const [outcome, codex, after] of [
        ['started', fakeAgentCommand(), 'the start'],
        ['failed to start', ['sh', '-c', 'exit 1'], 'the failure'],
      ] as const) {
        test(`at ${at}, an empty paste in a ${as} read while its agent ${outcome} says nothing of the start`, async () => {
          // The clipboard answers only once the agent has started, or not.
          const held =
            Promise.withResolvers<Awaited<ReturnType<ClipboardReader>>>();

          await onCodex(
            size,
            as,
            codex,
            async (window, open) => {
              await window.paste('');
              await open();
              await until(
                after,
                () => !window.frame().includes('Starting codex…'),
              );
              held.resolve({
                image: {
                  mediaType: 'image/png',
                  data: PIXEL_PNG,
                  bytes: PIXEL_BYTES.length,
                },
              });
              await new Promise((resolve) => setTimeout(resolve, 300));
              expect(window.frame()).not.toContain('codex has not started yet');

              if (outcome === 'started') {
                await until(
                  'the image',
                  () => promptRow(window)?.includes('[Image #1]') ?? false,
                );
              }
            },
            () => held.promise,
          );
        });
      }

      test(`at ${at}, a ${as}'s empty clipboard once started is said until a key`, () =>
        onCodex(size, as, fakeAgentCommand(), async (window, open) => {
          await open();
          await until(
            'the start',
            () => !window.frame().includes('Starting codex…'),
          );
          await window.press(CTRL_V);
          await window.shows('No image in the clipboard');
          await new Promise((resolve) => setTimeout(resolve, 300));
          expect(window.frame()).toContain('No image in the clipboard');
          await window.type('x');
          await until(
            'the notice to go',
            () => !window.frame().includes('No image in the clipboard'),
          );
        }));
    }
  }
});

describe('CHD-490 tester: delayed startup clipboard stays with its conversation', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    {
      for (const fails of [false, true]) {
        test(`a child that ${fails ? 'fails' : 'starts'} preserves another session's notice at ${columns}×${rows}`, async () => {
          const gates = await mkdtemp(join(tmpdir(), 'chord-paste-session-'));
          const gate = join(gates, 'open');
          const server = serveChord();
          const admit = server.admit.bind(server);
          let main: Parameters<typeof admit>[0] | undefined;
          const command = fakeAgentCommand();
          const held =
            Promise.withResolvers<Awaited<ReturnType<ClipboardReader>>>();
          let reads = 0;
          let readFinished = false;

          void held.promise.then(() => {
            readFinished = true;
          });

          let finished = false;
          let childReplied = false;
          const notice = 'The parent clipboard has no image';

          server.admit = (caller) => {
            if (caller.role === 'person') {
              main = caller;
            }

            return admit(caller);
          };

          try {
            await withWindow(
              async (window) => {
                await ready(window);
                {
                  if (main === undefined) {
                    throw new Error('main was not admitted');
                  }

                  await main.window.open(main.key, {
                    agent: 'codex',
                    name: 'foreign',
                    prompt: 'text',
                  });
                  await window.shows('foreign');
                  await window.press(DOWN);
                  await window.press(DOWN);
                  await window.press('\r');
                }

                await window.shows('Starting codex…');
                await window.paste('');
                await until(
                  'the original clipboard read waits',
                  () => reads === 1,
                );
                {
                  await window.press(DOWN);
                  await window.press(UP);
                  await window.press('\r');
                  await until(
                    'the parent is shown',
                    () => !window.frame().includes('╭─ foreign ─'),
                  );
                }

                await window.press(CTRL_V);
                await window.shows(notice);
                expect(readFinished).toBe(false);
                await writeFile(gate, '');
                await until('the background startup settles', () => finished);

                if (!fails) {
                  await until(
                    'the child replies to its initial prompt',
                    () => childReplied,
                  );
                }

                expect(readFinished).toBe(false);
                expect(reads).toBe(2);
                held.resolve({
                  image: {
                    mediaType: 'image/png',
                    data: PIXEL_PNG,
                    bytes: PIXEL_BYTES.length,
                  },
                });
                await window.shows(notice);
                expect(promptRow(window)).not.toContain('[Image #1]');
                expect(window.frame()).not.toContain(
                  'codex has not started yet',
                );
                {
                  await window.press(DOWN);
                  await window.press(DOWN);
                  await window.press('\r');
                  await window.shows('╭─ foreign ─');
                }

                if (fails) {
                  await window.shows('codex did not start:');
                  expect(promptRow(window)).not.toContain('[Image #1]');
                } else {
                  await until(
                    'the image stays in its original conversation',
                    () => promptRow(window)?.includes('[Image #1]') ?? false,
                  );
                  await window.press('\r');
                  await window.shows(RECEIVED);
                }

                expect(window.frame()).not.toContain(
                  'codex has not started yet',
                );
                await window.type('x');
                await until(
                  'editing clears the ordinary notice',
                  () => !window.frame().includes(notice),
                );
              },
              {
                server,
                columns,
                rows,
                runtimes: ['fake', 'codex'],
                agentCommand: command,
                startupOf: (agent) => ({
                  agentCommand:
                    agent === 'codex'
                      ? gatedCommand(
                          gate,
                          fails ? ['sh', '-c', 'exit 1'] : command,
                        )
                      : command,
                }),
                clipboard: () => {
                  reads += 1;

                  return reads === 1
                    ? held.promise
                    : Promise.resolve({ failed: notice });
                },
                openWith: (options) => {
                  const opening = openSession(options);

                  if (options.agent !== 'codex') {
                    return opening;
                  }

                  return opening.then(
                    (session) => {
                      session.subscribe((update) => {
                        if (update.sessionUpdate === 'agent_message_chunk') {
                          childReplied = true;
                        }
                      });

                      finished = true;

                      return session;
                    },
                    (error: unknown) => {
                      finished = true;

                      throw error;
                    },
                  );
                },
              },
            );
          } finally {
            held.resolve({ failed: 'test finished' });
            await rm(gates, { recursive: true, force: true });
            await server.close();
          }
        });
      }
    }
  }
});
