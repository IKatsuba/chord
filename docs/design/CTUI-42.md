# CTUI-42: Markdown wrapping parity

This is a correction to CTUI-4, with no public API or new action. Keep
`Markdown(text, growing: ...)`, styles, streaming/cache rules and code-box
wrapping unchanged. The specification is the original, with the two
reported differences retained in CTUI-16/U7 evidence.

## Table cells

At 120x40 the original's `markdown` fake reply has this Holds cell:

```text
opening, prompting and closing
a session
```

The port previously put `a` on the first row. Keep CTUI-4's padded column
widths, widest-column shrink arithmetic and whole-table truncation fallback.
Apply markdansi's word-tail rule within a cell: at a whitespace wrap, carry
an ending `a`, `an`, `the`, `to`, `of`, `with`, `and`, `or`, `in`, `on` or
`for` onto the next row if the preceding row retains text. Carry the pair
`with|in|on|of|to|for` plus `a|an|the` together. The matching is insensitive
to letter case. This is a wrap-boundary rule, not a width adjustment. No
orphan adjustment happens at a break inside mixed CJK and Latin text.
Preserve source style spans across the move. Long unbreakable cell words
retain the existing whole-table truncation behavior.

Reference: installed markdansi 0.3.8, `dist/wrap.js`, `orphanPhraseTail` and
`wrapRanges`; original `src/ui/transcript/markdown.ts`, `renderTable`.
This is terminal layout; it does not replace the maintained Markdown parser.

## Paragraph URL

At 80x24, the original live `markdown` reply has this paragraph excerpt:

```text
Start with src/session/session.ts, then see the ACP spec (https://
agentclientprotocol.com) for the wire format.
```

The framework previously moved the entire parenthesized URL to the next
row. Match the original live renderer's URL boundary, preserving link
underline and the dim destination suffix. The original uses `softMarkdown`
for paragraphs, leaving this wrap to OpenTUI; this URL behavior must not be
inferred from markdansi's table wrapping. Fit against the width actually
received after the reply inset, rather than the whole terminal width.
Do not add invisible width, split graphemes or hard-code this hostname.
Developer's direct OpenTUI TextRenderable probe at width 20 established
break opportunities after slash, hyphen, colon, period, comma, semicolon,
exclamation, question mark, parentheses, square/curly brackets and backslash.
Underscore, equals, plus, ampersand, hash, at, percent, pipe, tilde, curly
apostrophe and en/em dash did not provide them. Preserve punctuation on the
preceding row. The lead approved a private Markdown wrapping path using
existing TextLayout glyphs and Text.rich explicit lines; this avoids a
second segmentation engine and does not change generic Text or Code.

At 120x40 the paragraph remains on its existing two rows. At 80x24 table
cells use the same cell rule in their narrower columns. Empty input,
focus, code blocks and streaming state retain CTUI-4's behavior; narrow
constraints retain clipping and the existing table fallback. No key is
added by a passive wrapping fix.

## Proof

Regress both reported cases with exact visible rows, including a styled
URL and the table's inline-code cells. Include the rule boundaries that
justify any shared layout change; avoid changing plain Text or Code policy
unless independently required and explicitly handed to the lead. Check
chunked and complete Markdown agree. Designer checks the developer's named
fixture and the original `markdown` fake at 120x40 and 80x24, saving new
side-by-side captures under `docs/design/evidence/CTUI-42/`.

Existing comparison references:
`docs/design/evidence/CTUI-16/U7/compare-markdown-home-120x40.txt` and
`compare-markdown-home-80x24.txt`. These are prior baseline evidence, not a
visual pass of this correction.
