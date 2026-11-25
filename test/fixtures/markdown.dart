// The fake agent's markdown replies, as the original's
// tests/fixtures/markdown.ts has them: `markdown` streams [markdownLines]
// line by line and waits inside an open code fence twice, at the top level,
// [markdownOpenFence] lines in, and in the list, [markdownOpenNestedFence]
// lines in.

/// The `markdown` reply, a line each.
const markdownLines = [
  "# Reading the session layer",
  "",
  "The **session layer** wraps *the SDK* so the interface never touches a",
  "process. Start with `src/session/session.ts`, then see the",
  "[ACP spec](https://agentclientprotocol.com) for the wire format.",
  "",
  "## What it does",
  "",
  "- opens one persistent session per chord session",
  "- starts turns with `startTurn` and cancels them",
  "  1. a cancel stops the turn at once",
  "  2. the agent is told with `session/cancel`",
  "- closes the agent and waits until its exit is seen",
  "",
  "> A closed agent counts as gone only once its exit is seen:",
  ">",
  "> ```ts",
  "> await session.close(); // resolves once the exit is seen",
  "> ```",
  "",
  "| Module | Holds | Tested by |",
  "| --- | --- | --- |",
  "| `session.ts` | opening, prompting and closing a session | `session_test.ts` |",
  "| `processes.ts` | the promise that a closed agent is gone | `processes_test.ts` |",
  "| `transcript.ts` | the reducer from events to what is drawn | `transcript_test.ts` |",
  "",
  "```ts",
  "const session = await openSession({ agent: 'claude', cwd });",
  "const turn = session.prompt('hello');",
  "await turn.result;",
  "```",
  "",
  "That is the whole loop. To land a change:",
  "",
  "1. Run the checks:",
  "   ```sh",
  "   bun quality",
  "   ```",
  "2. Commit on `main` once every check has passed and the tree is clean, so whoever picks the work up next starts from a build that runs.",
  "",
  "Then build the binary with:",
  "",
  "```sh",
  "bun dev compile --all",
  "for bin in dist/*/chord; do echo \"built \$bin\"; done",
  "```",
];

/// Lines sent before the reply first waits.
final markdownOpenFence = markdownLines.indexOf("```ts") + 2;

/// Lines sent before it waits again, inside the fence in the list.
final markdownOpenNestedFence = markdownLines.indexOf("   ```sh") + 2;

/// The `markdown` reply whole.
final markdownReply = markdownLines.join("\n");

/// The `markdownwrap` reply (CHD-396).
const markdownWrap =
    "## A heading long enough that at eighty columns it has to wrap onto a second row of its own"
    '\n'
    ""
    '\n'
    "- package.json:3: the package @chorded/chord at version 0.54.1 needs Bun 1.4.2 or newer. check runs check:static and then the tests."
    '\n'
    "  - a nested item long enough to wrap at eighty columns, whose wrapped lines should hang under its own text"
    '\n'
    "    1. deeper still, a numbered item that also runs past the edge of the window so its hang shows too"
    '\n'
    "- a short item"
    '\n'
    ""
    '\n'
    "> A quote whose paragraph is long enough to wrap inside its bar at eighty columns, and at a hundred and twenty too, once it runs on."
    '\n'
    ""
    '\n'
    "8. eight"
    '\n'
    "9. nine"
    '\n'
    "10. ten, with a two-digit marker and text long enough to wrap so the hang under a wider marker shows"
    '\n'
    ""
    '\n'
    "- [ ] open task"
    '\n'
    "- [x] done task"
    '\n'
    ""
    '\n'
    "Soft"
    '\n'
    "break and a hard  "
    '\n'
    "break here.";

/// The `markdowncode` reply (CHD-396).
const markdownCode =
    "A paragraph before the code."
    '\n'
    ""
    '\n'
    "```typescript"
    '\n'
    "x"
    '\n'
    "```"
    '\n'
    ""
    '\n'
    "```sh"
    '\n'
    "bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p > /tmp/screen.txt"
    '\n'
    ""
    '\n'
    "echo done"
    '\n'
    "```"
    '\n'
    ""
    '\n'
    "- a loose item"
    '\n'
    ""
    '\n'
    "- a loose item with a box:"
    '\n'
    ""
    '\n'
    "  ```sh"
    '\n'
    "  bun dev check"
    '\n'
    "  ```"
    '\n'
    ""
    '\n'
    "A paragraph after.";
