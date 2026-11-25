# U24b2 freshness repair: focused designer recheck

Signed repair: `ef7ba17c39d5a7a5335ba7780681cf2f30f1b90a`.
Public context API: `7fc2382ee17994bc9eb81221ee100e7aaa1cea0a`, consumed only
after tester gate `ac7216e47cbc41abddb192715f68bb93e8bfb70e` was green.
Four developer-owned paths: window/terminal and their two test files.
Return this repair to reviewer; no direct tester handover.

The original857b4c2 settled-screen evidence remains valid but did not prove
pre-frame async safety. Reviewer blocked that head because cached positive room
could survive resize/dirty layout until the next frame and accept stale text.
The supplied original red excerpt retains the ten failures, including expected
@a or @ax versus inserted @alpha. It is developer-supplied evidence, not a
designer reproduction. The supplied green summary reports230 reached checks
and clean analyzer/format. Reviewer/tester verify those implementation claims.

The handed repair validates geometry through the supported public context
method BEFORE publishing the result/removing the pending surface, then checks
live ownership/query/candidates/generation/request/room around callbacks.
There is no internal-member call, dummy selection snapshot or new pass budget.
Pending Enter-to-no-match must remain valid after its own result removes the
surface; do not replace the prepublication eligibility with a stale post-removal
visibility check. The public API's true result means current geometry only.

## Focused live result

Exact ef7ba17 ran from one immutable ignored-build snapshot with offline pinned
framework/port dependencies:

```sh
env -u NO_COLOR dart run example/chord/tool/mentions.dart --slow
```

At120x40, empty prior @srczz edited to @src retains the pending no-paint
surface; Enter waits and inserts the current @src/beta.dart result. At80x24,
Enter during @src-to-@srczz matching settles to no matches and retains @srczz
in this recording fixture, with no stale choice. The fixture has no session;
actual no-match Enter submission is covered by the handed fake-window tests,
not established by that unchanged draft alone.

At80x6, pending Tab on @src has no result-row room. Returning to80x24 and
allowing the result to settle leaves @src unchanged: no dropped acceptance is
replayed. Existing full both-size/theme/quoting/wheel/help evidence remains in
UI-857b4c2; it was not expanded or repeated for this four-file repair.

No new screen finding remains. Native captures here allow geometry to settle;
they DO NOT reproduce or prove the unpumped resize/constraints/unlink,
exhaustion or callback reentrancy race. The public-layout/controller regressions
and reviewer/tester own those guarantees. This is the narrow affected-path
screen recheck, not a new API or full-matrix acceptance.

Literal input, separate Enter events, controlled350ms matching and brief
bounded capture waits; no real agent/walk/shell/clipboard, heavy compile/suite,
WIP execution or original rerun. The owned session/process exited, snapshot and
temporary raw captures were removed. Original developer logs were left intact;
only compact error/result lines without private stack paths are retained here.
