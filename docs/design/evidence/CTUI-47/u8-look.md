# CTUI-47 U8 port wheel visual pass

Handed implementation: signed `c58a544`. Owner-accepted original discrepancy
is recorded by developer's decisions-only commit `f32b41e`. Designer ran
only the handed unit, using owned tmux at 120x40 and 80x24 plus the approved
natural 40x12 overflow case. All input was keyboard or bounded injected SGR;
no physical wheel/trackpad delivery is claimed. Plain/ANSI raw captures and
u8-compare-* side-by-side text are saved here.

Result: pass with the owner-accepted bigask120 known limit below. This is a
visual pass, not source review, final suite acceptance or physical-input proof.

## Capture setup and distinction

The real port fake ran with the developer-confirmed equivalent bin argv in
an owned neutral QA cwd and unique XDG_STATE_HOME. The dev runner itself
forces repository cwd; the equivalent child avoids private directory text
in captures. The agent command names only the original fake and
`--step-ms 1`. No real agent/model was selected. The original reference is
`577b58167672e12c999aeaf4eed2a1a988513dc2`, run with its normal fake dev
command and neutral QA name. No original source was changed.

The exact live sequence was completed `long`, then `permission` rejected
with Esc, then `bigask`. Prompts were sent literally, Enter in its own call.
Long parity uses complete 200-row output, not timing-dependent partial rows.
The original long baseline is documented in original-baseline.md.

Separately, `dart run example/chord/tool/wheel.dart --help --tall-draft`
is a seeded stress fixture: 100 named entries and seven real draft lines.
It is not claimed to be the original fake payload. Its current 19-entry M1
help fits at 120x40/80x24; the original full catalog overflows at 80x24.
The proposed 80-column overflow assertion was disproved and corrected,
without changing catalog, prompt limits or available height. Both apps
naturally overflow at 40x12, but the seeded port has the tall draft while
the original uses its ordinary empty-prompt help. The original closed help
when a multiline paste was entered, so no fabricated tall-help parity state
was forced. Catalog, draft and viewport differences are explicit in those
side-by-side captures. Actual fitting/overflowing route behavior is compared.

## Completed long and root routes

At 120x40, the real port and original show first row 166 at the bottom;
one up report over transcript or prompt shows 165, one down restores 166.
At 80x24 the corresponding rows are 182 -> 181 -> 182. The unsubmitted
`wheel keeps this draft` stays unchanged. Each final plain screen equals
its own completed baseline exactly. Mouse input does not browse history.

Home exposes the compact header. Down over position 3,2 removes its first
row, and up restores it, matching the original. Other root positions use
10,10/10,38 at 120 and 10,8/10,22 at 80 (transcript/prompt respectively).
SGR 64 is up and 65 down, with uppercase M and one-based coordinates.
No wheel burst or acceleration was applied.

Fitting help in the live port bubbles to the transcript at both required
sizes, retaining one-row movement. The original fits and bubbles at 120;
its larger catalog consumes at 80, as already established and owner-approved.
The seeded tall help also fits at both required sizes and preserves all
seven draft lines through wheel reports.

## Natural overflow and the body/rule boundary

At 40x12, port help shows a real overflowing body. Down over its first body
row introduces the one-line-above rule; up over the current body row restores
the first item. The underlying transcript after dismissal exactly matches
an unscrolled deterministic baseline. The original40 empty-prompt help
likewise scrolls one row down/up and restores its underlying baseline.

The body's screen coordinates change when the above rule appears. Port
reports used row 2 for initial down and row 3 for subsequent body up. A
separate up report over row 2, now the above-rule row, correctly bubbles
and moves the transcript instead. These are labeled u8-help-rule-up and
u8-help-dismissed-after-rule; they are not mislabeled as failed body routing.
This demonstrates the actual body-only boundary without a forced height.

## Fitting and overflowing permissions

The live fake `permission` proposal is the same notes.txt diff in both
apps. Down selects option 2 before wheel input. At both required sizes,
body/title/choice reports bubble to the transcript; up/down restore its
position and option 2 remains highlighted. Those whole screens match the
original after ignoring only the independently elapsed waiting timer.
Representative side-by-side evidence is u8-compare-permission-fit-*.

The live fake `bigask` proposal is the same MCP write_file release-note
content in both apps. Its body overflows at both required sizes. One body
down exposes one line above, and up restores the body, with unchanged
transcript and option-2 highlight. The whole before/body-down screens match
the original except elapsed timer. The title, below-rule and choices remain
outside the consuming body. At 120 they produce root movement; at 80 the
large proposal leaves no readable transcript rows to measure movement in
pixels. Their root dispatch at that height remains a test/source assertion,
not an extra visible-row claim. Option 2 remains selected through every
report, exercising the stable-choice lifecycle fix.

## Accepted original discrepancy

At bigask120, after the same final wrapped MCP-headline baseline, one up
report over title/rule/choices shows different underlying transcript rows:
the port shows the preceding wrapped MCP line with `2 lines below`, while
the original shows `4. Line 4 of 200` with `1 line below`. The proposal and
its selection remain the same. Exact representative raw paths are:

- original-u8-proposal-title-up-120x40.txt (and .ansi)
- u8-live-proposal-title-up-120x40.txt (and .ansi)

The cause is unproven. Main explicitly accepted keeping existing one-line
ScrollStep behavior and assigned geometry follow-up separately; no geometry
fix or imitation of the original jump is part of U8. Developer recorded the
same scope decision in docs/decisions.md at f32b41e. This limit must remain
in onward review/testing and final handoff, not be erased by this pass.

## Closing and streaming

The whole-window `--permission --closing` fixture was checked at both
required sizes: three reports over transcript/prompt/top coordinates leave
the entire plain screen unchanged. Closing removes the active panels, so
this is a root no-op observation. The fresh body predicates and same-chunk
closing transitions are covered by developer's reached tests; pixels do not
prove callbacks on a body that is no longer drawn. Fixture Ctrl+Q provides
bounded owned exit even while product keys intentionally ignore closing.

A separate slow fake `long` at 80x24 (`--step-ms 5`, no load generator)
checks streaming hold. After wheel input, first visible row 139 stays fixed
while the new-output count grows from 3 to 23 rows below over the observed
interval. End resumes following (first visible row 162 at that instant),
and completion returns to rows 182-200. These are bounded observations,
not a throughput benchmark or exact synchronized original-stream comparison.

## Cleanup and limits

All fixture sessions quit with Ctrl+Q. Live fake requests were cancelled
with Esc, then Ctrl+D quit; the stream completed before Ctrl+D. All owned
sessions were checked absent or killed. The neutral QA directories had no
open-handle PIDs before removal. Their task-owned state and task-specific
original QA directories were removed; no original source was edited.

No real model/agent, clipboard/notification effect, selection/copy feature,
AOT, full suite or signal lifecycle test ran during this designer look.
Framework mouse protocol/mode/signal proofs remain U7's handed checks;
U8's pure reducer, fresh predicate, bounded panel and lifecycle assertions
remain reviewer/tester work. The 226-test developer handoff is evidence from
its author, not a suite rerun by designer. Proceed through reviewer before
tester, preserving the accepted known limit and staged catalog distinction.
