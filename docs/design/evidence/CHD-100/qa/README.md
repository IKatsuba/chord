# CHD-100 independent QA

Compiled from main at `5c60f43`, with the documented CHD-98 working changes
present. No production source was changed during QA. The approved appearance
was not reconsidered.

## Commands and isolation

Ran `deno task check`, `deno task compile`, and the compiled binary's
`--help`. Ran the compiled binary against `tests/fixtures/fake_agent.ts` in
an isolated tmux server, with a separate temporary HOME, XDG config/state/cache
and neutral working directory for every case. The fake agent used Deno with
this repository's configuration. No live agent was used. Text and keys were
sent separately with `tmux send-keys -l` and `tmux send-keys`; screens were read
with `tmux capture-pane -p` and `-p -e` after settling.

The first sandboxed check and tmux startup encountered environment restrictions;
the unchanged check was rerun with process access. No source workaround was
made for those restrictions. The current-tree check passed: 705 tests and
20 steps, zero failures. Compile and compiled `--help` both exited 0. A final
check includes the staged evidence. The whitespace and evidence privacy scans
passed. After the compiled probes exited, `ps` found no process from their
launch directories, and the isolated tmux server was removed.

## Behavior

- At 120x40 and 80x24, rebound Enter to null, send to ctrl+s and editor to
  ctrl+e (ctrl+g unbound). The panel names ctrl+s, ctrl+e and backslash plus
  ctrl+s. Enter keeps `text` in the draft; the editor receives `text`; ctrl+s
  produces the fake agent's `Hello, world. This reply came in chunks.`
- Also rebound cancel to ctrl+t, mode cycle to ctrl+b and transcript toggle
  to ctrl+y. The working hint names ctrl+t. Resizing a running slow turn
  between the two sizes preserves it; ctrl+t ends it with `Interrupted by
  user`. ctrl+b changes to accept-edits mode, and the wide hint names ctrl+b.
  ctrl+y reveals `Considering the question.` in a collapsed thought.
- `error` sent with ctrl+s draws `The fake agent failed on purpose.` at both
  sizes, and the next prompt still works.
- The invalid-file case has a Global conflict on ctrl+o, unknown action
  `chat:nope`, unknown modifier `hyper`, and Chat pageup conflicting with
  Scroll. The status line starts with `4 problems` at both sizes. Four
  transcript warnings remain readable through wrapping, and valid ctrl+s
  still sends. None of those rejected bindings becomes effective.
- ctrl+j unbound leaves `abcd` unchanged, proven by editor readback; ctrl+j
  bound to submit sends `text`. A bracketed paste of `one\ntwo` retains the
  line break. `a` plus backslash, then ctrl+s, creates a newline, proven by
  editor readback as `a\n`.
- Chat ctrl+k ctrl+e opens the editor with `abcd`, not an empty draft. Waiting
  past the three-second timeout also preserves `abcd`. While history search
  owns typing, Chat ctrl+x ctrl+e does not wait: ctrl+r, ctrl+x, `a` yields
  `no matching prompt: a`.
- Autocomplete ctrl+k ctrl+e preserves `/mod` after timeout and completion;
  editor readback is `/mod`. Outside the list, ctrl+a then ctrl+k cuts `abcd`
  normally and editor readback is empty.
- Help ctrl+x ctrl+e does not wait with Help closed; with Help open it waits
  and completion dismisses the panel.
- Every compiled probe exits 0 and returns to the shell, with alternate
  screen off, cursor visible, and identical `stty -g` before and after.
  This includes quitting during a slow turn. `terminal-restoration.json`
  records the values; `editor-receipts.json` records editor input (the editor
  file adds a final newline to nonempty drafts).

The repository tests also cover parsing, conflict detection, unchanged default
bindings without a file, LF/paste ownership, active chord eligibility and the
session layer against the fake ACP agent, with temporary settings directories.

## Scope and libraries

No new component, parser, renderer, protocol helper or dependency was written.
The implementation's library trials remain recorded in `docs/decisions.md`:
`ctrl-keys` 1.0.6 and `is-hotkey` 0.2.0 under Deno run and compile, with their
validation/chord/lookup limitations. Plain JSON needs no JSONC reader.

No new minor finding was filed. Fixed list/form/vim key ownership limitations
remain the existing CHD-107. The pre-existing CHD-98 working changes and unrelated
untracked evidence are preserved; only this QA evidence belongs to this run.
