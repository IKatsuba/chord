# OpenTUI 0.8.4 visual pass (U1, commit 626373b1e)

The design's table of screens, each at 120x40 and 80x24, CHD-624 beside
origin/main (49b4c650c, OpenTUI 0.8.1) in the same tmux 3.6a, both driven by
the same keys at once. `--fake --qa`; the title page and picker by `--qa`
alone, no agent picked. `text/` holds every capture as plain text
(`main-…` is origin/main); each PNG puts the branch on the left and
origin/main on the right. Under `OPENTUI_FORCE_UNICODE` and
`OPENTUI_FORCE_WCWIDTH` the branch is shown alone, except graphemes under
wcwidth, which has origin/main beside it.

| Screen | Captures | Result |
| --- | --- | --- |
| Title page, picker | `title-*`, `picker-80x24` | identical |
| Markdown | `md-*` (a `markdown`, b `markdownwrap`, c `markdowncode`) | identical |
| Wide graphemes | `graph-*` (a typed `naïve 日本語 👩‍💻 ok`, b cursor moved left) | identical |
| Permission | `perm-*` (a `permission`, b `bigask`, c `multidiffask`) | identical; reason, choices and Esc hint kept at 80x24 |
| Forms | `form-*` (a `form`, b `requestform`) | identical |
| Plan | `plan-*` (a `plan`, b `todos`, c `exitplan`) | identical |
| Tools and diffs | `tools-*` (a `edit`, b `tools`, c `longresults`) | identical |
| Long transcript | `long-*` (a end, b–c pgup, d home, e pgdn, f end) | identical; no blank or stale rows |
| Subagents | `sub-*` (a `subagent`, b `agents`) | identical |
| Floats | `float-*` (0 before, a `?`, b `/`, c `/resume`, d ctrl+r) | identical; prompt and status line fixed |
| Status line | `mode-*` (a, then t1–t5 shift+tab) | identical |
| Compaction | `comp-*` (a `compact`, b ctrl+o) | identical |
| `$EDITOR` | `ed-*` (a in vi, b after `:q`) | identical; vi's temp path redacted to `$TMPDIR/…`; prompt holds only `draft` |
| Colour | `col-*` (`edit`, `COLORTERM` unset) | text identical; the branch keeps truecolor text where origin/main falls back to 256 colours |
| Width methods | `graph-`, `md-`, `perm-` `UNICODE`/`WCWIDTH` | unicode draws the same as the default; wcwidth (wrong for tmux 3.6) draws the same as origin/main under it |

All 74 paired captures under the default width method match their origin/main
captures, both as text and in colour. No regression from the design's list.
In the wcwidth PNGs the browser draws the emoji narrower than tmux does, so
the prompt's right border looks short there; the text captures show it in
place.

## U1b: OpenTUI picks the width method (commit e9cd1cd32)

chord no longer forces `OPENTUI_FORCE_UNICODE` under tmux. `u1b-*`, with no
`OPENTUI_FORCE_*` set, in tmux 3.6a: a `graphemes` and `naïve 日本語 👩‍💻 ok`
typed, b cursor moved left, c `‼️ ⚠️ ❤️ 🖥️ end` typed, d cursor moved left.
All eight frames match origin/main (which still forces unicode) as text and
in colour, and a and b match U1's `graph-UNICODE-*` captures.
