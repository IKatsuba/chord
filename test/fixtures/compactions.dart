// What the fake agent's `compact` scenario streams as its compaction's
// summary, chunk by chunk, and why `compactfail`'s fails, as the
// original's tests/fixtures/compactions.ts has them.

/// The summary's chunks, as Claude's adapter streams the model's text.
const compactSummary = [
  '## Summary\n\n',
  'The person asked for a README section on install, ',
  'then for the tests to run.\n\n',
  '- Read `README.md` and `deno.json`\n',
  '- Wrote the install section with `bun install`\n',
  '- Ran `bun dev test`: 3 passed\n\n',
  'Next: commit the change.',
];

/// Why the `compactfail` scenario's compaction failed, as Claude says it.
const compactError = 'Not enough messages to compact.';
