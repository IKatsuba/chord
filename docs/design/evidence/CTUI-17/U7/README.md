# U7 integrated prompt visual check

Handed-over implementation: 1146ba1. Original checkout: 577b58167.
Designer result: pass for reviewer handoff; no open visual findings.

Commands:

- Port: `dart run example/chord/tool/dev.dart chord --fake`.
- Original: `(cd ../chord && bun dev chord --fake --qa designer-ctui17-u7)`.

Owned tmux panes ran at 120x40 then 80x24. `.txt` files are full panes;
`.ansi` files preserve color. Side-by-side files select prompt or queue
regions from the full panes. Directory labels in headers are redacted as
`[task directory]` and `[isolated QA directory]`. No prompt text is redacted.

Observed:

- Sent `first prompt`, typed `draft to preserve`, Up recalled `first prompt`,
  Down returned the draft unchanged. Prompt regions matched at 120x40.
- The suggested `slow` scenario completed before capture, draining its two
  prompts normally. To keep the queue visible, used the existing bounded
  `readsheld` scenario, which waits up to 60 seconds or until cancelled.
- At 120x40 queued a two-line prompt and a second prompt, then typed
  `current draft`. Queue shows `queued first …` and `queued second`, dim,
  in the same columns as the original. Esc restores four logical lines:
  queued first, continuation, queued second, current draft. Cancellation
  receipt also matches. These are the saved queue/interrupted captures.
- Resize to 80x24 retains that restored draft. Ctrl+C clears it without
  quitting. Both cleared prompt regions match.
- At 80x24 sent `readsheld`, then six queued prompts including a multiline
  first prompt and a long second row. Four queue rows show the first three
  and `… +3 more`. Long text has the identical middle `...` cut and ending.
  ANSI evidence confirms queue marks, text and count are dim on both sides.
- Esc restores all six ahead of `narrow draft`. Eight visible wrapped rows
  show the same `↑` and identical contents in both windows. Up from a fresh
  `narrow saved draft` recalls `narrow queued 6`; Down returns the saved draft.
- Every extracted paired prompt and queue region matches character for
  character. Literal text used `send-keys -l`; LF inserted logical newlines.
  Enter, Up, Down, Esc, Ctrl+C and Ctrl+D were separate key calls.

The interim header/footer differ from the original and remain outside U7.
Working/status/plan are later units. The original's working row appears in
queue captures; U7's window does not yet draw it. Extra wide-pane blank
space above the prompt was queried with developer and resolved: the interim
header is shorter and unused Expanded transcript room remains blank. Narrow
clipped panes have matching prompt gap and fixed bottom alignment, so this
is not an extra prompt margin. Integrated working furniture is checked again
when handed over. No model or real agent was used; designer ran no tests or
AOT build. Request-held queue headers are covered by developer's focused
tests, not by this live scenario.

Cleanup: cleared drafts and quit each app with Ctrl+D. Both owned tmux
sessions and all tracked descendant processes, including fake agents,
were checked gone after shutdown.
