# CHD-175 independent QA

Tested approved commits `840c788` and `ebc6d66` on main `b16354d`.
The designer's appearance approval and the owner's optional-id grammar decision
stand. This run judged behaviour and lifecycle, not appearance or intervening
features on main.

## What ran

- Foreground `deno task check`: 1340 passed, 20 steps, 0 failed, 7m38s.
- `deno task compile`: produced the macOS arm64 binary, which started and
  completed the no-id picker-to-window transition.
- Source and compiled TUI in an isolated tmux server, driven by keys only,
  at 120x40 and 80x24, including live resize between these sizes.
- Temporary HOME, XDG config/state/cache and a neutral directory. The claude,
  codex and gemini names all ran `tests/fixtures/fake_agent/main.ts` through
  temporary settings. Saved records used fixture UUIDs and public prompts.
- Fake prompt error, slow-turn interrupt, subsequent prompt, fake load refusal
  in source, startup Esc/Ctrl+C, normal quit and process inspection.
- Compiled no-id invocation with piped output: exit 2 and
  `--resume needs an id when not in a terminal`.

No real agent or model was used. No runtime source or dependency changed.

## What was observed

The source `resume` and `resume-all` captures show windows among single
sessions, scope switching, the multi-directory `+1`, and folded agent counts.
`opened` shows replacement of an unused tab with the three recorded tabs.
`beside` shows two tabs appended after three existing tabs, with their recorded
front selected. The source and binary `start-opened` captures show
claude/codex/claude in order, with codex in front; the ANSI capture preserves
its selected-tab styling. The startup picker has no prompt/status line and
zero owned agents before Enter; choosing the window starts three.

`open-marks` and `all-open-selected` show an all-open window and no duplicate
agent. Later binary picker captures also show single sessions marked
`open in 4` and `open in 7`. Some later records were created by quitting the
QA windows themselves; those seven- and five-tab rows are expected records.

The cap left seven tabs and seven fake agents unchanged. Both wide action-time
notes and narrow action-time notes matched CHD-174. The explicit
`*-80-cap-entered-narrow` captures distinguish performing the action at 80
columns from shrinking an existing wide note.

`elsewhere` shows a whole-window refusal and its exact resume command on its
own line. `start-empty` shows the empty local scope, while the subsequent
all-directory startup choice successfully opens a window from another
working directory.

`agent-error` shows the fake agent's deliberate failure. `interrupted` shows
`Interrupted by user`; `after-interrupt` shows the next prompt succeeds.
`load-refused` shows the fake agent's resume refusal rather than swallowing it.

Esc and Ctrl+C at startup returned the shell. Final quit left the cursor
visible (`cursor=1`), alternate screen off (`alternate=0`) and `icanon echo`
restored, as the terminal captures show. Final owned-agent counts were zero.
The isolated tmux server was killed and its PID verified absent. The only
remaining fixture was the pre-existing PID 78189, tracked by CHD-158 and left
untouched. The full gate emitted the 16 existing Vim DOM diagnostics tracked
by CHD-220 while passing.

## Follow-ups and library use

CHD-250 is a minor improvement: after a wide cap refusal, shrinking to 80
columns truncates the stored note instead of rewording it. Performing the
action at 80 correctly produces the short wording. It does not block this
restore change. CHD-246 already covers the designer-accepted empty-middle-tab
placement wording; no duplicate was filed.

No component, parser, renderer or protocol helper was written in QA. Verified
in source and binary: existing picker/string-width reuse, Cliffy's native
optional collected option, and Ink's rerender transition. The owner's accepted
flag-spelling-id limitation is pinned by the production CLI tests; no argv
rewrite or library patch was introduced.

Captures are raw tmux text and ANSI. Original shell captures containing launch
command paths were discarded and retaken using a neutral launcher. The staged
QA evidence contains no private paths.
