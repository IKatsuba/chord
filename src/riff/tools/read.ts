/**
 * riff's `read` (CHD-485, "Tools"): a file, or a range of its lines, with
 * `node:fs`; `file-type` tells a binary file, which is refused. The one
 * tool that reaches a path outside the session's directory.
 */
import { z } from '@zod/zod';
import { fileTypeFromBuffer } from 'file-type';
import { Buffer } from 'node:buffer';
import { createInterface } from 'node:readline';
import { LIMITS } from './limits.ts';
import { openReal } from './paths.ts';

export const ReadInput = z
  .object({
    path: z.string().min(1).describe('The file to read.'),
    offset: z.int().min(1).optional().describe('The first line, from 1.'),
    limit: z.int().min(1).optional().describe('How many lines to return.'),
  })
  .strict();

export type ReadInput = z.infer<typeof ReadInput>;

export const READ_DESCRIPTION = [
  'Read a text file, or a range of its lines. The path is relative to the',
  "session's directory or absolute; a file outside the directory may need",
  "the person's permission. Lines come numbered from 1. Without `limit`,",
  `at most ${LIMITS.readLines} lines; at most ${LIMITS.readBytes / 1024} KiB`,
  `in all, and a line over ${LIMITS.readLineChars} characters is cut. When`,
  'more is left, the answer says which `offset` reads on. Binary files',
  '(images, archives, PDFs and the like) are refused.',
].join(' ');

/** Types file-type names that are text all the same. */
function textual(mime: string): boolean {
  return mime.startsWith('text/') || mime === 'application/xml';
}

/**
 * The lines `input` asks for of the file at `path` (already resolved
 * against the session's directory), numbered as the model reads them.
 */
export async function readLines(
  path: string,
  input: ReadInput,
  signal: AbortSignal,
): Promise<string> {
  signal.throwIfAborted();

  const { real, handle, size } = await openReal(path);

  try {
    const head = new Uint8Array(Math.min(size, LIMITS.sniffBytes));

    await handle.read(head, 0, head.length, 0);

    const type = await fileTypeFromBuffer(head);

    if (type !== undefined && !textual(type.mime)) {
      throw new Error(`${real}: a binary file (${type.mime}); not read`);
    }

    signal.throwIfAborted();

    const first = input.offset ?? 1;
    const count = input.limit ?? LIMITS.readLines;
    const stream = handle.createReadStream({
      encoding: 'utf8',
      autoClose: false,
      start: 0,
    });
    const lines = createInterface({ input: stream, crlfDelay: Infinity });
    const out: string[] = [];
    let number = 0;
    let bytes = 0;
    let more: number | undefined;

    const stop = () => stream.destroy();

    signal.addEventListener('abort', stop, { once: true });

    try {
      for await (const line of lines) {
        number++;

        if (number < first) {
          continue;
        }

        const cut =
          line.length > LIMITS.readLineChars
            ? `${line.slice(0, LIMITS.readLineChars)}…`
            : line;
        const row = `${number}\t${cut}`;

        const size = Buffer.byteLength(row) + 1;

        if (out.length === count || bytes + size > LIMITS.readBytes) {
          more = number;

          break;
        }

        out.push(row);

        bytes += size;
      }
    } finally {
      signal.removeEventListener('abort', stop);
      lines.close();
      stream.destroy();
    }

    signal.throwIfAborted();

    if (out.length === 0) {
      return number === 0
        ? `${real} is empty.`
        : `${real} has ${number} lines; nothing at line ${first}.`;
    }

    return more === undefined
      ? out.join('\n')
      : `${out.join('\n')}\n… more from line ${more}; read on with offset ${more}.`;
  } finally {
    await handle.close();
  }
}
