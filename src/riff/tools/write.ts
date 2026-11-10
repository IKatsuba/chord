/** Whole-file writes, including a new file under an existing parent. */
import { z } from '@zod/zod';
import { propose } from './mutation.ts';

export const WriteInput = z
  .object({ path: z.string().min(1), content: z.string() })
  .strict();

export type WriteInput = z.infer<typeof WriteInput>;

export const WRITE_DESCRIPTION =
  'Write the whole file content, replacing an existing file or creating a new file under an existing parent directory. The path is relative to the session directory or absolute.';

export function write(path: string, input: WriteInput, signal: AbortSignal) {
  return propose(path, () => input.content, signal);
}
