/**
 * What the `shell` scenario's command writes, piece by piece: a line a
 * progress count rewrites with `\r`, pieces that end mid-line, and a colour
 * and a hyperlink whose escapes a piece ends inside.
 */
import { OUTPUT_LIMIT } from '../../src/session/context.ts';

export const SHELL_OUTPUT = [
  'Task test deno test\n',
  'running 3 tests\n1/3',
  '\r2/3\r3/3\n\x1b[3',
  '2mok\x1b[0m | 2 passed\n\x1b]8;;https://example.com/failed',
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed\n',
];

/**
 * What the `shellcut` scenario's command writes: a hyperlink whose URL alone
 * runs past `OUTPUT_LIMIT`, its end in the next piece, then the link's text.
 * The URL is never text, so it counts for nothing against the bound and
 * the line before it stays.
 */
export const CUT_OUTPUT = [
  'Task test deno test\n',
  `\x1b]8;;https://example.com/${'u'.repeat(OUTPUT_LIMIT)}`,
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed',
];

/** What the `bash` scenario's command writes. */
export const BASH_OUTPUT = ' M src/main.tsx\n?? notes.md\n';
