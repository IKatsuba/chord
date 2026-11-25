# U54c1: Picker exact extents live look

Implementation observed: signed `ffa1efd2f86b9d92013aa0b9ebe7b7d4af73938a`.
Command: `dart run example/picker.dart`, owned designer tmux server.
API shape and screen look pass to reviewer. This is not a code audit,
AOT performance gate or actual resume integration pass.

The public Picker itemExtentBuilder/itemExtentVersion match CTUI-54,
including final content width, pure exact heights, inline closure/revision
semantics, query/order/gutter invalidation and runtime error documentation.
The ListView/ListViewport public error-doc follow-up from U54b is included.
Picker keeps existing furniture for zero-height content; ListView may have
zero-height items. The design now explicitly records that boundary and
AOT-active extent errors.

## Observed screens and inputs

Every text capture has matching ANSI. At 120x40, six Down presses highlight
choice 7; both source lines inherit selected styling, continuation stays
under the label, and edge arrows/hidden count remain legible. Resize to
80x24 preserves choice 7 and reveals its first line at the top as configured.
Enter reports `Chosen: choice 7`. See `u54c1-wrapped-*` and
`u54c1-accepted-80x24`.

Literal `/` enters editing; literal `nomatchzz` yields `No matches.` at
both required sizes. Help contains Finish editing filter and Quit, with no
choice navigation/acceptance. Ctrl+U and literal `Choice 7`, then Enter in
a separate call, leave filtering with choices 7/17/27. At 24x24 the first
choice wraps cleanly to three lines with the fixed inset; see
`u54c1-filtered-24x24`. Esc reports canceled while retaining the query.

At 80x3 only filter/status/help rows fit. Enter, Down and digit 1 leave
chosen value and query unchanged; help lists only filter/cancel/quit.
Returning to 80x24 restores choice 7 with no deferred acceptance. See
`u54c1-zero-80x3`, `u54c1-restored-80x24` and `u54c1-canceled-80x24`.
Live j moved selection to choice 2 and k returned it to choice 1.

The first generic captures inherited NO_COLOR=1. Initial light attempts
therefore are labelled `u54c1-inherited-plain-light-*`, retained as a harness
limitation and not light-colour evidence. Corrected runs use
`env -u NO_COLOR COLORFGBG="15;0"` for dark and `"0;15"` for light;
plain uses NO_COLOR=1. Corrected dark/light/plain captures cover both
120x40 and 80x24. ANSI inspection confirms dark selected RGB 177/185/249,
light 74/90/224 and bold/dim-only plain with no colour SGR. Selection marker,
number and label remain legible in each.

## Limits and cleanup

No new screen finding. These are framework captures; no original chord
screen comparison is applicable. Empty-item and custom fallback lifecycle
cases remain reached-test obligations, not states fabricated in this fixture.
Large-list responsiveness, exact cost counters and port resume rows await
later developer handoffs and tester gates.

All fixture instances exited through Ctrl+Q; the owned tmux server ended.
No fake agent or model was used, no temporary state root was created,
and captures contain no private path. No unrelated WIP was inspected.

## Later negative-height boundary clarification

Tester subsequently found that Picker rejects a negative callback height
inside its LayoutBuilder build; the framework presents the ArgumentError
through its normal build-error boundary rather than letting pumpWidget throw.
The mounted measured-height mismatch occurs during render layout and uses
normal render-error handling. CTUI-54 now states those boundaries explicitly;
AOT rejection remains required. Developer owns a follow-up to disable stale
choice actions before failed projection and test initial failure plus
positive-to-negative-to-valid recovery. This note does not claim that fix or
its error screen has passed designer review.

## Fix 877c545 API and positive-screen recheck

Exact handed fix: signed `877c545dae9046fa0bf16b6e842cd6b7f5443330`.
Designer checked its public field documentation: negative heights report
ArgumentError through normal build-error handling; measured mismatch uses
StateError during layout, including compiled executables. This matches the
clarified design and passes the API look.

The shared checkout had later tester work; `git diff --quiet 877c545 -- lib
example/picker.dart pubspec.yaml pubspec.lock` confirmed the running fixture
source/dependencies matched the handed fix. Unhanded tests were not inspected.
Ran the same positive fixture, dark theme with NO_COLOR removed, at 120x40
and 80x24. Six Down presses, multiline choice 7, resize and Enter still look
right and select choice 7. Retained `u54c1-fix-877c545-*` text/ANSI captures
show the selected row at both sizes. No new positive-screen finding.

Developer confirms no live failure-toggle fixture exists. Therefore this
recheck does not claim a live negative-height error/recovery screen pass.
Initial failure, stale actions and positive-to-negative-to-valid recovery
remain the separate developer/tester headless regression gate at this fix;
reviewer must receive tester's result before clearance. No code audit or
headless execution was performed by designer. The owned fixture exited with
Ctrl+Q, its tmux server ended and no owned Picker Dart process remained.
