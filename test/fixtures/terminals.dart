// What the fake agent's `shell` and `bash` scenarios' commands write, as
// the original's tests/fixtures/terminals.ts has it: a line a progress
// count rewrites with `\r`, pieces that end mid-line, and a colour and a
// hyperlink whose escapes a piece ends inside.

/// The most of each stream chord keeps, as the original's
/// src/session/context.ts has it; here so the fake reads nothing of the
/// app.
const outputLimit = 30000;

/// What `shell`'s command writes, piece by piece.
const shellOutput = [
  'Task test deno test\n',
  'running 3 tests\n1/3',
  '\r2/3\r3/3\n\x1b[3',
  '2mok\x1b[0m | 2 passed\n\x1b]8;;https://example.com/failed',
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed\n',
];

/// What `shellcut`'s command writes: a hyperlink whose URL alone runs past
/// [outputLimit], its end in the next piece, then the link's text.
final List<String> cutOutput = [
  'Task test deno test\n',
  '\x1b]8;;https://example.com/${'u' * outputLimit}',
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed',
];

/// What `bash`'s command writes.
const bashOutput = ' M src/main.tsx\n?? notes.md\n';
