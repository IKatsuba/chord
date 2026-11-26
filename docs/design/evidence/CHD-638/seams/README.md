# CHD-638: the box-line seams, probed

The owner does not want the thin ticks on `─` rules. chord's fixtures and
the framework's examples draw those frames themselves, so the fix has to be
in the terminal, not in the site's chrome. This folder holds the captures
and measurements. The probe code was scratch work and is not in the tree.

**Setup.** The site at commit f011062b0 was built once with one scratch
addition: `?probe=permission` shows chord's live permission fixture
(`LivePermission`) in a frame. That build was served under eight terminal
setups, with only `index.html` changed between them, all driving the same
`globalThis.chordTerminal` host object that `WebTerminal` binds. Each was
captured in headless Chrome 157 on three screens:

- `home`: the top line and its rule;
- `permission`: the live fixture in its frame;
- `markdown`: the gallery example, with code and table frames.

**Measurement.** `measure.json` finds every horizontal rule in a capture
(a lit run of at least 300 device pixels). Along each rule it counts:

- **breaks**: dips below half the rule's brightness;
- **ticks**: any dip or bump of more than 20 % of the rule's contrast, which
  is the seams.

A handful of breaks on `markdown` are real content: the short rule above the
example's own help row.

## Run 1: every option at DPR 2 (`dpr2/`)

1440x900 at DPR 2. Each capture also has a zoom (`*-zoom.png`).

| Setup | home | permission | markdown | Kitty keys (`CSI ?u` answered) |
| ----- | ---- | ---------- | -------- | ----------------------------- |
| wterm 0.6.0, WebGL, built-in core (today) | 0 ticks | 0 | 1 | yes |
| wterm, DOM renderer | 278 | 363 | 462 | yes |
| (a) Ghostty core, WebGL | 0 | 0 | 1 | yes |
| (a) Ghostty core, DOM | 278 | 363 | 462 | yes |
| (b) WebGL, 12 px type instead of 12.5 | 7 | 13 | 22 | yes |
| (d) WebGL, system Menlo instead of JetBrains Mono | 434 | 613 | 785 | yes |
| (c) xterm.js 6.0, DOM | 1 | 3 | 2 | **no** |
| (c) xterm.js 6.0, WebGL addon 0.19 | page drawn empty | 1 | 3 | **no** |

What it says:

- The seams come from the renderer and the cell width. The core makes no
  difference: Ghostty matches the built-in core under each renderer.
- WebGL with JetBrains Mono at 12.5 px is clean at DPR 2. A cell there is
  12.5 × 0.6 = 7.5 CSS px, which is 15 device pixels.
- At 12 px a cell is 14.4 device pixels and the ticks return. Menlo's advance
  is fractional at every size we use.

## Run 2: DPR 1, 2 and 3 (`dpr123/`)

1440x900 at DPR 1 and 2, and 390x844 at DPR 3 (a phone).

| Setup | DPR 1 (desktop) | DPR 2 | DPR 3 (phone) | Grid at 1440x900 / 390x844 |
| ----- | --------------- | ----- | ------------- | -------------------------- |
| WebGL, 12.5 px (today) | 138 / 218 / 267 ticks | 0 / 0 / 1 | 12 / 37 / 50 | 192x56 / 52x52 |
| (b) WebGL, 12.5 px, `letter-spacing: 0.5px` (8 px cell) | 1 / 3 / 51 | 0 / 0 / 40 | 48 / 151 / 222 | 180x56 / 48x52 |
| **(b) WebGL, 12.5 px, `letter-spacing: -0.5px` (7 px cell)** | **2 / 3 / 11** | **0 / 0 / 1** | **0 / 3 / 3** | **205x56 / 55x52** |
| (c) xterm.js, DOM | 0 / 2 / 6 | 1 / 3 / 2 | 0 / 2 / 5 | 192x41 / – |

Each cell gives home / permission / markdown.

Today's setup is clean only at DPR 2. On an ordinary DPR 1 monitor (7.5
px cells) and on a DPR 3 phone (22.5 px), the rules are dashed: compare
`dpr123/wterm-webgl-permission-dpr1-zoom.png` with
`dpr123/wterm-webgl-ls-0.5-permission-dpr1-zoom.png`.

With `letter-spacing: -0.5px` wterm measures a 7 CSS px cell. That is a whole
number of device pixels at DPR 1, 2 and 3, and the rules are clean at all
three: the few remaining counts are real content. Text reads slightly
tighter but well (`dpr123/wterm-webgl-ls-0.5-markdown-1440x900-dpr2.png`,
`…-permission-390x844-dpr3.png`). `+0.5px` (an 8 px cell) did not help at
DPR 3, so the effect is not only about the cell being a whole number.

Not measured: fractional ratios such as Windows' 125 % and 150 % (DPR 1.25,
1.5). There a 7 px cell is 8.75 or 10.5 device pixels, and some ticks
should be expected. No CSS value is whole at every fractional ratio.

## Costs

| Option | Download | index.html | build.dart | WebTerminal | Else |
| ------ | -------- | ---------- | ---------- | ----------- | ---- |
| (a) Ghostty core | +600 KB wasm (198 KB gzip) +47 KB JS | import `GhosttyCore`, `load({wasmPath})`, pass `core` | pin and ship `@wterm/ghostty` | none | **does not remove seams**; brings OSC 52, richer underlines, OSC 8 |
| (b) `letter-spacing: -0.5px` | none | one CSS line on `#terminal` | none | none | grid 205x56 at 1440x900, 55 columns on a 390 px phone, 51 on 360 px; Q432's table and the recording rooms change accordingly (48x32 then fits framed on every phone we listed); mouse, Kitty keys, copy and start time unchanged |
| (c) xterm.js 6.0 (+fit, +webgl) | about 127 KB gzip JS + CSS, replacing wterm's 116 KB | new loader, FitAddon, theme | pin and ship `@xterm/*` | host object fits as is | **no Kitty keyboard** (`CSI ?u` unanswered: Shift+Enter, Ctrl+letters with modifiers fall back to legacy keys); row height differs (192x41 here) and needs tuning; the WebGL addon drew an empty home page; selection and accessibility differ; S5's browser tests are rewritten |
| (d) another font | none or a new woff2 | `@font-face` | the font's pin | none | system Menlo is worse; the cause is the advance, not the font |

## Recommendation

**(b): keep wterm 0.6.0 with WebGL and the built-in core, and add
`letter-spacing: -0.5px` to `#terminal`.** It is the only option that is
clean at DPR 1, 2 and 3, and it costs one CSS line, no download, and nothing
in input, copy or start time. What it changes is the cell: 7 px instead of
7.5 px, so 205x56 at 1440x900 and 55 columns on a 390 px phone. That is a
change to Q432's single-size table, which the owner set, so it needs the
owner's yes.

Not recommended:

- (a) the Ghostty core does nothing for the seams.
- (c) xterm.js loses Kitty keys, which the site's examples and chord's
  fixtures use, and it brings rendering surprises.
- (d) other fonts are worse.

The upstream report to wterm (`../wterm-seam-report.md`) still stands for
fractional ratios.

## Run 3: the site as built after Q436 (`q436/`)

The site at ef49590c8 (S7's `letter-spacing: -0.5px`), with the same
`?probe=permission` addition, captured at DPR 1, 1.25, 1.5 and 2 at
1440x900, and at DPR 3 at 390x844. wterm measures the 7 px cell: 1440x900
gives 205x56. The glyphs sit on the cell grid; frames join with no drift.

Ticks on the rules:

- **home**: only its top line's rule. Home is now direction C, and its
  giant blocks and band text are lit runs, not rules, so the other lines in
  `measure.json` don't count.
- **permission**: the fixture's frame.
- **markdown**: the example's code and table frames.

| DPR | Cell in device px | home rule | permission | markdown |
| --- | ----------------- | --------- | ---------- | -------- |
| 1 | 7 | 1 | 3 | 11 |
| 1.25 (Windows 125 %) | 8.75 | 28 | 110 | 134 |
| 1.5 (Windows 150 %) | 10.5 | 48 | 151 | 238 |
| 2 | 14 | 0 | 0 | 1 |
| 3 (phone) | 21 | 0 | 3 | 3 |

At 1, 2 and 3 the rules are clean; the few counts are real content, as
before. At the fractional ratios the ticks return, because a 7 px cell is
not a whole number of device pixels there. No single CSS value is whole at
1, 1.25, 1.5, 2 and 3 at once except a 4 px or 8 px cell. 4 px is too narrow
to read. 8 px (`+0.5px`) ticked at DPR 2 and 3 in run 2, because the glyph
then no longer fills its cell.

So after Q436 the seams remain only on displays scaled to 125 % or 150 %,
which is typical of Windows laptops. Closing those needs wterm itself to
snap glyph or cell positions to device pixels. That is what the upstream
report (`../wterm-seam-report.md`) asks, now narrowed to fractional ratios.
