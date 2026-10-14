# CHD-263 QA at 7cd9ac2

## Ran

- `deno task check` on the current main tree, with process-query access for
  the fake-window harness's cleanup assertions: 1485 passed (20 steps),
  0 failed in 8m52s; types, lint and format passed.
- `deno task compile` passed; source `deno task chord:fake` and the compiled
  `dist/aarch64-apple-darwin/chord`, on isolated fake-agent settings, HOME,
  state and project directories under `/tmp`.
- Keyboard-only tmux at 120x40 and 80x24: picker, Esc/Enter, saved and running
  show, expansion, typed run, a second run, stop, completion, main routing
  with a child picked, broken run, new/save, edit-with-words/save, native vi,
  resize, fake-agent errors, Esc interruption and quit.
- A pure Deno editor probe: the original fake bugfix fixture through
  `editInEditor` with `EDITOR=true`, which changes no bytes in the temporary
  editor file.
- Privacy check on the evidence; terminal state and `ps` cleanup checks.

## Saw

**Native editing fails byte preservation.** In source and compiled chord,
copy `tests/fixtures/teams/fake/bugfix.md` into the scratch project's
`.chord/teams/bugfix.md`, type `/team edit bugfix`, and quit vi with `:q`
without any edit. chord reports that the team is valid, but writes the file
back with its em dash changed to `â€”`:

```diff
-description: Fixes a bug end to end — a failing test first, then the fix.
+description: Fixes a bug end to end â€” a failing test first, then the fix.
```

SHA-1 changes from `8bcef721d95ea3fb7e2e23f21e0fc66c6fe8272d` to
`b66f28a315e381cab0f00f1d568084661d31da63`. The no-op Deno editor probe
returns the same corruption. The library's `readTemporaryFile` guesses the
encoding with chardet and decodes through iconv. This is new file-writing
behavior in `/team edit`, although the shared editor helper predates it.
Existing editor tests use a multilingual string and the team-window tests
inject an editor, so neither catches this fixture's round trip. No repair
or library workaround was made in QA.

The other exercised command paths worked. The running report carries the
latest incoming message; Enter on a running team starts another run; stop
closes that run and its members without arming. New and edit-with-words
reach main's proposal and write only after a save choice. The source's held
run note was confirmed in its record ahead of the next typed prompt.
A broken native edit reports its problem and a subsequent run is refused.
The fake agent's deliberate error is visible and Esc draws `Interrupted by
user`.

**CHD-277:** an already-open picker retains its opening-width row layout
through resize. The header/hint resize, but row runtimes and broken paths
remain at 80 until Esc and reopen. The reverse resize retains narrow rows.
Filed separately under the two-return bound; original designer/reviewer
returns are fixed and proven. The resized picker remains usable.

Source and compiled quit restored the shell, cursor and alternate screen.
The final source pane reported `alternate_on=0`, `cursor_flag=1`; `ps`
showed its shell and no descendants. The isolated tmux server was removed.
The stty delta was only macOS's PENDIN bit. No real agent or model was used,
and unrelated existing processes were left alone.

## Scope and library reuse

Designer-approved appearance was preserved. CHD-264 resume acceptance and
physical kitty keyboard negotiation were not judged. The implementation
reuses PickerList, @cliffy/table/proposal rendering, Tool's run_team row,
messageHeader, and @inquirer/external-editor. QA added no dependency or code.
The editor library was independently tried on the actual fixture; its no-op
round trip did not preserve UTF-8 text.
