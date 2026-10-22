/**
 * The fake agent's `markdown` reply: one of each block a reply draws, with a
 * table wide enough to be cut at 80 columns and a code block inside a list.
 * It streams line by line, and waits inside an open code fence twice: at the
 * top level, `MARKDOWN_OPEN_FENCE` lines in, and in the list,
 * `MARKDOWN_OPEN_NESTED_FENCE` lines in.
 */
export const MARKDOWN_LINES = [
  '# Reading the session layer',
  '',
  'The **session layer** wraps *the SDK* so the interface never touches a',
  'process. Start with `src/session/session.ts`, then see the',
  '[ACP spec](https://agentclientprotocol.com) for the wire format.',
  '',
  '## What it does',
  '',
  '- opens one persistent session per chord session',
  '- starts turns with `startTurn` and cancels them',
  '  1. a cancel stops the turn at once',
  '  2. the agent is told with `session/cancel`',
  '- closes the agent and waits until its exit is seen',
  '',
  '> A closed agent counts as gone only once its exit is seen:',
  '>',
  '> ```ts',
  '> await session.close(); // resolves once the exit is seen',
  '> ```',
  '',
  '| Module | Holds | Tested by |',
  '| --- | --- | --- |',
  '| `session.ts` | opening, prompting and closing a session | `session_test.ts` |',
  '| `processes.ts` | the promise that a closed agent is gone | `processes_test.ts` |',
  '| `transcript.ts` | the reducer from events to what is drawn | `transcript_test.ts` |',
  '',
  '```ts',
  "const session = await openSession({ agent: 'claude', cwd });",
  "const turn = session.prompt('hello');",
  'await turn.result;',
  '```',
  '',
  'That is the whole loop. To land a change:',
  '',
  '1. Run the checks:',
  '   ```sh',
  '   deno task check',
  '   ```',
  '2. Commit on `main` once every check has passed and the tree is clean, so whoever picks the work up next starts from a build that runs.',
  '',
  'Then build the binary with:',
  '',
  '```sh',
  'deno task compile --all',
  'for bin in dist/*/chord; do echo "built $bin"; done',
  '```',
];

/**
 * Lines sent before the reply first waits: the fence and one line of code,
 * the least a box is drawn around.
 */
export const MARKDOWN_OPEN_FENCE = MARKDOWN_LINES.indexOf('```ts') + 2;

/** Lines sent before it waits again, inside the fence in the list. */
export const MARKDOWN_OPEN_NESTED_FENCE =
  MARKDOWN_LINES.indexOf('   ```sh') + 2;

export const MARKDOWN_REPLY = MARKDOWN_LINES.join('\n');

/**
 * The fake agent's `markdownwrap` reply (`docs/design/CHD-396.md`): a
 * heading, a list nested three deep, a quote and a paragraph each long
 * enough to wrap at 80 columns, a two-digit marker, task items, and a soft
 * and a hard line break.
 */
export const MARKDOWN_WRAP = [
  '## A heading long enough that at eighty columns it has to wrap onto a second row of its own',
  '',
  '- package.json:3: the package @chorded/chord at version 0.54.1 needs Bun 1.4.2 or newer. check runs check:static and then the tests.',
  '  - a nested item long enough to wrap at eighty columns, whose wrapped lines should hang under its own text',
  '    1. deeper still, a numbered item that also runs past the edge of the window so its hang shows too',
  '- a short item',
  '',
  '> A quote whose paragraph is long enough to wrap inside its bar at eighty columns, and at a hundred and twenty too, once it runs on.',
  '',
  '8. eight',
  '9. nine',
  '10. ten, with a two-digit marker and text long enough to wrap so the hang under a wider marker shows',
  '',
  '- [ ] open task',
  '- [x] done task',
  '',
  'Soft',
  'break and a hard  ',
  'break here.',
].join('\n');
