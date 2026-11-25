# U25c1 and U25c2 combined designer pass

Accepted combined head: `29e178a77109d7a9da23d69f045fd23e9f768f65`.
Earlier ! screen implementation/reference:70498fe, sibling U25c1-70498fe.
Original reference:577b58167672e12c999aeaf4eed2a1a988513dc2, read-only ../chord.
Pass both handed screen units together to reviewer, not tester.

## Required repair and scope

Do not accept70498fe alone as reached-green. U25c2 includes the required
source-option repair: lazy catalog/hint and mounted transcript now share
shellStopKey=esc, so current source revision/geometry agreement is retained.
Developer reports the12 existing code_pick_window regressions green in its
reached run; reviewer/tester verify that claim. The live current copy button
also succeeds through the injected recording adapter with sent30chars feedback.
No stale copy or unresolved-geometry fallback was introduced or is approved.

This look covers ! entry/history/prompt/status/shell row plus run buttons,
keyboard block picking, prompt insertion/refusal, real help and wheel routing.
It is not an ACP/queued context/process audit. Existing pure/reached tests own
held context send/restore, cancellation, ownership and exact timing assertions.
No real port agent/process is launched by this fixture.

## Screen observations

At120x40 and80x24, closed sh has copy+run, TypeScript only copy, and quoted
bash no pointer control. ctrl+x b reaches the quoted bash descriptor; hint is
↑ ↓ another block · c copy · r put in the prompt · esc done. r puts quoted
script in bash mode, with leading dollar-space removed, and ends picking.
Nothing executes. Picking TypeScript then r is inert, keeps the pick and
omits the run hint. Selecting sh then r inserts both lines, printf first and
printf second, preserving their newline and stripping only column-zero $ .
The original's existing markdowncode fixture proves equivalent runnable vs
nonrunnable controls/hints/insertion; its source text differs from the port's
small quoted scenario, so the captures are not relabelled as identical code.
Quoted bash keyboard policy is current source/design-defined plus live port
proof, not a claim that markdowncode contains a quoted bash block.

With a nonempty script, another run action preserves every draft cell and
shows The prompt holds a draft · ctrl+c clears it. Timed warning was captured
promptly and later observed expired back to bash status with draft unchanged;
exact3000ms is the logical-test contract, not a stopwatch claim. Pointer run
also fills the two-line script with no execution. Code copy uses only the
injected adapter, says sent30chars, and leaves the existing draft intact.
No host clipboard write or receipt is claimed.

The final head also received a direct !empty local submit at80x24 and wide
reflow, compared with original !true; both show No output and ordinary empty
prompt afterward. Earlier70498fe captures supply the full !typing/paste/
Backspace/Up/history/clear/running/stop/error matrix. Current final run-filled
screens retain the same bash palette/gutter/status in dark/light/plain.
Physical cursor focus/unfocus appearance is outside this change and unclaimed.

Shortcuts list actual bash actions and c r to copy or put in the prompt.
The staged panel naturally fits at80x24 and120x40; no rows were trimmed to
force fit. At80x18 it genuinely overflows. One wheel report over its surface
scrolls the panel; closing it yields byte-identical underlying transcript text
before/after in both original and port. This directly retains the overflowing
box's wheel ownership without moving the transcript.

## Evidence limits and probe correction

An initial final-head probe sent Escape then ! too closely in one tool cell;
the legacy decoder treated it as Alt+!, in both original and port. It did not
test bash entry. That probe was discarded and repeated using standalone Escape,
then a later literal bang input, then a separate Enter call. Final dark/original
direct-bang/submitted captures are from the corrected sequence. Invalid theme
direct-entry captures are excluded. The original later scene includes its
ordinary fake Hello world reply from that discarded probe; no real model was
reached and that extra row is not a port behavior difference. No batch failure
is called a product fix or silently counted as successful input.

Original's full live roster/model facts and other finished features remain
outside the small recording fixture. Its code text, inset/label and mid-token
wrapping differ under already-approved port geometry. Full original/port
comparison captures preserve those differences; no OpenTUI quirks are copied.

## Provenance and cleanup

Separate immutable snapshots of70498fe and29e178a ran with offline pinned
framework/port dependencies. Final fixture commands from its snapshot root:

```sh
env -u NO_COLOR dart run example/chord/tool/bash.dart --code
env -u NO_COLOR dart run example/chord/tool/bash.dart --code --light
env NO_COLOR=1 dart run example/chord/tool/bash.dart --code --plain
```

Original command: env -u NO_COLOR bun dev chord --fake --qa
ctui-designer-u25c-code, followed by the existing markdowncode scenario.
Text sent literally, Enter separately, primary/wheel SGR reports in owned tmux
sessions; normal captures120x40/80x24 plus the explicit80x18 wheel edge.
No compile/heavy tests, current-tree WIP execution, real port shell/agent or
host clipboard access occurred. Both port callbacks and shell process are
recording/injected. Original scripts inserted from run were cleared, never run.
Only explicit bounded printf/true/sleep fixtures ran for earlier comparisons.

All owned earlier/final sessions and processes were checked gone; pending
drafts were cleared before cooperative exit. QA state, immutable snapshots and
temporary raw capture copies were removed after retention. Signed evidence
contains only designs/findings/captures, no implementation changes. No remaining
screen blocker on the combined head; reviewer receives the mandatory repair
and exact scope before tester can run its gate.
