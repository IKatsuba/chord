/** Unique-string edits; jsdiff and node:fs implement the shared proposal. */
import { z } from '@zod/zod';
import { propose } from './mutation.ts';

export const EditInput = z
  .object({
    path: z.string().min(1),
    oldString: z.string().min(1),
    newString: z.string(),
  })
  .strict();

export type EditInput = z.infer<typeof EditInput>;

export const EDIT_DESCRIPTION =
  'Replace a unique exact oldString with newString in an existing file. The path is relative to the session directory or absolute. Missing or non-unique strings fail without writing.';

export function edit(path: string, input: EditInput, signal: AbortSignal) {
  return propose(
    path,
    (text) => {
      if (text === null) {
        throw new Error('no such file');
      }

      const first = text.indexOf(input.oldString);

      if (first < 0) {
        throw new Error('oldString was not found in the file');
      }

      if (text.indexOf(input.oldString, first + 1) >= 0) {
        throw new Error('oldString is not unique in the file');
      }

      return (
        text.slice(0, first) +
        input.newString +
        text.slice(first + input.oldString.length)
      );
    },
    signal,
  );
}
