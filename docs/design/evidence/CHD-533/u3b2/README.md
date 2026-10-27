# U3b2 Resources screen check

Screen code: `df1da2b700cd432c9a110be5b4c783694c1a4568`.
Design: D2, `4eb12bd7`. Capture time: 2026-10-27, 17:05 UTC.
This directory's later commit contains evidence only; it is not the screen
code revision. No later source edits were used for these captures.

The screen ran from a fresh archive of that exact code revision outside the
shared checkout. Only dependencies were linked from the checkout; the snapshot
had no original Git directory, worktree or linked Git index. The dependency
lockfile was the archived `bun.lock`; dependencies were held unchanged during
the exclusive UI QA slot.

Each case used the archived tracked launcher:
`nice -n 19 bun tests/fixtures/resource_qa.ts <case>`.
The launcher recreates its fixed named QA directory, isolates configuration
and state, and supplies scripted ACP and explicit fixture-only resource
sources. No real provider, credential, login, auth-source or paid prompt was
used. Each size/case ran sequentially in its own tmux session.

Type `resources` with `send-keys -l`, then send Enter separately. Captures
are `capture-pane -p` text and matching `-e` ANSI text. Both represent the
running terminal, not renderer snapshots or design mocks. All saved captures
were inspected as text; ANSI output was checked against matching plain text
and its emitted styling. No images were generated.

## Result

Visual PASS for normal, partial, pending, unavailable and long cases, each
at 120x40 and 80x24. All values and warnings remain legible and wrap beside
the existing tool gutter. The partial case retains short-window utilization
and labels weekly utilization/reset unknown. Pending and unavailable remain
advisory tool results. Receipt age and unknown provider freshness remain
separate. Precision `12.345%` is preserved. No combined balance or raw account
identity is displayed. Active work is explicitly reported coverage, with an
external-work caveat.

The long narrow case exceeds the viewport: `long-80x24` shows the bottom,
including the complete warning; `long-home-80x24` shows the heading and
preferences after Home, with the existing lines-below indicator. This is
ordinary scrollback, with no read-result folding. The wide Home capture is
unchanged because the report fits. `normal-expanded-120x40` records ctrl+o;
the formatted read remains visible without a new control or hidden warning.

The normal wide snapshot's read time and receipt age remained unchanged after
ctrl+o. Pending captures were taken promptly, before the collector deadline.
All QA sessions were killed; a final tmux query found no server, and the
process query found no matching QA/helper processes.

Scope: this is a first visual look at handed U3b2 only. No implementation
review, real collector verification, release-target check or full test suite
was performed. The narrow footer uses its existing abbreviated context label;
that footer is outside this unit's Resources report.
