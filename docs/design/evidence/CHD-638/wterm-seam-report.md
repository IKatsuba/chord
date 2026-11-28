# Draft: upstream report to wterm (not posted)

This is a draft for the owner. Nobody on the team posts it. It has been
narrowed after Q436: the site now sets a whole-pixel cell, which closes the
seams at DPR 1, 2 and 3. What is left is fractional device pixel ratios.
The images it names are in `seams/q436/`. Whoever posts it attaches them.

---

**Title:** Box-drawing rules show seams at fractional device pixel ratios
(1.25, 1.5), even with a whole-pixel cell (WebGL renderer)

**Version:** `@wterm/dom` and `@wterm/core` 0.6.0, the built-in core,
`renderer: "webgl"`.

**Environment:** Chrome 157 on macOS (arm64), headless. JetBrains Mono
2.304 (woff2 via `@font-face`) at 12.5 px with `letter-spacing: -0.5px`, so
wterm measures a 7 CSS px cell. A 1440x900 window gives 205x56.

**What happens:**

- At device pixel ratios 1, 2 and 3 the cell is 7, 14 or 21 device pixels,
  and runs of `─` (U+2500), including the horizontal parts of
  `┌ ┐ └ ┘ ╭ ╮ ╰ ╯ ┬ ┴`, draw as one unbroken line.
- At 1.25 and 1.5 the cell is 8.75 or 10.5 device pixels, and the same runs
  show thin vertical notches at regular x positions, the same columns on
  every row.
- Counted along the rules of three screens, the notches are:
  - DPR 1: 1–11, which is real content;
  - DPR 1.25: 28–134;
  - DPR 1.5: 48–238;
  - DPR 2 and 3: 0–3.

**Expected:** an unbroken line at any ratio, as the README says ("Common
light, heavy, and rounded box-drawing characters keep their strokes
connected across cell edges even when the selected font leaves gaps").
Snapping each cell's x origin, or the box-drawing quads, to whole device
pixels would close them. So would drawing a horizontal run as one quad.

**To reproduce** (view at a device pixel ratio of 1.25 or 1.5, for example
Windows display scaling at 125 % or 150 %, or Chrome's device emulation):

```js
import { WTerm } from "@wterm/dom";
const el = document.getElementById("t");
el.style.cssText = "--term-font-size:12.5px;letter-spacing:-0.5px";
const term = await new WTerm(el, { cols: 120, rows: 3, autoResize: false, renderer: "webgl" }).init();
term.write("┌" + "─".repeat(118) + "┐\r\n│" + " ".repeat(118) + "│\r\n└" + "─".repeat(118) + "┘");
```

**Images** (`seams/q436/`):

- `site-permission-dpr1.25-zoom.png` and `site-permission-dpr1.5-zoom.png`:
  a framed box at 1.25 and 1.5, with notches along its top edge.
- `site-permission-1440x900-dpr1.25.png` and
  `site-permission-1440x900-dpr1.5.png`: the whole window.
- `site-markdown-1440x900-dpr1.25.png` and
  `site-markdown-1440x900-dpr1.5.png`: code and table frames.
- For comparison, the same screens clean at whole ratios:
  `site-permission-dpr2.0-zoom.png`, `site-permission-1440x900-dpr1.0.png`
  and `site-permission-390x844-dpr3.png`.
