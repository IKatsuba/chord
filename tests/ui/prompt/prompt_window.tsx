/**
 * The keys, files and clipboards the prompt's window tests share:
 * `Prompt_test.tsx` and the files split from it (CHD-501).
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { ClipboardReader } from '../../../src/images.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import { until, type Window } from '../app/render.tsx';

export const LEFT = '\x1b[D';

export const BACKSPACE = '\x7f';

/** Makes `paths` in the window's working directory, empty. */
export async function files(window: Window, ...paths: string[]) {
  for (const path of paths) {
    await mkdir(join(window.dir, path, '..'), { recursive: true });
    await writeFile(join(window.dir, path), '');
  }
}

/** A clipboard holding the one-pixel PNG, counting its reads. */
export function pixelClipboard(): ClipboardReader & { reads: number } {
  const read = Object.assign(
    () => {
      read.reads++;

      return Promise.resolve({
        image: {
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        },
      });
    },
    { reads: 0 },
  );

  return read;
}

/** Waits for the session to be up, so the agent has said what it takes. */
export async function connected(window: Window): Promise<void> {
  await until(
    'the session to start',
    () => !window.frame().includes('Starting'),
  );
}

export const RECEIVED = `Received an image: image/png, ${PIXEL_BYTES.length} bytes`;
