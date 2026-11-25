# Optional follower opacity: designer/API pass

Handed framework head: `3126fecb4612bad50d0f2003b40cfdf959cdb17e`.
Design: CTUI-24 follower prerequisite, signed625c3ef.
Pass this generic public-widget/screen unit to reviewer before port consumption.
Port U24b2 work was not inspected or run.

Live120x40/80x24 default/passive comparison confirms the positive-size empty
opaque:false follower preserves the full numbered row above the editor
(row34 and row18 respectively). Default renders its completion and covers only
its child's rectangle; underlying tail cells outside that rectangle remain,
as expected from the existing bounded opaque extent. No transparency/visibility
semantics are inferred from a missing label or a zero-sized child.

Typing x updates Draft to stax in both modes, retaining editor focus. Ctrl+R
resets, and Tab completes to status with Last Tab: completed at both sizes.
At80x5 the follower has zero room: Tab leaves Draft: sta and says ignored.
Returning to80x24 without another Tab leaves the draft unchanged and the last
result ignored. No dropped action is replayed just because room returns.
All three keys/full descriptions remain readable at each checked size.

API shape follows the approved explicit opaque:false option with true default;
this is a generic follower capability, not a new room-query API. The live look
proves preserved cells, editor focus and raw geometry eligibility in this
fixture. It does not independently exercise pointer/wheel hit passthrough,
interactive-child hit retention, selection/code query exposure, same-geometry
opacity toggles, unknown child coverage or unlink behavior: those are the
handed reached tests and reviewer/tester gate. Do not turn their reported
results into designer runtime proof. No blocking API/screen finding remains.

Commands from a separate immutable ignored-build source snapshot:

```sh
env -u NO_COLOR dart run example/overlay_visibility.dart
env -u NO_COLOR dart run example/overlay_visibility.dart --passive
```

Dependencies resolved offline. Both owned sessions began120x40, resized80x24,
then80x5 and back80x24. Literal input, TXT+ANSI pairs, full windows retained.
No real process/model/clipboard use, compile/heavy tests, current-tree WIP or
original port screen was involved; this framework fixture has no original
counterpart. Owned sessions/processes exited cooperatively, the immutable
snapshot and temporary raw copies were removed after retention. Only this
evidence is designer-owned; six-file implementation remains developer-owned.
