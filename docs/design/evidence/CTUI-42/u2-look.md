# CTUI-42 U2 visual pass

Handed implementation: `5420954`. Designer ran developer's named command,
`dart run example/markdown_wrap.dart`, in an owned tmux session at 120x40
and 80x24. Both plain and ANSI captures are saved as u2-markdown-*.
The fixture has the transcript's three-cell left and one-cell right inset.

The original was run with `bun dev chord --fake --qa markdown`, then sent
`markdown` with literal send-keys and Enter separately. Home exposes the
paragraph and the 120-column table; PageDown exposes the 80-column table.
The original captures predate U2 and were made from the installed original
source, read-only. No real agent/model was used.

Visual result: pass. At 120 columns Holds ends its first row at `closing`
and its second row is `a session`. At 80 columns the paragraph breaks
after `https://`, and the narrower Holds cell breaks after `prompting`.
The two paragraphs and every visible original table row match the handed
fixture's plain rows exactly, including borders, inset and spacing. The
ANSI captures retain link underline, dim destination on both wrapped rows,
bold heading cells and dim borders. The whole standalone screen is clear:
no unexpected blank rows inside the paragraph or table, displaced column,
clipped right border or source escape text.

u2-comparison-* puts the full original capture on the left and standalone
fixture on the right. Different surrounding app furniture means vertical
positions differ. u2-excerpts-* aligns the actual paragraph/table excerpts;
these are derived from the unaltered plain captures, and only include rows
visible in both. The 120-column original viewport clips the closing table
border; the standalone fixture shows it. That is viewport height, not a
wrapping difference.

No public API or key was added by wrapping. This look does not re-prove all
Markdown forms, parser streaming, physical terminal colors, performance or
the complete port window; developer's focused tests cover style/streaming
boundaries. Ctrl+Q quit the fixture; absence of its owned tmux session was
verified. The original owned session also exited and was cleaned up.
