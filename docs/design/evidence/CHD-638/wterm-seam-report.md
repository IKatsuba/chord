# Draft: upstream report to wterm (not posted)

A draft for the owner, per question 8 of `docs/design/CHD-638.md`. Nobody
on the team posts it; the lead hands it to main. The images it names are in
this folder; whoever posts it attaches them.

---

**Title:** Horizontal box-drawing lines show thin seams at fixed columns
(DOM and WebGL renderers)

**Version:** `@wterm/dom` and `@wterm/core` 0.6.0, the built-in core.

**Environment:** Chrome 157 on macOS (arm64), headless. Device
pixel ratio 2 and 4. Fonts: Menlo (system) and JetBrains Mono 2.304
(woff2, via `@font-face`, `--term-font-family`). `autoResize` on, and also
fixed `cols`/`rows`.

**What happens:** a run of `─` (U+2500), including the horizontal parts of
`┌ ┐ └ ┘ ╭ ╮ ╰ ╯`, is drawn with thin vertical tick marks: short dark or
light notches across the line. They sit at the same x positions on every
row of the screen, so a header rule, a box's top edge and its bottom edge
all show ticks in the same columns. Vertical runs of `│` join cleanly across
rows; only horizontal runs are affected.

- DOM renderer: seams at ratio 2 and at ratio 4, with Menlo and with
  JetBrains Mono.
- WebGL renderer (`renderer: "webgl"`): seams at ratio 2 with both fonts.
  At ratio 4 with Menlo the line was clean; with JetBrains Mono it still
  shows them.

**Expected:** an unbroken line, as the README describes ("Common light,
heavy, and rounded box-drawing characters keep their strokes connected
across cell edges even when the selected font leaves gaps").

**To reproduce:**

```js
import { WTerm } from "@wterm/dom";
const term = new WTerm(document.getElementById("t"), {
  cols: 120, rows: 10, autoResize: false, renderer: "webgl", // or "dom"
});
await term.init();
term.write("┌" + "─".repeat(118) + "┐\r\n");
term.write("│" + " ".repeat(118) + "│\r\n");
term.write("└" + "─".repeat(118) + "┘\r\n");
```

View it at device pixel ratio 2. Because the ticks fall in fixed columns,
they look like they follow span or glyph-batch boundaries, not cell
boundaries: they are several cells apart, not one per cell.

**Images:**

- `box-corner-dom-4x.png`: DOM renderer, Menlo, ratio 4: ticks on the top
  edge.
- `box-corner-webgl-4x.png`: WebGL renderer, Menlo, ratio 4: clean.
- `s5-dialog-zoom-dpr2.png`, `s5-dialog-zoom-dpr4.png`: WebGL renderer,
  JetBrains Mono, ratio 2 and 4: ticks on the header rule and on a box's
  top and bottom edges, in the same columns.
- `s5-home-auto-1280x800.png`: a full window, ratio 2: ticks along the rule
  under the header and on the box below it.
