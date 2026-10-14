# CHD-56 independent QA

Baseline: aeb240d, with the designer's approved appearance and the lead's
amended text-only acceptance. These captures come from a freshly compiled
binary, driven only by keys against the repository's fake ACP agent in an
isolated temporary working directory and state directory.

## Commands and actions

- `deno task check` and `deno task compile`.
- Start the compiled binary in an isolated tmux server at 120x40.
- Type `/echo explain @stt`, capture the narrowed finder, press Tab, then
  Enter separately; capture the fake agent's reply.
- Type the same prompt, resize the open finder to 80x24, then Tab and Enter;
  capture the finder and reply at the narrow size.
- Type `@`, press Esc, create `new.ts` in the temporary working directory,
  type `new` in the retained draft; capture the refreshed finder.
- Exercise Down/Up/Down and Enter to insert a file without sending, then
  Enter to submit. Complete and echo a path containing spaces. Check an
  email address does not open the finder.
- Submit the fake agent's `error` scenario; submit `slow`, interrupt with
  Esc, and send `/echo recovered @new` through completion afterwards.
- Open the shortcuts panel, close it, then quit with Ctrl+D. Compare the
  terminal settings and inspect the recorded binary and fake-agent PIDs
  with `ps` before killing the QA-owned tmux session.

## Observations

Both required sizes show the narrowed finder and the sent prompt followed by
`explain @src/ui/state.ts`. Completion belongs to the finder inside `/echo`.
The resized finder remains usable. Esc keeps the draft; reopening finds the
new file. Arrow selection and both insertion keys work. The quoted path
`@"docs/meeting notes.md"` is echoed intact. Root and nested `.gitignore`
exclusions and `.git` are absent from the empty finder. The temporary
working directory is not a git repository.

The agent's deliberate error appears as `The fake agent failed on purpose.`
An interrupted turn shows `Interrupted by user`; the next completed mention
is echoed as `recovered @new.ts`. The shortcuts panel lists all four finder
rows at 80x24.

Quit exits with code 0, returns to the shell, and reports `alternate=0` and
`cursor=1`. The before/after `stty -g` strings are identical. Both recorded
QA PIDs are absent from `ps`; the isolated tmux server has no session left.
No live agent was used. No resource blocks are claimed: CHD-60 owns that
future work; CHD-61 owns optional shared list overflow hints.

Library choices were exercised in the compiled binary: globby 16 for the
walk and fzf for matching. The engineer tried globby and reused fzf;
`git ls-files` was passed over because it requires git and a repository.
Ink Box/Text follows the documented trial and rejection of
ink-select-input for typing-driven lists. QA added no implementation.
