# U14 shortcuts panel visual look and pending-status finding

Developer screen d83648e, exact-commit export under ignored build/ with
root/port package metadata copied. Port command `dart run example/chord/
tool/dev.dart chord --fake`, CHORD_SOURCE selecting ../chord. Original
577b58167: `(cd ../chord && bun dev chord --fake --qa ctui21-u14)`.
U15/later WIP excluded. Captures are live tmux plain/ANSI pairs; directory
text is neutralized. Original full catalog versus M1 subset is intentional.

Panel appearance/interaction passes at120x40 and80x24: three/two columns,
original M1 ordering/wording, dim top rule, unchanged prompt/status location,
opaque background. Real overflow at40x12 uses one column and five content
rows at top/end, four in the middle between two hidden-count rules. Home,
End, PageDown, Shift+Down and PageUp move panel rows; resize clamps and
close/reopen resets to top. Shorter M1 catalog fits at80 while original
full catalog scrolls. This is the designed difference, not forced overflow.

Help opens over an active permission at both sizes. Ctrl+X then Esc clears
only pending state and keeps help/request; a separately delivered second
Esc closes help, leaving the same request active.1 allows it and returns
one visible Permission: allow response. Test evidence owns RPC call counts.
Status hint is now present and matches the original's facts budget.

Finding at80: port pending status shows only ctrl+x … plus model facts;
original names next keys and suppresses facts. Lead/main settled M1 text:
`ctrl+x …  a the one that waits · esc never mind`, no facts. Drop original
b/code-block clause until its task. Existing Escape cancellation passed
this live check, so keep it while fixing text/facts. Developer accepted.
U14 is not passed to reviewer until the signed fix is rechecked.

Native `draft?` in a single input burst stays native in port; original can
open help and restore an empty draft. Main chose the port behavior as a
fix for original stale-state handling, not parity. Rapid Escape sequences
can also be parsed together by original input; separately delivered Escape
was used for the authoritative permission dismissal comparison. Captures
preserve observed outcomes rather than pretending exact frame timing.

No source audit, extra tests, whole suite or AOT run. Both owned windows
quit through empty Ctrl+D; sessions were confirmed closed and export removed.
