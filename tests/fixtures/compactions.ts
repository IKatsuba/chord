/**
 * What the fake agent's `compact` scenario streams as its compaction's
 * summary, chunk by chunk, as Claude's adapter streams the model's text.
 */
export const COMPACT_SUMMARY = [
  '## Summary\n\n',
  'The person asked for a README section on install, ',
  'then for the tests to run.\n\n',
  '- Read `README.md` and `deno.json`\n',
  '- Wrote the install section with `deno task install`\n',
  '- Ran `deno task test`: 3 passed\n\n',
  'Next: commit the change.',
];

/** Why the `compactfail` scenario's compaction failed, as Claude says it. */
export const COMPACT_ERROR = 'Not enough messages to compact.';
