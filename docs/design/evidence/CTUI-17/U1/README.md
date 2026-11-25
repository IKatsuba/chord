# U1 visual check

Implementation checked: 98f8480, `feat: report settled text area viewports`.
Command: `dart run example/text_area_viewport.dart`.
Designer ran the live TUI in owned tmux session `designer-ctui17-u1`.
Pane sizes were 120x40 and 80x24. Captures are full panes, captured with
`capture-pane -p`; `.ansi` files use `capture-pane -ep` for styling.

Result: pass for designer handoff to reviewer. This is a framework example,
not the port, so no original screen equivalence is claimed or required.

- Empty: logical gutter 1 beside placeholder and steady cursor, both sizes.
- Six logical lines: four-row viewport shows gutter 3/4/5/6 beside the
  corresponding text, with label rows 3–6 of 6, both sizes.
- Up four times at 120x40: viewport becomes logical lines 2/3/4/5 and label
  rows 2–5 of 6. Gutter tracks the scroll without displacement.
- A single long line including Japanese and emoji wraps into six rows at
  120x40 and nine at 80x24. The last four visible rows all show logical
  gutter 1, correctly aligned; label changes from rows 3–6 to rows 6–9.
- Enter submitted the six-line draft and later the wrapped draft, separately
  from literal text entry. Editor returns to empty and gutter 1.
- Resize 120x40 → 80x24 → 120x40 preserves draft/cursor and gutter alignment.
  The existing KeyHelp row clips to available width as before.
- ANSI captures retain dim gutter and placeholder, normal text, and inverse
  cursor styling. No border or gutter focus change was introduced.

Literal text was sent with `send-keys -l`. Embedded LF supplied logical
newlines through the editor's Ctrl+J behavior. Up and Enter were separate
key calls. No real agent, model, fake process, AOT build or tests were run
by designer. Zero-space and callback lifecycle behavior are not visual
claims; developer's handed-over focused tests cover those contracts.

Cleanup: Ctrl+Q closed the demo and the owned tmux session was checked gone.
No fake agents were started. No visual findings remain for U1.
