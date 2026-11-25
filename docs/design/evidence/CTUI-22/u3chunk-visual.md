# U3 batched-input corrected visual gate

Handed exact signed head:74acadea8c8a3c0c0ab2ca5c601fbf6177a23178.
Original:577b58167672e12c999aeaf4eed2a1a988513dc2. Ran port from an exact
git archive with isolated package roots; shared U5 work was not run.
Result: visual pass, hand corrected U3 directly to reviewer.

## Input evidence

Actual fake windows at120x40 and80x24. Type /model literally, Enter in a
separate call. Send each named batch as one tmux send-keys -l invocation,
containing complete arrow/keyboard byte sequences. This exercises running
terminal dispatch; OS-level read grouping itself is not measured here.
Closing/same-frame guards remain developer/reviewer/tester checks.

Right+Down highlights Fake Small while retaining High effort pending and
the asked-for explanation, matching original at both required sizes.
Left+Up returns Large/Medium without marker. At80x24 Right+Enter commits
High, drawing Effort set to High. Reopen, then Left+Esc+Enter closes without
committing Medium; reported High and prior outcome remain unchanged. Esc
uses the complete kitty CSI27u sequence to avoid bare-ESC Alt ambiguity.
Reset to Medium through Left+Enter, reopen, then Down+Right+2 in one batch
accepts Fake Small with High effort. Outcome note/status match original;
the same settled state is retained after resize to120x40.

For post-exit flow reset both to Large/Medium, reopen model, identify each
fake child through the owned tmux pane descendant tree and TERM only that
fake. Both keep the picker. Right+Down+Enter in one batch draws identical
normal-gutter failed note: Could not switch to Fake Small: The agent exited.
Required120x40 and80x24 captures retain this original-faithful refusal.

## Captures and limits

Paired u3chunk-{original,port}-right-down, left-up, right-enter,
left-escape-enter, down-right-number and post-exit-batch txt/ansi at named
sizes. All ten captured plain comparisons match below known startup-header
version/help differences. Isolated fixture-directory header text alone is
redacted; no user home directory appears. Current run inherited NO_COLOR;
prior true dark/light/plain and long-label evidence remains unaffected.

Earlier9e541c9 covers wrapped hints/CUT/initialized-session mapping;
7af723b covers status/compound/long overlay/wheel/focus, and dab2a8e covers
actual error-note colour. No new screen finding remains. This gate does
not claim code review, whole-suite/AOT coverage or wire-level chunk timing.
Owned sessions exited Ctrl+D. Runtime/session cleanup checked; the exact
archive was removed after retaining evidence.
