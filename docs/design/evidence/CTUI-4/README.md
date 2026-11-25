# CTUI-4 Markdown visual check

Unit 4: initial implementation 1482fc7, table fix 598850c. Design includes
42a86f7's exact markdansi table arithmetic. Ran the handed-over command
`dart run example/markdown.dart` in owned tmux session designer-markdown
at 120x40 and 80x24. The original fake agent's markdown scenario ran in
owned session designer-original at both sizes. Original input was sent
literally, with Enter in its own call. No code diff was used for the look.

Result: visual pass on 598850c. The initial handover's real-grid table fit
was returned as finding 1; the lead chose markdansi's fit arithmetic and
developer returned 598850c. The compact 30x24 extra capture shows its
whole-table single-line ellipsis fallback and source alignment. All other
screens are the required sizes.

The fix-dark-top/middle/lower captures show headings, inline styling,
hanging nested/task/ordered/loose lists, quote bars, code frames, table,
40-cell em-dash rule and visible reference definition. The Japanese text
keeps cell alignment; code wraps with the approved `│ ↪ ` continuation.
Unknown/unlabelled code boxes remain plain and correctly inset. ANSI
captures retain theme roles: dim grid/markers/rule, bold heading, slant,
inline code and link colour. Light theme is explicitly selected, without
claiming a light-background terminal measurement. Plain mode keeps
attributes without colour.

Streaming captures show an unfinished fence at 120x40 and 80x24 and an
incomplete table row at 87 percent. The received content stays readable;
these are sampled frames, not a performance or all-boundaries proof.
The before-table capture is intentionally an earlier frame. Initial-*
files record the pre-fix fixture; fix-* supersede them for acceptance.

Original-markdown captures provide the live reference for code/table
furniture and spacing. The fixture's sample text differs from the fake's,
so these are a look comparison, not a claim of row-for-row text equality.
The original carries reply gutters and copy/run buttons, which this
framework widget intentionally omits. The framework's wrapped code and
six-cell inset are the approved differences. The fixture's top-level label
follows the settled design; original nested quoted code also demonstrates
the `┌ ts ─…┐` form. No further undecided visual difference found.

Scope limits: no performance measurement, parser audit, cache inspection,
NO_COLOR startup test, or exhaustive image/mailto/reference split cases.
Those remain developer/reviewer/tester evidence. Both owned sessions
exited; tmux reported both absent, and their terminal devices were gone.
No other tmux session was touched. Captures contain no home directory or
runtime directory names.

## Reviewer fixes: regression look

Implementation 4a81d91 fixes table theme.text inheritance and empty quotes.
Per the lead's direction, re-ran the existing fixture at 120x40 and 80x24;
no additional fixture was required. review-fix-* captures show top and
lower blocks at both sizes plus the narrow code/quote region. No movement
or new visual finding: table geometry, code wrapping, spacing and visible
reference definitions remain unchanged.

This is a no-regression look. The existing sample uses a plain text role
and does not contain empty quotes, so the captures do not independently
prove custom text colour propagation or invisible-quote suppression.
Developer's dedicated widget tests are the evidence for those exact fixes,
as the lead directed; reviewer checks their technical correctness.

Returned 4a81d91 to reviewer. The owned designer-markdown-fix session exited
and was confirmed absent; its terminal device was gone.
