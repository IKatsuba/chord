# U4 boundary visual look

Unit: ErrorBoundary API and fixture, signed developer commit 49cb74c.
Command: `dart run example/error_boundary.dart`. Designer-owned live tmux
pane started at 120x40, resized to 80x24. Original comparison does not apply
to this framework fixture; the port crash screen is a separate unit.

Pass: x replaces the healthy child with a readable three-line fallback;
resize updates its width label from 120 to 80 without losing the error or
instructions; r replaces the keyed boundary and restores the healthy child.
The bottom key-help row remains visible, with x/r/q described at both sizes.
q exits. Captures u4-healthy-120x40, u4-fallback-120x40,
u4-fallback-80x24 and u4-reset-healthy-80x24 include plain and ANSI panes.

This is a visual/API look, not a code audit or proof of every lifecycle
failure type. No additional tests, whole suite or compile were run.
The owned session exited; no fixture process was left behind.
