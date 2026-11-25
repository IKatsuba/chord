# U5 custom KeyHelp visual look

Unit: KeyHelp.builder API and fixture, signed developer commit 0366c5f.
Command: `dart run example/key_help.dart`, in a designer-owned tmux pane
at 120x40, then 80x24. The call site matches CTUI-21 section 2. This is a
framework API fixture; an original port screen comparison does not apply.

Pass: both sizes display the custom heading and the two complete bindings
without clipping or collision. Ctrl+X adds `Pending: ctrl+x` above the full
list; Q remains listed during the pending prefix. At 120x40, literal a
completes the chord and clears Pending. At 80x24, Esc cancels it and clears
Pending. The bindings retain their order and text. q exits the fixture.
Captures u5-{idle,pending,completed}-120x40 and
u5-{idle,pending,cancelled}-80x24 include plain and ANSI panes.

This proves the visible sample and its pending/completion/cancel states;
it does not substitute for unit tests of immutable snapshots, focus
precedence or disposal. No additional tests, whole suite or AOT run.
Both U4 and U5 owned sessions were confirmed closed after their quit keys.
