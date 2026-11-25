# CTUI-50 designer screen pass

Implementation examined: `de6b473ca9a4fe01a2d808dec414bc2d8d5b48ec`.
Original baseline: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
C1 and C2 pass the designer screen look. No implementation finding raised.
Physical focused/unfocused hollow cursor appearance remains unverified.

## Runs and retained evidence

Owned isolated tmux server `designer-ctui50`; every app was run from the
CTUI-50 checkout, with the original read-only from `../chord`. Commands:

- C1 TextArea: `dart run example/text_area.dart`.
- C1 TextInput: `dart run example/demo.dart`.
- C2 port: `dart run example/chord/tool/dev.dart chord --fake`.
- Original: `(cd ../chord && bun dev chord --fake --qa designer-ctui50)`;
  distinct names ending in `light`, `plain`, `colorlight`, `colordark` kept
  original QA state separate for theme runs.

Each state has a full `.txt` pane, `.ansi` pane and `.cursor` metadata.
Coordinates in metadata are zero-based. `comparison-*.txt` puts original
and port panes side by side. The working-directory line is replaced with
`<working directory>` in port captures to omit private paths. Version,
working directory and staged header/help wording differ independently of
this cursor slice; they are not used as cursor parity evidence.

## Observations

| State | 120x40 original and port | 80x24 original and port |
| --- | --- | --- |
| Empty/restored prompt | (4,37), visible | (4,21), visible |
| Passive `/sta` completion | (8,37), visible | (8,21), visible |
| Ten-line Unicode draft EOF | (17,37), visible | (17,21), visible |
| Same draft, two Left presses | (14,37), visible | (14,21), visible |
| Focus-taking `/model` picker | hidden | hidden |

Every visible caret above reports `shape=block blinking=0`. Hidden picker
metadata can retain a renderer write position outside the last column;
visibility is zero, and there is no displayed editing caret there. Esc
restores the prompt's current insertion point. Completion does not take
focus or move the prompt. The completion rule/item, model picker geometry,
and the ten-line draft's visible lines 3 through 10 match at 80x24; the
wide draft likewise matches. Unicode input was `界é🙂` (combining acute).

Use `port-empty-after-input-120x40` and
`original-empty-after-input-120x40` for the wide empty observation.
`*-input-attempt-empty-120x40` retains an automation attempt: sending Esc
and Ctrl+U together did not clear `/sta` in either app, so these are not
empty-state evidence. The following typed `/model` consequently submitted
`/sta/model` in both; later empty/picker/draft captures share that same
completed fake response and context-use status. Sending reset keys in
separate calls produced the intended states. This is an input-sequence
correction, with no product fix or failure claim.

C1 TextArea captures show focused placeholder blank, Unicode EOF, six
logical lines scrolling to rows 3–6, four Up presses revealing rows 2–5,
and live resize from 120x40 to 80x24 without losing logical cursor. The
caret remains on the edited row and before the wide/combining characters
when moved. TextInput captures show its own prefix/placeholder placement,
Unicode movement, and word-wrapped text at 80x24 with the caret on the
actual second painted row. These are framework demos, so no original
screen comparison is claimed for them. The wrapped TextInput retains a
suffix emoji after a mid-text Ctrl+U; it is ordinary retained draft text,
not a second cursor glyph.

## Themes and limits

Initial sessions inherited `NO_COLOR=1`. Thus unqualified state captures
and the earlier `*-light-completion-*` captures prove placement under that
environment, not a colour-selected light palette. They are retained rather
than relabelled as successful colour evidence.

Explicit `*-colordark-*` and `*-colorlight-*` sessions used `env -u NO_COLOR`
with `FORCE_COLOR=3`, `COLOR=1`, `COLORTERM=truecolor`, and respectively
`COLORFGBG='15;0'` or `'0;15'`. Their completion states are retained at both
sizes; the light focus-taking picker is also retained at both sizes.
`*-plain-*` uses `NO_COLOR=1` explicitly, at both sizes. The selected
completion tone matches the original's dark/light tones, and caret
shape/visibility/blinking do not depend on those app palettes. Existing
rendering differences include terminal-default foreground versus the
original's explicit foreground and dim borders versus its indexed border;
this look makes no new palette parity claim beyond the changed caret.

Plain and ANSI pane captures do not contain the real terminal cursor.
The separately captured tmux metadata establishes placement, visibility,
block shape and nonblinking state. It does not observe a physical window's
focus or its terminal renderer. No native terminal surface was available,
so the requested filled-to-hollow observation is still unverified; it must
be checked on a terminal that actually provides that appearance. No injected
focus sequence, widget blur or inverse cell is presented as physical proof.
Renderer-byte and terminal restoration checks belong to reviewer/tester;
this screen look does not substitute for those checks.

## Cleanup and handoff

All owned apps were quit, and the isolated tmux server exited with no
sessions remaining. A final process check found no owned demo, dev runner,
port window or original fake-agent process. No implementation edits, tests,
compiles, full suites or external writes were performed by designer.
Evidence was checked for private home paths before commit. C1/C2 go to
reviewer with their implementation head and this evidence; not to tester.
