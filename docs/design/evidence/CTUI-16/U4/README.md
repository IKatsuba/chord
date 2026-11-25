# U4: transcript entries

Designer visual pass for production commit `e79711d`, with fixture-only
extension `dfe6339`. Ran `dart run tool/transcript_entries.dart` from the
port package in a designer-owned tmux session at 120x40 and 80x24. ctrl+o
expanded/collapsed thought; ctrl+q exited. Also ran its --permission,
--markdown and --wrap modes at both sizes. NO_COLOR was unset with
TERM=xterm-256color and COLORTERM=truecolor. `.ansi.txt` retains colors and
attributes with capture-pane -p -e; other captures use -p.

Pass: the whole compound fixture fits at both sizes. User and reply
markers, block margins, dim italic expanded thought, Markdown list,
attached cancelled/stopped outcomes, yellow warning/red failure, and the
finished checklist retain the original's structure. No gap separates an
outcome from the preceding block. The wrapped Unicode prompt keeps its
continuations at the text column; the long stopped outcome wraps beneath
its own text column. Permission mode displays allowed and rejected
receipts without gaps. Growing Markdown mode displays an open Dart fence
as a highlighted code block without spilling into adjacent rows.

`compare-*` puts original runtime captures beside these port fixtures at
the same size. The fixtures deliberately combine several entries and use
different text; header, input and status furniture belong to the original
window and are outside this U4 fixture. Compare entry columns, spacing,
attributes and wrapping rather than whole-screen row equality. The
Markdown framework's existing copy/run omission and wrapped code behavior
were already settled in CTUI-4; U4 adds no new difference.

The permission mode checks settled receipts only. No live permission
scenario was run, as instructed; active permission choices belong to
CTUI-18. Streaming behavior here is a rendered growing-state snapshot,
not a live agent run; U7 supplies live integration. No new visual findings.
This is a visual pass, not a code review or a test-suite run. All owned
fixture sessions exited and were removed.
