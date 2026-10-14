# CHD-334 — independent repair acceptance

QA of repair `37e3eac9`, on final implementation/design tree `27ebc48b`
on `opentui`. Main remains at `3538862f`. Approved appearance is settled.
This proves the parent-resize warning repair; CHD-310 remains the separate
whole-migration acceptance and merge gate.

## What ran

- `bun run check`, including fake ACP session tests, column cut/wrap
  shrink/grow, shared-listener disposal and complete-instruction regressions.
- `bun run compile`, followed by actual host-binary startup and keys.
- Fresh isolated keyboard-only tmux source and host-binary sessions, each
  at 120×40 and 80×24, with scratch work/config/state and terminal stdin.
  Literal text and Enter were delivered separately.
- Six shortcuts open/dismiss cycles per build/size; two shrink/grow cycles
  while open, then hello, a deliberate agent error, slow-turn Esc interruption
  and a new reply. Captures include each dismissed screen and the replies.
- Existing M1/M2 recipes: streamed text/markdown/code, tools/diff/thought
  expansion, permission denial, multiline/history/search, plans, shortcuts,
  mode/model/effort, slash/file completion, resource links, bash context,
  cost/context/status/help, queued input returned on interruption, scrolling,
  expansion and resize.
- Four rebound-key sessions: Enter creates a newline, Ctrl+S submits,
  Ctrl+T opens a session, three shortcuts cycles show the bound hints,
  and a reply continues in the new session.
- Four complete-instruction sessions: an opened `/team show` contains all
  90 distinct instruction words and the member's ending through both widths
  and back, read across pages, followed by another prompt/reply.
- Independent scratch harness warning observer installed before mount:
  the same parent through 12 → 3 → 0 → 12 → 0 → 12 children, each at
  40 → 20 → 60 columns, then unmount.
- Exact before/after `stty -g` and `stty -a`, tmux terminal flags, raw bytes
  through the existing maintained `@ansi-tools/parser`, and owned-process
  inspection through `ps`.

## What was seen

The shortcuts open, dismiss and refit without warning fragments. Input and
replies continue; the deliberate agent error is visible, Esc interrupts,
and the next prompt works. M1/M2 and rebound-key actions work at both sizes
and on both builds. Every instruction word and the member ending remains
readable after shrink/grow.

The same harness parent holds listeners 1 → 1 → 0 → 1 → 0 → 1, then 0
after unmount. Every surviving child is fitted at each width, with no warning.
This proves subscription ownership/disposal, not a retained-memory claim.

`bun run check` passed: 51 lint tests and 1,498 session/UI tests across
108 files, zero failures. Staged privacy passed 7/7.

`verification.json` records check results, build identity, warning
counts, terminal restoration and process cleanup. Each case has paired
text/ANSI screens, exact termios records and compressed unedited raw output.
`listener-lifecycle.json` records the independent lifecycle probe.

QA added no component, renderer, parser or protocol helper. The existing
fake agent, OpenTUI harness, QA key recipes and maintained ANSI parser were
reused. The repair's OpenTUI event-API investigation and rejected
`setMaxListeners` alternative are recorded under CHD-332 in
`docs/decisions.md`; warnings remain enabled. No library was patched.

Only the host binary is run. This focused acceptance does not repeat every
CHD-310 forced-exit/M3/M4/M5 row, establish other-platform execution, or
claim owner final acceptance. No real agent, merge, push, publication or PR.
