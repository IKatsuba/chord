# CTUI-47 original-only wheel baseline

Original source: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Command: `(cd ../chord && bun dev chord --fake --qa ctui47)` in one
owned tmux session, first at 120x40, then resized to 80x24. The `long`
prompt was sent literally with Enter in its own call. Captures start only
after all 200 numbered rows arrived and the working indicator disappeared.
No port WIP was run, inspected or compared in this preparation.

Wheel input was bounded injected SGR: CSI < 64;x;y M for up and
CSI < 65;x;y M for down. Coordinates below are one-based cell positions.
A 150 ms frame-settle allowance followed each report; there was no wheel
burst, acceleration probe or physical trackpad/mouse measurement.

| Size | Area and setup | Position | Observed bounded steps |
| --- | --- | --- | --- |
| 120x40 | Completed bottom, transcript | 10,10 | first row 166 -> 165 up -> 166 down |
| 120x40 | Completed bottom, prompt | 10,38 | first row 166 -> 165 up -> 166 down |
| 120x40 | Home, visible header | 3,2 | down removes header's first row; up restores it |
| 120x40 | End, fitting shortcuts open | 10,24 | transcript first row 166 -> 165 up -> 166 down |
| 80x24 | Completed bottom, transcript | 10,8 | first row 182 -> 181 up -> 182 down |
| 80x24 | Completed bottom, prompt | 10,22 | first row 182 -> 181 up -> 182 down |
| 80x24 | Home, visible header | 3,2 | down removes header's first row; up restores it |
| 80x24 | End, overflowing shortcuts open | 10,8 | down exposes panel's one-line-above rule; up restores its first row |

The unsubmitted draft `wheel keeps this draft` remains unchanged through
transcript, prompt and header reports at each size. Full plain bottom
screens after each down report exactly equal their corresponding baseline.
Before opening shortcuts, End restores the bottom, Ctrl+U clears the draft,
and literal `?` opens help. Escape dismisses it. The draft is retyped before
the second-size prompt tests; no second model turn is sent.

At 80 columns help fills the transcript area. The initial up report at the
panel's top is a no-op. A subsequent down report scrolls help rather than
the transcript. Dismissal after either report reveals the unchanged
transcript first row 182. `original-help-pair-{down,up}-80x24` records an
isolated pair in one opening; `original-help-*-dismissed-80x24` reveals the
underlying transcript. The panel's down then up pair returns to the initial
help content. At 120 columns the panel fits and the transcript moves instead.

This exposed an incorrect blanket assumption in the initial task/design.
Main decided to match the original overflow exception. A fitting panel
lets wheel reach the transcript; an overflowing body takes it itself.

## Reached original scrollbox audit

The original UI scan found these current port-reached consumers:

- `src/ui/shortcuts/Shortcuts.tsx`, scrollbox at line 132 and handler at
  144-148: stop propagation when total exceeds room.
- `src/ui/dialogs/Permission.tsx`, proposal scrollbox at line 374 and handler
  at 386-389: the same overflow condition. This permission case is source
  evidence here, not a live runtime capture.

Both explicitly use `new LinearScrollAccel()`. The installed OpenTUI
implementation, `chunk-bun-83k2gdpc.js` line 4058, has tick returning 1 and
reset doing nothing. The one-row step is not a guessed default. Only the
scrollbox's body consumes: titles, hidden-row rules and choices are outside
that handler. Main authorized matching this rule in other already-reached
scroll areas if found, without extending the slice to future features.

The remaining original scrollboxes are command/file completion panels in
`src/ui/prompt/Prompt.tsx` and the background view in
`src/ui/background/BackgroundView.tsx`; FEATURES lists those as future
port work. They are not introduced by this slice.

## Cleanup and limits

Ctrl+D quit the original fake session, and its owned tmux session was
checked absent. No original source was changed. Captures use only the
original runner's neutral QA directory in the header. This is a prepared
original baseline and owner-scope finding, not U7/U8 acceptance, physical
wheel delivery, port runtime proof, closing behavior or a test-suite result.
U8 must repeat the same setup after explicit developer handoff, including
fitting and overflowing permission proposal bodies and closing guards.
