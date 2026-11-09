/**
 * The Worker that holds one fff finder (CHD-485, "Tools"). fff's calls are
 * synchronous FFI and its first grep can hold a thread for seconds, so they
 * run here, off the main thread; `fff.ts` is the side that talks to it.
 */
import { FileFinder, type Result } from '@ff-labs/fff-bun';
import type { FffReply, FffRequest } from './fff.ts';

declare const self: Worker;

/** How long the first scan may take before calls run on a partial index. */
const SCAN_MS = 30_000;

let finder: Promise<FileFinder> | undefined;

function open(basePath: string): Promise<FileFinder> {
  finder ??= (async () => {
    const made = FileFinder.create({ basePath, aiMode: true });

    if (!made.ok) {
      throw new Error(made.error);
    }

    // A scan cut by its bound still answers, on what it has indexed.
    await made.value.waitForScan(SCAN_MS);

    return made.value;
  })();

  return finder;
}

function value<T>(result: Result<T>): T {
  if (!result.ok) {
    throw new Error(result.error);
  }

  return result.value;
}

async function answer(request: FffRequest): Promise<unknown> {
  // Nothing to destroy is no reason to scan.
  if (request.op === 'destroy' && finder === undefined) {
    return null;
  }

  const found = await open(request.basePath);

  switch (request.op) {
    case 'grep':
      return value(found.grep(request.query, request.options));
    case 'glob':
      return value(found.glob(request.pattern, request.options));
    case 'directorySearch':
      return value(found.directorySearch(request.query, request.options));
    case 'destroy':
      found.destroy();

      return null;
  }
}

self.onmessage = async ({ data }: MessageEvent<FffRequest>) => {
  let reply: FffReply;

  try {
    reply = { id: data.id, ok: true, value: await answer(data) };
  } catch (error) {
    reply = {
      id: data.id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }

  self.postMessage(reply);
};
