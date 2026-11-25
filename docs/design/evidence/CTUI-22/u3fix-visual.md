# U3 corrected visual gate

Fix handed: signed 5162f54fa6ebb4cfb628d759dee90906c2099028, on U3
2db2ff72dab3a14c06179c5974e17a82972a2fe3. Original head remains
577b58167672e12c999aeaf4eed2a1a988513dc2. Prior failing evidence f07c80d
is retained. Result: visual pass; hand corrected U3 to reviewer.

## Status finding resolved

At 120x40 and 80x24, literal draft then Shift+Tab preserves the draft and
now draws original mode/cycle hint and width-drop behavior. Paired with
retained u3-original-mode-draft captures, the final four rows match exactly.
Ctrl+U then /effort retains the mode instead of replacing it with the idle
shortcuts hint. At 80x14 the cycle hint still fits; at 40x10 it drops while
the mode label remains, matching retained original overflow/tiny captures.
No palette/prompt border change is observed. Fixed captures are
u3fix-port-mode-draft and u3fix-port-mode-effort at named sizes.

## Remaining long overlay and compound flow

Both original and port ran the same fake: send long literally, Enter
separately; confirm Line200 and no working line before typing /model.
At 120x40 the floating opaque frame, visible transcript, prompt and status
match exactly as plain full screens. One injected up report over model
choice1 at(15,29) scrolls the transcript under the fixed picker in both,
without moving choices. Resize to80x24 preserves the matching window.

Right makes High pending, Down highlights Fake Small, Enter applies both.
Both show Fake Small/high effort and the same21-lines-below held scroll
rule. Typing kept draft reaches the restored prompt in both; End reveals
the identical /model outcome note: Switched to Fake Small · High effort.
The note and draft match after resize to120x40 as well. Reopen /model and
resize to80x24; one up report over choice1 at(15,13) again scrolls transcript
and retains the overlay. All corresponding original/port plain captures
for these states are byte-identical. ANSI companions retain style evidence.
No physical mouse or trackpad claim is made; wheel reports are byte injected.

See paired u3fix-{original,port}-long-model, compound-pending,
compound-applied, focus-draft, compound-note, long-reopen and
long-reopen-wheel at named sizes. Screens were viewed during the run; file
comparison confirms whole-screen row equality rather than replacing it.

## Scope and cleanup

Earlier U3 captures cover config/back, pending/cancel, tiny/no-choice and
true dark/light/plain picker roles at both required sizes. The fix touches
status semantics and does not change that passed palette evidence. Current
fix run inherited NO_COLOR=1, matching original plain status evidence.
Real-notice precedence and reentrancy are developer/reviewer/tester checks,
not claimed from this visual run. Esc then Ctrl+D exited owned sessions;
remaining tmux and fake/port process checks were clean. No implementation
review was performed, no WIP inspected and no code changed by designer.
