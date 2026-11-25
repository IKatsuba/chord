# U3 visual finding: status mode hint and precedence

Handed signed unit: 2db2ff72dab3a14c06179c5974e17a82972a2fe3.
Original head: 577b58167672e12c999aeaf4eed2a1a988513dc2.
Result: return to developer for one status fidelity finding; no reviewer
handoff yet. This is a visual gate, not implementation review.

## Finding

Start both fake windows at 120x40, type literal `draft`, then Shift+Tab
(BTab). Draft and prompt border match. Original status says
`⏵⏵ accept edits on (shift+tab to cycle)`; port omits the parenthesized
cycle hint. Clear draft with Ctrl+U, open `/effort`: original retains mode
status, while port replaces it with `? for shortcuts`. This is captured at
80x14 and 40x10. Restore the original mode/hint precedence and width
drop order. Real notices must retain their original higher priority.

Evidence: paired `u3-*-mode-draft-120x40`, `mode-draft-80x24`,
`overflow-80x14` and `tiny-40x10`, txt plus ansi.

## Passed checks

Model default, Right pending effort, Down alternate model preview, Esc
cancellation, settings list, values and Esc back match row-for-row at
120x40 and 80x24 except known startup-header version/directory/help staging.
Model pending marker and short hint at 80 columns match. At 80x14 the effort
picker's one visible choice, edge marker and hidden count match. At 40x10
both keep title and Esc, with no visible acceptance; Esc closes both.

True dark and light palette model captures at both required sizes verify
picker border/title/highlight permission roles: RGB177,185,249 dark and
RGB74,90,224 light. Main prompt remains dim. Plain captures retain legible
selection. Default shell inherited NO_COLOR=1: initial U3 interaction captures
are plain. Files originally captured with COLORFGBG alone are explicitly
renamed inherited-plain; they are not light evidence. True colour runs unset
NO_COLOR and set FORCE_COLOR=3, COLORTERM=truecolor with COLORFGBG15;0 or0;15.
The original paints explicit white default text; port uses terminal default,
an existing style difference outside this callback/picker change. Palette
permission tones match exactly in ANSI captures.

Commands: port `dart run example/chord/tool/dev.dart chord --fake`, original
`bun dev chord --fake --qa designer-u3`, with isolated names for theme runs.
Long transcript opacity/wheel and accepted compound model+effort flow remain
for the corrected-unit gate. No claim is made for those unrun interactions.
All owned sessions exited through Esc then Ctrl+D; process cleanup checked.
