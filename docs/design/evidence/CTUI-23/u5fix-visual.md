# U5 corrected visual gate

Exact handed fix f05f3cafdb7e18ebccb548c95bc0b23a9e689b4b on unit
831ccb358defdfc99c95c3dd99b95ed33c06dc3d. Isolated git archive with root
and port package configs pointing to that archive; no shared WIP run.
Original577b58167672e12c999aeaf4eed2a1a988513dc2. Result: visual pass,
hand U5 to reviewer. Prior failure/pass evidence a624b37 remains retained.

## Hidden hint fixed

At120x40 and80x24 /sta offers status. Resize80x5 and Tab: both keep /sta
and show not enough space with the same model facts. These entire five-row
plain frames are byte-identical. Return80x24 clears hint and restores list
without accepting. Shift+Tab then80x5: accept-edits mode and cycle hint
retain priority over the hidden-completion hint, with identical width/drop
behavior and entire five-row frames. The getter contract remains unchanged;
this gate does not audit the deferred observer implementation.

Captures u5fix-{original,port}-filter at both required sizes, zero-tab-80x5,
room-return-80x24 and mode-priority-80x5, each txt/ansi.

## Active turn Esc semantics

Actual fake with CHORD_FAKE_STEP_MS=100, start slow and type /sta. At120x40
Esc dismisses completion, keeps /sta, and working spinner remains. Resize
80x24: still running, no list. Type literal t: /stat reopens the match.
Esc dismisses it; next Esc interrupts, draws Interrupted by user, removes
working spinner and retains /stat. Captures at80x24 and after resize120x40
retain settled result. Fake reply text itself starts Working, so the
spinner assertion concerns Working… plus timer, not that literal reply.
Both implementations show the same semantic states; dot counts/timers vary
with separately captured streaming time and are not asserted byte-identical.

Captures u5fix-*-running-menu, first-escape, running-edit-reopen and
second-escape at named sizes. No real model or agent was contacted.

## Gate scope and disclosed reached failures

All unaffected U5 comparisons in a624b37 remain applicable: staged catalog,
local/agent dispatch, literal input/focus, clear/queued restoration,
status/help/omitted-name handling, live Unicode CUT, dark/light/plain and
fitting-body wheel. No visual finding remains. Current fix run inherited
NO_COLOR; actual palette evidence is retained from the previous exact unit.

This is a visual pass, not an all-tests-pass claim. Developer disclosed
146 reached passes plus exactly2 obsolete tester whitespace expectation
failures (expected surrounding spaces, actual trimmed prompt) at the two
required sizes; no others/skips reported. Main explicitly requires the
original submitted() trim for every prompt. Tester owns those test groups
and may correct them only after reviewed handoff. Reviewer/tester must
carry that known failure disclosure through their gates; no test was edited
by designer and no failure was silently waived.

Known header version/staged-help differences remain; isolated fixture
directory text alone is redacted. Text literal/Enter separate, owned slow
turns interrupted. Sessions exited Ctrl+D, process/session cleanup checked,
exact archive removed after evidence. No code review, whole-suite or AOT
claim is made by designer.
