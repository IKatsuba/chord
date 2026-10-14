# CHD-307 QA — transcript behavior

Checked `opentui` at `d3a44c3` against `main` at `3538862`, independently
of the engineer, designer and reviewer. Appearance remains designer-approved.

## Ran

- `bun run compile`: host `bun-darwin-arm64` binary built successfully.
- Key-driven real tmux matrices on the repository fake ACP agent, source and
  host binary at 120×40 and 80×24; matching source matrices on `main`.
  Each used a separate tmux socket, a scratch working directory and isolated
  XDG configuration/state. Literal prompt text and Enter were separate sends.
- `calls`, then `long`: PgUp during streaming, Esc, three wheel-up SGR
  reports, Home then Shift+Down, Ctrl+O twice while scrolled back, resize to
  100×30, End; then `rewrite` folded/opened/scrolled back and `error`.
- Fresh-session `rewrite` captures at 120×40 on both trees, to compare
  without different amounts of interrupted earlier output above the diff.
- Real tmux tab regression at 100×24: tab 1 `long`; tab 2 `calls`, `long`;
  Home then 30 Shift+Down in both; switch 2 → 1 → 2; resize to 80×24 while
  tab 2 is behind, then return. Two wheel-down SGR reports and one sideways
  report. Ctrl+C twice during a new `long` turn.
- `CHORD_FAKE_STEP_MS=1 bun test` on the reviewer's three scratch window
  probes: equal-offset tabs, resize while behind, parent/picked child.
  3 pass, 0 fail in 35.01 s; `withWindow` verified all fake processes gone.
- `long` ten times, completed, at 120×40 with `CHORD_FAKE_STEP_MS=1` on each
  tree; chord's RSS measured with `ps`, then after 20 seconds idle, ten PgUp
  keys and Ctrl+O.

## Saw

- Scrolling holds the view while new output arrives below; the indicator
  names that output. End follows the bottom and removes the indicator.
- Ctrl+O opens and closes the tool output with the top entry held. Resizing
  keeps it. These captures match `main` after normalizing the scratch path
  and the timing-dependent below count.
- Folded and opened diffs match `main`; the long added row retains its edge
  ellipsis at 80 columns. Fresh-session 120-column diff captures also match.
  Interrupted-stream captures can contain different earlier numbered lines.
- Each tab returns to its own entry at numeric offset 30, including after
  a resize while behind. Two wheel steps move exactly two rows; sideways
  does nothing. The window probes also prove distinct picked-child anchors.
- The failed Read result and the agent's deliberate error are displayed.
  Esc interrupts the streaming turn. Ctrl+C twice quits mid-turn.
- Every matrix, RSS run and tab run exits with identical `stty -g` before
  and after. Captured terminal bytes contain alternate-screen leave and
  cursor-show sequences. The shell returns. No QA-owned fake, test or tmux
  process remains after completion.

| RSS, KB | main | opentui |
| --- | ---: | ---: |
| Start | 171,936 | 117,408 |
| 2,000 reply rows | 515,712 | 517,232 |
| After 20 s idle | 107,312 | 191,872 |
| After ten PgUp keys | 278,096 | 276,960 |
| After Ctrl+O | 302,688 | 281,088 |

These are single-run snapshots, not peak measurements or a benchmark.
At 2,000 rows the measurements are essentially equal; garbage collection
changes idle values. Neither tree virtualizes. CHD-327 tracks virtualization.

## Evidence and limits

`source-120-*` and `source-80-*` are independent text captures. `anchor`
is Home then Shift+Down; `open-back`/`closed-back` follow Ctrl+O;
`resize` is 100×30. `tabs-*` records the equal-offset regression and resize
while behind. Scratch paths are normalized to `/tmp/chord-qa`; the returned
shell's machine-specific prompt is normalized to `$`.

The maintained-library trial is the engineer's documented OpenTUI 0.6.0
sticky-bottom scrollbox: row anchoring, wheel ownership and click focus did
not fit. CHD-307 explicitly permits the existing chord-offset fallback.
QA added no component, parser, renderer, protocol helper or dependency.

No live agent was used. Full cross-platform compilation, kitty-protocol
terminal checks and the migration's complete acceptance matrix belong to
later parts. This part changes no colours; light-terminal appearance was
not reopened. CHD-326 tracks the tall-draft wheel issue; CHD-273 tracks the
three older orphan fixtures, left untouched. No new defect was found.
