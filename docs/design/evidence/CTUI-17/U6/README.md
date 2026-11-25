# U6 prompt visual check

Handed-over implementation: 5a242ae. Original checkout: 577b58167.
Designer result: pass for reviewer handoff. No prompt-region visual findings.

Commands:

- Port fixture: `(cd example/chord && dart run tool/prompt.dart)`.
- Original: `(cd ../chord && bun dev chord --fake --qa designer-ctui17-u6)`.

Both ran in owned tmux sessions, at pane sizes 120x40 then 80x24, then
120x40 again. Full panes are `.txt`; `.ansi` files retain color escapes.
Side-by-side files extract each rounded prompt region from the corresponding
full capture, original left and port fixture right. The original QA directory
label is redacted as `[isolated QA directory]`; prompt content is unchanged.

Observed comparison:

- Empty at both sizes: full-width rounded border, one-cell inner horizontal
  padding, two-cell gutter, `›` and blank cursor position match.
- Twelve logical lines at 120x40: ten visible rows, `↑` at logical line 3
  while the cursor is at line 12. Eleven Up keys reveal line 1 with `›`,
  and `↓` on line 10 because more draft remains below.
- Resizing to 80x24: eight visible rows, `›` at line 1 and `↓` at line 8.
  Eleven Down keys reveal lines 5–12 with `↑` on line 5.
- Enter was sent separately in each pane, submitting and clearing the draft.
- Matching Unicode text wraps into three prompt rows at 80x24 and two at
  120x40. Japanese and emoji remain whole; gutters and retained spaces
  match character for character.
- Every saved side-by-side prompt region is identical as plain text.
  ANSI captures show the port's dim border/arrows and inverse cursor;
  original border uses its dim-border palette and its native terminal cursor.

Literal text used `send-keys -l`; embedded LF used each editor's newline
handling. Arrows and Enter were separate key calls. This isolates U6's
prompt component. The port fixture has sent-text echo above and no status
row below; the original has its header, transcript and status. Those
surroundings are not port screen implementations in this fixture. Prompt
position is correspondingly one row lower in the fixture. Integrated window,
real history callbacks, queue, Ctrl+C clearing and interruption are later
units and are not claimed here. No test suite or AOT build was run by designer.

Cleanup: port quit with Ctrl+Q; original cleared its draft and quit via
Ctrl+C. Both owned sessions were checked gone. All tracked descendants,
including the original fake agent, were checked absent afterward.
