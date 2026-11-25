# CTUI-50: the terminal owns the editing cursor

The original prompt uses `cursorStyle={STEADY}` in
`../chord/src/ui/prompt/Prompt.tsx`: block, without blinking. The terminal
then supplies its own focused and unfocused appearance. The port's inverse
cell cannot do that. This replaces the painted caret in both framework
editors with a real terminal cursor; editing and layout semantics stay as
specified in CTUI-7. Lead-approved API and reset boundary follow.

## Call sites

```dart
TextArea(
  controller: draft,
  autofocus: true,
  cursorStyle: CursorStyle.steadyBlock,
  maxHeight: 4,
)

TextInput(
  controller: filter,
  cursorStyle: CursorStyle.steadyBar,
)

// In a custom render object's paint, after painting its content:
canvas.setCursor(offset, style: CursorStyle.steadyBlock);
```

Export `CursorStyle` with `blinkingBlock`, `steadyBlock`,
`blinkingUnderline`, `steadyUnderline`, `blinkingBar`, `steadyBar`, mapping
respectively to DECSCUSR 1 through 6. Both editors take non-null
`CursorStyle cursorStyle = CursorStyle.steadyBlock`. This deliberately
replaces the old nullable `Style` parameter; this early framework has no
compatibility requirement for inverse-cell caret styling. Retain the old
`ThemeData.cursor` role without removing or repurposing it in this slice.
There is no application blink timer or colour override. The terminal owns
cursor colour, size, blinking and its physical focus appearance.

`Canvas.setCursor(Offset position, {CursorStyle style =
CursorStyle.steadyBlock})` records a frame-local claim in terminal cell
coordinates, subject to the canvas clip and buffer bounds. Buffer exposes
the final position and style to renderer and terminal-free tests. A new
frame starts without a claim. A later valid claim replaces an earlier one.
An invalid claim has no effect. No new public cursor widget is necessary.

## Geometry, focus and paint order

Only an editor with primary framework focus claims the cursor. Disabled,
unfocused, absent, zero-width and zero-height editors claim nothing.
Focus and text changes must redraw cursor metadata even when no character
cell changes. Cursor claims are made after that editor paints its content.
Later paint over the claimed cell invalidates the claim, including a fill
with the same character/style; transparent unpainted cells do not. Account
for both cells of wide graphemes when paint replaces either half. Another
editor painted later can establish its own claim. Do not move a covered
cursor to another cell or leave a stale cursor after a frame/resize.

TextArea uses `cursorColumn` and `cursorRow - rowOffset` from its settled
layout, translated through padding and render offsets. Existing exact-width
continuation rows, LF positions, scrolling and grapheme boundaries remain.
The cursor never points at a wide grapheme's continuation cell. A grapheme
clipped at the right boundary is not split to make room for a caret; an
insertion point outside the actual clip hides the cursor rather than
clamping it onto visible text. TextInput must map its existing text layout,
prefix, wrapping and newline positions to the same actual painted cells;
it does not acquire new horizontal scrolling or TextArea editing semantics.

Remove all inverse styling of characters under the caret. Preserve a blank
cell at EOF/before LF where needed by existing layout. Preserve the existing
focused empty placeholder convention: a normal blank at the insertion
point, then the dim placeholder one cell later; unfocused placeholder
starts at the insertion point. The real cursor occupies that normal blank.
This settles the placeholder spacing explicitly; no extra blank appears
between ordinary text and EOF, and prefix width is counted only once.

A focus-taking overlay suppresses the underlying prompt claim; its focused
input claims its own cursor, or a nonediting picker shows none. Closing it
restores the prompt's current cursor. A passive completion overlay retains
prompt focus and cursor while it paints above the prompt. If a passive
surface actually paints over the insertion point it hides the claim by the
same paint-order rule; `OverlayEntry.visible` alone is not occlusion proof.

## Renderer and terminal ownership

Hide the terminal cursor before painting changed cells. After painting,
reset text attributes, emit the requested DECSCUSR, place the cursor, then
show it, within the synchronized frame when enabled. With no valid claim,
leave it hidden. This applies to unchanged-cell frames, cursor-only movement,
style-only updates, full redraws and resize. No fake cell or periodic frame
is emitted to imitate the terminal's caret.

On suspend, release, normal exit and supported signal cleanup, reset cursor
style with DECSCUSR 0 and show the cursor through the terminal's existing
cleanup path. On resumption the next app frame reapplies its selected style.
Cleanup remains best effort across write errors as existing ownership rules
require. Main approved resetting to the terminal default: this does not
claim recovery of an unknown style selected before the app. No style query
or new focus-report protocol is added. SIGKILL and terminal crashes remain
outside restoration guarantees.

## Appearance and keys

These are schematic crops, not observed captures. At 120x40 the editable
row is 114 cells in the existing framed TextArea demo; at 80x24 it is 74.
The surrounding screen, frame, hint and status do not move. `▉` below marks
the terminal cursor and is not a buffer character.

| State | 120x40 crop | 80x24 crop |
| --- | --- | --- |
| Empty, focused | `│ ▉Write a message … │` | `│ ▉Write a message … │` |
| Empty, unfocused | `│ Write a message … │` | `│ Write a message … │` |
| Text, focused EOF | `│ hello▉ … │` | `│ hello▉ … │` |
| Cursor before wide text | `│ hello ▉界 … │` | `│ hello ▉界 … │` |
| Overflowing four-row area | `line 3` through `line 6▉` | `line 3` through `line 6▉` |
| Narrow/zero surface | wrapped cursor if visible; otherwise hidden | same rule |
| Focus-taking picker | no prompt cursor | no prompt cursor |
| Passive completion | cursor stays in prompt | cursor stays in prompt |

The wide-text marker denotes the insertion point at the first cell of 界,
not an added space or a new glyph before it. An unfocused physical terminal
may draw the same cursor hollow; framework focus has not changed in that
case. Do not simulate that state using inverse styling or widget blur.

All existing editing keys, Actions descriptions and shortcut rows remain.
No user action is added by selecting a cursor style. A demonstration style
switch, if provided, must have a described Actions binding visible in
KeyHelp. The port explicitly selects steadyBlock, matching the original.

## Units and verification

C1 covers the cursor enum/metadata, Canvas paint invalidation, renderer,
terminal reset lifecycle, both editors and framework demo/regressions.
C2 covers the explicit port prompt choice and reached prompt/focus tests.
They may share one coherent implementation commit, with separate handoffs.
No drag selection, code buttons or clipboard changes belong to this task.

Tests must check real cursor metadata instead of inverse cells; cover all
six styles, cursor-only/style-only frames, EOF/LF, prefix, placeholder,
wide/combining/emoji text, wrapping, exact-width continuation, scrolling,
resize, zero surface, clipping, overpaint, focus transfer and passive layers.
Renderer byte tests check hide/position/style/show ordering and no-cursor
frames. Terminal tests check default reset on release/suspend/exit, resume,
repeat ownership and cleanup failures. Run reached tests and static checks.

After explicit screen handoff, designer runs owned tmux sessions at 120x40
and 80x24, retains plain and ANSI captures under
`docs/design/evidence/CTUI-50/`, compares the port with the original fake in
the same state, checks dark/light/plain themes where colour is relevant,
and kills every owned session. Capture cursor coordinates/visibility/style
separately because capture-pane text does not contain a real caret.

A byte trace and tmux cursor metadata prove protocol and placement only.
The task's physical focus claim requires observing a real terminal window
focused and then unfocused in a terminal that draws a hollow cursor. If that
surface is unavailable, report the physical check as unverified; neither a
pane capture nor injected focus bytes establishes it. Retain failure/fix
captures rather than replacing failed evidence.

## C1 clarification: TextInput source positions

TextInput word-wrap uses the existing TextLayout, which can remove wrapping
spaces. Add optional `Glyph.sourceOffset` metadata for the flattened display
text's grapheme offset; wrapping preserves it, expanded tab cells share it,
and synthetic ellipsis/middle dots have no source offset. This metadata is
terminal text layout, not a second editing or selection subsystem.

The private input paragraph finds the caret in the same full TextLayout it
paints. Translate the controller offset past its prefix exactly once and
keep existing span segmentation semantics. Map the existing EOF/LF blank
through that layout too. The insertion point on a tab uses its first painted
cell; a wide grapheme uses its leading cell. A source space removed by
word-wrap has no painted insertion cell, so hide the cursor rather than
jumping it to another visible character. No independent wrapping algorithm
or new scrolling rule is introduced.
